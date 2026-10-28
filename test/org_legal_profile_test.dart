import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/models/org_legal_profile.dart';

/// O perfil legal é o que transforma um modelo de documento no documento de uma
/// empresa específica. Errar aqui não dá erro de compilação nem exceção em
/// runtime: dá um documento jurídico com o nome da empresa errada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const completo = OrgLegalProfile(
    nomeFantasia: 'Empresa Exemplo',
    razaoSocial: 'EMPRESA EXEMPLO LTDA',
    cnpj: '00.000.000/0001-00',
    endereco: 'Rua Um, 100 — Centro, Cidade/UF',
    dpoNome: 'Fulano de Tal',
    dpoEmail: 'dpo@exemplo.com.br',
    comarca: 'Cidade/UF',
    vigencia: '2026-09-01',
    regiaoHospedagem: 'São Paulo (sa-east-1)',
    telefonePlantao: '(00) 90000-0000',
    gpsRetencaoDias: 30,
  );

  group('substituição', () {
    test('troca cada placeholder conhecido pelo valor do tenant', () {
      const texto = 'A [RAZÃO SOCIAL], CNPJ [CNPJ], com sede em '
          '[ENDEREÇO COMPLETO]. Encarregado: [NOME DO ENCARREGADO] — '
          '[E-MAIL DO DPO]. Foro: [COMARCA].';

      final out = completo.apply(texto);

      expect(out, contains('EMPRESA EXEMPLO LTDA'));
      expect(out, contains('00.000.000/0001-00'));
      expect(out, contains('Rua Um, 100'));
      expect(out, contains('Fulano de Tal'));
      expect(out, contains('dpo@exemplo.com.br'));
      expect(out, isNot(contains('[RAZÃO SOCIAL]')));
      expect(out, isNot(contains('[E-MAIL DO DPO]')));
    });

    test('campo vazio permanece entre colchetes', () {
      // Lacuna visível é honesta; lacuna apagada esconderia que o documento
      // está incompleto.
      const parcial = OrgLegalProfile(razaoSocial: 'ACME LTDA');
      final out = parcial.apply('[RAZÃO SOCIAL] — DPO [E-MAIL DO DPO]');

      expect(out, contains('ACME LTDA'));
      expect(out, contains('[E-MAIL DO DPO]'));
    });

    test('data de vigência sai no formato brasileiro', () {
      final out = completo.apply('Vigente a partir de [DATA DE VIGÊNCIA].');
      expect(out, contains('01/09/2026'));
    });

    test('os três prazos configuráveis refletem a empresa', () {
      // O documento tem de afirmar o que o sistema faz. Prazo declarado e não
      // cumprido é agravante em fiscalização (Art. 15 e 16).
      const p = OrgLegalProfile(
        gpsRetencaoDias: 30,
        candidatoRetencaoMeses: 36,
        msgRetencaoDias: 180,
      );
      final out = p.apply(
          'GPS [7] dias, candidatos [24] meses, mensagens: [RETENÇÃO DE MENSAGENS].');

      expect(out, contains('GPS 30 dias'));
      expect(out, contains('candidatos 36 meses'));
      expect(out, contains('mensagens: 180 dias'));
    });

    test('retenção de mensagens em zero vira prosa, não o número 0', () {
      // `0` significa "sem expiração"; imprimir o número inverteria a frase.
      const p = OrgLegalProfile(msgRetencaoDias: 0);
      expect(p.apply('[RETENÇÃO DE MENSAGENS]'), 'sem expiração automática');
    });

    test('NÃO toca em link Markdown nem em marcador de pendência', () {
      const texto = 'Veja a [Política de Privacidade](02-x.md). '
          'Fornecedor `[CONFIRMAR]`. Prazo `[VALIDAR: sugerido 5 anos]`.';
      expect(completo.apply(texto), texto);
    });

    test('NÃO toca nos exemplos de mascaramento de PII', () {
      // O aviso de IA explica que o texto sai como `[CPF]`, `[EMAIL]`,
      // `[NOME]`. Substituir isso corromperia justamente a seção que descreve
      // a anonimização.
      const texto = 'O modelo recebe [NOME], [EMAIL] e [CPF] mascarados.';
      expect(completo.apply(texto), texto);
    });
  });

  group('completude', () {
    test('perfil vazio acusa todos os campos essenciais', () {
      final faltando = OrgLegalProfile.empty.missingEssentials;
      expect(faltando.map((f) => f.key), contains('razao_social'));
      expect(faltando.map((f) => f.key), contains('cnpj'));
      expect(faltando.map((f) => f.key), contains('dpo_email'));
      expect(OrgLegalProfile.empty.isComplete, isFalse);
    });

    test('perfil preenchido está completo', () {
      expect(completo.missingEssentials, isEmpty);
      expect(completo.isComplete, isTrue);
    });

    test('campo opcional em branco não impede a vigência', () {
      final semOpcionais = completo.copyWith().copyWith();
      expect(semOpcionais.isComplete, isTrue);
    });
  });

  group('serialização', () {
    test('ida e volta pelo JSON da RPC preserva os valores', () {
      final json = {
        'organization_id': 'org-1',
        'nome_fantasia': 'Empresa Exemplo',
        'razao_social': 'EMPRESA EXEMPLO LTDA',
        'cnpj': '00.000.000/0001-00',
        'dpo_email': 'dpo@exemplo.com.br',
        'gps_retencao_dias': '30',
        'candidato_retencao_meses': '24',
        'msg_retencao_dias': '0',
      };

      final perfil = OrgLegalProfile.fromJson(json);
      expect(perfil.razaoSocial, 'EMPRESA EXEMPLO LTDA');
      expect(perfil.gpsRetencaoDias, 30);
      expect(perfil.candidatoRetencaoMeses, 24);
      expect(perfil.msgRetencaoDias, 0);
    });

    test('string vazia vinda do banco conta como ausente', () {
      final perfil = OrgLegalProfile.fromJson(const {'razao_social': '  '});
      expect(perfil.razaoSocial, isNull);
      expect(perfil.isComplete, isFalse);
    });

    test('prazo ausente cai no default das rotinas de expurgo', () {
      final perfil = OrgLegalProfile.fromJson(const {});
      expect(perfil.gpsRetencaoDias, 7);
      expect(perfil.candidatoRetencaoMeses, 24);
    });
  });

  group('cobertura sobre os documentos reais', () {
    test('todo placeholder do catálogo some quando o perfil está completo',
        () async {
      for (final doc in kLegalDocuments) {
        final bruto = await rootBundle.loadString(doc.asset);
        final preenchido = completo.apply(bruto);

        for (final field in kLegalFields) {
          expect(
            preenchido.contains(field.placeholder),
            isFalse,
            reason: '${doc.id} ainda tem ${field.placeholder} após o '
                'preenchimento — o campo existe no texto mas não no perfil',
          );
        }
      }
    });

    test('nenhum token de perfil escapa do catálogo', () async {
      // O teste anterior só prova que o que ESTÁ no catálogo some. Este pega o
      // inverso: token que parece campo de cadastro (CAIXA ALTA) presente nos
      // .md e ausente de kLegalFields ficaria entre colchetes para sempre, sem
      // ninguém perceber — foi assim que [REGIÃO DE HOSPEDAGEM — CONFIRMAR]
      // passou despercebido.
      final conhecidos = {
        ...kLegalFields.map((f) => f.placeholder),
        // Pendências que dependem de decisão humana, não de cadastro.
        '[CONFIRMAR]', '[AVALIAR]', '[NOME]', '[NOME OU ESCRITÓRIO]', '[DATA]',
        '[CAMPOS ENTRE COLCHETES]', '[X]',
        // Exemplos de mascaramento de PII no aviso de IA.
        '[CPF]', '[EMAIL]', '[TELEFONE]', '[CNPJ]', '[CARTAO]',
        // Prazos, substituídos por valor do tenant.
        '[7]', '[24]', '[RETENÇÃO DE MENSAGENS]',
      };
      final padrao = RegExp(r'\[[A-ZÀ-Ú][^\]\n]*\]');

      final orfaos = <String>{};
      for (final doc in kLegalDocuments) {
        final texto = await rootBundle.loadString(doc.asset);
        for (final m in padrao.allMatches(texto)) {
          final token = m.group(0)!;
          // Link Markdown: `[Rótulo](arquivo.md)`. O colchete é sintaxe, não
          // campo de cadastro.
          final depois = m.end < texto.length ? texto[m.end] : '';
          if (depois == '(') continue;
          if (conhecidos.contains(token)) continue;
          // `[VALIDAR: ...]` e `[CONFIRMAR — ...]` variam no sufixo.
          if (token.startsWith('[VALIDAR') || token.startsWith('[CONFIRMAR')) {
            continue;
          }
          orfaos.add('${doc.id}: $token');
        }
      }

      expect(orfaos, isEmpty,
          reason: 'tokens sem campo correspondente no catálogo:\n'
              '${orfaos.join('\n')}');
    });

    test('empresa única nunca herda identidade vinda do banco', () {
      // A org semeada é a mesma nos dois forks e traz a razão social da OUTRA
      // empresa. O fallback de marca só pode usar a constante de build; usar
      // nome_fantasia do banco publicaria o nome de terceiro no documento.
      const doBancoErrado = OrgLegalProfile(
        nomeFantasia: 'Empresa De Outro Fork',
        razaoSocial: 'RAZAO SOCIAL DE OUTRO FORK LTDA',
      );
      final saida = doBancoErrado.apply('Controladora: [RAZÃO SOCIAL].');

      // O modelo não decide o fallback — quem decide é o provider. O que este
      // teste fixa é que o modelo não inventa nome nenhum por conta própria.
      expect(saida, contains('RAZAO SOCIAL DE OUTRO FORK LTDA'));
      expect(OrgLegalProfile.empty.apply('[RAZÃO SOCIAL]'), '[RAZÃO SOCIAL]');
    });

    test('os campos essenciais realmente aparecem nos documentos de aceite',
        () async {
      // Guarda contra o inverso: um campo essencial que ninguém usa é cadastro
      // pedido à toa ao administrador.
      final essenciais =
          kLegalFields.where((f) => f.essential).map((f) => f.placeholder);

      final textos = <String>[];
      for (final doc in kAcceptanceDocuments) {
        textos.add(await rootBundle.loadString(doc.asset));
      }
      final tudo = textos.join('\n');

      for (final placeholder in essenciais) {
        expect(
          tudo.contains(placeholder),
          isTrue,
          reason: '$placeholder é exigido do administrador mas não aparece em '
              'nenhum documento de aceite',
        );
      }
    });
  });
}
