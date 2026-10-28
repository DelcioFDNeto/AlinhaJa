import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/absence_model.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

// ----- Para o RH (Todas as ausências da Org) -----
final hrAbsencesProvider = FutureProvider<List<AbsenceModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];

  final res = await supabase
      .from('rh_ausencia')
      .select('*, funcionario(nome)')
      .order('created_at', ascending: false);

  return (res as List).map((e) {
    final funcNome = e['funcionario']?['nome'];
    return AbsenceModel.fromJson({...e, 'funcionario_nome': funcNome});
  }).toList();
});

/// Funcionário vinculado ao usuário logado (null quando não há vínculo).
final myFuncionarioIdProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
  final res = await supabase
      .from('funcionario')
      .select('id')
      .eq('user_id', user.id)
      .isFilter('deleted_at', null)
      .maybeSingle();
  return res?['id'] as String?;
});

// ----- Para o Funcionário (Minhas Ausências) -----
// Filtra pelo próprio funcionário: para usuários de RH a policy de
// SELECT devolve a org inteira, então confiar só no RLS mostraria
// as ausências de todo mundo em "Minhas Ausências".
final myAbsencesProvider = FutureProvider<List<AbsenceModel>>((ref) async {
  final funcionarioId = await ref.watch(myFuncionarioIdProvider.future);
  if (funcionarioId == null) return [];

  final res = await supabase
      .from('rh_ausencia')
      .select('*, funcionario(nome)')
      .eq('funcionario_id', funcionarioId)
      .order('created_at', ascending: false);

  return (res as List).map((e) {
    final funcNome = e['funcionario']?['nome'];
    return AbsenceModel.fromJson({...e, 'funcionario_nome': funcNome});
  }).toList();
});

// ----- Saldo de férias e calendário (RH-26) -----

/// Saldos de todos os funcionários (visão do RH), do mais antigo para o
/// mais novo — quem vence primeiro aparece primeiro.
final hrFeriasSaldosProvider =
    FutureProvider.autoDispose<List<FeriasSaldo>>((ref) async {
  final res = await supabase
      .from('rh_ferias_saldo')
      .select()
      .order('limite_gozo', ascending: true);
  return (res as List)
      .map((e) => FeriasSaldo.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Saldos do próprio funcionário logado.
final myFeriasSaldosProvider =
    FutureProvider.autoDispose<List<FeriasSaldo>>((ref) async {
  final funcionarioId = await ref.watch(myFuncionarioIdProvider.future);
  if (funcionarioId == null) return const [];
  final res = await supabase
      .from('rh_ferias_saldo')
      .select()
      .eq('funcionario_id', funcionarioId)
      .order('limite_gozo', ascending: true);
  return (res as List)
      .map((e) => FeriasSaldo.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Ausências que tocam o mês de [mes] (usar o dia 1 como chave).
/// A RLS decide o alcance: RH vê a org, funcionário vê as próprias.
final absenceCalendarProvider = FutureProvider.autoDispose
    .family<List<AbsenceCalendarEntry>, DateTime>((ref, mes) async {
  final primeiro = DateTime(mes.year, mes.month, 1);
  final ultimo = DateTime(mes.year, mes.month + 1, 0);
  String iso(DateTime d) => d.toIso8601String().split('T').first;

  // Pega tudo que se sobrepõe ao mês, inclusive períodos que começam
  // antes e terminam depois.
  final res = await supabase
      .from('rh_ausencia_calendario')
      .select()
      .lte('data_inicio', iso(ultimo))
      .gte('data_fim', iso(primeiro))
      .order('data_inicio');
  return (res as List)
      .map((e) => AbsenceCalendarEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});

// Provider para ações (aprovar, rejeitar, criar)
final absenceActionsProvider = Provider((ref) => AbsenceActions(ref));

class AbsenceActions {
  final Ref ref;
  AbsenceActions(this.ref);

  Future<void> create(Map<String, dynamic> data) async {
    final funcionarioId = await ref.read(myFuncionarioIdProvider.future);
    if (funcionarioId == null) {
      throw Exception('Você não está vinculado a um funcionário nesta organização.');
    }

    // organization_id é carimbado pelo trg_force_org no banco.
    await supabase.from('rh_ausencia').insert({
      ...data,
      'funcionario_id': funcionarioId,
    });
    ref.invalidate(myAbsencesProvider);
    ref.invalidate(hrAbsencesProvider);
  }

  /// Aprova a solicitação. Férias passam pela validação de saldo no
  /// servidor (RH-26) e ficam amarradas a um período aquisitivo —
  /// [periodoId] força qual; sem ele, o banco escolhe o que vence antes.
  Future<void> approve(String id, {String? periodoId}) async {
    await supabase.rpc('rh_decidir_ausencia', params: {
      'p_ausencia_id': id,
      'p_aprovar': true,
      'p_periodo_id': periodoId,
    });
    _invalidarTudo();
  }

  Future<void> reject(String id) async {
    await supabase.rpc('rh_decidir_ausencia', params: {
      'p_ausencia_id': id,
      'p_aprovar': false,
    });
    _invalidarTudo();
  }

  /// Abre um novo período aquisitivo. Sem [inicio], encadeia a partir do
  /// último período ou da data de admissão.
  Future<void> abrirPeriodoAquisitivo(String funcionarioId,
      {DateTime? inicio}) async {
    await supabase.rpc('rh_abrir_periodo_aquisitivo', params: {
      'p_funcionario_id': funcionarioId,
      'p_inicio': inicio?.toIso8601String().split('T').first,
    });
    _invalidarTudo();
  }

  /// Abono pecuniário ("venda") de dias do período.
  Future<void> setDiasAbonados(String periodoId, int dias) async {
    await supabase.rpc('rh_set_dias_abonados', params: {
      'p_periodo_id': periodoId,
      'p_dias': dias,
    });
    _invalidarTudo();
  }

  void _invalidarTudo() {
    ref.invalidate(hrAbsencesProvider);
    ref.invalidate(myAbsencesProvider);
    ref.invalidate(hrFeriasSaldosProvider);
    ref.invalidate(myFeriasSaldosProvider);
    ref.invalidate(absenceCalendarProvider);
  }
}
