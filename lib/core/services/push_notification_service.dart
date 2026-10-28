import 'dart:io';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/features/settings/providers/notification_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/services/web_notification_service.dart';
import 'package:alinha_ja/core/services/notifications/chat_notification_renderer.dart';
import 'package:alinha_ja/core/services/notifications/notification_action_bridge.dart';
import 'package:alinha_ja/core/services/notifications/notification_actions_gateway.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/services/call_service_callkit_stub.dart'
    if (dart.library.io) 'package:alinha_ja/core/services/call_service_callkit_native.dart'
    as callkit;

/// Provider exposto para o serviço de push notifications.
final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Plugin de notificações locais para exibição agrupada no Android.
final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

/// Responsável por gerenciar permissões FCM, setup local e registro no Supabase.
class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final Ref? _ref;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  RealtimeChannel? _joinRequestsChannel;
  bool _isInitialized = false;
  static bool _launchTapHandled = false;

  PushNotificationService([this._ref]);

  /// Inicializa o Firebase, solicita permissões e registra o Token FCM no banco.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Solicita permissão do usuário
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      _isInitialized = true;
      debugPrint('FCM: Permissão concedida.');

      // 2. Configurar flutter_local_notifications (Android)
      // Falha aqui não pode impedir o registro do token logo abaixo: sem
      // token o aparelho não recebe push nenhum, e `_isInitialized` já está
      // marcado — não haveria nova tentativa até reiniciar o app.
      if (!kIsWeb) {
        try {
          await _setupLocalNotifications();
        } catch (e) {
          debugPrint('FCM: Falha ao configurar notificações locais: $e');
        }
      }

      // 3. Registrar Token (com retry)
      await _registerTokenWithRetry();

      // 4. Listener de rotação de token
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM: Token rotacionado. Registrando novo token...');
        _saveTokenToSupabase(newToken);
      });

      // 5. Setup Listeners de mensagem (Foreground)
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. Listener para quando o usuário clica na notificação (app em background)
      _openedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 7. Verificar se o app foi aberto a partir de uma notificação (app terminado)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      // Inicializa a escuta por solicitações de entrada nos canais (Realtime)
      _listenToChannelJoinRequests();

      // Sincroniza inscrições em tópicos por módulo com base nas permissões
      // já resolvidas (o listener em app.dart cobre mudanças subsequentes).
      final moduleIds = Globals.accessibleModuleIds;
      if (moduleIds != null) {
        await syncModuleTopicSubscriptions(moduleIds);
      }
    } else {
      debugPrint('FCM: Permissão não concedida.');
    }
  }

  /// Estado atual da permissão, sem abrir o pedido ao usuário.
  Future<AuthorizationStatus> permissionStatus() async =>
      (await _messaging.getNotificationSettings()).authorizationStatus;

  /// Pede permissão a partir de um toque do usuário e registra o token.
  ///
  /// No Safari (iPhone com o PWA instalado) o pedido só é aceito dentro de um
  /// gesto; o pedido automático feito no login é recusado em silêncio. O
  /// primeiro `await` de [initialize] é o próprio pedido, então a ativação do
  /// gesto ainda vale quando ele acontece.
  Future<bool> enableFromUserGesture() async {
    await initialize();
    return _isInitialized;
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    final joinRequests = _joinRequestsChannel;
    _joinRequestsChannel = null;
    if (joinRequests != null) supabase.removeChannel(joinRequests);
    _isInitialized = false;
  }

  /// Configura o plugin de notificações locais para exibição agrupada.
  Future<void> _setupLocalNotifications() async {
    // Registra também o handler das ações (Responder / Marcar como lida),
    // que o plugin executa num isolate de segundo plano.
    await ChatNotificationRenderer.initialize(
      onResponse: _handleNotificationResponse,
    );

    // Criar canais de notificação no Android
    await _createAndroidNotificationChannels();

    if (Platform.isAndroid) {
      // As ações rodam em outro isolate; com o app vivo, elas pedem a este
      // isolate que execute com a sessão dele (ver NotificationActionBridge).
      NotificationActionBridge.registerMain(supabase);

      // App aberto por toque numa notificação local com o processo morto:
      // o toque não chega pelo callback nem pelo getInitialMessage do FCM.
      // Os detalhes valem pelo processo inteiro: sem o flag, sair e entrar de
      // novo na conta reabriria a mesma conversa.
      final launch = _launchTapHandled
          ? null
          : await _localNotif.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _launchTapHandled = true;
        Future.delayed(const Duration(milliseconds: 800),
            () => _handleNotificationResponse(response));
      }
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'end_call') {
      CallService.instance.endCall();
      return;
    }
    if (response.actionId == kReplyActionId ||
        response.actionId == kMarkReadActionId) {
      ChatNotificationRenderer.handleAction(response);
      return;
    }

    final payloadStr = response.payload;
    if (payloadStr == null || payloadStr.isEmpty || payloadStr == 'summary') {
      return;
    }
    if (payloadStr.startsWith('workflow:')) {
      final channelId = payloadStr.substring('workflow:'.length);
      if (channelId.isNotEmpty) {
        _navigateToChat(channelId, chatType: 'channel', name: 'Canal');
      }
      return;
    }
    if (payloadStr.startsWith('module:')) return;
    if (payloadStr.startsWith('route:')) {
      _openRoute(payloadStr.substring('route:'.length));
      return;
    }

    final ctx = ConversationPayload.decode(payloadStr);
    if (ctx != null) {
      clearNotificationsForChat(ctx.chatId);
      _navigateToChat(ctx.chatId, chatType: ctx.chatType, name: ctx.name);
    }
  }

  Future<void> _createAndroidNotificationChannels() async {
    final plugin = _localNotif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

    // Canal para Mensagens Diretas - Alta prioridade
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_dms',
      'Mensagens Diretas',
      description: 'Notificações de mensagens diretas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    ));

    // Canal para Grupos - Alta prioridade
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_groups',
      'Grupos',
      description: 'Notificações de grupos',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    // Canal para Canais Oficiais - Prioridade média
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_channels',
      'Canais Oficiais',
      description: 'Notificações de canais da empresa',
      importance: Importance.defaultImportance,
      playSound: true,
    ));

    // Canal para Workflow - Prioridade baixa
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_workflow',
      'Workflow',
      description: 'Notificações de cards e atividades',
      importance: Importance.low,
      playSound: false,
    ));

    // Workflow que pede ação (card atribuído / urgente). Canal separado do
    // `alinhaja_workflow` porque canal Android não muda de importância depois de
    // criado, e aquele nasceu silencioso.
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_workflow_alerts',
      'Workflow — atribuições',
      description: 'Cards atribuídos a você e cards urgentes',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));

    // Canal para Chamadas - Alta prioridade com som contínuo
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'alinhaja_calls',
      'Chamadas',
      description: 'Notificações de chamadas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    // ── Canais por módulo (broadcast de departamento) ──
    // Derivados do registro de módulos: cada módulo com ModuleNotificationSpec
    // ganha seu próprio canal Android. Ver lib/core/modules/module_registry.dart.
    for (final m in modulesWithNotification) {
      final spec = m.notification!;
      await plugin.createNotificationChannel(AndroidNotificationChannel(
        spec.androidChannelId,
        spec.channelName,
        description: spec.description,
        importance: spec.importance,
        playSound: true,
      ));
    }
  }

  /// Sincroniza as inscrições em tópicos FCM por módulo com base nas
  /// permissões do usuário: inscreve nos tópicos `mod_<id>` dos módulos
  /// acessíveis (com `subscribeByDefault`) e desinscreve dos demais.
  ///
  /// Tópicos não são suportados pelo FCM Web da mesma forma, então no Web
  /// esta função é no-op (broadcast por módulo é entregue por outros meios).
  Future<void> syncModuleTopicSubscriptions(
      Set<String> accessibleModuleIds) async {
    if (kIsWeb) return;
    for (final m in modulesWithNotification) {
      final spec = m.notification!;
      if (!spec.subscribeByDefault) continue;
      try {
        if (accessibleModuleIds.contains(m.id)) {
          await _messaging.subscribeToTopic(spec.topic);
        } else {
          await _messaging.unsubscribeFromTopic(spec.topic);
        }
      } catch (e) {
        debugPrint('FCM: erro ao sincronizar tópico ${spec.topic}: $e');
      }
    }
  }

  /// Tenta registrar o token com retry exponential backoff (max 3 tentativas).
  Future<void> _registerTokenWithRetry() async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        String? token;

        if (kIsWeb) {
          token = await _messaging.getToken(
            vapidKey: AppEnv.firebaseVapidKey.isNotEmpty
                ? AppEnv.firebaseVapidKey
                : dotenv.env['FIREBASE_VAPID_KEY'],
          );
        } else {
          token = await _messaging.getToken();
        }

        if (token != null) {
          await _saveTokenToSupabase(token);
          debugPrint(
              'FCM: Token registrado com sucesso na tentativa $attempt.');
          return;
        } else {
          debugPrint('FCM: Token null na tentativa $attempt.');
        }
      } catch (e) {
        debugPrint(
            'FCM: Erro ao registrar token (tentativa $attempt/$maxAttempts): $e');
        if (attempt < maxAttempts) {
          final delay = Duration(seconds: 1 << (attempt - 1));
          debugPrint(
              'FCM: Aguardando ${delay.inSeconds}s antes de tentar novamente...');
          await Future.delayed(delay);
        }
      }
    }
    debugPrint('FCM: Falha ao registrar token após $maxAttempts tentativas.');
  }

  /// Persiste o token FCM na tabela user_fcm_tokens do Supabase.
  Future<void> _saveTokenToSupabase(String token) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('FCM: Usuário não logado, pulando registro de token.');
      return;
    }

    final platformStr =
        kIsWeb ? 'web' : (Platform.isAndroid ? 'android' : 'ios');

    await supabase.from('user_fcm_tokens').upsert(
      {
        'user_id': user.id,
        'token': token,
        'platform': platformStr,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id, token',
    );

    debugPrint('FCM: Token gravado no Supabase ($platformStr).');
  }

  /// Desregistra e deleta o token FCM do banco do Supabase. Chamado ao fazer logoff.
  Future<void> deleteToken() async {
    try {
      final token = kIsWeb
          ? await _messaging.getToken(
              vapidKey: AppEnv.firebaseVapidKey.isNotEmpty
                  ? AppEnv.firebaseVapidKey
                  : dotenv.env['FIREBASE_VAPID_KEY'],
            )
          : await _messaging.getToken();
      final userId = supabase.auth.currentUser?.id;

      if (token != null && userId != null) {
        await supabase
            .from('user_fcm_tokens')
            .delete()
            .match({'user_id': userId, 'token': token});

        await _messaging.deleteToken();
        debugPrint('FCM: Token removido local e DB.');
      }
    } catch (e) {
      debugPrint('FCM: Erro ao deletar token: $e');
    } finally {
      dispose();
    }
  }

  /// Limpa o cache de notificações de um chat (chamado quando o usuário abre o chat).
  Future<void> clearNotificationsForChat(String chatId) =>
      dismissConversationNotification(chatId);

  /// Remove da bandeja a notificação da conversa e o histórico dela.
  /// Chamado ao abrir a conversa. No-op na web (o SW fecha pela URL).
  static Future<void> dismissConversationNotification(String chatId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await ChatNotificationRenderer.dismiss(chatId);
    } catch (e) {
      debugPrint('FCM: Falha ao limpar notificação de $chatId: $e');
    }
  }

  static Future<void> showOngoingCallNotification(String callerName) async {
    if (kIsWeb || !Platform.isAndroid) return;

    // Configuração para notificação persistente (Ongoing)
    const androidDetails = AndroidNotificationDetails(
      'alinhaja_calls',
      'Chamadas',
      importance: Importance.low,
      priority: Priority.low,
      ongoing:
          true, // Torna a notificação fixa pra não ser despachada pelo usuário
      autoCancel: false,
      usesChronometer: true, // Ligar cronômetro
      actions: [
        AndroidNotificationAction('end_call', 'Encerrar Chamada',
            cancelNotification: true, showsUserInterface: true),
      ],
      color: Color(0xFF00B4D8),
      category: AndroidNotificationCategory.call,
      icon: '@mipmap/launcher_icon',
    );

    await _localNotif.show(
      id: 99999, // ID fixo para evitar duplicatas de Call em Anadamneto
      title: 'Chamada em andamento',
      body: callerName,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> cancelOngoingCallNotification() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _localNotif.cancel(id: 99999);
  }

  /// Handler para as mensagens no Foreground (quando o aplicativo está aberto/visível).
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM: Push em Foreground: ${message.notification?.title}');

    // ── Impedir notificação de si mesmo (verifica sender_id E caller_id) ──
    final senderId = message.data['sender_id'] as String?;
    final callerId = message.data['caller_id'] as String?;
    final myId = supabase.auth.currentUser?.id;
    final originatorId = senderId ?? callerId;
    if (originatorId != null && myId != null && originatorId == myId) {
      debugPrint('FCM: Notificação de si mesmo — ignorada.');
      return;
    }

    final chatId = message.data['chat_id'] as String?;
    final chatType = message.data['chat_type'] as String? ?? 'direct';
    final dataType = message.data['type'] as String?;

    // ── INTERCEPTAR CHAMADAS — rotear para CallService (Web + Android) ──
    if (dataType == 'call' ||
        dataType == 'voice' ||
        dataType == 'video' ||
        message.data['call_id'] != null) {
      final callerName = message.data['caller_name'] as String? ?? 'Chamada';
      final realCallId = message.data['call_id'] as String?;
      final isVideoStr = message.data['is_video']?.toString().toLowerCase();
      final isVideo = isVideoStr == 'true' || isVideoStr == '1';

      // Push antigo de chamada em canal mandava chat_id "null".
      final contextId =
          chatId == 'null' ? message.data['channel_id'] as String? : chatId;
      if (contextId != null && contextId.isNotEmpty && contextId != 'null') {
        debugPrint(
            'FCM: Push de chamada em Foreground — acionando CallService.');
        CallService.instance.handleIncomingCall(
          callerName,
          contextId,
          isVideo: isVideo,
          callId: realCallId,
          callerId: callerId,
        );
      }
      return;
    }

    // ── Aviso de conta (pedido recusado, administração recebida) ──
    if (dataType == 'account') {
      final title = message.data['title'] as String? ?? AppConstants.appName;
      final body = message.data['body'] as String? ?? '';
      final route = message.data['route'] as String?;
      if (!kIsWeb && Platform.isAndroid) {
        ChatNotificationRenderer.showSimple(
          key: 'account_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}',
          chatType: 'channel',
          title: title,
          body: body,
          payload: route == null ? null : 'route:$route',
        );
      } else if (!WebNotificationService.showPushIfUnfocused(message.data)) {
        _showWebToast(title: title, body: body, chatType: 'channel');
      }
      return;
    }

    // ── Card de workflow: não tem chat_id, abre o canal do card ──
    if (dataType == 'workflow_card') {
      final prefs = _ref?.read(notificationSettingsProvider);
      if (prefs != null &&
          (!prefs.notificationsEnabled || !prefs.notifyWorkflow)) {
        debugPrint('FCM: Workflow desativado — suprimida.');
        return;
      }
      final title = message.notification?.title ??
          message.data['title'] as String? ??
          'Workflow';
      final body =
          message.notification?.body ?? message.data['body'] as String? ?? '';
      final channelId = message.data['channel_id'] as String?;
      if (!kIsWeb && Platform.isAndroid) {
        ChatNotificationRenderer.showSimple(
          key: 'workflow_${message.data['card_id'] ?? channelId}',
          chatType: 'workflow',
          title: title,
          body: body,
          payload: channelId == null ? null : 'workflow:$channelId',
        );
      } else if (!WebNotificationService.showPushIfUnfocused(message.data)) {
        _showWebToast(
            title: title, body: body, chatId: channelId, chatType: 'channel');
      }
      return;
    }

    // ── Verificar configurações de notificação do usuário (apenas no foreground com Ref) ──
    if (_shouldSuppressForegroundMessageAlert(message)) {
      debugPrint('FCM: App em foreground; alerta de mensagem suprimido.');
      return;
    }

    if (_ref != null) {
      final settings = _ref.read(notificationSettingsProvider);

      // Master toggle
      if (!settings.notificationsEnabled) {
        debugPrint('FCM: Notificações desativadas pelo usuário — suprimida.');
        return;
      }

      // Toggle por módulo (broadcast de departamento): se a mensagem traz um
      // `module` e o usuário desativou aquele módulo, suprime.
      final moduleId = message.data['module'] as String?;
      if (moduleId != null && !settings.isModuleEnabled(moduleId)) {
        debugPrint('FCM: Módulo $moduleId desativado — suprimida.');
        return;
      }

      // Horário silencioso (DND)
      if (settings.doNotDisturbEnabled) {
        final now = TimeOfDay.now();
        final start = settings.dndStartTime;
        final end = settings.dndEndTime;
        final nowMinutes = now.hour * 60 + now.minute;
        final startMinutes = start.hour * 60 + start.minute;
        final endMinutes = end.hour * 60 + end.minute;

        bool isDndActive;
        if (startMinutes <= endMinutes) {
          isDndActive = nowMinutes >= startMinutes && nowMinutes < endMinutes;
        } else {
          isDndActive = nowMinutes >= startMinutes || nowMinutes < endMinutes;
        }
        if (isDndActive) {
          debugPrint('FCM: Horário silencioso ativo — suprimida.');
          return;
        }
      }

      // Filtros por tipo de conversa
      if (chatType == 'direct' && !settings.notifyDm) {
        debugPrint('FCM: DMs desativadas — suprimida.');
        return;
      }
      if (chatType == 'group' && !settings.notifyGroups) {
        debugPrint('FCM: Grupos desativados — suprimida.');
        return;
      }
      if (chatType == 'channel' && !settings.notifyChannels) {
        debugPrint('FCM: Canais desativados — suprimida.');
        return;
      }
      if (chatType == 'workflow' && !settings.notifyWorkflow) {
        debugPrint('FCM: Workflow desativado — suprimida.');
        return;
      }
      if (chatType == 'call' && !settings.notifyCalls) {
        debugPrint('FCM: Chamadas desativadas — suprimida.');
        return;
      }
    }

    // ── Suprimir se o usuário já está na conversa ──
    if (chatId != null && Globals.currentOpenChatId == chatId) {
      debugPrint(
          'FCM: Usuário já está no chat $chatId — notificação suprimida.');
      return;
    }

    final title = message.notification?.title ??
        message.data['title'] as String? ??
        'Nova mensagem';
    final body =
        message.notification?.body ?? message.data['body'] as String? ?? '';

    // No Android, notificação de conversa estilo WhatsApp
    if (!kIsWeb && Platform.isAndroid && chatId != null) {
      final incoming = IncomingChatMessage.fromData(message.data);
      if (incoming != null) {
        ChatNotificationRenderer.showIncoming(incoming);
        return;
      }
    }

    // Na Web com a janela sem foco, notificação do sistema (o toast não seria
    // visto). Com foco, toast in-app elegante style Desktop/PWA.
    if (kIsWeb && WebNotificationService.showPushIfUnfocused(message.data)) {
      return;
    }
    _showWebToast(title: title, body: body, chatId: chatId, chatType: chatType);
  }

  /// Exibe um Toast animado superior no estilo Web/Desktop PWA (também responsivo no mobile web)
  void _showWebToast({
    required String title,
    required String body,
    String? chatId,
    required String chatType,
  }) {
    final context = Globals.navigatorKey.currentContext;
    if (context == null) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final width = MediaQuery.of(context).size.width;
        final isDesktop = width > 600;

        return Positioned(
          top: 32,
          right: isDesktop ? 32 : 16,
          left: isDesktop ? null : 16,
          width: isDesktop ? 360 : null,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, -60 + (60 * value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () {
                  if (chatId != null) {
                    _navigateToChat(chatId, chatType: chatType, name: title);
                  }
                  if (entry.mounted) entry.remove();
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.notifications_active_rounded,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                body,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            if (entry.mounted) entry.remove();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  /// Exibe uma notificação MessagingStyle (padrão WhatsApp) no Android.
  bool _shouldSuppressForegroundMessageAlert(RemoteMessage message) {
    if (_ref == null) return false;

    final chatId = message.data['chat_id'];
    if (chatId == null) return false;

    try {
      // Checar seleção Desktop primeiro (mais rápido e seguro que GoRouter)
      final selection = _ref.read(desktopSelectionProvider);
      if (selection != null && selection.id == chatId) {
        return true; // Suprime pois o chat já está selecionado/aberto
      }

      // Em dispositivos móveis ou se não houver seleção desktop, checar a rota atual
      final context = Globals.navigatorKey.currentContext;
      if (context != null) {
        final location = GoRouterState.of(context).uri.toString();
        if (location.contains('/chat/$chatId') ||
            location.contains('/channel/$chatId')) {
          return true; // Suprime pois está na tela do chat em tela cheia
        }
      }
    } catch (_) {
      // Se houver falha na leitura (ex: contexto inválido ou fora da árvore), não suprimir
    }

    return false; // Se chegou aqui, não está no chat atual, portanto não suprimir (deve mostrar a notificação)
  }

  /// Handler para quando o usuário clica na notificação nos estados Background/Terminated.
  void _handleNotificationTap(RemoteMessage message) {
    if (message.data['type'] == 'account') {
      final route = message.data['route'] as String?;
      if (route != null && route.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () => _openRoute(route));
      }
      return;
    }

    // Card de workflow chega como notificação do sistema e abre o canal.
    if (message.data['type'] == 'workflow_card') {
      final channelId = message.data['channel_id'] as String?;
      if (channelId != null && channelId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToChat(channelId, chatType: 'channel', name: 'Canal');
        });
      }
      return;
    }

    final chatId = message.data['chat_id'] as String?;
    final chatType = message.data['chat_type'] as String? ?? 'direct';
    final title = message.notification?.title ??
        message.data['title'] as String? ??
        'Chat';

    if (chatId != null && chatId.isNotEmpty && chatId != 'null') {
      debugPrint('FCM: Notificação clicada, navegando para chat $chatId');
      // Limpar cache — mensagens "lidas"
      clearNotificationsForChat(chatId);
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateToChat(chatId, chatType: chatType, name: title);
      });
    }
  }

  /// Abre uma rota interna vinda de um aviso de conta. Só aceita caminho do
  /// próprio app — o payload vem do servidor, mas não deve virar URL externa.
  void _openRoute(String route) {
    if (!route.startsWith('/') || route.startsWith('//')) return;
    try {
      final context = Globals.navigatorKey.currentContext;
      if (context == null) return;
      final router = GoRouter.of(context);
      router.go('/chats');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = Globals.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted || route == '/chats') return;
        GoRouter.of(ctx).push(route);
      });
    } catch (e) {
      debugPrint('FCM: Erro ao abrir rota $route: $e');
    }
  }

  /// Navega para a tela de chat ou canal usando o GoRouter global.
  /// Usa navegação em dois passos: primeiro vai para /chats (garante stack limpo),
  /// depois faz push para a conversa. Isso evita que go() destrua e recrie o
  /// provider tree, o que causava perda de mensagens carregadas.
  void _navigateToChat(String chatId,
      {String chatType = 'direct', String name = 'Chat'}) {
    try {
      final context = Globals.navigatorKey.currentContext;
      if (context == null) return;

      final router = GoRouter.of(context);

      // Passo 1: Garantir que estamos na raiz autenticada
      router.go('/chats');

      // Passo 2: Após o frame renderizar /chats, empilhar a conversa por cima
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = Globals.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final r = GoRouter.of(ctx);

        if (chatType == 'channel') {
          r.push('/channel/$chatId');
        } else {
          r.push('/chat/$chatId', extra: {
            'name': name,
            'isGroup': chatType == 'group',
          });
        }
      });
    } catch (e) {
      debugPrint('FCM: Erro ao navegar para chat: $e');
    }
  }

  void _listenToChannelJoinRequests() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final joinRequests = _joinRequestsChannel;
    _joinRequestsChannel = null;
    if (joinRequests != null) supabase.removeChannel(joinRequests);

    _joinRequestsChannel = supabase
        .channel('public:channel_join_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'channel_join_requests',
          callback: (payload) async {
            final newData = payload.newRecord;
            final userId = newData['user_id'] as String?;
            final channelId = newData['channel_id'] as String?;
            final requestId = newData['id'] as String?;
            final status = newData['status'] as String?;

            if (userId == null ||
                channelId == null ||
                requestId == null ||
                status != 'pending') {
              return;
            }
            if (userId == myId) {
              return;
            }

            try {
              final userRes = await supabase
                  .from('users')
                  .select('full_name, avatar_url')
                  .eq('id', userId)
                  .maybeSingle();

              final channelRes = await supabase
                  .from('channels')
                  .select('name')
                  .eq('id', channelId)
                  .maybeSingle();

              if (userRes != null && channelRes != null) {
                final userName =
                    userRes['full_name'] as String? ?? 'Colaborador';
                final avatarUrl = userRes['avatar_url'] as String?;
                final channelName = channelRes['name'] as String? ?? 'Canal';

                _showJoinRequestNotificationPopup(
                  requestId: requestId,
                  userId: userId,
                  userName: userName,
                  avatarUrl: avatarUrl,
                  channelId: channelId,
                  channelName: channelName,
                );
              }
            } catch (e) {
              debugPrint('Erro ao processar notificação de solicitação: $e');
            }
          },
        );

    _joinRequestsChannel!.subscribe();
  }

  void _showJoinRequestNotificationPopup({
    required String requestId,
    required String userId,
    required String userName,
    required String? avatarUrl,
    required String channelId,
    required String channelName,
  }) {
    final context = Globals.navigatorKey.currentContext;
    if (context == null) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        final width = MediaQuery.of(context).size.width;
        final isDesktop = width > 600;

        return Positioned(
          top: 32,
          right: isDesktop ? 32 : 16,
          left: isDesktop ? null : 16,
          width: isDesktop ? 380 : null,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, -60 + (60 * value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade900,
                      Colors.orange.shade800,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_person_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Solicitação de Acesso',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (entry.mounted) entry.remove();
                          },
                          child: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (entry.mounted) entry.remove();
                        Globals.navigatorKey.currentContext
                            ?.go('/channel/$channelId/info', extra: {
                          'channelName': channelName,
                        });
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white24,
                            backgroundImage: avatarUrl != null
                                ? CachedNetworkImageProvider(avatarUrl,
                                    maxWidth: 320)
                                : null,
                            child: avatarUrl == null
                                ? Text(
                                    userName.isNotEmpty
                                        ? userName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Solicitou entrada no canal #$channelName',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          onPressed: () async {
                            if (entry.mounted) entry.remove();
                            try {
                              await supabase
                                  .from('channel_join_requests')
                                  .delete()
                                  .eq('id', requestId);
                              _showQuickFeedback('Solicitação recusada.');
                            } catch (e) {
                              _showQuickFeedback('Erro ao recusar: $e',
                                  isError: true);
                            }
                          },
                          child: const Text('Recusar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.orange.shade900,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            if (entry.mounted) entry.remove();
                            try {
                              await supabase
                                  .from('channel_join_requests')
                                  .update({'status': 'approved'}).eq(
                                      'id', requestId);
                              _showQuickFeedback('Solicitação aprovada!');
                            } catch (e) {
                              _showQuickFeedback('Erro ao aprovar: $e',
                                  isError: true);
                            }
                          },
                          child: const Text(
                            'Aprovar',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Timer(const Duration(seconds: 12), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  void _showQuickFeedback(String msg, {bool isError = false}) {
    final context = Globals.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Horário silencioso ativo? Formato salvo pelo provider: "H:M".
/// Valor malformado não pode derrubar o handler: conta como inativo.
bool isQuietHoursActive(String start, String end, TimeOfDay now) {
  int? minutes(String v) {
    final parts = v.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  final s = minutes(start), e = minutes(end);
  if (s == null || e == null || s == e) return false;
  final n = now.hour * 60 + now.minute;
  return s < e ? (n >= s && n < e) : (n >= s || n < e);
}

/// Handler Root-level isolado do Flutter para mensagens Background / Terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
      'FCM: Background message recebida (${message.data['type'] ?? 'chat'}).');

  if (kIsWeb || !Platform.isAndroid) return;

  final data = message.data;
  final chatId = data['chat_id'] as String?;
  final chatType = data['chat_type'] as String? ?? 'direct';

  // O isolate do FCM sobrevive entre mensagens: sem reload, uma preferência
  // alterada no app (ex.: desligar DMs) só valeria após matar o processo.
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  // Registra o handler das ações também neste isolate: ele pode ser o
  // primeiro a inicializar o plugin depois de um boot do aparelho.
  await ChatNotificationRenderer.initialize();

  // ── Broadcast de módulo (data-only, sem chat) — ex.: alertas do RH ──
  final moduleId = data['module'] as String?;
  if (moduleId != null && chatId == null) {
    if (!(prefs.getBool('notif_enabled') ?? true)) return;
    if (!(prefs.getBool('notif_mod_$moduleId') ?? true)) return;

    final spec = moduleById(moduleId)?.notification;
    if (spec == null) return;

    await _localNotif.show(
      id: stableNotificationId('mod_$moduleId'),
      title: data['title'] as String? ?? spec.channelName,
      body: data['body'] as String? ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          spec.androidChannelId,
          spec.channelName,
          channelDescription: spec.description,
          importance: spec.importance,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: AppConstants.primary,
        ),
      ),
      payload: 'module:$moduleId',
    );
    return;
  }

  // ── Aviso de conta: não depende de conversa nem das preferências de chat ──
  if (data['type'] == 'account') {
    final route = data['route'] as String?;
    await ChatNotificationRenderer.showSimple(
      key: 'account_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}',
      chatType: 'channel',
      title: data['title'] as String? ?? AppConstants.appName,
      body: data['body'] as String? ?? '',
      payload: route == null ? null : 'route:$route',
    );
    return;
  }

  if (chatId == null || chatId.isEmpty) return;

  // ── BYPASS PARA CHAMADAS: Deve tocar SEMPRE, mesmo com chat silenciado ou DND ativo ──
  final isCall = data['type'] == 'call' ||
      data['type'] == 'voice' ||
      data['type'] == 'video' ||
      data['call_id'] != null ||
      chatType == 'call';

  if (isCall) {
    // Push antigo de chamada em canal mandava chat_id "null"; o id útil
    // nesse caso é o channel_id.
    final contextId = chatId == 'null' ? data['channel_id'] as String? : chatId;
    if (contextId == null || contextId.isEmpty || contextId == 'null') return;
    final isVideoStr = data['is_video']?.toString().toLowerCase();
    callkit.showIncomingCall(
      data['caller_name'] as String? ?? data['title'] as String? ?? 'Chamada',
      data['caller_id'] as String? ?? '',
      avatar: data['caller_avatar'] as String? ?? '',
      isVideo: isVideoStr == 'true' || isVideoStr == '1',
      callId: data['call_id'] as String?,
      chatId: contextId,
    );
    return;
  }

  // ── LER CONFIGURAÇÕES DO USUÁRIO PARA MENSAGENS NORMAIS ──
  if (!(prefs.getBool('notif_enabled') ?? true)) return;
  if (chatType == 'direct' && !(prefs.getBool('notif_dm') ?? true)) return;
  if (chatType == 'group' && !(prefs.getBool('notif_groups') ?? true)) return;
  if (chatType == 'channel' && !(prefs.getBool('notif_channels') ?? true)) {
    return;
  }
  if ((prefs.getBool('notif_dnd') ?? false) &&
      isQuietHoursActive(prefs.getString('notif_dnd_start') ?? '22:0',
          prefs.getString('notif_dnd_end') ?? '8:0', TimeOfDay.now())) {
    return;
  }

  final incoming = IncomingChatMessage.fromData(data);
  if (incoming != null) {
    await ChatNotificationRenderer.showIncoming(incoming);
  }
}
