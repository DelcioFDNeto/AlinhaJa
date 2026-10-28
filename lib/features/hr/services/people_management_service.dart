import 'dart:typed_data';

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/beneficio_model.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/models/holerite_model.dart';
import 'package:alinha_ja/features/hr/models/ponto_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

/// Fase 8 — Gestão de Pessoas (Ponto, Holerites, Benefícios, Desempenho,
/// Histórico salarial e Dependentes). Tudo sobre as tabelas da rh21 com as
/// RPCs cifradas da rh22; valores sensíveis nunca são cifrados/decifrados
/// no cliente.
class PeopleManagementService {
  /// Funcionários ativos (id + nome) para dropdowns/seletores.
  Future<List<Map<String, dynamic>>> fetchFuncionariosLite() async {
    final res = await supabase
        .from('funcionario')
        .select('id, nome, user_id')
        .isFilter('deleted_at', null)
        .order('nome');
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Ponto eletrônico ─────────────────────────────────────────

  Future<List<PontoRegistroModel>> fetchPontoRegistros({
    String? funcionarioId,
    required DateTime de,
    required DateTime ate,
  }) async {
    var query = supabase
        .from('rh_ponto_registro')
        .select('*, funcionario(nome)')
        .gte('data_hora', de.toUtc().toIso8601String())
        .lt('data_hora',
            ate.add(const Duration(days: 1)).toUtc().toIso8601String());
    if (funcionarioId != null) {
      query = query.eq('funcionario_id', funcionarioId);
    }
    final res = await query.order('data_hora', ascending: false);
    return (res as List)
        .map((e) => PontoRegistroModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Batida do próprio colaborador (policy de INSERT own no banco).
  Future<void> registrarPonto({
    required String funcionarioId,
    required String tipo,
    String? dispositivoInfo,
  }) async {
    await supabase.from('rh_ponto_registro').insert({
      'funcionario_id': funcionarioId,
      'data_hora': DateTime.now().toUtc().toIso8601String(),
      'tipo': tipo,
      'origem': 'app',
      'dispositivo_info': dispositivoInfo,
    });
  }

  /// Lançamento manual do RH (ajuste/importação de REP).
  Future<void> lancarPontoManual({
    required String funcionarioId,
    required DateTime dataHora,
    required String tipo,
  }) async {
    await supabase.from('rh_ponto_registro').insert({
      'funcionario_id': funcionarioId,
      'data_hora': dataHora.toUtc().toIso8601String(),
      'tipo': tipo,
      'origem': 'importacao',
    });
  }

  Future<void> atualizarStatusPonto(String id, String status) async {
    await supabase
        .from('rh_ponto_registro')
        .update({'status': status}).eq('id', id);
  }

  // ── Holerites ────────────────────────────────────────────────

  Future<List<HoleriteModel>> fetchHolerites({
    String? funcionarioId,
    int? ano,
  }) async {
    var query = supabase.from('rh_holerite').select('*, funcionario(nome)');
    if (funcionarioId != null) {
      query = query.eq('funcionario_id', funcionarioId);
    }
    if (ano != null) query = query.eq('ano_referencia', ano);
    final res = await query
        .order('ano_referencia', ascending: false)
        .order('mes_referencia', ascending: false);
    return (res as List)
        .map((e) => HoleriteModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Upload do PDF + registro. Path: holerites/{funcionarioId}/{arquivo}
  /// (a policy da rh22 libera o SELECT do próprio colaborador nesse prefixo).
  Future<void> uploadHolerite({
    required String funcionarioId,
    required int mes,
    required int ano,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName =
        '${ano}_${mes.toString().padLeft(2, '0')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final path = 'holerites/$funcionarioId/$safeName';
    await supabase.storage.from('rh-documentos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );
    await supabase.from('rh_holerite').insert({
      'funcionario_id': funcionarioId,
      'mes_referencia': mes,
      'ano_referencia': ano,
      'arquivo_pdf_path': path,
    });
  }

  Future<void> deleteHolerite(HoleriteModel h) async {
    if (h.arquivoPdfPath != null) {
      await supabase.storage.from('rh-documentos').remove([h.arquivoPdfPath!]);
    }
    await supabase.from('rh_holerite').delete().eq('id', h.id);
  }

  /// URL temporária para abrir o PDF (funciona para RH e para o próprio
  /// colaborador, conforme as policies do bucket).
  Future<String> holeriteSignedUrl(String path) {
    return supabase.storage.from('rh-documentos').createSignedUrl(path, 300);
  }

  /// Carimbo de leitura quando o colaborador abre o próprio holerite.
  Future<void> marcarHoleriteVisualizado(String id) async {
    await supabase.from('rh_holerite').update({
      'data_visualizacao': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).isFilter('data_visualizacao', null);
  }

  // ── Benefícios ───────────────────────────────────────────────

  Future<List<BeneficioModel>> fetchBeneficios({bool somenteAtivos = false}) async {
    var query = supabase.from('rh_beneficio').select();
    if (somenteAtivos) query = query.eq('ativo', true);
    final res = await query.order('nome');
    return (res as List)
        .map((e) => BeneficioModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> createBeneficio({
    required String nome,
    required String tipo,
    String? fornecedor,
  }) async {
    await supabase.from('rh_beneficio').insert({
      'nome': nome,
      'tipo': tipo,
      'fornecedor': fornecedor,
    });
  }

  Future<void> updateBeneficio(
    String id, {
    String? nome,
    String? tipo,
    String? fornecedor,
    bool? ativo,
  }) async {
    await supabase.from('rh_beneficio').update({
      if (nome != null) 'nome': nome,
      if (tipo != null) 'tipo': tipo,
      if (fornecedor != null) 'fornecedor': fornecedor,
      if (ativo != null) 'ativo': ativo,
    }).eq('id', id);
  }

  Future<List<BeneficioAdesao>> fetchAdesoes({String? funcionarioId}) async {
    final res = await supabase.rpc('rh_list_adesoes_beneficio', params: {
      'p_funcionario_id': funcionarioId,
    });
    return (res as List)
        .map((e) => BeneficioAdesao.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> addAdesao({
    required String funcionarioId,
    required String beneficioId,
    required DateTime dataAdesao,
    String? valorDesconto,
  }) async {
    await supabase.rpc('rh_add_adesao_beneficio', params: {
      'p_funcionario_id': funcionarioId,
      'p_beneficio_id': beneficioId,
      'p_data_adesao': dataAdesao.toIso8601String().split('T').first,
      'p_valor_desconto': valorDesconto,
    });
  }

  Future<void> cancelarAdesao(String id) async {
    await supabase.from('rh_funcionario_beneficio').update({
      'data_cancelamento': DateTime.now().toIso8601String().split('T').first,
    }).eq('id', id);
  }

  // ── Avaliação de desempenho ──────────────────────────────────

  Future<List<AvaliacaoDesempenhoModel>> fetchAvaliacoes({
    String? funcionarioId,
  }) async {
    var query =
        supabase.from('rh_avaliacao_desempenho').select('*, funcionario(nome)');
    if (funcionarioId != null) {
      query = query.eq('funcionario_id', funcionarioId);
    }
    final res = await query.order('data_avaliacao', ascending: false);
    return (res as List)
        .map((e) =>
            AvaliacaoDesempenhoModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> createAvaliacao({
    required String funcionarioId,
    required String tipo,
    required DateTime dataAvaliacao,
    double? pontuacao,
    String? feedback,
  }) async {
    await supabase.from('rh_avaliacao_desempenho').insert({
      'funcionario_id': funcionarioId,
      'avaliador_id': supabase.auth.currentUser?.id,
      'tipo': tipo,
      'data_avaliacao': dataAvaliacao.toIso8601String().split('T').first,
      'pontuacao_geral': pontuacao,
      'feedback_texto': feedback,
    });
  }

  Future<void> deleteAvaliacao(String id) async {
    await supabase.from('rh_avaliacao_desempenho').delete().eq('id', id);
  }

  // ── Histórico de cargos e salários (ficha do funcionário) ────

  Future<List<Map<String, dynamic>>> fetchHistoricoSalarial(
      String funcionarioId) async {
    final res = await supabase.rpc('rh_get_historico_cargo_salario', params: {
      'p_funcionario_id': funcionarioId,
    });
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> addHistoricoSalarial({
    required String funcionarioId,
    required String salario,
    required DateTime dataInicio,
    required String motivo,
    String? cargoId,
    String? departamentoId,
  }) async {
    await supabase.rpc('rh_add_historico_cargo_salario', params: {
      'p_funcionario_id': funcionarioId,
      'p_salario': salario,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_motivo': motivo,
      'p_cargo_id': cargoId,
      'p_departamento_id': departamentoId,
    });
  }

  Future<void> deleteHistoricoSalarial(String id) async {
    await supabase.from('rh_historico_cargo_salario').delete().eq('id', id);
  }

  // ── Dependentes (ficha do funcionário) ───────────────────────

  Future<List<Map<String, dynamic>>> fetchDependentes(
      String funcionarioId) async {
    final res = await supabase.rpc('rh_list_dependentes', params: {
      'p_funcionario_id': funcionarioId,
    });
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> addDependente({
    required String funcionarioId,
    required String nome,
    required DateTime dataNascimento,
    required String parentesco,
    String? cpf,
  }) async {
    await supabase.rpc('rh_add_dependente', params: {
      'p_funcionario_id': funcionarioId,
      'p_nome': nome,
      'p_data_nascimento': dataNascimento.toIso8601String().split('T').first,
      'p_parentesco': parentesco,
      'p_cpf': cpf,
    });
  }

  Future<void> deleteDependente(String id) async {
    await supabase.from('rh_dependente').delete().eq('id', id);
  }
}
