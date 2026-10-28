import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/onboarding_model.dart';

/// RH-5 — Onboarding e Período de Experiência.
/// Templates e execução via tabelas com RLS de RH; ações de estado
/// (iniciar/concluir/decidir) via RPCs SECURITY DEFINER.
class OnboardingService {
  const OnboardingService();

  Future<String> _orgId() async {
    final me = await supabase
        .from('users')
        .select('organization_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();
    return me['organization_id'] as String;
  }

  // ── Templates ──────────────────────────────────────────────
  Future<List<OnboardingTemplate>> fetchTemplates() async {
    final data = await supabase
        .from('onboarding_template')
        .select('*, onboarding_template_item(id)')
        .isFilter('deleted_at', null)
        .order('padrao', ascending: false)
        .order('nome');
    return (data as List)
        .map((e) => OnboardingTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<OnboardingTemplateItem>> fetchTemplateItems(
      String templateId) async {
    final data = await supabase
        .from('onboarding_template_item')
        .select()
        .eq('template_id', templateId)
        .order('ordem');
    return (data as List)
        .map((e) => OnboardingTemplateItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cria/edita um template e substitui seus itens numa única passada.
  Future<String> saveTemplate({
    String? id,
    required String nome,
    String? descricao,
    required bool ativo,
    required bool padrao,
    required List<OnboardingTemplateItem> itens,
  }) async {
    final org = await _orgId();
    final uid = supabase.auth.currentUser!.id;

    String templateId;
    if (id == null) {
      final row = await supabase
          .from('onboarding_template')
          .insert({
            'organization_id': org,
            'nome': nome,
            'descricao': descricao,
            'ativo': ativo,
            'padrao': padrao,
            'created_by': uid,
          })
          .select('id')
          .single();
      templateId = row['id'] as String;
    } else {
      await supabase.from('onboarding_template').update({
        'nome': nome,
        'descricao': descricao,
        'ativo': ativo,
        'padrao': padrao,
      }).eq('id', id);
      templateId = id;
      await supabase
          .from('onboarding_template_item')
          .delete()
          .eq('template_id', templateId);
    }

    if (itens.isNotEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < itens.length; i++) {
        final it = itens[i];
        rows.add(OnboardingTemplateItem(
          ordem: i,
          titulo: it.titulo,
          descricao: it.descricao,
          categoria: it.categoria,
          obrigatorio: it.obrigatorio,
          prazoDias: it.prazoDias,
          responsavel: it.responsavel,
        ).toInsert(templateId, org));
      }
      await supabase.from('onboarding_template_item').insert(rows);
    }
    return templateId;
  }

  Future<void> deleteTemplate(String id) async {
    await supabase.from('onboarding_template').update(
        {'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }

  // ── Execução de onboarding ─────────────────────────────────
  Future<OnboardingExecucao?> fetchExecucaoAtiva(String funcionarioId) async {
    final data = await supabase
        .from('onboarding_execucao')
        .select()
        .eq('funcionario_id', funcionarioId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data == null ? null : OnboardingExecucao.fromJson(data);
  }

  Future<List<OnboardingItem>> fetchItens(String execucaoId) async {
    final data = await supabase
        .from('onboarding_item')
        .select()
        .eq('execucao_id', execucaoId)
        .order('ordem');
    return (data as List)
        .map((e) => OnboardingItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> iniciarOnboarding(
      String funcionarioId, String templateId) async {
    final id = await supabase.rpc('rh_iniciar_onboarding', params: {
      'p_funcionario_id': funcionarioId,
      'p_template_id': templateId,
    });
    return id as String;
  }

  Future<void> atualizarItem(String itemId, String status,
      {String? observacao}) async {
    await supabase.rpc('rh_atualizar_item_onboarding', params: {
      'p_item_id': itemId,
      'p_status': status,
      'p_observacao': observacao,
    });
  }

  Future<void> concluirOnboarding(String execucaoId) async {
    await supabase.rpc('rh_concluir_onboarding',
        params: {'p_execucao_id': execucaoId});
  }

  /// Anexa um documento a um item do checklist e o conclui (S092/RH-6.9).
  /// Sobe o arquivo para o bucket rh-documentos (pasta <funcionario_id>/) e
  /// chama a RPC, que cria a linha no repositório (rh_documento), vincula ao
  /// item (documento_id) e marca o item como concluído numa transação.
  /// Retorna o id do documento criado.
  Future<String> anexarDocumentoAoItem({
    required String itemId,
    required String funcionarioId,
    required Uint8List bytes,
    required String fileName,
    required String titulo,
    String categoria = 'outro',
    DateTime? dataVencimento,
  }) async {
    final ext = fileName.toLowerCase().endsWith('.docx')
        ? 'docx'
        : fileName.toLowerCase().endsWith('.png')
            ? 'png'
            : fileName.toLowerCase().endsWith('.jpg') ||
                    fileName.toLowerCase().endsWith('.jpeg')
                ? 'jpg'
                : 'pdf';
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'docx'
            ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            : ext == 'png'
                ? 'image/png'
                : 'image/jpeg';

    final path =
        '$funcionarioId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supabase.storage.from('rh-documentos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );

    final docId = await supabase.rpc('rh_anexar_documento_onboarding', params: {
      'p_item_id': itemId,
      'p_storage_path': path,
      'p_titulo': titulo,
      'p_categoria': categoria,
      'p_data_vencimento':
          dataVencimento?.toIso8601String().split('T').first,
    });
    return docId as String;
  }

  // ── Self-service do funcionário (RH-25) ────────────────────

  /// Conclui (ou reabre) um item do próprio checklist. Só passa em itens
  /// com `responsavel = 'funcionario'` — a RPC valida o vínculo e o dono.
  Future<void> concluirMeuItem(
    String itemId, {
    required bool concluido,
    String? observacao,
  }) async {
    await supabase.rpc('rh_meu_item_onboarding', params: {
      'p_item_id': itemId,
      'p_concluido': concluido,
      'p_observacao': observacao,
    });
  }

  // ── Período de experiência ─────────────────────────────────
  Future<PeriodoExperiencia?> fetchExperiencia(String funcionarioId) async {
    final data = await supabase
        .from('periodo_experiencia')
        .select()
        .eq('funcionario_id', funcionarioId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data == null ? null : PeriodoExperiencia.fromJson(data);
  }

  Future<String> iniciarExperiencia(String funcionarioId,
      {DateTime? dataInicio}) async {
    final id = await supabase.rpc('rh_iniciar_experiencia', params: {
      'p_funcionario_id': funcionarioId,
      'p_data_inicio': dataInicio?.toIso8601String().split('T').first,
    });
    return id as String;
  }

  /// decisao: efetivar | prorrogar | desligar.
  Future<void> decidirExperiencia(String periodoId, String decisao,
      {String? observacao}) async {
    await supabase.rpc('rh_decidir_experiencia', params: {
      'p_periodo_id': periodoId,
      'p_decisao': decisao,
      'p_observacao': observacao,
    });
  }

  // ── Feed de alertas ────────────────────────────────────────
  Future<List<RhAlerta>> fetchAlertas({bool apenasNaoLidos = false}) async {
    var query = supabase.from('rh_alerta').select();
    if (apenasNaoLidos) query = query.eq('lido', false);
    final data = await query.order('created_at', ascending: false).limit(100);
    return (data as List)
        .map((e) => RhAlerta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> countAlertasNaoLidos() async {
    final data =
        await supabase.from('rh_alerta').select('id').eq('lido', false);
    return (data as List).length;
  }

  Future<void> marcarAlertaLido(String alertaId) async {
    await supabase
        .rpc('rh_marcar_alerta_lido', params: {'p_alerta_id': alertaId});
  }
}
