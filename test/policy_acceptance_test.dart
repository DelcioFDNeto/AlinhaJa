import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/ui/policy_acceptance_screen.dart';

/// A tela de consentimento roda em três alvos com larguras muito diferentes —
/// APK, web mobile e web desktop. Estes testes fixam o comportamento em cada
/// faixa: o aceite não pode liberar antes da leitura, e o layout precisa
/// entregar os três documentos em qualquer tamanho de tela.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PolicyAcceptanceScreen(pending: kAcceptanceDocuments),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Rola a lista até o alvo aparecer. Os cartões passam da altura da tela no
  /// celular, então nada abaixo da dobra existe na árvore sem isso.
  Future<Finder> reveal(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return finder;
  }

  CheckboxListTile checkboxOf(WidgetTester tester, LegalDocument doc) {
    return tester.widget<CheckboxListTile>(
      find.byKey(ValueKey('policy-check-${doc.id}')),
    );
  }

  testWidgets('celular: lista os três documentos e trava o aceite',
      (tester) async {
    await pumpAt(tester, const Size(390, 844));

    for (final doc in kAcceptanceDocuments) {
      await reveal(tester, ValueKey('policy-tile-${doc.id}'));
      expect(find.text(doc.title), findsOneWidget);
      // Sem leitura, a caixa não é clicável.
      expect(checkboxOf(tester, doc).onChanged, isNull);
    }

    final botao = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aceitar e continuar'),
    );
    expect(botao.onPressed, isNull);
  });

  testWidgets('celular: ler o documento libera e marca a caixa',
      (tester) async {
    await pumpAt(tester, const Size(390, 844));
    final doc = kAcceptanceDocuments.first;

    await reveal(tester, ValueKey('policy-tile-${doc.id}'));
    await tester.tap(find.widgetWithText(TextButton, 'Ler').first);
    await tester.pumpAndSettle();

    // Leitor em tela cheia, com a confirmação ao pé da leitura.
    expect(find.text('Li e concordo'), findsOneWidget);
    await tester.tap(find.text('Li e concordo'));
    await tester.pumpAndSettle();

    final check = checkboxOf(tester, doc);
    expect(check.value, isTrue);
    expect(check.onChanged, isNotNull);

    // Os outros seguem travados — o aceite é documento a documento.
    for (final outro in kAcceptanceDocuments.skip(1)) {
      await reveal(tester, ValueKey('policy-tile-${outro.id}'));
      expect(checkboxOf(tester, outro).onChanged, isNull);
    }
  });

  testWidgets('desktop: painel duplo mostra o primeiro documento aberto',
      (tester) async {
    await pumpAt(tester, const Size(1440, 900));

    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('v${kAcceptanceDocuments.first.version}'), findsOneWidget);

    // O documento já visível no painel direito libera a própria caixa…
    expect(checkboxOf(tester, kAcceptanceDocuments.first).onChanged, isNotNull);
    // …e só ele.
    for (final outro in kAcceptanceDocuments.skip(1)) {
      await reveal(tester, ValueKey('policy-check-${outro.id}'));
      expect(checkboxOf(tester, outro).onChanged, isNull);
    }
  });

  testWidgets('celular em paisagem: cai no fluxo de leitura, não no painel duplo',
      (tester) async {
    // 844x390 passa dos 800px de largura mas não tem altura para duas colunas.
    await pumpAt(tester, const Size(844, 390));

    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.widgetWithText(TextButton, 'Ler'), findsWidgets);
  });

  testWidgets('desktop: selecionar e marcar todos habilita o aceite',
      (tester) async {
    await pumpAt(tester, const Size(1440, 900));

    for (final doc in kAcceptanceDocuments) {
      final tile = await reveal(tester, ValueKey('policy-tile-${doc.id}'));
      await tester.tap(find.descendant(of: tile, matching: find.byType(ListTile)).first);
      await tester.pumpAndSettle();

      final check = await reveal(tester, ValueKey('policy-check-${doc.id}'));
      await tester.tap(check);
      await tester.pumpAndSettle();

      expect(checkboxOf(tester, doc).value, isTrue);
    }

    final botao = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aceitar e continuar'),
    );
    expect(botao.onPressed, isNotNull);
  });
}
