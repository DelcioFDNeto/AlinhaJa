import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/brand/identidade_repository.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/features/admin/ui/tabs/identidade_visual_tab.dart';

class _RepoFalso extends IdentidadeRepository {
  _RepoFalso();

  final chamadas = <Map<String, Object?>>[];

  @override
  Future<OrgIdentity> salvar({
    required String? logoUrl,
    required Color? corPrimaria,
    required Color? corSecundaria,
  }) async {
    chamadas.add({
      'logo': logoUrl,
      'primaria': corPrimaria,
      'secundaria': corSecundaria,
    });
    return OrgIdentity(
        organizationId: 'org-1',
        corPrimaria: corPrimaria,
        corSecundaria: corSecundaria);
  }
}

void main() {
  Future<_RepoFalso> montar(WidgetTester tester, OrgIdentity atual) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _RepoFalso();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        orgIdentityProvider.overrideWith((ref) async => atual),
        identidadeRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: Scaffold(body: IdentidadeVisualTab())),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder campoHex() => find.widgetWithText(TextField, 'Código da cor');

  Color corDaBarraDaPrevia(WidgetTester tester) => tester
      .widget<Container>(find.byKey(const ValueKey('previa-barra')))
      .color!;

  testWidgets('carrega a empresa e salva a cor digitada', (tester) async {
    final repo = await montar(tester,
        const OrgIdentity(organizationId: 'org-1', nome: 'Empresa Um'));

    expect(find.text('Empresa Um'), findsOneWidget);

    await tester.enterText(campoHex().first, '#1565c0');
    await tester.pumpAndSettle();
    expect(corDaBarraDaPrevia(tester), const Color(0xFF1565C0),
        reason: 'a prévia usa o mesmo tema do app');

    await tester.tap(find.text('Salvar identidade visual'));
    await tester.pumpAndSettle();

    expect(repo.chamadas, hasLength(1));
    expect(repo.chamadas.single['primaria'], const Color(0xFF1565C0));
    expect(repo.chamadas.single['secundaria'], isNull);
    expect(repo.chamadas.single['logo'], isNull);
    expect(find.text('Identidade visual salva.'), findsOneWidget);
  });

  testWidgets('código inválido avisa e não altera a cor', (tester) async {
    await montar(tester, const OrgIdentity(organizationId: 'org-1'));
    await tester.enterText(campoHex().first, '#12');
    await tester.pumpAndSettle();
    expect(find.text('Use o formato #RRGGBB'), findsOneWidget);
  });

  testWidgets('cor clara mostra aviso de contraste', (tester) async {
    await montar(tester, const OrgIdentity(organizationId: 'org-1'));
    await tester.enterText(campoHex().first, '#FFEB3B');
    await tester.pumpAndSettle();
    expect(find.textContaining('pouco visíveis'), findsOneWidget);
  });

  testWidgets('"Padrão do produto" limpa a cor da empresa', (tester) async {
    final repo = await montar(tester,
        const OrgIdentity(organizationId: 'org-1', corPrimaria: Color(0xFF2E7D32)));
    await tester.tap(find.text('Padrão do produto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar identidade visual'));
    await tester.pumpAndSettle();
    expect(repo.chamadas.single['primaria'], isNull);
  });
}
