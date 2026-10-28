import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/onboarding_model.dart';
import 'package:alinha_ja/features/hr/providers/meus_documentos_provider.dart';
import 'package:alinha_ja/features/hr/services/onboarding_service.dart';

final onboardingServiceProvider =
    Provider<OnboardingService>((_) => const OnboardingService());

// ── Templates ──────────────────────────────────────────────

final onboardingTemplatesProvider =
    FutureProvider.autoDispose<List<OnboardingTemplate>>((ref) {
  return ref.watch(onboardingServiceProvider).fetchTemplates();
});

final onboardingTemplateItemsProvider = FutureProvider.autoDispose
    .family<List<OnboardingTemplateItem>, String>((ref, templateId) {
  return ref.watch(onboardingServiceProvider).fetchTemplateItems(templateId);
});

// ── Execução de onboarding ─────────────────────────────────

final onboardingExecucaoProvider = FutureProvider.autoDispose
    .family<OnboardingExecucao?, String>((ref, funcionarioId) {
  return ref.watch(onboardingServiceProvider).fetchExecucaoAtiva(funcionarioId);
});

final onboardingItemsProvider = FutureProvider.autoDispose
    .family<List<OnboardingItem>, String>((ref, execucaoId) {
  return ref.watch(onboardingServiceProvider).fetchItens(execucaoId);
});

// ── Self-service do funcionário (RH-25) ────────────────────

/// Onboarding em andamento do usuário logado (`null` sem vínculo ou sem
/// onboarding). A leitura é liberada pelas policies do RH-25.
final meuOnboardingProvider =
    FutureProvider.autoDispose<OnboardingExecucao?>((ref) async {
  final funcionarioId = await ref.watch(meuFuncionarioIdProvider.future);
  if (funcionarioId == null) return null;
  return ref.watch(onboardingServiceProvider).fetchExecucaoAtiva(funcionarioId);
});

/// Itens do próprio onboarding, já em ordem.
final meusOnboardingItensProvider =
    FutureProvider.autoDispose<List<OnboardingItem>>((ref) async {
  final exec = await ref.watch(meuOnboardingProvider.future);
  if (exec == null) return const [];
  return ref.watch(onboardingServiceProvider).fetchItens(exec.id);
});

// ── Período de Experiência ─────────────────────────────────

final periodoExperienciaProvider = FutureProvider.autoDispose
    .family<PeriodoExperiencia?, String>((ref, funcionarioId) {
  return ref.watch(onboardingServiceProvider).fetchExperiencia(funcionarioId);
});

// ── Feed de Alertas do RH ──────────────────────────────────

final rhAlertasProvider = FutureProvider.autoDispose<List<RhAlerta>>((ref) {
  return ref.watch(onboardingServiceProvider).fetchAlertas();
});

final rhAlertasNaoLidosProvider = FutureProvider.autoDispose<List<RhAlerta>>((ref) {
  return ref.watch(onboardingServiceProvider).fetchAlertas(apenasNaoLidos: true);
});

final rhAlertasCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(onboardingServiceProvider).countAlertasNaoLidos();
});
