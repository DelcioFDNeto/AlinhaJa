import 'package:flutter/foundation.dart';

/// Um campo do perfil legal que aparece entre colchetes nos documentos.
@immutable
class LegalField {
  const LegalField({
    required this.key,
    required this.placeholder,
    required this.label,
    required this.hint,
    this.essential = false,
  });

  /// Chave no JSON de `get_org_legal_profile()` / `admin_set_org_legal_profile`.
  final String key;

  /// Token literal como aparece no Markdown, com colchetes.
  final String placeholder;

  final String label;
  final String hint;

  /// Sem este campo o documento não deveria entrar em vigor.
  final bool essential;
}

/// Campos que o app preenche automaticamente nos documentos.
///
/// A lista é deliberadamente FECHADA. Os documentos usam colchetes para outras
/// coisas — links Markdown (`[Política de Privacidade]`), marcadores de
/// pendência (`[CONFIRMAR]`, `[VALIDAR: …]`) e, no aviso de IA, exemplos do
/// mascaramento de PII (`[CPF]`, `[EMAIL]`, `[NOME]`). Substituir por regex
/// genérico de colchetes corromperia justamente o texto que explica a
/// anonimização.
const kLegalFields = <LegalField>[
  LegalField(
    key: 'razao_social',
    placeholder: '[RAZÃO SOCIAL]',
    label: 'Razão social',
    hint: 'Nome empresarial completo, como no CNPJ',
    essential: true,
  ),
  LegalField(
    key: 'cnpj',
    placeholder: '[CNPJ]',
    label: 'CNPJ',
    hint: '00.000.000/0001-00',
    essential: true,
  ),
  LegalField(
    key: 'endereco',
    placeholder: '[ENDEREÇO COMPLETO]',
    label: 'Endereço da sede',
    hint: 'Rua, número, bairro, cidade/UF, CEP',
    essential: true,
  ),
  LegalField(
    key: 'dpo_nome',
    placeholder: '[NOME DO ENCARREGADO]',
    label: 'Encarregado (DPO)',
    hint: 'Nome de quem responde pela proteção de dados (Art. 41)',
    essential: true,
  ),
  LegalField(
    key: 'dpo_email',
    placeholder: '[E-MAIL DO DPO]',
    label: 'E-mail do Encarregado',
    hint: 'Canal público para o titular exercer direitos',
    essential: true,
  ),
  LegalField(
    key: 'vigencia',
    placeholder: '[DATA DE VIGÊNCIA]',
    label: 'Data de vigência',
    hint: 'A partir de quando os documentos valem',
    essential: true,
  ),
  LegalField(
    key: 'comarca',
    placeholder: '[COMARCA]',
    label: 'Comarca do foro',
    hint: 'Cidade/UF eleita nos Termos de Uso',
  ),
  LegalField(
    key: 'regiao_hospedagem',
    placeholder: '[REGIÃO DE HOSPEDAGEM]',
    label: 'Região de hospedagem',
    hint: 'Onde o banco de dados roda — define transferência internacional',
  ),
  LegalField(
    key: 'telefone_plantao',
    placeholder: '[TELEFONE DE PLANTÃO]',
    label: 'Telefone de plantão',
    hint: 'Contato para incidente fora do horário comercial',
  ),
];

/// Dados da empresa que preenchem os documentos LGPD do tenant corrente.
///
/// Vem de `get_org_legal_profile()`, que resolve a organização por
/// `fn_current_org()` — ou seja, acompanha automaticamente a empresa do usuário
/// e, no produto white label, a empresa em atuação do dono da plataforma.
@immutable
class OrgLegalProfile {
  const OrgLegalProfile({
    this.organizationId,
    this.nomeFantasia,
    this.razaoSocial,
    this.cnpj,
    this.endereco,
    this.dpoNome,
    this.dpoEmail,
    this.dpoTelefone,
    this.comarca,
    this.vigencia,
    this.regiaoHospedagem,
    this.telefonePlantao,
    this.gpsRetencaoDias = 7,
    this.candidatoRetencaoMeses = 24,
    this.msgRetencaoDias = 0,
  });

  final String? organizationId;
  final String? nomeFantasia;
  final String? razaoSocial;
  final String? cnpj;
  final String? endereco;
  final String? dpoNome;
  final String? dpoEmail;
  final String? dpoTelefone;
  final String? comarca;
  final String? vigencia;
  final String? regiaoHospedagem;
  final String? telefonePlantao;

  /// Prazos EFETIVOS do tenant. Entram no texto para o documento afirmar o que
  /// o sistema faz, e não o que o modelo dizia — política declarada e não
  /// cumprida é agravante em fiscalização (Art. 15 e 16).
  final int gpsRetencaoDias;
  final int candidatoRetencaoMeses;
  final int msgRetencaoDias;

  static const empty = OrgLegalProfile();

  factory OrgLegalProfile.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int intOr(String key, int fallback) {
      final v = json[key];
      if (v == null) return fallback;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return OrgLegalProfile(
      organizationId: str('organization_id'),
      nomeFantasia: str('nome_fantasia'),
      razaoSocial: str('razao_social'),
      cnpj: str('cnpj'),
      endereco: str('endereco'),
      dpoNome: str('dpo_nome'),
      dpoEmail: str('dpo_email'),
      dpoTelefone: str('dpo_telefone'),
      comarca: str('comarca'),
      vigencia: str('vigencia'),
      regiaoHospedagem: str('regiao_hospedagem'),
      telefonePlantao: str('telefone_plantao'),
      gpsRetencaoDias: intOr('gps_retencao_dias', 7),
      candidatoRetencaoMeses: intOr('candidato_retencao_meses', 24),
      msgRetencaoDias: intOr('msg_retencao_dias', 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'razao_social': razaoSocial,
        'cnpj': cnpj,
        'endereco': endereco,
        'dpo_nome': dpoNome,
        'dpo_email': dpoEmail,
        'dpo_telefone': dpoTelefone,
        'comarca': comarca,
        'vigencia': vigencia,
        'regiao_hospedagem': regiaoHospedagem,
        'telefone_plantao': telefonePlantao,
      };

  String? valueOf(String key) => switch (key) {
        'razao_social' => razaoSocial,
        'cnpj' => cnpj,
        'endereco' => endereco,
        'dpo_nome' => dpoNome,
        'dpo_email' => dpoEmail,
        'dpo_telefone' => dpoTelefone,
        'comarca' => comarca,
        'vigencia' => vigencia,
        'regiao_hospedagem' => regiaoHospedagem,
        'telefone_plantao' => telefonePlantao,
        _ => null,
      };

  OrgLegalProfile copyWith({
    String? razaoSocial,
    String? cnpj,
    String? endereco,
    String? dpoNome,
    String? dpoEmail,
    String? dpoTelefone,
    String? comarca,
    String? vigencia,
    String? regiaoHospedagem,
    String? telefonePlantao,
  }) {
    return OrgLegalProfile(
      organizationId: organizationId,
      nomeFantasia: nomeFantasia,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      cnpj: cnpj ?? this.cnpj,
      endereco: endereco ?? this.endereco,
      dpoNome: dpoNome ?? this.dpoNome,
      dpoEmail: dpoEmail ?? this.dpoEmail,
      dpoTelefone: dpoTelefone ?? this.dpoTelefone,
      comarca: comarca ?? this.comarca,
      vigencia: vigencia ?? this.vigencia,
      regiaoHospedagem: regiaoHospedagem ?? this.regiaoHospedagem,
      telefonePlantao: telefonePlantao ?? this.telefonePlantao,
      gpsRetencaoDias: gpsRetencaoDias,
      candidatoRetencaoMeses: candidatoRetencaoMeses,
      msgRetencaoDias: msgRetencaoDias,
    );
  }

  /// Retenção de mensagens em prosa, porque `0` significa "sem expiração" e não
  /// "zero dias" — imprimir o número cru inverteria o sentido da frase.
  String get retencaoMensagensTexto => msgRetencaoDias > 0
      ? '$msgRetencaoDias dias'
      : 'sem expiração automática';

  /// Campos essenciais ainda em branco. Vazio = documento pronto para vigorar,
  /// no que depende de dado cadastral.
  List<LegalField> get missingEssentials => kLegalFields
      .where((f) => f.essential && (valueOf(f.key) ?? '').isEmpty)
      .toList(growable: false);

  bool get isComplete => missingEssentials.isEmpty;

  /// Aplica o perfil ao Markdown, trocando cada placeholder conhecido pelo
  /// valor do tenant. O que não estiver preenchido **permanece entre
  /// colchetes**: um documento com lacuna visível é honesto; um com lacuna
  /// apagada esconde que está incompleto.
  String apply(String markdown) {
    var out = markdown;

    for (final field in kLegalFields) {
      final value = valueOf(field.key);
      if (value == null || value.isEmpty) continue;
      out = out.replaceAll(field.placeholder, _format(field.key, value));
    }

    // Prazos efetivos do tenant. Os três marcadores existem nos documentos
    // porque os três são configuráveis por empresa — deixar qualquer um como
    // número fixo no texto faz o documento afirmar prazo que o sistema não
    // pratica, que é agravante em fiscalização (Art. 15 e 16), não detalhe.
    out = out.replaceAll('[7]', '$gpsRetencaoDias');
    out = out.replaceAll('[24]', '$candidatoRetencaoMeses');
    out = out.replaceAll('[RETENÇÃO DE MENSAGENS]', retencaoMensagensTexto);

    return out;
  }

  /// Datas saem do banco em ISO e devem aparecer no formato brasileiro.
  String _format(String key, String value) {
    if (key != 'vigencia') return value;
    final iso = DateTime.tryParse(value);
    if (iso == null) return value;
    final d = iso.day.toString().padLeft(2, '0');
    final m = iso.month.toString().padLeft(2, '0');
    return '$d/$m/${iso.year}';
  }
}
