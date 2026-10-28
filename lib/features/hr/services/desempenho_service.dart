import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';

/// RH-27 / Fase 8 — ciclos de avaliação, metas e feedback 360.
///
/// Leituras vão direto nas tabelas/views (a RLS decide o alcance).
/// Toda escrita sensível passa por RPC: convidar avaliador, responder
/// 360 e atualizar progresso de meta têm regra de negócio no servidor.
class DesempenhoService {
  const DesempenhoService();

  // ── Ciclos ──────────────────────────────────────────────────

  Future<List<CicloAvaliacao>> fetchCiclos() async {
    final data = await supabase
        .from('rh_ciclo_avaliacao')
        .select()
        .isFilter('deleted_at', null)
        .order('periodo_inicio', ascending: false);
    return (data as List)
        .map((e) => CicloAvaliacao.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> salvarCiclo({
    String? id,
    required String nome,
    String? descricao,
    required DateTime periodoInicio,
    required DateTime periodoFim,
    DateTime? prazoResposta,
    required bool usaAuto,
    required bool usaGestor,
    required bool usaPares,
    required bool usaSubordinado,
    int minParesAnonimato = 3,
  }) async {
    String d(DateTime v) => v.toIso8601String().split('T').first;
    final dados = {
      'nome': nome.trim(),
      'descricao': descricao?.trim(),
      'periodo_inicio': d(periodoInicio),
      'periodo_fim': d(periodoFim),
      'prazo_resposta': prazoResposta == null ? null : d(prazoResposta),
      'usa_auto': usaAuto,
      'usa_gestor': usaGestor,
      'usa_pares': usaPares,
      'usa_subordinado': usaSubordinado,
      'min_pares_anonimato': minParesAnonimato,
    };

    if (id == null) {
      final row = await supabase
          .from('rh_ciclo_avaliacao')
          .insert({...dados, 'created_by': supabase.auth.currentUser!.id})
          .select('id')
          .single();
      return row['id'] as String;
    }
    await supabase.from('rh_ciclo_avaliacao').update(dados).eq('id', id);
    return id;
  }

  /// `rascunho` → `aberto` → `encerrado`.
  Future<void> mudarStatusCiclo(String id, String status) async {
    await supabase
        .from('rh_ciclo_avaliacao')
        .update({'status': status}).eq('id', id);
  }

  Future<void> excluirCiclo(String id) async {
    await supabase.from('rh_ciclo_avaliacao').update(
        {'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  // ── Metas ───────────────────────────────────────────────────

  Future<List<MetaModel>> fetchMetas({
    String? cicloId,
    String? funcionarioId,
  }) async {
    var query =
        supabase.from('rh_meta').select('*, funcionario(nome)');
    if (cicloId != null) query = query.eq('ciclo_id', cicloId);
    if (funcionarioId != null) query = query.eq('funcionario_id', funcionarioId);
    final data = await query.order('created_at');
    return (data as List)
        .map((e) => MetaModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> salvarMeta({
    String? id,
    required String cicloId,
    required String funcionarioId,
    required String titulo,
    String? descricao,
    String? metrica,
    String? alvo,
    int peso = 1,
    DateTime? prazo,
  }) async {
    final dados = {
      'ciclo_id': cicloId,
      'funcionario_id': funcionarioId,
      'titulo': titulo.trim(),
      'descricao': descricao?.trim(),
      'metrica': metrica?.trim(),
      'alvo': alvo?.trim(),
      'peso': peso,
      'prazo': prazo?.toIso8601String().split('T').first,
    };
    if (id == null) {
      await supabase.from('rh_meta').insert(
          {...dados, 'created_by': supabase.auth.currentUser!.id});
    } else {
      await supabase.from('rh_meta').update(dados).eq('id', id);
    }
  }

  /// Atualiza o andamento. Vale para o RH e para o dono da meta — quem
  /// decide é a RPC.
  Future<void> atualizarProgresso(String metaId, int progresso,
      {String? resultado}) async {
    await supabase.rpc('rh_meta_progresso', params: {
      'p_meta_id': metaId,
      'p_progresso': progresso,
      'p_resultado': resultado,
    });
  }

  Future<void> excluirMeta(String id) async {
    await supabase.from('rh_meta').delete().eq('id', id);
  }

  // ── Avaliação 360 ───────────────────────────────────────────

  /// RH convida alguém para avaliar. Idempotente: repetir o mesmo trio
  /// devolve o convite existente em vez de duplicar.
  Future<String> convidar({
    required String cicloId,
    required String avaliadoId,
    required String avaliadorUserId,
    required String origem,
  }) async {
    final id = await supabase.rpc('rh_360_convidar', params: {
      'p_ciclo_id': cicloId,
      'p_avaliado_id': avaliadoId,
      'p_avaliador_id': avaliadorUserId,
      'p_origem': origem,
    });
    return id as String;
  }

  /// Convites do usuário logado (o que ele precisa responder).
  Future<List<Convite360>> fetchMeusConvites() async {
    final data = await supabase
        .from('rh_minhas_avaliacoes_360')
        .select()
        .order('status')
        .order('prazo_resposta', nullsFirst: false);
    return (data as List)
        .map((e) => Convite360.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> responder({
    required String avaliacaoId,
    required int nota,
    String? pontosFortes,
    String? pontosMelhoria,
  }) async {
    await supabase.rpc('rh_360_responder', params: {
      'p_avaliacao_id': avaliacaoId,
      'p_nota': nota,
      'p_pontos_fortes': pontosFortes,
      'p_pontos_melhoria': pontosMelhoria,
    });
  }

  /// Consolidado do ciclo — visão do RH.
  Future<List<DesempenhoConsolidado>> fetchConsolidado(String cicloId) async {
    final data = await supabase
        .from('rh_desempenho_consolidado')
        .select()
        .eq('ciclo_id', cicloId)
        .order('avaliado_nome');
    return (data as List)
        .map((e) => DesempenhoConsolidado.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Resultado do próprio avaliado, já anonimizado pelo servidor.
  Future<MeuResultado360?> fetchMeuResultado(String cicloId) async {
    final data =
        await supabase.rpc('rh_meu_resultado_360', params: {'p_ciclo_id': cicloId});
    final linha = (data as List?)?.firstOrNull;
    if (linha == null) return null;
    return MeuResultado360.fromMap(Map<String, dynamic>.from(linha as Map));
  }
}
