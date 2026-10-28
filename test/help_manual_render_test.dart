import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/support/data/help_faq.dart';
import 'package:alinha_ja/features/support/data/help_guides.dart';
import 'package:alinha_ja/features/support/data/help_manual.dart';
import 'package:alinha_ja/features/support/ui/help_guides_view.dart';
import 'package:alinha_ja/features/support/ui/help_manual_view.dart';

void main() {
  testWidgets('Manual: expandir artigo mostra o conteúdo markdown',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HelpManualView()),
      ),
    );
    await tester.pumpAndSettle();

    // O primeiro artigo da primeira categoria deve estar listado.
    const firstTitle = 'O que é o ${AppConstants.appName}';
    expect(find.text(firstTitle), findsOneWidget);

    await tester.tap(find.text(firstTitle));
    await tester.pumpAndSettle();

    // O corpo markdown deve renderizar texto do parágrafo.
    expect(
      find.textContaining('plataforma corporativa unificada',
          findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('Manual: busca filtra artigos pelo corpo do texto',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HelpManualView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'LGPD');
    await tester.pumpAndSettle();

    expect(find.text('Ajustes: etapas, catálogo e retenção LGPD'),
        findsOneWidget);
    expect(find.text('Holerites e comprovação de entrega'), findsNothing);
  });

  testWidgets('Guias: lista os roteiros e busca pelo texto dos passos',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HelpGuidesView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Primeiros passos'), findsOneWidget);

    // "biometria" não está no título nem nas palavras-chave do guia de
    // chamadas, só no texto de um passo — a busca precisa alcançá-lo.
    await tester.enterText(find.byType(TextField), 'biometria');
    await tester.pumpAndSettle();

    expect(find.text('Chamadas e reuniões'), findsOneWidget);
    expect(find.text('Primeiros passos'), findsNothing);
  });

  test('Guias e Manual: todo passo/artigo tem conteúdo utilizável', () {
    expect(kHelpGuides, isNotEmpty);
    for (final guide in kHelpGuides) {
      expect(guide.steps, isNotEmpty, reason: 'guia ${guide.id} sem passos');
      for (final step in guide.steps) {
        expect(step.description.length, greaterThan(40),
            reason: 'passo "${step.title}" (${guide.id}) é raso demais');
        final image = step.image;
        if (image != null) {
          expect(image, startsWith('assets/images/help/'),
              reason: 'passo "${step.title}" aponta para fora dos assets');
        }
      }
    }

    expect(kManualArticles, isNotEmpty);
    for (final article in kManualArticles) {
      expect(article.markdown.trim(), isNotEmpty,
          reason: 'artigo ${article.id} sem corpo');
      expect(article.keywords.trim(), isNotEmpty,
          reason: 'artigo ${article.id} sem palavras-chave para a busca');
    }
  });

  test('FAQ: marcadores de negrito estão balanceados', () {
    // A Central de Ajuda renderiza `**negrito**` manualmente alternando a cada
    // par de asteriscos: um marcador solto deixaria o resto do texto em negrito.
    expect(kHelpTopics, isNotEmpty);
    for (final topic in kHelpTopics) {
      expect('**'.allMatches(topic.content).length.isEven, isTrue,
          reason: 'tópico "${topic.title}" tem marcador ** sem par');
      expect(topic.tags, isNotEmpty,
          reason: 'tópico "${topic.title}" sem etiquetas de busca');
    }
  });

  test('Ids de guias e artigos são únicos', () {
    final guideIds = kHelpGuides.map((g) => g.id).toList();
    expect(guideIds.toSet().length, guideIds.length);

    final articleIds = kManualArticles.map((a) => a.id).toList();
    expect(articleIds.toSet().length, articleIds.length);
  });
}
