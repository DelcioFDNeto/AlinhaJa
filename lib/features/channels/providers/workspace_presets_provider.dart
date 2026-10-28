import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';

/// Lista os presets visíveis para o usuário: os de sistema, os compartilhados
/// pela empresa e os privados do próprio usuário. A RLS de
/// `public.workspace_presets` já aplica esse recorte — aqui só ordenamos.
final workspacePresetsProvider =
    FutureProvider<List<WorkspacePreset>>((ref) async {
  ref.watch(authStateProvider);
  if (supabase.auth.currentUser == null) return const [];

  final result = await supabase
      .from('workspace_presets')
      .select('*, users:created_by(full_name)')
      .order('is_system', ascending: false)
      .order('usage_count', ascending: false)
      .order('name');

  return (result as List)
      .map((e) => WorkspacePreset.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// Operações de escrita nos presets. Todas passam por RPC `SECURITY DEFINER`,
/// que revalida a permissão no banco (presets de sistema são somente leitura e
/// presets de terceiros exigem papel global de admin).
class WorkspacePresetService {
  final Ref _ref;

  const WorkspacePresetService(this._ref);

  /// Cria (quando [id] é nulo) ou atualiza um preset. Devolve o id resultante.
  Future<String> save({
    String? id,
    required String name,
    String? description,
    required String category,
    required String icon,
    required String color,
    required String cardType,
    required bool workflowEnabled,
    required String assignmentMode,
    String postingPermission = 'everyone',
    required List<WorkflowStageDraft> stages,
    bool isShared = true,
  }) async {
    final result = await supabase.rpc('upsert_workspace_preset', params: {
      'p_id': id,
      'p_name': name.trim(),
      'p_description': description?.trim(),
      'p_category': category,
      'p_icon': icon,
      'p_color': color,
      'p_card_type': cardType,
      'p_workflow_enabled': workflowEnabled,
      'p_assignment_mode': assignmentMode,
      'p_posting_permission': postingPermission,
      // Presets não pertencem a um canal: as etapas vão sem `id`.
      'p_status_config':
          stagesToJson(stages.map((s) => s.detached()).toList()),
      'p_is_shared': isShared,
    });

    _ref.invalidate(workspacePresetsProvider);
    return result.toString();
  }

  /// Cria uma cópia editável — o caminho oferecido para presets de sistema.
  Future<String> duplicate(WorkspacePreset preset, {String? newName}) {
    return save(
      name: newName ?? _nextCopyName(preset.name),
      description: preset.description,
      category: preset.category,
      icon: preset.icon,
      color: preset.color,
      cardType: preset.cardType,
      workflowEnabled: preset.workflowEnabled,
      assignmentMode: preset.assignmentMode,
      postingPermission: preset.postingPermission,
      stages: preset.freshStages(),
      isShared: false,
    );
  }

  Future<void> delete(String id) async {
    await supabase.rpc('delete_workspace_preset', params: {'p_id': id});
    _ref.invalidate(workspacePresetsProvider);
  }

  static String _nextCopyName(String name) {
    final base = name.length > 40 ? name.substring(0, 40) : name;
    return '$base (cópia)';
  }
}

final workspacePresetServiceProvider = Provider<WorkspacePresetService>(
  (ref) => WorkspacePresetService(ref),
);

/// Traduz erros vindos do Postgres em texto legível para o usuário.
///
/// As RPCs usam `RAISE EXCEPTION` com mensagens já em português; o
/// `PostgrestException` chega com ruído de driver em volta, então extraímos só
/// a mensagem quando ela existe.
String describePresetError(Object error) {
  final raw = error.toString();
  final marker = raw.indexOf('message: ');
  if (marker >= 0) {
    final rest = raw.substring(marker + 9);
    final end = rest.indexOf(', code:');
    return end > 0 ? rest.substring(0, end) : rest;
  }
  return raw;
}
