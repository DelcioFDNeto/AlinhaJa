import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/avaliacao_model.dart';

/// RH-12 / Fase 3 — banco de questões e resultados de avaliações.
/// Escrita direta em `questao` (RLS exige papel RH; org carimbada por
/// trigger). A geração por IA passa pela Edge Function `rh-gerar-questoes`;
/// a correção das provas é 100% server-side (Edge Function do portal).
class AvaliacaoService {
  const AvaliacaoService();

  // ── Banco de questões ───────────────────────────────────────

  Future<List<QuestaoModel>> fetchQuestoes({String? cargoId}) async {
    var query = supabase
        .from('questao')
        .select('id, cargo_id, area_id, nivel, enunciado, opcoes, correta_idx, origem, ativa')
        .isFilter('deleted_at', null);
    if (cargoId != null) query = query.eq('cargo_id', cargoId);
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((e) => QuestaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createQuestao({
    String? cargoId,
    String? areaId,
    String? nivel,
    required String enunciado,
    required List<String> opcoes,
    required int corretaIdx,
  }) async {
    await supabase.from('questao').insert({
      'cargo_id': cargoId,
      'area_id': areaId,
      'nivel': nivel,
      'enunciado': enunciado.trim(),
      'opcoes': opcoes,
      'correta_idx': corretaIdx,
      'origem': 'manual',
      'created_by': supabase.auth.currentUser!.id,
    });
  }

  Future<void> updateQuestao(
    String id, {
    String? cargoId,
    String? nivel,
    String? enunciado,
    List<String>? opcoes,
    int? corretaIdx,
    bool? ativa,
  }) async {
    await supabase.from('questao').update({
      if (cargoId != null) 'cargo_id': cargoId,
      if (nivel != null) 'nivel': nivel,
      if (enunciado != null) 'enunciado': enunciado.trim(),
      if (opcoes != null) 'opcoes': opcoes,
      if (corretaIdx != null) 'correta_idx': corretaIdx,
      if (ativa != null) 'ativa': ativa,
    }).eq('id', id);
  }

  /// Soft delete (padrão S006 do módulo).
  Future<void> deleteQuestao(String id) async {
    await supabase.from('questao').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Gera questões por IA (Edge Function). Retorna quantas foram criadas.
  Future<int> gerarQuestoesIA({
    required String cargoNome,
    String? cargoId,
    String? areaId,
    String? nivel,
    int quantidade = 5,
  }) async {
    final res = await supabase.functions.invoke('rh-gerar-questoes', body: {
      'cargo_nome': cargoNome,
      'cargo_id': cargoId,
      'area_id': areaId,
      'nivel': nivel,
      'quantidade': quantidade,
    });
    final data = (res.data as Map).cast<String, dynamic>();
    if (data['error'] != null) {
      throw Exception(data['error'] as String);
    }
    return ((data['geradas'] ?? 0) as num).toInt();
  }

  // ── Configuração da prova (RH-23) ───────────────────────────

  /// Quantidade de questões e tempo limite da prova, por org.
  Future<AvaliacaoConfig> fetchConfig() async {
    final data = await supabase.rpc('rh_get_avaliacao_config');
    final linha = (data as List?)?.firstOrNull as Map<String, dynamic>?;
    return AvaliacaoConfig(
      qtd: ((linha?['qtd'] ?? 5) as num).toInt(),
      minutos: ((linha?['minutos'] ?? 0) as num).toInt(),
    );
  }

  /// Salva a configuração. `minutos = 0` remove o limite de tempo.
  Future<void> saveConfig({required int qtd, required int minutos}) async {
    await supabase.rpc('rh_set_avaliacao_config', params: {
      'p_qtd': qtd,
      'p_minutos': minutos,
    });
  }

  // ── Resultados ──────────────────────────────────────────────

  /// Avaliações finalizadas de um candidato (view avaliacao_resumo).
  Future<List<AvaliacaoResumo>> fetchAvaliacoesCandidato(
      String candidatoId) async {
    final data = await supabase
        .from('avaliacao_resumo')
        .select()
        .eq('candidato_id', candidatoId)
        .order('finalizada_em', ascending: false);
    return (data as List)
        .map((e) => AvaliacaoResumo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
