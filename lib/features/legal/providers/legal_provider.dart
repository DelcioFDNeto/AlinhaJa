import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import '../data/legal_documents.dart';
import '../data/legal_repository.dart';
import '../models/legal_document_model.dart';
import '../models/org_legal_profile.dart';

final legalRepositoryProvider = Provider<LegalRepository>((ref) {
  return LegalRepository(supabase);
});

/// Perfil legal da empresa corrente.
///
/// Resolvido no banco por `fn_current_org()`: acompanha o tenant do usuário e,
/// no produto white label, a empresa em atuação do dono da plataforma.
///
/// **Depende de [currentUserProvider] de propósito.** É esse `watch` que faz o
/// perfil ser refeito quando o dono da plataforma troca de empresa — o switcher
/// invalida o usuário corrente, e a cascata chega até aqui. Sem essa ligação, a
/// troca no celular (que não recarrega o app como na web) deixaria os
/// documentos da Empresa B exibindo a razão social e o Encarregado da Empresa
/// A. Não invalide manualmente em cada tela nova: quem esquecer produz
/// exatamente esse vazamento.
final orgLegalProfileProvider = FutureProvider<OrgLegalProfile>((ref) async {
  await ref.watch(currentUserProvider.future);

  final repo = ref.watch(legalRepositoryProvider);
  final perfil = await repo.fetchLegalProfile();

  // Deployment de empresa única pode herdar o nome da build como último
  // recurso; white label NÃO — ver AppConstants.isSingleTenant.
  //
  // O fallback usa APENAS a constante de build. Já usou `nomeFantasia` do
  // banco, e isso era um vazamento: a linha semeada em
  // `..._fase0_multitenant_organizations.sql` é a mesma nos dois forks e traz o
  // nome da OUTRA empresa. Nome vindo do banco não prova ser desta marca; a
  // constante, sim.
  if (AppConstants.isSingleTenant &&
      (perfil.razaoSocial == null || perfil.razaoSocial!.isEmpty)) {
    return perfil.copyWith(razaoSocial: AppConstants.companyName);
  }
  return perfil;
});

/// Markdown de um documento, já preenchido com os dados do tenant corrente.
///
/// O texto cru vem dos assets; a identidade vem do banco. Placeholder sem valor
/// permanece entre colchetes de propósito — lacuna visível é honesta, lacuna
/// apagada esconde que o documento está incompleto.
final legalDocumentTextProvider =
    FutureProvider.family<String, String>((ref, docId) async {
  final repo = ref.watch(legalRepositoryProvider);
  final bruto = await repo.loadDocumentText(docId);

  // Perfil indisponível não pode tirar o documento do ar: o titular tem direito
  // de ler o texto, e sem os dados ele aparece com os colchetes — degradação
  // visível. O aviso de "documento não personalizado" cobre o resto.
  try {
    final perfil = await ref.watch(orgLegalProfileProvider.future);
    return perfil.apply(bruto);
  } catch (_) {
    return bruto;
  }
});

/// Aceites registrados no servidor para o usuário logado.
final myAcceptancesProvider =
    FutureProvider<List<PolicyAcceptanceRecord>>((ref) async {
  final repo = ref.watch(legalRepositoryProvider);
  return repo.fetchMyAcceptances();
});

/// Documentos obrigatórios ainda pendentes de aceite, na versão vigente.
///
/// Deriva de [myAcceptancesProvider] em vez de consultar o banco por conta
/// própria — e isso não é detalhe: é o que faz `invalidate(myAcceptancesProvider)`
/// derrubar o portão depois do aceite. Quando o provider consultava direto o
/// repositório, aceitar registrava tudo no servidor e a tela de consentimento
/// simplesmente não saía da frente.
///
/// Erro aqui vira estado de erro, que o `PolicyGate` trata liberando o acesso:
/// barrar quem já aceitou por causa de uma consulta que não respondeu é pior do
/// que atrasar o aceite de quem ainda não aceitou.
final pendingPoliciesProvider = FutureProvider<List<LegalDocument>>((ref) async {
  final acceptances = await ref.watch(myAcceptancesProvider.future);
  final aceitos =
      acceptances.map((a) => '${a.policyType}@${a.policyVersion}').toSet();

  return kAcceptanceDocuments
      .where((doc) => !aceitos.contains('${doc.policyType?.code}@${doc.version}'))
      .toList(growable: false);
});

/// Pedidos do titular (Art. 18) abertos por este usuário.
final myTitularRequestsProvider =
    FutureProvider<List<TitularRequestRecord>>((ref) async {
  final repo = ref.watch(legalRepositoryProvider);
  return repo.fetchMyTitularRequests();
});
