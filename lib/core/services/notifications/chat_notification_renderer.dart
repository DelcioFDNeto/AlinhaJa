import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/services/notifications/notification_action_bridge.dart';
import 'package:alinha_ja/core/services/notifications/notification_actions_gateway.dart';
import 'package:alinha_ja/core/services/notifications/notification_store.dart';

const kMessagesGroupKey = 'alinhaja_unified_messages';
final int kSummaryNotificationId =
    stableNotificationId('alinhaja_unified_summary');

/// Quantas mensagens a notificação expandida mostra. Cada linha carrega o
/// ícone do remetente no Parcel do Android; acima disso o tamanho da
/// transação se aproxima do limite do Binder (~1 MB).
const _visibleLines = 8;

/// Id estável entre execuções (FNV-1a 31 bits). `String.hashCode` não tem
/// garantia de ser o mesmo em isolates/execuções diferentes, e o id precisa
/// bater entre o isolate que exibe e o que cancela a notificação.
int stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Mensagem recebida pelo push, já normalizada.
class IncomingChatMessage {
  final String chatId;
  final String chatType;
  final String? source;
  final String title;
  final String senderName;
  final String? senderId;
  final String? senderAvatar;
  final String text;
  final bool mentioned;

  const IncomingChatMessage({
    required this.chatId,
    required this.chatType,
    required this.title,
    required this.senderName,
    required this.text,
    this.source,
    this.senderId,
    this.senderAvatar,
    this.mentioned = false,
  });

  /// `preview` e `sender_name` vêm das versões novas da Edge Function. Para
  /// payload antigo, reconstrói a partir de `body` ("Nome: conteúdo").
  static IncomingChatMessage? fromData(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    if (chatId == null || chatId.isEmpty) return null;
    final chatType = data['chat_type'] as String? ?? 'direct';
    final title = data['title'] as String? ?? 'Nova mensagem';
    final body = data['body'] as String? ?? '';

    var sender = data['sender_name'] as String?;
    var text = data['preview'] as String?;
    if (text == null) {
      text = body.replaceFirst(RegExp(r'^(@ |📣 )'), '');
      if (chatType != 'direct' && text.contains(': ')) {
        final idx = text.indexOf(': ');
        sender ??= text.substring(0, idx);
        text = text.substring(idx + 2);
      }
    }
    return IncomingChatMessage(
      chatId: chatId,
      chatType: chatType,
      source: data['conversation_table'] as String?,
      title: title,
      senderName: (sender == null || sender.isEmpty) ? title : sender,
      senderId: data['sender_id'] as String?,
      senderAvatar: data['sender_avatar'] as String?,
      text: text,
      mentioned: data['is_mention'] == 'true',
    );
  }
}

/// Payload gravado na notificação local (tap e ações).
class ConversationPayload {
  final String chatId;
  final String chatType;
  final String name;
  final String? source;

  const ConversationPayload(this.chatId, this.chatType, this.name, this.source);

  String encode() => jsonEncode({
        'chatId': chatId,
        'chatType': chatType,
        'name': name,
        if (source != null) 'source': source,
      });

  static ConversationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'summary') return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['chatId'] as String?;
      if (id == null || id.isEmpty) return null;
      return ConversationPayload(id, map['chatType'] as String? ?? 'direct',
          map['name'] as String? ?? 'Chat', map['source'] as String?);
    } catch (_) {
      return null;
    }
  }
}

({String id, String name}) androidChannelFor(String chatType) =>
    switch (chatType) {
      'group' => (id: 'alinhaja_groups', name: 'Grupos'),
      'channel' => (id: 'alinhaja_channels', name: 'Canais Oficiais'),
      'workflow' => (
          id: 'alinhaja_workflow_alerts',
          name: 'Workflow — atribuições'
        ),
      _ => (id: 'alinhaja_dms', name: 'Mensagens Diretas'),
    };

/// Entry point das ações sem interface (Responder / Marcar como lida).
/// O plugin sempre executa essas ações num isolate de segundo plano.
@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse response) {
  unawaited(ChatNotificationRenderer.handleAction(response));
}

/// Exibição das notificações de conversa no Android, estilo WhatsApp.
/// Seguro para qualquer isolate: não depende de Riverpod nem do router.
class ChatNotificationRenderer {
  ChatNotificationRenderer._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize({
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse:
          notificationActionBackgroundHandler,
    );
  }

  static Future<void> showIncoming(IncomingChatMessage m) async {
    await NotificationStore.append(
      m.chatId,
      NotificationLine(
        sender: m.senderName,
        senderId: m.senderId,
        avatarUrl: m.senderAvatar,
        text: m.text,
        time: DateTime.now().millisecondsSinceEpoch,
      ),
      title: m.title,
      chatType: m.chatType,
      source: m.source,
    );
    await render(m.chatId, mentioned: m.mentioned);
  }

  /// Redesenha a notificação da conversa a partir do cache.
  static Future<void> render(String chatId,
      {bool silent = false, bool mentioned = false}) async {
    final lines = await NotificationStore.lines(chatId);
    if (lines.isEmpty) return dismiss(chatId);
    final title = await NotificationStore.title(chatId) ?? 'Conversa';
    final chatType = await NotificationStore.chatType(chatId) ?? 'direct';
    final source = await NotificationStore.source(chatId);
    final isGroup = chatType != 'direct';
    final channel = androidChannelFor(chatType);

    final visible = lines.length > _visibleLines
        ? lines.sublist(lines.length - _visibleLines)
        : lines;
    final avatars = await _loadAvatars(
        visible.where((l) => !l.fromMe).map((l) => l.avatarUrl));

    const me = Person(name: 'Você', key: 'me');
    final messages = visible.map((l) {
      final person = l.fromMe
          ? me
          : Person(
              name: l.sender,
              key: l.senderId ?? l.sender,
              icon: avatars[l.avatarUrl] == null
                  ? null
                  : ByteArrayAndroidIcon(avatars[l.avatarUrl]!),
            );
      return Message(
          l.text, DateTime.fromMillisecondsSinceEpoch(l.time), person);
    }).toList();

    final last = lines.last;
    final unread = lines.where((l) => !l.fromMe).length;
    final lastReceived = lines.lastWhere((l) => !l.fromMe, orElse: () => last);
    final dmAvatar = !isGroup ? avatars[lastReceived.avatarUrl] : null;

    final details = AndroidNotificationDetails(
      channel.id,
      channel.name,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      styleInformation: MessagingStyleInformation(
        me,
        conversationTitle: isGroup ? title : null,
        groupConversation: isGroup,
        messages: messages,
      ),
      groupKey: kMessagesGroupKey,
      color: AppConstants.primary,
      icon: '@drawable/ic_notification',
      largeIcon: dmAvatar == null ? null : ByteArrayAndroidBitmap(dmAvatar),
      number: unread,
      when: last.time,
      showWhen: true,
      silent: silent,
      onlyAlertOnce: silent,
      subText: mentioned ? 'Mencionou você' : null,
      ticker: '${last.sender}: ${last.text}',
      actions: [
        if (chatType != 'workflow')
          const AndroidNotificationAction(
            kReplyActionId,
            'Responder',
            icon: DrawableResourceAndroidBitmap('ic_notification'),
            inputs: [AndroidNotificationActionInput(label: 'Mensagem')],
            // A notificação continua na bandeja para exibir a resposta.
            cancelNotification: false,
            semanticAction: SemanticAction.reply,
          ),
        const AndroidNotificationAction(
          kMarkReadActionId,
          'Marcar como lida',
          semanticAction: SemanticAction.markAsRead,
        ),
      ],
    );

    await _plugin.show(
      id: stableNotificationId(chatId),
      title: title,
      body: isGroup ? '${last.sender}: ${last.text}' : last.text,
      notificationDetails: NotificationDetails(android: details),
      payload: ConversationPayload(chatId, chatType, title, source).encode(),
    );
    await _renderSummary();
  }

  /// Remove a notificação da conversa (ao abrir o chat ou marcar como lida).
  static Future<void> dismiss(String chatId) async {
    await NotificationStore.clear(chatId);
    await _plugin.cancel(id: stableNotificationId(chatId));
    // Notificações exibidas pela versão anterior usavam `String.hashCode`.
    await _plugin.cancel(id: chatId.hashCode);
    await _renderSummary();
  }

  static Future<void> _renderSummary() async {
    final digests = await NotificationStore.digests();
    if (digests.isEmpty) {
      await _plugin.cancel(id: kSummaryNotificationId);
      return;
    }
    final text = summaryText(digests);
    await _plugin.show(
      id: kSummaryNotificationId,
      title: AppConstants.appName,
      body: text,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'alinhaja_dms',
          'Mensagens Diretas',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          groupKey: kMessagesGroupKey,
          setAsGroupSummary: true,
          // Só a conversa toca; o resumo apenas se atualiza.
          groupAlertBehavior: GroupAlertBehavior.children,
          onlyAlertOnce: true,
          color: AppConstants.primary,
          icon: '@drawable/ic_notification',
          styleInformation: InboxStyleInformation(
            digests.take(5).map(digestLine).toList(),
            contentTitle: AppConstants.appName,
            summaryText: text,
          ),
        ),
      ),
      payload: 'summary',
    );
  }

  /// Notificação simples (workflow, avisos) no mesmo visual das conversas.
  static Future<void> showSimple({
    required String key,
    required String chatType,
    required String title,
    required String body,
    String? payload,
  }) async {
    final channel = androidChannelFor(chatType);
    await _plugin.show(
      id: stableNotificationId(key),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: Importance.high,
          priority: Priority.high,
          color: AppConstants.primary,
          icon: '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
  }

  // ── Ações ──────────────────────────────────────────────────────

  static Future<void> handleAction(NotificationResponse response) async {
    final actionId = response.actionId;
    if (actionId != kReplyActionId && actionId != kMarkReadActionId) return;
    final ctx = ConversationPayload.decode(response.payload);
    if (ctx == null) return;
    final source = sourceFor(
      table: ctx.source ?? await NotificationStore.source(ctx.chatId),
      chatType: ctx.chatType,
    );

    if (actionId == kMarkReadActionId) {
      await NotificationActionBridge.perform(
          kMarkReadActionId, ctx.chatId, source, null);
      await dismiss(ctx.chatId);
      return;
    }

    final text = response.input?.trim() ?? '';
    if (text.isEmpty) {
      // O Android deixa o campo de resposta "enviando" até a notificação ser
      // atualizada: redesenha sem alterar nada.
      await render(ctx.chatId, silent: true);
      return;
    }
    final sent = await NotificationActionBridge.perform(
        kReplyActionId, ctx.chatId, source, text);
    if (sent) {
      // Responder conta como leitura, igual ao WhatsApp.
      await NotificationActionBridge.perform(
          kMarkReadActionId, ctx.chatId, source, null);
    }
    await NotificationStore.append(
      ctx.chatId,
      NotificationLine(
        sender: 'Você',
        text: sent ? text : '⚠️ Não enviada: $text',
        time: DateTime.now().millisecondsSinceEpoch,
        fromMe: true,
      ),
    );
    await render(ctx.chatId, silent: sent);
  }

  // ── Avatares ───────────────────────────────────────────────────

  static Future<Map<String?, Uint8List?>> _loadAvatars(
      Iterable<String?> urls) async {
    final unique = urls.whereType<String>().toSet();
    final result = <String?, Uint8List?>{};
    await Future.wait(unique.map((u) async => result[u] = await _avatar(u)));
    return result;
  }

  /// Baixa, recorta em quadrado de 128 px e guarda por 24 h. O Android aplica
  /// a máscara circular. Qualquer falha devolve null: a notificação sai sem
  /// foto, nunca deixa de sair.
  static Future<Uint8List?> _avatar(String url) async {
    if (!url.startsWith('https://')) return null;
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/notif_avatars/${stableNotificationId(url)}.png');
      if (await file.exists() &&
          DateTime.now().difference(await file.lastModified()) <
              const Duration(hours: 24)) {
        return await file.readAsBytes();
      }
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200 || resp.bodyBytes.length > 5 * 1024 * 1024) {
        return null;
      }
      final bytes = await squareThumbnail(resp.bodyBytes, 128);
      if (bytes == null) return null;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    } catch (e) {
      debugPrint('[Notif] Avatar indisponível: $e');
      return null;
    }
  }
}

/// Recorte central quadrado, redimensionado para [size] px, em PNG.
Future<Uint8List?> squareThumbnail(Uint8List encoded, int size) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final w = descriptor.width, h = descriptor.height;
  if (w == 0 || h == 0) return null;
  // Decodifica já reduzido: o lado menor fica com `size`.
  final scale = size / (w < h ? w : h);
  final codec = await descriptor.instantiateCodec(
    targetWidth: (w * scale).ceil(),
    targetHeight: (h * scale).ceil(),
  );
  final frame = await codec.getNextFrame();
  final src = frame.image;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final dx = (src.width - size) / 2, dy = (src.height - size) / 2;
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(dx, dy, size.toDouble(), size.toDouble()),
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final out = await recorder.endRecording().toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  src.dispose();
  out.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return data?.buffer.asUint8List();
}
