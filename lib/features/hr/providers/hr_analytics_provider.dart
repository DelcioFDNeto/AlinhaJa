import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/services/hr_analytics_service.dart';

final hrAnalyticsServiceProvider =
    Provider<HrAnalyticsService>((_) => const HrAnalyticsService());

final distribuicaoFonteProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchDistribuicaoFonte();
});

final distribuicaoNivelProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchDistribuicaoNivel();
});

final movimentacaoMesProvider =
    FutureProvider.autoDispose<List<MovimentacaoMes>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchMovimentacaoMes();
});

final topTalentosProvider =
    FutureProvider.autoDispose<List<CandidateModel>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchTopTalentos();
});

final distribuicaoAreaProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchDistribuicaoArea();
});

final tempoPipelineProvider =
    FutureProvider.autoDispose<TempoPipeline?>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchTempoPipeline();
});

final headcountStatusProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchHeadcountStatus();
});

final tempoCasaProvider = FutureProvider.autoDispose<TempoCasa?>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchTempoCasa();
});

final aniversariantesProvider =
    FutureProvider.autoDispose<List<Aniversariante>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchAniversariantes();
});

final aniversariantesCasaProvider =
    FutureProvider.autoDispose<List<Aniversariante>>((ref) {
  return ref.watch(hrAnalyticsServiceProvider).fetchAniversariantesCasa();
});
