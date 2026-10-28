import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/avaliacao_model.dart';
import 'package:alinha_ja/features/hr/services/avaliacao_service.dart';

final avaliacaoServiceProvider =
    Provider<AvaliacaoService>((_) => const AvaliacaoService());

/// Banco de questões, opcionalmente filtrado por cargo (`null` = todas).
final questoesProvider = FutureProvider.autoDispose
    .family<List<QuestaoModel>, String?>((ref, cargoId) {
  return ref.watch(avaliacaoServiceProvider).fetchQuestoes(cargoId: cargoId);
});

/// RH-23 — quantidade de questões e tempo limite da prova, por org.
final avaliacaoConfigProvider =
    FutureProvider.autoDispose<AvaliacaoConfig>((ref) {
  return ref.watch(avaliacaoServiceProvider).fetchConfig();
});

/// Avaliações finalizadas de um candidato (ficha).
final avaliacoesCandidatoProvider = FutureProvider.autoDispose
    .family<List<AvaliacaoResumo>, String>((ref, candidatoId) {
  return ref
      .watch(avaliacaoServiceProvider)
      .fetchAvaliacoesCandidato(candidatoId);
});
