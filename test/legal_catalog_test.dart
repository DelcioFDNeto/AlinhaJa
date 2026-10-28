import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';

/// O catálogo em `data/legal_documents.dart` é a fonte única dos documentos e
/// das suas versões — a `version` daqui é o que vai para `accept_policy`.
///
/// Já existiu um segundo catálogo em paralelo. Enquanto os dois concordavam
/// nada quebrava; na primeira divergência de versão o reaceite falharia em
/// silêncio. Estes testes existem para que a fonte volte a ser única sem
/// depender de alguém lembrar disso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('todo documento aponta para um arquivo que existe nos assets', () async {
    for (final doc in kLegalDocuments) {
      final texto = await rootBundle.loadString(doc.asset);
      expect(
        texto.trim(),
        isNotEmpty,
        reason: '${doc.id} aponta para ${doc.asset}, que está vazio',
      );
    }
  });

  test('o catálogo cobre os 12 documentos do pacote legal', () {
    // docs/legal/ tem 12 documentos + README. Se você acrescentar um documento
    // e este teste falhar, é porque ele existe no disco mas não no app.
    expect(kLegalDocuments.length, 12);
  });

  test('ids são únicos — é por eles que a rota /legal/:id resolve', () {
    final ids = kLegalDocuments.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('assets são únicos — dois ids para o mesmo texto seriam duplicata', () {
    final assets = kLegalDocuments.map((d) => d.asset).toList();
    expect(assets.toSet().length, assets.length);
  });

  test('cada tipo de política do servidor tem exatamente um documento', () {
    for (final tipo in PolicyType.values) {
      final docs =
          kLegalDocuments.where((d) => d.policyType == tipo).toList();
      expect(
        docs.length,
        1,
        reason: 'PolicyType.${tipo.name} precisa de um documento e só um',
      );
    }
  });

  test('os documentos de aceite cobrem todos os tipos aceitos pela RPC', () {
    // A RPC `accept_policy` valida contra este conjunto e levanta exceção em
    // qualquer outro valor.
    const aceitosPeloBanco = {'uso', 'privacidade', 'monitoramento'};

    final codigos =
        kAcceptanceDocuments.map((d) => d.policyType!.code).toSet();
    expect(codigos, aceitosPeloBanco);
  });

  test('versão segue formato semântico — é o valor gravado no aceite', () {
    final semver = RegExp(r'^\d+\.\d+\.\d+$');
    for (final doc in kLegalDocuments) {
      expect(
        semver.hasMatch(doc.version),
        isTrue,
        reason: '${doc.id} tem versão inválida: ${doc.version}',
      );
    }
  });

  test('busca por código de política acha o documento de volta', () {
    for (final doc in kAcceptanceDocuments) {
      expect(legalDocumentByPolicyCode(doc.policyType!.code)?.id, doc.id);
    }
  });

  test('links entre documentos resolvem pelo nome do arquivo', () {
    for (final doc in kLegalDocuments) {
      final fileName = doc.asset.split('/').last;
      expect(legalDocumentByFile(fileName)?.id, doc.id);
      // Com âncora, como aparece no Markdown.
      expect(legalDocumentByFile('$fileName#secao')?.id, doc.id);
    }
  });
}
