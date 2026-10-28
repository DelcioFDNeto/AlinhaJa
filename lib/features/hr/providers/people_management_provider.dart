import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/beneficio_model.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/models/holerite_model.dart';
import 'package:alinha_ja/features/hr/models/ponto_model.dart';
import 'package:alinha_ja/features/hr/services/people_management_service.dart';

/// Fase 8 — Providers da Gestão de Pessoas (Ponto, Holerites,
/// Benefícios, Desempenho, Histórico salarial e Dependentes).
final peopleManagementServiceProvider =
    Provider<PeopleManagementService>((ref) => PeopleManagementService());

/// Funcionários ativos (id + nome) para seletores.
final funcionariosLiteProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(peopleManagementServiceProvider).fetchFuncionariosLite();
});

// ── Ponto ────────────────────────────────────────────────────

class PontoFilters {
  final String? funcionarioId;
  final DateTime de;
  final DateTime ate;
  const PontoFilters({this.funcionarioId, required this.de, required this.ate});

  @override
  bool operator ==(Object other) =>
      other is PontoFilters &&
      other.funcionarioId == funcionarioId &&
      other.de == de &&
      other.ate == ate;

  @override
  int get hashCode => Object.hash(funcionarioId, de, ate);
}

final pontoRegistrosProvider = FutureProvider.autoDispose
    .family<List<PontoRegistroModel>, PontoFilters>((ref, f) {
  return ref.watch(peopleManagementServiceProvider).fetchPontoRegistros(
      funcionarioId: f.funcionarioId, de: f.de, ate: f.ate);
});

// ── Holerites ────────────────────────────────────────────────

class HoleriteFilters {
  final String? funcionarioId;
  final int? ano;
  const HoleriteFilters({this.funcionarioId, this.ano});

  @override
  bool operator ==(Object other) =>
      other is HoleriteFilters &&
      other.funcionarioId == funcionarioId &&
      other.ano == ano;

  @override
  int get hashCode => Object.hash(funcionarioId, ano);
}

final holeritesProvider = FutureProvider.autoDispose
    .family<List<HoleriteModel>, HoleriteFilters>((ref, f) {
  return ref
      .watch(peopleManagementServiceProvider)
      .fetchHolerites(funcionarioId: f.funcionarioId, ano: f.ano);
});

// ── Benefícios ───────────────────────────────────────────────

final beneficiosProvider =
    FutureProvider.autoDispose<List<BeneficioModel>>((ref) {
  return ref.watch(peopleManagementServiceProvider).fetchBeneficios();
});

final adesoesProvider = FutureProvider.autoDispose
    .family<List<BeneficioAdesao>, String?>((ref, funcionarioId) {
  return ref
      .watch(peopleManagementServiceProvider)
      .fetchAdesoes(funcionarioId: funcionarioId);
});

// ── Desempenho ───────────────────────────────────────────────

final avaliacoesDesempenhoProvider = FutureProvider.autoDispose
    .family<List<AvaliacaoDesempenhoModel>, String?>((ref, funcionarioId) {
  return ref
      .watch(peopleManagementServiceProvider)
      .fetchAvaliacoes(funcionarioId: funcionarioId);
});

// ── Ficha do funcionário ─────────────────────────────────────

final historicoSalarialProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, funcionarioId) {
  return ref
      .watch(peopleManagementServiceProvider)
      .fetchHistoricoSalarial(funcionarioId);
});

final dependentesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, funcionarioId) {
  return ref
      .watch(peopleManagementServiceProvider)
      .fetchDependentes(funcionarioId);
});
