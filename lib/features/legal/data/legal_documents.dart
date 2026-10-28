import 'package:flutter/material.dart';

/// Tipos de política que o servidor aceita em `accept_policy(p_policy_type, …)`.
///
/// Os nomes PRECISAM bater com o `CHECK` da RPC — qualquer outro valor faz a
/// função levantar exceção. Documento informativo não tem tipo: não é aceito,
/// é lido.
enum PolicyType {
  uso('uso'),
  privacidade('privacidade'),
  monitoramento('monitoramento');

  const PolicyType(this.code);

  /// Valor enviado ao banco.
  final String code;
}

/// Um documento do pacote legal.
///
/// O texto NÃO vive aqui: vive em `docs/legal/*.md`, declarado como asset no
/// `pubspec.yaml` e compartilhado com a landing page. Duplicar o texto em Dart
/// criaria duas fontes da verdade que divergem na primeira revisão jurídica.
class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.summary,
    required this.asset,
    required this.version,
    required this.icon,
    this.policyType,
  });

  /// Identificador estável, usado em rotas (`/legal/:id`).
  final String id;
  final String title;
  final String summary;

  /// Caminho do Markdown, relativo à raiz do projeto.
  final String asset;

  /// Versão semântica do documento. Subir a versão MAIOR de um documento com
  /// [policyType] faz a tela de aceite reaparecer para todo mundo — é assim que
  /// uma mudança material volta a ser informada.
  final String version;

  final IconData icon;

  /// Nulo para documentos informativos (não geram registro de aceite).
  final PolicyType? policyType;

  bool get requiresAcceptance => policyType != null;

  /// Chave usada para comparar com o que já foi aceito no servidor.
  String get acceptanceKey => '${policyType!.code}@$version';
}

/// Catálogo completo — **fonte única** dos documentos e das suas versões.
///
/// A ordem é a de exibição na Central de Privacidade. Não crie um segundo
/// catálogo em paralelo: a `version` daqui é o que vai para `accept_policy`, e
/// duas listas divergindo quebram o reaceite em silêncio — o app deixa de pedir
/// a nova versão, ou passa a pedir para sempre, sem erro nenhum aparecer.
const kLegalDocuments = <LegalDocument>[
  LegalDocument(
    id: 'termos',
    title: 'Termos de Uso',
    summary: 'Regras de uso da plataforma, conduta e responsabilidades.',
    asset: 'docs/legal/01-termos-de-uso.md',
    version: '1.0.0',
    policyType: PolicyType.uso,
    icon: Icons.gavel_rounded,
  ),
  LegalDocument(
    id: 'privacidade',
    title: 'Política de Privacidade',
    summary: 'Quais dados tratamos, por quê, por quanto tempo e seus direitos.',
    asset: 'docs/legal/02-politica-de-privacidade.md',
    version: '1.0.0',
    policyType: PolicyType.privacidade,
    icon: Icons.verified_user,
  ),
  LegalDocument(
    id: 'monitoramento',
    title: 'Monitoramento e Uso Aceitável',
    summary: 'O que a empresa pode acessar, quem pode e sob qual controle.',
    asset: 'docs/legal/03-politica-de-monitoramento-e-uso-aceitavel.md',
    version: '1.0.0',
    policyType: PolicyType.monitoramento,
    icon: Icons.visibility_rounded,
  ),
  LegalDocument(
    id: 'geolocalizacao',
    title: 'Consentimento — Geolocalização',
    summary: 'Termo específico do rastreamento. Opcional e revogável.',
    asset: 'docs/legal/04-termo-de-consentimento-geolocalizacao.md',
    version: '1.0.0',
    icon: Icons.location_on_rounded,
  ),
  LegalDocument(
    id: 'candidatos',
    title: 'Aviso de Privacidade — Candidatos',
    summary: 'Tratamento de dados de quem se candidata a vagas.',
    asset: 'docs/legal/05-aviso-de-privacidade-candidatos.md',
    version: '1.0.0',
    icon: Icons.work_outline_rounded,
  ),
  LegalDocument(
    id: 'cookies',
    title: 'Cookies e Armazenamento Local',
    summary: 'O que fica guardado no navegador e no seu dispositivo.',
    asset: 'docs/legal/06-politica-de-cookies.md',
    version: '1.0.0',
    icon: Icons.cookie_rounded,
  ),
  LegalDocument(
    id: 'ia',
    title: 'Uso de IA e Decisões Automatizadas',
    summary: 'Onde há IA, o que sai da empresa e seu direito a revisão.',
    asset: 'docs/legal/07-aviso-de-ia-e-decisoes-automatizadas.md',
    version: '1.0.0',
    icon: Icons.auto_awesome_rounded,
  ),
  LegalDocument(
    id: 'retencao',
    title: 'Retenção e Descarte',
    summary: 'Por quanto tempo cada tipo de dado é guardado.',
    asset: 'docs/legal/08-politica-de-retencao-e-descarte.md',
    version: '1.0.0',
    icon: Icons.schedule_rounded,
  ),
  LegalDocument(
    id: 'incidentes',
    title: 'Resposta a Incidentes',
    summary: 'Como comunicamos e tratamos incidentes de segurança.',
    asset: 'docs/legal/09-plano-de-resposta-a-incidentes.md',
    version: '1.0.0',
    icon: Icons.shield_rounded,
  ),
  LegalDocument(
    id: 'ropa',
    title: 'Registro de Operações de Tratamento (ROPA)',
    summary: 'O que a empresa trata, com qual base legal, operação a operação.',
    asset: 'docs/legal/10-registro-de-operacoes-ropa.md',
    version: '1.0.0',
    icon: Icons.fact_check_rounded,
  ),
  LegalDocument(
    id: 'fornecedores',
    title: 'Fornecedores e Transferência Internacional',
    summary: 'Quem processa dados em nome da empresa e em qual país.',
    asset: 'docs/legal/11-suboperadores-e-transferencia-internacional.md',
    version: '1.0.0',
    icon: Icons.public_rounded,
  ),
  LegalDocument(
    id: 'aceite',
    title: 'Termo de Ciência e Aceite',
    summary: 'O texto que você confirmou no primeiro acesso.',
    asset: 'docs/legal/12-termo-de-ciencia-e-aceite.md',
    version: '1.0.0',
    icon: Icons.assignment_turned_in_rounded,
  ),
];

/// Documentos que exigem aceite, na ordem da tela de aceite.
final kAcceptanceDocuments =
    kLegalDocuments.where((d) => d.requiresAcceptance).toList(growable: false);

/// Busca por id de rota. Retorna nulo para id desconhecido — o chamador decide
/// se cai em 404 ou em fallback.
LegalDocument? legalDocumentById(String id) {
  for (final doc in kLegalDocuments) {
    if (doc.id == id) return doc;
  }
  return null;
}

/// Resolve o documento a partir do `policy_type` gravado no servidor — o
/// caminho de volta, usado para dar nome a um aceite já registrado.
LegalDocument? legalDocumentByPolicyCode(String code) {
  for (final doc in kLegalDocuments) {
    if (doc.policyType?.code == code) return doc;
  }
  return null;
}

/// Resolve um link relativo entre documentos (`02-politica-de-privacidade.md`)
/// para o item do catálogo, permitindo navegar entre eles dentro do app.
LegalDocument? legalDocumentByFile(String fileName) {
  final clean = fileName.split('/').last.split('#').first;
  for (final doc in kLegalDocuments) {
    if (doc.asset.endsWith(clean)) return doc;
  }
  return null;
}
