import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';

/// Filtros da listagem do Banco de Talentos (RH-1.1 / S037).
class TalentFilters {
  final String search;
  final String? status;
  final String? area;
  final String? nivel;
  final String? cidade;
  final String? fonte;

  /// Filtro por vaga (RH-10) — vindo da aba Vagas ("ver candidatos").
  final String? vagaId;

  /// Título da vaga filtrada, só para exibir o chip removível na UI.
  final String? vagaTitulo;

  /// Filtro por responsável (RH-13) — "meus candidatos" na UI.
  final String? responsavelId;

  const TalentFilters({
    this.search = '',
    this.status,
    this.area,
    this.nivel,
    this.cidade,
    this.fonte,
    this.vagaId,
    this.vagaTitulo,
    this.responsavelId,
  });

  /// Há algum recorte aplicado.
  ///
  /// Separa "ninguém se candidatou ainda" de "os filtros atuais não
  /// acharam" — os dois casos pedem telas de vazio diferentes.
  bool get temFiltro =>
      search.trim().isNotEmpty ||
      status != null ||
      area != null ||
      nivel != null ||
      cidade != null ||
      fonte != null ||
      vagaId != null ||
      responsavelId != null;

  TalentFilters copyWith({
    String? search,
    String? Function()? status,
    String? Function()? area,
    String? Function()? nivel,
    String? Function()? cidade,
    String? Function()? fonte,
    String? Function()? vagaId,
    String? Function()? vagaTitulo,
    String? Function()? responsavelId,
  }) =>
      TalentFilters(
        search: search ?? this.search,
        status: status != null ? status() : this.status,
        area: area != null ? area() : this.area,
        nivel: nivel != null ? nivel() : this.nivel,
        cidade: cidade != null ? cidade() : this.cidade,
        fonte: fonte != null ? fonte() : this.fonte,
        vagaId: vagaId != null ? vagaId() : this.vagaId,
        vagaTitulo: vagaTitulo != null ? vagaTitulo() : this.vagaTitulo,
        responsavelId:
            responsavelId != null ? responsavelId() : this.responsavelId,
      );

  bool get hasAny =>
      search.isNotEmpty ||
      status != null ||
      area != null ||
      nivel != null ||
      cidade != null ||
      fonte != null ||
      vagaId != null ||
      responsavelId != null;

  @override
  bool operator ==(Object other) =>
      other is TalentFilters &&
      other.search == search &&
      other.status == status &&
      other.area == area &&
      other.nivel == nivel &&
      other.cidade == cidade &&
      other.fonte == fonte &&
      other.vagaId == vagaId &&
      other.responsavelId == responsavelId;

  @override
  int get hashCode => Object.hash(
      search, status, area, nivel, cidade, fonte, vagaId, responsavelId);
}

class TalentBankService {
  const TalentBankService();

  /// Itens por página (S027).
  static const pageSize = 50;

  /// Lista candidatos com filtros combinados e paginação.
  Future<List<CandidateModel>> fetchCandidates(
      TalentFilters filters, int page) async {
    var query = supabase
        .from('candidato')
        .select('*, responsavel:responsavel_id(full_name)');

    if (filters.status != null) query = query.eq('status', filters.status!);
    if (filters.vagaId != null) query = query.eq('vaga_id', filters.vagaId!);
    if (filters.responsavelId != null) {
      query = query.eq('responsavel_id', filters.responsavelId!);
    }
    if (filters.area != null) query = query.eq('area_interesse', filters.area!);
    if (filters.nivel != null) query = query.eq('nivel', filters.nivel!);
    if (filters.fonte != null) query = query.eq('fonte', filters.fonte!);
    if (filters.cidade != null) {
      query = query.ilike('cidade', filters.cidade!);
    }
    if (filters.search.isNotEmpty) {
      final s = filters.search.replaceAll('%', r'\%');
      query = query.or(
          'nome.ilike.%$s%,email.ilike.%$s%,cargo_pretendido.ilike.%$s%');
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    return (data as List)
        .map((e) => CandidateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Contagem por status para o cabeçalho/dashboard (S041).
  Future<Map<String, int>> fetchStatusCounts() async {
    final data = await supabase
        .from('candidato_contagem_status')
        .select('status, total');
    return {
      for (final row in data as List)
        row['status'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Ficha completa do candidato (RH-1.2).
  Future<CandidateDetail> fetchDetail(String candidatoId) async {
    final results = await Future.wait([
      // Join com a vaga (RH-10) e responsável (RH-13) para a ficha.
      supabase
          .from('candidato')
          .select('*, vaga:vaga_id(titulo), responsavel:responsavel_id(full_name)')
          .eq('id', candidatoId)
          .single(),
      supabase
          .from('candidato_curriculo')
          .select()
          .eq('candidato_id', candidatoId)
          .order('created_at', ascending: false),
      supabase
          .from('candidato_formacao')
          .select()
          .eq('candidato_id', candidatoId),
      supabase
          .from('candidato_experiencia')
          .select()
          .eq('candidato_id', candidatoId)
          .order('data_inicio', ascending: false),
      supabase
          .from('candidato_habilidade')
          .select()
          .eq('candidato_id', candidatoId)
          .order('nome'),
      supabase
          .from('candidato_historico')
          .select('*, users(full_name)')
          .eq('candidato_id', candidatoId)
          .order('created_at', ascending: false),
      supabase
          .from('rh_comunicacao_log')
          .select()
          .eq('candidato_id', candidatoId)
          .order('enviado_em', ascending: false),
    ]);

    List<T> mapList<T>(dynamic data, T Function(Map<String, dynamic>) from) =>
        (data as List).map((e) => from(e as Map<String, dynamic>)).toList();

    return CandidateDetail(
      candidato:
          CandidateModel.fromJson(results[0] as Map<String, dynamic>),
      curriculos: mapList(results[1], CandidateResume.fromJson),
      formacoes: mapList(results[2], CandidateEducation.fromJson),
      experiencias: mapList(results[3], CandidateExperience.fromJson),
      habilidades: mapList(results[4], CandidateSkill.fromJson),
      historico: mapList(results[5], CandidateHistoryEntry.fromJson),
      emails: mapList(results[6], CandidateEmailLog.fromJson),
    );
  }

  /// Cadastro manual pelo RH (RH-1.3), com currículo opcional.
  /// O consentimento LGPD é obrigatório também no fluxo interno (S036).
  Future<String> createCandidate({
    required Map<String, dynamic> fields,
    Uint8List? cvBytes,
    String? cvFileName,
  }) async {
    final me = await supabase
        .from('users')
        .select('organization_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();

    final inserted = await supabase
        .from('candidato')
        .insert({
          ...fields,
          'organization_id': me['organization_id'],
          'created_by': supabase.auth.currentUser!.id,
          'consentimento_lgpd': true,
        })
        .select('id')
        .single();
    final candidatoId = inserted['id'] as String;

    await supabase.from('candidato_historico').insert({
      'candidato_id': candidatoId,
      'acao': 'cadastro',
      'detalhes': {'fonte': fields['fonte'] ?? 'upload_manual'},
      'usuario_id': supabase.auth.currentUser!.id,
    });

    if (cvBytes != null && cvFileName != null) {
      await uploadResume(
          candidatoId: candidatoId, bytes: cvBytes, fileName: cvFileName);
    }
    return candidatoId;
  }

  /// Sobe o currículo para o bucket `rh-curriculos` e registra a linha.
  Future<void> uploadResume({
    required String candidatoId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.toLowerCase().endsWith('.docx') ? 'docx' : 'pdf';
    final path =
        '$candidatoId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

    await supabase.storage.from('rh-curriculos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );

    await supabase.from('candidato_curriculo').insert({
      'candidato_id': candidatoId,
      'arquivo_url': path,
      'tipo_arquivo': ext,
      'tamanho_bytes': bytes.length,
    });
  }

  /// URL assinada temporária para abrir/baixar o currículo.
  Future<String> signedResumeUrl(String path) =>
      supabase.storage.from('rh-curriculos').createSignedUrl(path, 900);

  /// Reprocessa manualmente um currículo via IA.
  Future<void> retryExtraction(String curriculoId) async {
    await supabase.rpc('retry_cv_extraction', params: {'p_curriculo_id': curriculoId});
  }

  /// Último erro de extração registrado em ia_usage_log para o candidato.
  /// Retorna null quando não há falha registrada (ou sem permissão de leitura).
  Future<String?> lastExtractionError(String candidatoId) async {
    try {
      final data = await supabase
          .from('ia_usage_log')
          .select('erro, modelo')
          .eq('candidato_id', candidatoId)
          .eq('funcao', 'rh-extract-cv')
          .eq('sucesso', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return data?['erro'] as String?;
    } catch (_) {
      return null; // RLS pode negar para não-admins — falha silenciosa
    }
  }

  /// Muda o status; o trigger do banco valida a transição e grava histórico.
  Future<void> updateStatus(String candidatoId, String status) async {
    await supabase.from('candidato').update({
      'status': status,
      'updated_by': supabase.auth.currentUser!.id,
    }).eq('id', candidatoId);
  }

  // ── RH-13 — Pipeline avançado: responsável + ações em massa ─

  /// Atribui (ou remove, com null) o responsável de vários candidatos.
  /// Retorna quantos foram atualizados. Guard e org validados na RPC.
  Future<int> atribuirResponsavel(
      List<String> ids, String? responsavelId) async {
    final n = await supabase.rpc('rh_atribuir_responsavel', params: {
      'p_ids': ids,
      'p_responsavel': responsavelId,
    });
    return (n as num?)?.toInt() ?? 0;
  }

  /// Move vários candidatos para [status] (o trigger valida cada transição).
  /// Aplica um a um para tolerar falhas parciais; retorna quantos avançaram.
  Future<int> bulkUpdateStatus(List<String> ids, String status) async {
    var ok = 0;
    for (final id in ids) {
      try {
        await updateStatus(id, status);
        ok++;
      } catch (_) {
        // Transição inválida para este candidato — ignora e segue.
      }
    }
    return ok;
  }

  /// Usuários da org (id + nome) para o seletor de responsável.
  Future<List<Map<String, dynamic>>> fetchOrgUsers() async {
    final data = await supabase
        .from('org_users_vinculaveis')
        .select('id, full_name, email')
        .order('full_name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── RH-14 — Etapas customizáveis do pipeline ────────────────

  /// Etapas do funil da org (RLS filtra). Vazio = org usa o padrão.
  Future<List<Map<String, dynamic>>> fetchPipelineEtapas() async {
    final data =
        await supabase.from('pipeline_etapa').select().order('ordem');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Semeia o funil padrão para a org (idempotente; guard admin RH na RPC).
  /// Necessário antes da primeira personalização em orgs novas.
  Future<void> seedPipelinePadrao() async {
    await supabase.rpc('rh_pipeline_seed_padrao');
  }

  /// Cria etapa intermediária (tipo 'normal'); org carimbada por trigger.
  Future<void> createPipelineEtapa({
    required String slug,
    required String nome,
    required int ordem,
    required String roleCor,
  }) async {
    await supabase.from('pipeline_etapa').insert({
      'slug': slug,
      'nome': nome,
      'ordem': ordem,
      'role_cor': roleCor,
      'created_by': supabase.auth.currentUser!.id,
    });
  }

  /// Renomeia/recolore/reordena uma etapa (slug e tipo são imutáveis).
  Future<void> updatePipelineEtapa(String id,
      {String? nome, String? roleCor, int? ordem}) async {
    await supabase.from('pipeline_etapa').update({
      if (nome != null) 'nome': nome,
      if (roleCor != null) 'role_cor': roleCor,
      if (ordem != null) 'ordem': ordem,
    }).eq('id', id);
  }

  /// Exclui etapa 'normal' sem candidatos (o trigger do banco protege).
  Future<void> deletePipelineEtapa(String id) async {
    await supabase.from('pipeline_etapa').delete().eq('id', id);
  }

  /// Comentário livre no histórico do candidato (RH-1.9).
  Future<void> addComment(String candidatoId, String texto) async {
    await supabase.from('candidato_historico').insert({
      'candidato_id': candidatoId,
      'acao': 'comentario',
      'detalhes': {'texto': texto},
      'usuario_id': supabase.auth.currentUser!.id,
    });
  }

  /// Mensagens trocadas com o candidato (RH-2.8).
  Future<List<Map<String, dynamic>>> listMessages(String candidatoId) async {
    final data = await supabase
        .from('candidato_mensagem')
        .select('autor, texto, anexo_url, anexo_nome, created_at')
        .eq('candidato_id', candidatoId)
        .order('created_at');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// RH envia mensagem ao candidato (aparece na área pública dele).
  Future<void> sendMessageToCandidate(String candidatoId, String texto) async {
    await supabase.from('candidato_mensagem').insert({
      'candidato_id': candidatoId,
      'autor': 'rh',
      'texto': texto,
      'usuario_id': supabase.auth.currentUser!.id,
    });
  }

  /// URL assinada para anexo enviado pelo candidato (bucket rh-documentos).
  Future<String> signedDocumentUrl(String path) =>
      supabase.storage.from('rh-documentos').createSignedUrl(path, 900);

  /// Soft delete (S006) — o registro some das listagens via RLS.
  Future<void> softDelete(String candidatoId) async {
    await supabase.rpc('rh_soft_delete_candidato', params: {
      'p_candidato_id': candidatoId,
    });
  }

  /// Direito ao esquecimento (S010): remove todo PII e apaga os
  /// currículos/documentos do Storage, preservando o id para auditoria.
  /// Irreversível — usar mediante solicitação do titular (LGPD Art. 18).
  Future<void> anonimizarCandidato(String candidatoId) async {
    await supabase.rpc('rh_anonimizar_candidato',
        params: {'p_candidato_id': candidatoId});
  }

  /// Define a política de retenção de candidatos não contratados, em
  /// meses (S011). Aplica-se à organização do usuário logado (admin+).
  Future<void> setRetencaoCandidatos(int meses) async {
    await supabase.rpc('rh_set_retencao_candidatos', params: {'p_meses': meses});
  }

  // ── F1.1 — Central de Recrutamento: divulgação do portal ────

  /// Configuração da página de carreiras da org do usuário
  /// (slug + toggle + textos da mini-landing + retenção LGPD).
  Future<Map<String, dynamic>> fetchPortalConfig() async {
    final me = await supabase
        .from('users')
        .select('organization_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();
    final data = await supabase
        .from('organizations')
        .select(
            'slug, logo_url, carreiras_ativo, carreiras_headline, carreiras_sobre, settings')
        .eq('id', me['organization_id'] as String)
        .single();
    return data;
  }

  /// Liga/desliga a página pública e edita headline/sobre.
  /// Parâmetros null preservam o valor atual (contrato da RPC).
  Future<void> setCarreirasConfig(
      {bool? ativo, String? headline, String? sobre}) async {
    await supabase.rpc('rh_set_carreiras_config', params: {
      'p_ativo': ativo,
      'p_headline': headline,
      'p_sobre': sobre,
    });
  }

  /// Métricas de divulgação (inscrições via portal, conversão).
  /// A view agregada devolve no máximo 1 linha (a org do usuário).
  Future<Map<String, int>> fetchMetricasDivulgacao() async {
    final data = await supabase
        .from('rh_metricas_divulgacao')
        .select('portal_total, portal_30d, portal_em_processo, portal_contratados')
        .maybeSingle();
    return {
      'portal_total': ((data?['portal_total'] ?? 0) as num).toInt(),
      'portal_30d': ((data?['portal_30d'] ?? 0) as num).toInt(),
      'portal_em_processo':
          ((data?['portal_em_processo'] ?? 0) as num).toInt(),
      'portal_contratados':
          ((data?['portal_contratados'] ?? 0) as num).toInt(),
    };
  }
}
