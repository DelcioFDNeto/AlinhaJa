import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/providers/meus_documentos_provider.dart';
import 'package:alinha_ja/features/hr/services/desempenho_service.dart';

/// RH-27 — ciclos de avaliação, metas e feedback 360.
final desempenhoServiceProvider =
    Provider<DesempenhoService>((_) => const DesempenhoService());

// ── Ciclos ──────────────────────────────────────────────────

final ciclosProvider =
    FutureProvider.autoDispose<List<CicloAvaliacao>>((ref) {
  return ref.watch(desempenhoServiceProvider).fetchCiclos();
});

/// Ciclos que o funcionário pode consultar (abertos ou encerrados —
/// rascunho é invisível fora do RH pela própria RLS).
final ciclosVisiveisProvider =
    FutureProvider.autoDispose<List<CicloAvaliacao>>((ref) async {
  final ciclos = await ref.watch(ciclosProvider.future);
  return ciclos.where((c) => !c.rascunho).toList();
});

// ── Metas ───────────────────────────────────────────────────

/// Metas de um ciclo (todas, visão do RH).
final metasDoCicloProvider = FutureProvider.autoDispose
    .family<List<MetaModel>, String>((ref, cicloId) {
  return ref.watch(desempenhoServiceProvider).fetchMetas(cicloId: cicloId);
});

/// Metas do funcionário logado, de todos os ciclos.
final minhasMetasProvider =
    FutureProvider.autoDispose<List<MetaModel>>((ref) async {
  final funcionarioId = await ref.watch(meuFuncionarioIdProvider.future);
  if (funcionarioId == null) return const [];
  return ref
      .watch(desempenhoServiceProvider)
      .fetchMetas(funcionarioId: funcionarioId);
});

// ── Avaliação 360 ───────────────────────────────────────────

/// Convites de avaliação do usuário logado.
final meusConvites360Provider =
    FutureProvider.autoDispose<List<Convite360>>((ref) {
  return ref.watch(desempenhoServiceProvider).fetchMeusConvites();
});

/// Quantos convites ainda esperam resposta — alimenta o selo da tela.
final convites360PendentesProvider = FutureProvider.autoDispose<int>((ref) async {
  final convites = await ref.watch(meusConvites360Provider.future);
  return convites.where((c) => c.podeResponder).length;
});

/// Consolidado de um ciclo (RH).
final consolidadoCicloProvider = FutureProvider.autoDispose
    .family<List<DesempenhoConsolidado>, String>((ref, cicloId) {
  return ref.watch(desempenhoServiceProvider).fetchConsolidado(cicloId);
});

/// Resultado anonimizado do próprio avaliado num ciclo.
final meuResultado360Provider = FutureProvider.autoDispose
    .family<MeuResultado360?, String>((ref, cicloId) {
  return ref.watch(desempenhoServiceProvider).fetchMeuResultado(cicloId);
});
