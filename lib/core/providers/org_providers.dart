import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:uuid/uuid.dart';

/// Provider que busca as filiais da tabela [branches] no Supabase.
///
/// Morava em `features/admin/ui/tabs/user_create_tab.dart` e era importado de
/// telas de quatro features diferentes só para chegar até aqui. Como agora o
/// composer de anúncio (em `core`) também precisa dele, a definição veio para
/// os providers de organização — `core` não pode depender da UI de um módulo.
final branchesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final res =
        await supabase.from('branches').select('id, name').order('name');
    if (res.isNotEmpty) {
      return List<Map<String, dynamic>>.from(res);
    }
  } catch (_) {
    // Ignora erro se a tabela não existir ou RLS bloquear
  }

  // Fallback usado só se a leitura de `branches` falhar (tabela ausente ou
  // RLS bloqueando). Aqui ficava uma lista fixa de lojas de um dos tenants,
  // que veio junto num sync e passou a ser oferecida na outra marca também.
  // Nome de filial é dado do tenant e não pode morar em código compartilhado
  // entre as marcas.
  //
  // 'Corporativo' é o único valor seguro para qualquer empresa; as filiais
  // reais devem sair da tabela `branches`.
  return [
    {'id': 'Corporativo', 'name': 'Corporativo'},
  ];
});

/// Provider que busca departamentos ativos da tabela [departments] no Supabase.
final departmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await supabase
        .from('departments')
        .select('id, name, icon')
        .eq('is_active', true)
        .order('name');
    
    // Supabase v2 returns List<Map<String, dynamic>> directly if not mapped
    return List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));
  } catch (e, st) {
    debugPrint('Error in departmentsProvider: $e\n$st');
    return [];
  }
});

/// Provider que busca cargos/funções ativos da tabela [job_positions] no Supabase.
/// Opcionalmente filtra por departamento.
final jobPositionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>(
        (ref, departmentId) async {
  try {
    final res = await supabase
        .from('job_positions')
        .select('id, name, department_ids')
        .eq('is_active', true)
        .order('name');

    final all = List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));

    // Se departmentId for null, retorna todos
    if (departmentId == null || departmentId.isEmpty) return all;

    // Filtra apenas cargos compatíveis com o departamento selecionado
    return all.where((jp) {
      final deptIds = (jp['department_ids'] as List?)?.cast<String>() ?? [];
      return deptIds.contains(departmentId);
    }).toList();
  } catch (e, st) {
    debugPrint('Error in jobPositionsProvider: $e\n$st');
    return [];
  }
});

/// Provider que busca TODOS os departamentos (ativos e inativos) para o painel de gestão.
final allDepartmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await supabase
        .from('departments')
        .select('id, name, icon, is_active')
        .order('name');
    
    return List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));
  } catch (e, st) {
    debugPrint('Error in allDepartmentsProvider: $e\n$st');
    return [];
  }
});

/// Provider que busca TODOS os cargos/funções (ativos e inativos) para o painel de gestão.
final allJobPositionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await supabase
        .from('job_positions')
        .select('id, name, department_ids, is_active')
        .order('name');

    return List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));
  } catch (e, st) {
    debugPrint('Error in allJobPositionsProvider: $e\n$st');
    return [];
  }
});

class OrgStructureMutator {
  final Ref ref;
  OrgStructureMutator(this.ref);

  Future<void> upsertDepartment({
    String? id,
    required String name,
    required bool isActive,
  }) async {
    final data = {
      'name': name,
      'is_active': isActive,
    };
    if (id != null) {
      await supabase.from('departments').update(data).eq('id', id);
    } else {
      data['id'] = const Uuid().v4();
      await supabase.from('departments').insert(data);
    }
    ref.invalidate(departmentsProvider);
    ref.invalidate(allDepartmentsProvider);
  }

  Future<void> upsertJobPosition({
    String? id,
    required String name,
    required List<String> departmentIds,
    required bool isActive,
  }) async {
    final data = {
      'name': name,
      'department_ids': departmentIds,
      'is_active': isActive,
    };
    if (id != null) {
      await supabase.from('job_positions').update(data).eq('id', id);
    } else {
      data['id'] = const Uuid().v4();
      await supabase.from('job_positions').insert(data);
    }
    ref.invalidate(jobPositionsProvider);
    ref.invalidate(allJobPositionsProvider);
  }
}

final orgStructureMutatorProvider = Provider<OrgStructureMutator>((ref) {
  return OrgStructureMutator(ref);
});
