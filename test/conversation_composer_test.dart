import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/core/ui/composer/conversation_composer.dart';
import 'package:alinha_ja/core/ui/message_cards/message_action_providers.dart';

/// Delegate de teste: registra o que foi enviado, sem tocar em Supabase.
class _FakeDelegate extends ComposerDelegate {
  final Set<ComposerActionId> allowed;
  final bool locked;
  final List<String> sentTexts = [];
  final List<Map<String, dynamic>> sentStructured = [];

  _FakeDelegate({
    this.allowed = const {...kMediaComposerActions, ...kRichComposerActions},
    this.locked = false,
  });

  @override
  String get destinationName => 'Financeiro';

  @override
  bool get canSend => !locked;

  @override
  Set<ComposerActionId> get actions => allowed;

  @override
  Future<void> sendText(String text) async {
    sentTexts.add(text);
  }

  @override
  Future<void> sendStructured(
      String content, Map<String, dynamic> metadata) async {
    sentStructured.add(metadata);
  }

  @override
  Future<void> sendMedia(List<XFile> files,
      {String? caption, bool isViewOnce = false}) async {}

  @override
  Future<void> sendDocuments(List<XFile> files, {String? caption}) async {}
}

Future<void> _pumpComposer(WidgetTester tester, ComposerDelegate delegate,
    {Size size = const Size(400, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Spacer(),
          // Key derivada do tamanho: repumpar em outra largura precisa de um
          // State novo, senão o painel continua aberto do pump anterior.
          ConversationComposer(key: ValueKey(size), delegate: delegate),
        ],
      ),
    ),
  ));
}

void main() {
  group('ConversationComposer', () {
    testWidgets('painel de anexos mostra todas as ações declaradas',
        (tester) async {
      await _pumpComposer(tester, _FakeDelegate());

      expect(find.text('Enquete'), findsNothing);

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();

      for (final id in kMediaComposerActions.followedBy(kRichComposerActions)) {
        expect(find.text(composerActionSpecs[id]!.label), findsOneWidget,
            reason: 'ação ${id.name} deveria aparecer no painel');
      }
    });

    testWidgets('conversa só de mídia não oferece enquete nem localização',
        (tester) async {
      await _pumpComposer(
          tester, _FakeDelegate(allowed: kMediaComposerActions));

      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Galeria'), findsOneWidget);
      expect(find.text('Enquete'), findsNothing);
      expect(find.text('Localização'), findsNothing);
    });

    testWidgets('conversa travada mostra o aviso no lugar do campo',
        (tester) async {
      await _pumpComposer(tester, _FakeDelegate(locked: true));

      expect(find.text('Apenas administradores podem enviar mensagens'),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('texto digitado troca o microfone pelo botão de enviar',
        (tester) async {
      final delegate = _FakeDelegate();
      await _pumpComposer(tester, delegate);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'olá equipe');
      await tester.pump();

      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(delegate.sentTexts, ['olá equipe']);
    });

    testWidgets('painel usa mais colunas em tela larga', (tester) async {
      // Estreito: 4 colunas → 8 ações ocupam 2 linhas.
      await _pumpComposer(tester, _FakeDelegate(),
          size: const Size(360, 900));
      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();

      final narrowCamera = tester.getTopLeft(find.text('Câmera'));
      final narrowContact = tester.getTopLeft(find.text('Contato'));
      expect(narrowContact.dy, greaterThan(narrowCamera.dy));

      // Largo: cabem todas na mesma linha.
      await _pumpComposer(tester, _FakeDelegate(),
          size: const Size(1000, 900));
      await tester.tap(find.byIcon(Icons.add_circle_rounded));
      await tester.pumpAndSettle();

      final wideCamera = tester.getTopLeft(find.text('Câmera'));
      final wideContact = tester.getTopLeft(find.text('Contato'));
      expect(wideContact.dy, equals(wideCamera.dy));
    });
  });

  group('MessageExtras', () {
    test('enquete faz round-trip pelo leitor de metadata', () {
      final metadata = MessageExtras.poll(
        options: ['Manhã', 'Tarde'],
        multipleChoice: true,
      );

      expect(metadata.isPoll, isTrue);
      expect(metadata.isStructured, isTrue);
      expect(metadata.pollOptions, ['Manhã', 'Tarde']);
      expect(metadata.pollAllowsMultiple, isTrue);
    });

    test('evento preserva título e data', () {
      final date = DateTime(2026, 8, 20, 14, 30);
      final metadata = MessageExtras.event(title: 'Reunião', date: date);

      expect(metadata.isEvent, isTrue);
      expect(metadata.eventTitle, 'Reunião');
      expect(metadata.eventDate, date);
    });

    test('localização aceita coordenada vinda como texto do JSONB', () {
      final metadata = <String, dynamic>{
        'type': 'location',
        'latitude': '-23.55052',
        'longitude': -46.633308,
      };

      expect(metadata.isLocation, isTrue);
      expect(metadata.latitude, closeTo(-23.55052, 0.00001));
      expect(metadata.longitude, closeTo(-46.633308, 0.00001));
    });

    test('metadata sem type não é tratado como card', () {
      expect(<String, dynamic>{'mentions': []}.isStructured, isFalse);
    });
  });

  group('Voto de enquete', () {
    test('múltipla escolha cabe em um registro só', () {
      final encoded = encodePollVote(['Manhã', 'Noite']);

      expect(encoded.contains(kPollVoteSeparator), isTrue);
      expect(decodePollVote(encoded), ['Manhã', 'Noite']);
    });

    test('voto vazio decodifica para lista vazia', () {
      expect(decodePollVote(null), isEmpty);
      expect(decodePollVote(''), isEmpty);
    });
  });

  group('MessageRef', () {
    test('cada origem grava na sua coluna de message_actions', () {
      expect(const MessageRef.chat('abc').actionColumn, 'message_id');
      expect(
          const MessageRef.channel('abc').actionColumn, 'channel_message_id');
    });

    test('mesmo id em tabelas diferentes são referências distintas', () {
      const chat = MessageRef.chat('mesmo-uuid');
      const channel = MessageRef.channel('mesmo-uuid');

      // Riverpod indexa a family por igualdade: se estas colidissem, o voto de
      // um canal apareceria no chat.
      expect(chat, isNot(equals(channel)));
      expect(chat.hashCode, isNot(equals(channel.hashCode)));
      expect(chat, equals(const MessageRef.chat('mesmo-uuid')));
    });
  });
}
