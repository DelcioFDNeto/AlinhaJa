import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/services/vacancy_service.dart';

final vacancyServiceProvider =
    Provider<VacancyService>((_) => const VacancyService());

/// Lista de vagas da org (view vaga_resumo, com contadores).
final vagasProvider = FutureProvider.autoDispose<List<VagaModel>>((ref) {
  return ref.watch(vacancyServiceProvider).fetchVagas();
});

/// Catálogo de áreas (RH-9). `true` = somente ativas (dropdowns).
final areasProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, bool>((ref, somenteAtivas) {
  return ref
      .watch(vacancyServiceProvider)
      .fetchAreas(somenteAtivas: somenteAtivas);
});

/// Catálogo de cargos (RH-9). `true` = somente ativos (dropdowns).
final cargosProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, bool>((ref, somenteAtivos) {
  return ref
      .watch(vacancyServiceProvider)
      .fetchCargos(somenteAtivos: somenteAtivos);
});
