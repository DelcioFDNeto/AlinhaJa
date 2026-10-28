import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/services/push_notification_service.dart';
import 'package:alinha_ja/core/services/mirotalk_service.dart';
import 'package:alinha_ja/core/services/web_notification_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionActions, PermissionStatusGetters;

// Importação condicional: CallKit somente no nativo
import 'call_service_callkit_stub.dart'
    if (dart.library.io) 'call_service_callkit_native.dart' as callkit;

/// Serviço singleton responsável por:
/// - Gerenciar o ciclo de vida do RtcEngine (Agora.io) — Web + Nativo
/// - Iniciar/receber chamadas via CallKit (nativo) ou In-App Dialog (web)
/// - Controlar joinChannel / leaveChannel
/// - Navegação para a tela de chamada ativa
class CallService {
  static final CallService instance = CallService._internal();
  CallService._internal();

  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isInCall = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isScreenSharing = false;
  String? _currentCallId;
  String? _currentChannelName;
  String? _currentCallerName;
  bool _isCurrentCallVideo = false;
  bool _isMeetingHost = false;
  String? mirotalkUrl;
  static String? lastJoinedRoomUrl; // Armazena a última URL usada para join
  final MiroTalkService _miroTalk = MiroTalkService();

  // Web Ringtone Player
  AudioPlayer? _webRingtonePlayer;

  // Flag para evitar race condition no endCall
  bool _isEndingCall = false;

  // Armazena se a chamada atual é uma videochamada (meetings)
  bool get isCurrentCallVideo => _isCurrentCallVideo;

  QualityType _rxNetworkQuality = QualityType.qualityUnknown;
  QualityType _txNetworkQuality = QualityType.qualityUnknown;
  QualityType get rxNetworkQuality => _rxNetworkQuality;
  QualityType get txNetworkQuality => _txNetworkQuality;

  // Estado de Grupo / Active Speaker e Presence ─────────────────────────────

  // Estado de Grupo / Active Speaker e Presence
  final Set<int> activeRemoteUids = {};
  final Map<int, bool> activeSpeakers = {};

  // Mapeamento dinâmico de UIDs numéricos para Nomes Reais (Web/Mobile cruzado)
  RealtimeChannel? _presenceChannel;
  final Map<int, String> participantNames = {};

  // Estado público para a UI
  bool get isInCall => _isInCall;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isScreenSharing => _isScreenSharing;

  String? get currentCallId => _currentCallId;
  String? get currentChannelName => _currentChannelName;
  String? get currentCallerName => _currentCallerName;
  String? get currentChatId {
    if (_currentChannelName == null) return null;
    if (_currentChannelName!.startsWith('call_')) {
      return _currentChannelName!.replaceFirst('call_', '');
    }
    if (_currentChannelName!.startsWith('room_')) {
      return _currentChannelName!.replaceFirst('room_', '');
    }
    return null;
  }

  RtcEngine? get engine => _engine;

  // Callbacks para a UI reagir
  final List<VoidCallback> _onCallStateChangedListeners = [];

  void addOnCallStateChangedListener(VoidCallback listener) {
    if (!_onCallStateChangedListeners.contains(listener)) {
      _onCallStateChangedListeners.add(listener);
    }
  }

  void removeOnCallStateChangedListener(VoidCallback listener) {
    _onCallStateChangedListeners.remove(listener);
  }

  void _notifyCallStateChanged() {
    for (final listener
        in List<VoidCallback>.from(_onCallStateChangedListeners)) {
      try {
        listener();
      } catch (e, stack) {
        debugPrint('📞 Erro ao notificar listener de chamada: $e\n$stack');
      }
    }
  }

  Timer? _speakersNotifyTimer;

  /// "Quem está falando" muda várias vezes por segundo (indicação de volume
  /// a cada 250 ms). Cada notificação reconstrói todas as telas da chamada —
  /// na web, com as views de vídeo HTML junto. Agrupa em no máximo uma
  /// notificação a cada 300 ms.
  void _notifySpeakersChanged() {
    if (_speakersNotifyTimer?.isActive ?? false) return;
    _speakersNotifyTimer =
        Timer(const Duration(milliseconds: 300), _notifyCallStateChanged);
  }

  void _resetLocalCallState({bool notify = true}) {
    _speakersNotifyTimer?.cancel();
    _isInCall = false;
    _isMuted = false;
    _isSpeakerOn = false;
    _isCurrentCallVideo = false;
    _isScreenSharing = false;
    _isMeetingHost = false;
    _currentCallId = null;
    _currentChannelName = null;
    _currentCallerName = null;
    activeRemoteUids.clear();
    activeSpeakers.clear();
    participantNames.clear();

    if (notify) {
      _notifyCallStateChanged();
    }
  }

  final List<Function(int)> _onRemoteUserJoinedListeners = [];
  final List<Function(int)> _onRemoteUserLeftListeners = [];

  void addRemoteUserJoinedListener(Function(int) listener) =>
      _onRemoteUserJoinedListeners.add(listener);
  void removeRemoteUserJoinedListener(Function(int) listener) =>
      _onRemoteUserJoinedListeners.remove(listener);

  void addRemoteUserLeftListener(Function(int) listener) =>
      _onRemoteUserLeftListeners.add(listener);
  void removeRemoteUserLeftListener(Function(int) listener) =>
      _onRemoteUserLeftListeners.remove(listener);

  Timer? _ringTimeoutTimer;

  // Canais Supabase para limpeza
  RealtimeChannel? _ringingChannel;
  RealtimeChannel? _updatesChannel;
  RealtimeChannel? _meetingsChannel;

  // ─── Inicialização ─────────────────────────────────────────

  Future<void> init() async {
    if (_isInitialized) {
      if (_engine == null) {
        await _initAgoraEngine();
      }
      return;
    }

    // 1. CallKit: apenas no nativo (Android/iOS)
    if (!kIsWeb) {
      callkit.initCallKitListeners(_handleCallAccepted, _handleCallDeclined,
          _handleCallEnded, _handleCallTimeout);
    }

    // 2. Agora RtcEngine: funciona em TODAS as plataformas (Web + Nativo)
    await _initAgoraEngine();

    _listenForIncomingCalls();
    _isInitialized = true;
  }

  /// Desliga todos os canais de background do Supabase e o RtcEngine para liberar memória.
  void dispose() {
    _isInitialized = false;
    _onCallStateChangedListeners.clear();

    // removeChannel: no próximo login o init() cria os canais de novo, e
    // os antigos (só desinscritos) seguiam no cliente.
    for (final channel in [_ringingChannel, _updatesChannel, _meetingsChannel]) {
      if (channel != null) supabase.removeChannel(channel);
    }
    _ringingChannel = null;
    _updatesChannel = null;
    _meetingsChannel = null;

    if (_presenceChannel != null) {
      _presenceChannel!.untrack();
      supabase.removeChannel(_presenceChannel!);
      _presenceChannel = null;
    }

    if (_engine != null) {
      _engine!.leaveChannel();
      _engine!.release();
      _engine = null;
    }
  }

  /// Escuta a tabela `calls` e `meetings` via Realtime para disparar a UI de "Tocando" (CallKit ou In-App)
  void _listenForIncomingCalls() {
    // Escuta chamadas de ÁUDIO da tabela calls
    _ringingChannel = supabase
        .channel('public:calls_ringing')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'status',
            value: 'ringing',
          ),
          callback: (payload) async {
            final newCall = payload.newRecord;
            final callerId = newCall['caller_id'] as String?;
            final chatId = newCall['chat_id'] as String?;
            final currentUserId = supabase.auth.currentUser?.id;

            if (callerId == currentUserId) {
              debugPrint(
                  '📞 Chamada originada por mim — ignorando trigger de toque local.');
              return;
            }

            String callerName = 'Desconhecido';
            try {
              if (callerId != null) {
                final callerData = await supabase
                    .from('users')
                    .select('full_name')
                    .eq('id', callerId)
                    .maybeSingle();
                if (callerData != null) {
                  callerName = callerData['full_name'] as String;
                }
              }
            } catch (e) {
              debugPrint('Erro ao buscar nome do caller: $e');
            }

            final realCallId = newCall['id'] as String?;
            final callType = newCall['type'] as String?;
            final isVideoCall = callType == 'video';

            if (chatId != null) {
              debugPrint(
                  '📞 Nova chamada de ${isVideoCall ? "VÍDEO" : "ÁUDIO"} recebida de $callerName!');
              handleIncomingCall(callerName, chatId,
                  isVideo: isVideoCall, callId: realCallId, callerId: callerId);
            }
          },
        )
        .subscribe();

    // Escuta atualizações no status das chamadas de ÁUDIO (Ex: missed, ended, rejected) para fechar o CallKit/Ringing UI
    _updatesChannel = supabase
        .channel('public:calls_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          callback: (payload) async {
            final updated = payload.newRecord;
            final status = updated['status'] as String?;
            final callId = updated['id'] as String?;

            if (callId == _currentCallId &&
                (status == 'missed' ||
                    status == 'ended' ||
                    status == 'in_progress' ||
                    status == 'rejected')) {
              if (status == 'in_progress' && _isInCall) {
                // Eu mesmo atendi neste dispositivo
                return;
              }

              debugPrint(
                  '📞 Supabase Update: Chamada ($status). Fechando UI ativa...');
              _closeWebIncomingCallDialogIfNeeded();

              if (status != 'in_progress') {
                // FORÇA limpeza imediata do estado para que a UI reaja AGORA
                final shouldLeaveChannel = _currentChannelName != null;
                _resetLocalCallState();
                if (shouldLeaveChannel) {
                  leaveChannel();
                }
                if (!kIsWeb) callkit.endAllCalls();
              } else {
                // Outro dispositivo atendeu. Apenas resetamos o rastreio local.
                _currentCallId = null;
                _currentChannelName = null;
                _currentCallerName = null;
                _isCurrentCallVideo = false;
              }
            }
          },
        )
        .subscribe();

    // Escuta chamadas de VÍDEO da tabela meetings (videochamadas)
    _meetingsChannel = supabase
        .channel('public:meetings_started')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meetings',
          callback: (payload) async {
            // DESABILITADO: Não mostra UI automaticamente
            // Usuários entram manualmente pelo card no chat
          },
        )
        .subscribe();

    // Escuta atualizações no status das chamadas de VÍDEO (Ex: missed, ended, rejected) para fechar o CallKit/Ringing UI
    supabase
        .channel('public:meetings_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meetings',
          callback: (payload) async {
            final updated = payload.newRecord;
            final status = updated['status'] as String?;
            final callId = updated['id'] as String?;

            if (callId != _currentCallId) {
              return;
            }

            if (callId == _currentCallId &&
                (status == 'missed' ||
                    status == 'ended' ||
                    status == 'in_progress' ||
                    status == 'rejected')) {
              if (status == 'in_progress' && _isInCall) {
                return;
              }

              debugPrint(
                  '📞 Supabase Update: Videocall ($status). Fechando UI ativa...');
              _closeWebIncomingCallDialogIfNeeded();

              if (status != 'in_progress') {
                // FORÇA limpeza imediata do estado para que a UI reaja AGORA
                final shouldLeaveChannel = _currentChannelName != null;
                _resetLocalCallState();
                if (shouldLeaveChannel) {
                  leaveChannel();
                }
                if (!kIsWeb) callkit.endAllCalls();
              } else {
                _currentCallId = null;
                _currentChannelName = null;
                _currentCallerName = null;
                _isCurrentCallVideo = false;
              }
            }
          },
        )
        .subscribe();
  }

  /// Inicializa o motor Agora.io com o App ID do .env
  Future<void> _initAgoraEngine() async {
    if (_engine != null) {
      debugPrint('📞 Agora: Engine já inicializado.');
      return;
    }

    final appId = AppEnv.agoraAppId.isNotEmpty
        ? AppEnv.agoraAppId
        : dotenv.env['AGORA_APP_ID'];
    if (appId == null || appId.isEmpty || appId == 'COLE_SEU_APP_ID_AQUI') {
      debugPrint('⚠️ Agora: AGORA_APP_ID não configurado no .env');
      return;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));

      // Perfil de áudio corporativo de alta qualidade
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Event handlers
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) async {
          debugPrint(
              '📞 Agora: Entrou no canal ${connection.channelId} em ${elapsed}ms');
          _isInCall = true;
          _setupPresence(connection.channelId, connection.localUid);

          _notifyCallStateChanged();
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('📞 Agora: Saiu do canal. Duração: ${stats.duration}s');
          _isInCall = false;
          _isSpeakerOn = false;
          _isScreenSharing = false;
          activeRemoteUids.clear();
          activeSpeakers.clear();

          _removePresenceChannel();
          participantNames.clear();

          _notifyCallStateChanged();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('📞 Agora: Usuário remoto $remoteUid entrou');
          _ringTimeoutTimer?.cancel();
          activeRemoteUids.add(remoteUid);
          for (final listener in _onRemoteUserJoinedListeners) {
            try {
              listener(remoteUid);
            } catch (e, stack) {
              debugPrint('📞 Erro em listener onRemoteUserJoined: $e\n$stack');
            }
          }
          _notifyCallStateChanged();
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint(
              '📞 Agora: Usuário remoto $remoteUid saiu (${reason.name})');
          activeRemoteUids.remove(remoteUid);
          activeSpeakers.remove(remoteUid);
          for (final listener in _onRemoteUserLeftListeners) {
            try {
              listener(remoteUid);
            } catch (e, stack) {
              debugPrint('📞 Erro em listener onRemoteUserLeft: $e\n$stack');
            }
          }
          _notifyCallStateChanged();

          // Se for a última pessoa numa chamada 1:1, encerramos IMEDIATAMENTE (Limpeza de Interface)
          if (_currentChannelName != null && activeRemoteUids.isEmpty) {
            debugPrint(
                'Agora: Último usuário saiu da chamada. Encerrando imediatamente...');
            endCall();
          }
        },
        onAudioVolumeIndication: (RtcConnection connection,
            List<AudioVolumeInfo> speakers,
            int speakerNumber,
            int totalVolume) {
          bool changed = false;
          for (final speaker in speakers) {
            final uid = speaker.uid ?? 0;
            // uid == 0 é o próprio usuário local
            final isActive = (speaker.volume ?? 0) > 5;
            if (activeSpeakers[uid] != isActive) {
              activeSpeakers[uid] = isActive;
              changed = true;
            }
          }
          if (changed) _notifySpeakersChanged();
        },
        onNetworkQuality: (RtcConnection connection, int remoteUid,
            QualityType txQuality, QualityType rxQuality) {
          if (remoteUid == 0) {
            if (_txNetworkQuality != txQuality ||
                _rxNetworkQuality != rxQuality) {
              _txNetworkQuality = txQuality;
              _rxNetworkQuality = rxQuality;
              _notifyCallStateChanged();
            }
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('📞 Agora ERRO: $err → $msg');
        },
      ));

      debugPrint(
          '📞 Agora: Engine inicializado com sucesso (${kIsWeb ? "Web" : "Nativo"}).');
    } catch (e) {
      debugPrint('📞 Agora: Erro ao inicializar engine: $e');
    }
  }

  /// Configura o mapa de presenças para traduzir User ID do Agora para nome real.
  void _setupPresence(String? channelName, int? localUid) {
    if (channelName == null || localUid == null) return;
    _removePresenceChannel();
    participantNames.clear();

    final myName =
        supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
            'Usuário';

    // Os callbacks usam ESTE canal, não o campo: um "closed" atrasado da
    // chamada anterior derrubava o canal da chamada nova.
    final channel = supabase.channel('presence:call_$channelName');
    _presenceChannel = channel;
    bool isCurrent() => identical(_presenceChannel, channel);

    channel.onPresenceSync((_) {
      if (!isCurrent()) return;
      final states = channel.presenceState();
      bool changed = false;
      for (final state in states) {
        for (final presence in state.presences) {
          final pUid = presence.payload['uid'] as int?;
          final pName = presence.payload['name'] as String?;
          if (pUid != null && pName != null) {
            if (participantNames[pUid] != pName) {
              participantNames[pUid] = pName;
              changed = true;
            }
          }
        }
      }
      if (changed) {
        _notifyCallStateChanged();
      }
    });

    channel.subscribe((status, [error]) async {
      if (!isCurrent()) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await channel.track({
            'uid': localUid,
            'name': myName,
          }).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('📞 Erro no track de presença (timeout): $e');
          if (isCurrent()) _removePresenceChannel();
        }
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed) {
        debugPrint('📞 Erro/Fechamento no canal de presença. Limpando...');
        _removePresenceChannel();
      }
    });
  }

  // ─── Callbacks do CallKit (Nativo) ─────────────────────────

  void _handleCallAccepted(Map<dynamic, dynamic> body) {
    if (_isInCall) {
      debugPrint(
          '📞 CallKit Aceite ignorado: o usuário já está em outra chamada ativa.');
      return;
    }

    final callId = body['id'] as String?;
    final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
    final callerName = body['nameCaller'] as String? ?? 'Desconhecido';
    final chatId = extra['chatId'] as String? ?? '';
    final isVideo = extra['isVideo'] == true;

    _currentCallId = callId;
    _currentChannelName = 'call_$chatId';
    _isCurrentCallVideo = isVideo;

    _acceptAndJoin(callerName, chatId, isVideo: isVideo);
  }

  void _handleCallDeclined(Map<dynamic, dynamic> body) {
    final callId = body['id'] as String?;
    final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
    _isCurrentCallVideo = extra['isVideo'] == true;

    _updateCallStatus(callId, 'rejected',
        table: _isCurrentCallVideo ? 'meetings' : 'calls');
    leaveChannel();

    // Garante reset do estado
    _isInCall = false;
    _currentCallId = null;
    _currentChannelName = null;
    _currentCallerName = null;
    _isCurrentCallVideo = false;
    _notifyCallStateChanged();

    if (!kIsWeb) callkit.endAllCalls();
    debugPrint('📞 CallKit: Chamada recusada — estado limpo');
  }

  void _handleCallEnded(Map<dynamic, dynamic> body) {
    _ringTimeoutTimer?.cancel();
    final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
    _isCurrentCallVideo = extra['isVideo'] == true;
    endCall();
  }

  void _handleCallTimeout(Map<dynamic, dynamic> body) {
    final callId = body['id'] as String?;
    final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
    _isCurrentCallVideo = extra['isVideo'] == true;

    _updateCallStatus(callId, 'missed',
        table: _isCurrentCallVideo ? 'meetings' : 'calls');
    leaveChannel();

    // Garante reset do estado
    _isInCall = false;
    _currentCallId = null;
    _currentChannelName = null;
    _currentCallerName = null;
    _isCurrentCallVideo = false;
    _notifyCallStateChanged();

    PushNotificationService.cancelOngoingCallNotification();
    if (!kIsWeb) callkit.endAllCalls();
    debugPrint('📞 CallKit: Chamada expirou (missed) — estado limpo');
  }

  // ─── LOTE 3: Compartilhamento de Tela ──────────────────────

  Future<void> toggleScreenShare() async {
    if (_engine == null) return;

    try {
      if (_isScreenSharing) {
        await _engine!.stopScreenCapture();
        _isScreenSharing = false;
      } else {
        await _engine!.startScreenCapture(const ScreenCaptureParameters2(
          captureAudio: true,
          captureVideo: true,
        ));
        _isScreenSharing = true;
      }

      // Atualiza as opções do canal para transmitir a tela ao invés da câmera (ou junto)
      await _engine!.updateChannelMediaOptions(
        ChannelMediaOptions(
          publishScreenTrack: _isScreenSharing,
          publishScreenCaptureAudio: _isScreenSharing,
          publishScreenCaptureVideo: _isScreenSharing,
          publishCameraTrack: !_isScreenSharing,
        ),
      );

      _notifyCallStateChanged();
    } catch (e) {
      debugPrint('📞 Agora: Falha ao alternar screen share: $e');
    }
  }

  // ─── Aceitar e Entrar ──────────────────────────────────────

  Future<void> _acceptAndJoin(String callerName, String chatId,
      {bool isVideo = false}) async {
    // Reset da flag de encerramento ao aceitar nova chamada
    _isEndingCall = false;

    // Solicitar permissão de microfone no nativo
    if (!kIsWeb) {
      // No nativo, permissões são concedidas via request do sistema
    }

    // Atualizar status no Supabase
    _updateCallStatus(_currentCallId, 'in_progress',
        table: isVideo ? 'meetings' : 'calls');

    // Navegar para a tela ativa IMEDIATAMENTE (desbloqueia a UI para o usuário)
    _navigateToActiveCall(callerName, chatId, isVideo: isVideo);

    // Dar tempo (300ms) para o navegador renderizar a janela de vídeo antes de travar a thread JS nativa
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Entrar no canal de áudio/vídeo Agora com proteção
    try {
      await joinChannel(_currentChannelName ?? 'call_$chatId',
          isVideoEnabled: isVideo);
    } catch (e) {
      _updateCallStatus(_currentCallId, 'rejected',
          table: isVideo ? 'meetings' : 'calls');
      final ctx = Globals.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted && Navigator.of(ctx).canPop()) {
        Navigator.of(ctx).pop();
      }
      debugPrint('📞 Erro crítico ao processar mídia: $e');
    }
  }

  // ─── Obter Token Dinâmico da Edge Function ──────────────────

  Future<String> _fetchAgoraToken(String channelName) async {
    try {
      debugPrint(
          '📞 Agora: Solicitando token dinâmico para canal "$channelName"...');
      final response = await supabase.functions.invoke(
        'get-agora-token',
        body: {
          'channelName': channelName,
          'uid': 0,
        },
      );

      if (response.status == 200 && response.data != null) {
        final token = response.data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          debugPrint('📞 Agora: Token dinâmico obtido com sucesso!');
          return token;
        }
      }
      debugPrint(
          '📞 Agora: Retorno inválido da Edge Function: status=${response.status}');
    } catch (e) {
      debugPrint(
          '📞 Agora: Falha ao obter token dinâmico da Edge Function: $e');
    }

    // SEGURANÇA: nunca entrar no canal sem token autenticado pelo servidor.
    // O fallback anterior permitia join com token vazio (modo inseguro),
    // possibilitando que qualquer pessoa com o nome do canal acessasse a chamada.
    throw Exception(
      'Não foi possível obter o token de chamada. Verifique sua conexão e tente novamente.',
    );
  }

  // ─── Controle do Canal Agora ───────────────────────────────

  Future<void> joinChannel(String channelName,
      {bool isVideoEnabled = false}) async {
    if (_engine == null) {
      debugPrint(
          '📞 Agora: Engine nulo no joinChannel, tentando inicializar de forma tardia...');
      await _initAgoraEngine();
    }

    final appId = AppEnv.agoraAppId.isNotEmpty
        ? AppEnv.agoraAppId
        : dotenv.env['AGORA_APP_ID'];
    if (_engine == null ||
        appId == null ||
        appId.isEmpty ||
        appId == 'COLE_SEU_APP_ID_AQUI') {
      debugPrint('📞 Agora: Engine não inicializado ou App ID não configurado');
      return;
    }

    // O app não pede mais permissões no boot, e quem ATENDE uma chamada chega
    // aqui sem nenhum pedido anterior. Sem câmera, entra só com áudio; sem
    // microfone, entra ouvindo — e avisa.
    if (!kIsWeb) {
      final micOk = (await Permission.microphone.request()).isGranted;
      if (isVideoEnabled && !(await Permission.camera.request()).isGranted) {
        isVideoEnabled = false;
      }
      if (!micOk) {
        Globals.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
                'Sem permissão de microfone: os outros participantes não vão te ouvir.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    try {
      if (isVideoEnabled) {
        await _engine!.enableVideo();

        // Perfil de vídeo universal cross-platform (Web ↔ Android):
        // 640x480 garante compatibilidade VP8/H264 entre Chrome e Android nativo.
        // orientationMode adaptive deixa o SDK detectar orientação do dispositivo.
        await _engine!.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 640, height: 480),
            frameRate: 30,
            bitrate: 0, // 0 = automático baseado na resolução
            orientationMode: OrientationMode.orientationModeAdaptive,
            mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
            degradationPreference: DegradationPreference.maintainBalanced,
          ),
        );

        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }
      await _engine!.enableAudio();
      // Ativa o indicador de volume (intervalo de 250ms, suavização 3)
      await _engine!.enableAudioVolumeIndication(
          interval: 250, smooth: 3, reportVad: true);
    } catch (e) {
      debugPrint('📞 Agora: Falha segura no enableAudio/Video: $e');
      final errorStr = e.toString().toLowerCase();
      String userMessage = 'Não foi possível acessar a câmera ou microfone.';
      if (errorStr.contains('permission') ||
          errorStr.contains('allowed') ||
          errorStr.contains('denied')) {
        userMessage =
            'Permissão de câmera/microfone negada. Verifique as configurações de privacidade do seu dispositivo.';
      } else if (errorStr.contains('notfound') || errorStr.contains('device')) {
        userMessage = 'Câmera ou microfone não detectados no seu dispositivo.';
      }

      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(userMessage)),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (!kIsWeb) {
      try {
        await _engine!.setEnableSpeakerphone(false);
      } catch (e) {
        debugPrint('📞 Agora: Falha segura no setEnableSpeakerphone: $e');
      }
    }

    final token = await _fetchAgoraToken(channelName);

    try {
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideoEnabled,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      _currentChannelName = channelName;
      debugPrint(
          '📞 Agora: joinChannel("$channelName") solicitado com sucesso');
    } catch (e) {
      debugPrint('📞 Agora: Falha CRÍTICA no joinChannel: $e');
      rethrow;
    }
  }

  /// Entrar em uma chamada em andamento (join ativo)
  Future<void> joinOngoingCall(String callId, String channelName,
      String callerName, String chatId, bool isVideo) async {
    if (_isInCall) {
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Você já está em uma chamada. Encerre-a primeiro.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _isEndingCall = false;
    _currentCallId = callId;
    _currentChannelName = channelName;
    _currentCallerName = callerName;
    _isCurrentCallVideo = isVideo;

    // IMPORTANTÍSSIMO: Força o estado para true ANTES de navegar,
    // para evitar que o _ActiveCallScreen pop imediatamente achando que a call acabou.
    _isInCall = true;
    _notifyCallStateChanged();

    await joinChannel(channelName, isVideoEnabled: isVideo);
  }

  Future<void> leaveChannel() async {
    if (_engine == null) {
      _resetLocalCallState();
      return;
    }

    try {
      final engine = _engine!;
      // Lido antes do reset, que zera a flag.
      final wasSharingScreen = _isScreenSharing;

      // Libera a UI antes do Agora finalizar o teardown. Em Android/Web o
      // leaveChannel pode demorar quando o outro lado encerra a chamada.
      _resetLocalCallState();

      // Desliga o que o join ligou, cada passo com teto de tempo. Na web uma
      // chamada ao SDK pode ficar pendurada, e sem teto as seguintes não
      // rodavam: câmera, preview e captura de tela seguiam ativos depois da
      // chamada, consumindo CPU/GPU até travar o dispositivo.
      if (wasSharingScreen) {
        await _teardownStep('stopScreenCapture', engine.stopScreenCapture);
      }
      await _teardownStep('stopPreview', engine.stopPreview);
      // Na web, o navegador segura a trilha de mídia ativa (luz vermelha)
      // se não for explicitamente desativada antes do leaveChannel.
      if (kIsWeb) {
        await _teardownStep('disableAudio', engine.disableAudio);
        await _teardownStep('disableVideo', engine.disableVideo);
      }
      await _teardownStep('leaveChannel', engine.leaveChannel);
      _removePresenceChannel();

      debugPrint('📞 Agora: leaveChannel() executado');
    } catch (e) {
      debugPrint('📞 Agora: Erro ao sair do canal: $e');
      _resetLocalCallState();
    }
  }

  Future<void> _teardownStep(String name, Future<void> Function() step) async {
    try {
      await step().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('📞 Agora: $name falhou no encerramento: $e');
    }
  }

  /// Sai do canal de presença e o REMOVE do cliente Realtime. Só o
  /// `unsubscribe` deixava um canal morto por chamada no cliente — e o de
  /// mesmo tópico, recriado na chamada seguinte, disputava a entrada.
  void _removePresenceChannel() {
    final channel = _presenceChannel;
    _presenceChannel = null;
    if (channel != null) unawaited(supabase.removeChannel(channel));
  }

  Future<void> toggleMute() async {
    if (_engine == null) return;
    _isMuted = !_isMuted;
    await _engine!.muteLocalAudioStream(_isMuted);
    _notifyCallStateChanged();
  }

  Future<void> toggleSpeaker() async {
    if (_engine == null || kIsWeb) return; // Speaker toggle não existe na Web
    _isSpeakerOn = !_isSpeakerOn;
    await _engine!.setEnableSpeakerphone(_isSpeakerOn);
    _notifyCallStateChanged();
  }

  /// Cancela uma chamada antes do outro usuário atender (Missed call)
  Future<void> cancelCall() async {
    debugPrint('📞 cancelCall: INICIANDO...');

    // IMPORTANTE: Salvar referências ANTES de leaveChannel (que as zera)
    final savedCallId = _currentCallId;
    final savedChannelName = _currentChannelName;

    final isMeeting = savedChannelName?.startsWith('room_') ?? false;

    await leaveChannel();

    // Garante que o estado seja resetado
    _isInCall = false;
    _notifyCallStateChanged();

    // 1:1 "cancel" é para ringing (originado antes de atender).
    // Em reuniões, cancelCall não faz sentido porque entra direto in_progress.
    // Mas, manter a integridade, apenas se for chamadas 'calls' tentamos dar missed
    if (!isMeeting) {
      await _updateCallStatus(savedCallId, 'missed', table: 'calls');
    }

    // Encerrar CallKit no nativo
    if (!kIsWeb) {
      callkit.endAllCalls();
    }

    _currentCallId = null;
    _currentChannelName = null;
    _currentCallerName = null;
    _isCurrentCallVideo = false;
    _isInCall = false;
    _notifyCallStateChanged();

    debugPrint('📞 cancelCall: FINALIZADO');
  }

  Future<void> endCall() async {
    // Evita race condition - só permite uma execução
    if (_isEndingCall) {
      debugPrint('📞 endCall: JÁ EM EXECUÇÃO - IGNORANDO');
      return;
    }
    _isEndingCall = true;

    try {
      debugPrint('📞 endCall: INICIANDO...');
      debugPrint(
          '📞 endCall: _isInCall=$_isInCall, _currentCallId=$_currentCallId');

      // IMPORTANTE: Salvar referências ANTES de leaveChannel (que as zera)
      final savedCallId = _currentCallId;
      final savedChannelName = _currentChannelName;
      final hadNoRemoteUsers = activeRemoteUids.isEmpty;
      final wasMeetingHost = _isMeetingHost;

      await leaveChannel();

      // Gravação e Transcrição desativadas por instrução

      final isMeeting = savedChannelName?.startsWith('room_') ?? false;
      // Para meetings: encerra globalmente se for host OU se não havia mais ninguém na sala
      final shouldEndGlobally =
          !isMeeting || (wasMeetingHost || hadNoRemoteUsers);

      // Se ninguém atendeu (sem peers remotos), marca como 'missed'
      // em vez de 'ended' para chamadas 1:1
      if (savedCallId != null && shouldEndGlobally) {
        final tableName = isMeeting ? 'meetings' : 'calls';
        final callStatus =
            (!isMeeting && hadNoRemoteUsers) ? 'missed' : 'ended';
        final updatePayload = <String, dynamic>{
          'status': callStatus,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          await supabase
              .from(tableName)
              .update(updatePayload)
              .eq('id', savedCallId);
        } catch (e) {
          debugPrint('📞 Erro ao atualizar status no banco: $e');
        }
      }

      // Encerrar CallKit no nativo
      if (!kIsWeb) {
        callkit.endAllCalls();
      }

      _resetLocalCallState();

      PushNotificationService.cancelOngoingCallNotification();
      debugPrint('📞 endCall: FINALIZADO - _isInCall=$_isInCall');
    } finally {
      _isEndingCall = false;
    }
  }

  /// Detecta se o ID pertence a um canal ou a um chat direto/grupo.
  /// Retorna true se for canal, false caso contrário.
  /// Lança exceção se o ID não existir em nenhum dos dois.
  Future<bool> _isChannel(String id) async {
    final ch =
        await supabase.from('channels').select('id').eq('id', id).maybeSingle();
    if (ch != null) return true;

    final chat =
        await supabase.from('chats').select('id').eq('id', id).maybeSingle();
    if (chat != null) return false;

    throw Exception('Conversa não encontrada');
  }

  // ─── Iniciar Chamada (quem liga) ───────────────────────────

  Future<void> startCall({
    required String chatId,
    required String callerName,
    required String calleeName,
    String? calleeId,
    bool isVideoEnabled = false,
  }) async {
    if (_isInCall) {
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Você já está em uma chamada. Encerre-a primeiro.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Reset da flag de encerramento ao iniciar nova chamada
    _isEndingCall = false;

    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    // Detectar contexto: primeiro tenta canal, depois chat
    bool isChannel = false;
    try {
      isChannel = await _isChannel(chatId);
      debugPrint(
          '📞 startCall: contexto é ${isChannel ? "CANAL" : "CHAT"} ($chatId)');
    } catch (e) {
      debugPrint('📞 Erro verificando contexto em startCall: $e');
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content:
              Text('Conversa não encontrada. Reabra o chat antes de ligar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final channelName = 'call_$chatId';

    // Chamadas usam a tabela "calls" (seja áudio ou vídeo)
    String? callId;
    try {
      final insertPayload = <String, dynamic>{
        'caller_id': myId,
        'type': isVideoEnabled ? 'video' : 'audio',
        'status': 'ringing',
        'provider_room_id': channelName,
      };

      // Preencher a coluna correta conforme o contexto
      if (isChannel) {
        insertPayload['channel_id'] = chatId;
      } else {
        insertPayload['chat_id'] = chatId;
        // Em DMs, registra quem é o destinatário da chamada
        if (calleeId != null) {
          insertPayload['callee_id'] = calleeId;
        }
      }

      final result = await supabase
          .from('calls')
          .insert(insertPayload)
          .select('id')
          .single();
      callId = result['id'] as String;
      debugPrint(
          '📞 Chamada criada na tabela calls (tipo: ${isVideoEnabled ? "video" : "audio"}, isChannel=$isChannel): $callId');
    } catch (e) {
      debugPrint('📞 Erro ao criar chamada no banco: $e');
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Erro ao iniciar chamada. Tente novamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _currentCallId = callId;
    _currentChannelName = channelName;
    _isCurrentCallVideo = isVideoEnabled;

    // Navegar para a tela de chamada imediatamente (status "Chamando...")
    _navigateToActiveCall(calleeName, chatId, isVideo: isVideoEnabled);

    // Entrar no canal Agora (quem liga entra primeiro)
    try {
      await joinChannel(channelName, isVideoEnabled: isVideoEnabled);

      // Timer de 40 segundos para ring timeout se ninguém atender
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = Timer(const Duration(seconds: 40), () async {
        if (_isInCall && activeRemoteUids.isEmpty) {
          debugPrint('📞 Timeout de chamada sem atendimento...');
          await endCall();
        }
      });

      // Envia notificação push para o destinatário
      await _sendCallNotification(callId, chatId, isVideoEnabled,
          isChannel: isChannel);
    } catch (e) {
      debugPrint('📞 Erro fatal ao iniciar o canal Agora: $e');
    }
  }

  // ─── Enviar Notificação Push (Edge Function) ───────────────

  Future<void> _sendCallNotification(String callId, String chatId, bool isVideo,
      {bool isChannel = false}) async {
    try {
      final supabaseUrl = AppEnv.supabaseUrl.isNotEmpty
          ? AppEnv.supabaseUrl
          : dotenv.env['SUPABASE_URL'];
      if (supabaseUrl == null || supabaseUrl.isEmpty) return;

      // Token de autenticação do usuário logado
      final accessToken = supabase.auth.currentSession?.accessToken;

      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/send-call-notification'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'type': 'INSERT',
          'record': {
            'id': callId,
            'chat_id': isChannel ? null : chatId,
            'channel_id': isChannel ? chatId : null,
            'caller_id': supabase.auth.currentUser?.id,
            'is_video': isVideo,
          },
          'table': _currentChannelName?.startsWith('room_') == true
              ? 'meetings'
              : 'calls',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📞 Notificação de chamada enviada com sucesso');
      } else {
        debugPrint(
            '📞 Erro ao enviar notificação: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('📞 Erro ao chamar Edge Function: $e');
    }
  }

  // ─── Salas de Reunião (VideoConferência) ───────────────────

  /// Cria uma sala de reunião vinculada a um chat (DM/Grupo) ou canal de workflow.
  /// O [contextId] pode ser o ID de um chat ou de um canal.
  Future<String?> createMeetingRoom({
    required String name,
    required String chatId,
    String? description,
  }) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return null;

    // Verifica a role do usuário - apenas super_admin, admin, manager podem criar
    try {
      final userData = await supabase
          .from('users')
          .select('role_level')
          .eq('id', myId)
          .maybeSingle();

      if (userData != null) {
        final role = userData['role_level'] as String? ?? 'member';
        debugPrint('createMeetingRoom: usuario role = $role');

        final canCreate =
            role == 'super_admin' || role == 'admin' || role == 'manager';
        if (!canCreate) {
          debugPrint('createMeetingRoom: usuario nao tem permissao');
          Globals.scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Apenas gestores podem criar videoconferencias.'),
              backgroundColor: Colors.orange,
            ),
          );
          return null;
        }
      }
    } catch (e) {
      debugPrint('createMeetingRoom: erro ao verificar role: $e');
    }

    // Detectar contexto: primeiro tenta canal, depois chat
    bool isChannel = false;
    try {
      isChannel = await _isChannel(chatId);
      debugPrint(
          '📞 createMeetingRoom: contexto é ${isChannel ? "CANAL" : "CHAT"} ($chatId)');
    } catch (e) {
      debugPrint('📞 Erro verificando contexto em createMeetingRoom: $e');
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Conversa não encontrada. Tente novamente.'),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }

    final roomStr = const Uuid().v4();

    // NÃO envia notificação push para meeting - usuarios vao entrar manualmente pelo card

    // Tenta criar via API primeiro
    mirotalkUrl = await _miroTalk.createRoom(
      roomName: roomStr,
      durationHours: 24,
    );

    // Se API falhou, usa URL direta do servidor
    if (mirotalkUrl == null || mirotalkUrl!.isEmpty) {
      mirotalkUrl = '${AppConstants.mirotalkServerUrl}/AlinhaJá_$roomStr';
      debugPrint('MiroTalk: Usando URL direta (fallback): $mirotalkUrl');
    } else {
      debugPrint('MiroTalk: Sala criada via API: $mirotalkUrl');
    }

    try {
      final insertPayload = <String, dynamic>{
        'title': name,
        'host_id': myId,
        'status': 'waiting',
        'room_id': roomStr,
        'mirotalk_url': mirotalkUrl,
      };

      // Preencher a coluna correta conforme o contexto
      if (isChannel) {
        insertPayload['channel_id'] = chatId;
      } else {
        insertPayload['chat_id'] = chatId;
      }

      final result = await supabase
          .from('meetings')
          .insert(insertPayload)
          .select('id')
          .single();

      final roomId = result['id'] as String;
      _isMeetingHost = true;
      debugPrint('Sala de reunião criada: $roomId (isChannel=$isChannel)');
      return roomId;
    } catch (e) {
      debugPrint('Erro ao criar sala de reunião: $e');
      return null;
    }
  }

  Future<void> joinMeetingRoomDirect({
    required String roomId,
    required String userName,
    bool asHost = false,
  }) async {
    if (_isInCall) {
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Você já está em uma chamada. Encerre-a primeiro.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _isEndingCall = false;

    try {
      final room = await supabase
          .from('meetings')
          .select('*')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null) {
        debugPrint('Sala de reunião não encontrada');
        return;
      }

      final roomStatus = room['status'] as String?;
      if (roomStatus == 'ended') {
        debugPrint('Sala de reunião já foi encerrada');
        return;
      }

      final context = Globals.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        _currentCallId = roomId;
        _currentChannelName = 'room_$roomId';
        _isCurrentCallVideo = true;
        _isMeetingHost =
            asHost || room['host_id'] == supabase.auth.currentUser?.id;

        if (roomStatus == 'waiting') {
          await supabase.from('meetings').update({
            'status': 'in_progress',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', roomId);
        }

        if (context.mounted) {
          // Passa o userName como extra para a rota
          context.push('/mirotalk/$roomId', extra: {'userName': userName});
        }
      }
    } catch (e) {
      debugPrint('Erro ao entrar na sala: $e');
    }
  }

  Future<void> joinMeetingRoom({
    required String roomId,
    String? userName,
  }) async {
    if (_isInCall) {
      Globals.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Você já está em uma chamada. Encerre-a primeiro.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _isEndingCall = false;

    // Busca o nome e filial do usuário atual para formatar "Nome - Filial"
    String finalUserName = userName ?? 'Participante';
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId != null) {
        final userData = await supabase
            .from('users')
            .select('full_name, branches(name)')
            .eq('id', myId)
            .maybeSingle();

        if (userData != null && userData['full_name'] != null) {
          final fullName = userData['full_name'] as String;
          final branchInfo = userData['branches'];
          if (branchInfo != null &&
              branchInfo is Map &&
              branchInfo['name'] != null) {
            final branchName = branchInfo['name'] as String;
            finalUserName = '$fullName - $branchName';
          } else {
            finalUserName = fullName;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar nome completo e filial: $e');
    }

    // Busca info da sala
    try {
      debugPrint('📞 joinMeetingRoom: Buscando sala $roomId');
      final room = await supabase
          .from('meetings')
          .select('*')
          .eq('id', roomId)
          .maybeSingle();

      debugPrint(
          '📞 joinMeetingRoom: Resultado: ${room != null ? "encontrada" : "nao encontrada"}');

      if (room == null) {
        debugPrint(
            '📞 Sala de reuniao nao encontrada - possivel erro de permissao RLS');
        Globals.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
                'Sala de reuniao nao encontrada ou voce nao tem permissao de acesso.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final roomStatus = room['status'] as String?;
      debugPrint('📞 Sala status: $roomStatus');

      if (roomStatus == 'ended') {
        debugPrint('📞 Sala de reunião já foi encerrada');
        Globals.scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
                'Esta reunião já foi encerrada. Crie uma nova reunião para iniciar.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      _currentCallId = roomId;
      _currentChannelName = 'room_$roomId';
      _isCurrentCallVideo = true;
      _isMeetingHost = room['host_id'] == supabase.auth.currentUser?.id;

      debugPrint(
          '📞 Entrando na reunião: $roomId, host=$_isMeetingHost, status atual=$roomStatus');

      // Armazena a URL para uso no mobile/native
      final storedUrl = room['mirotalk_url'] as String?;
      if (storedUrl != null && storedUrl.isNotEmpty) {
        mirotalkUrl = storedUrl;
        lastJoinedRoomUrl = storedUrl;
        debugPrint('📞 URL armazenada: $storedUrl');
      }

      // Atualiza status da sala apenas se estiver em modo waiting
      if (roomStatus == 'waiting') {
        await supabase.from('meetings').update({
          'status': 'in_progress',
          'started_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', roomId);
      }

      // Navega para a tela baseada em Jitsi (Web e Mobile compatível)
      final context = Globals.navigatorKey.currentContext;
      debugPrint(
          '📞 Tentando navegar para reunião. Context: ${context != null ? "ok" : "null"}');
      if (context != null && context.mounted) {
        try {
          // Encerra imediatamente da engine antiga
          _isInCall = false;

          // Passa userName como query parameter para evitar problemas com extra null
          final encodedUserName = Uri.encodeComponent(finalUserName);
          debugPrint(
              '📞 Navegando para /mirotalk/$roomId?userName=$encodedUserName');
          context.push('/mirotalk/$roomId?userName=$encodedUserName');
          debugPrint('📞 Navegação concluída');
        } catch (e, stack) {
          debugPrint('📞 Erro ao navegar para reunião: $e');
          debugPrint('Stack: $stack');
          _showError(context, 'Erro ao entrar na reunião: $e');
        }
      } else {
        debugPrint('📞 Context nulo - não foi possível navegar');
        if (context != null && context.mounted) {
          _showError(context,
              'Erro: contexto de navegação não disponível. Tente novamente.');
        }
      }
    } catch (e, stack) {
      debugPrint('📞 Erro ao entrar na sala de reunião: $e');
      debugPrint('Stack: $stack');
    }
  }

  /// Encerra a reunião para todos. Devolve `true` quando o servidor confirmou.
  ///
  /// Não propaga exceção de propósito: um dos chamadores dispara sem `await`
  /// (o card de reunião no chat) e o outro precisa liberar a tela mesmo se o
  /// encerramento falhar. Quem quiser avisar o usuário checa o retorno.
  Future<bool> endMeetingRoom(String roomId) async {
    try {
      debugPrint('📞 Encerrando reunião: $roomId');

      // Tudo em uma RPC: encerra a reunião e sincroniza o card nas duas
      // tabelas de mensagem dentro da mesma transação.
      //
      // Antes eram três escritas soltas pelo cliente, e duas dependiam de
      // policies que não cobriam o caso: em `messages` a RLS exige
      // `sender_id = auth.uid()` (falhava quando quem encerrava não era o autor
      // do card) e `channel_messages` não tem policy de UPDATE nenhuma — aquele
      // ramo afetava zero linhas e ainda logava sucesso.
      final result = await supabase.rpc('end_meeting_room', params: {
        'p_room_id': roomId,
      });

      if (result is Map && result['missing'] == true) {
        debugPrint(
            '📞 Reunião não encontrada no banco (provavelmente já excluída).');
        return true;
      }

      debugPrint('📞 Reunião $roomId encerrada com sucesso: $result');
      return true;
    } on PostgrestException catch (e) {
      // Banco ainda sem a migration 20260813120000: sem este fallback, publicar
      // o app antes de aplicá-la deixaria a reunião sem ser encerrada de todo —
      // pior do que o bug original, que ao menos gravava `meetings.status`.
      if (_isMissingFunction(e)) {
        debugPrint(
            '📞 RPC end_meeting_room ausente — usando encerramento legado.');
        return _endMeetingRoomLegacy(roomId);
      }
      debugPrint('📞 Erro ao encerrar reunião: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('📞 Erro ao encerrar reunião: $e');
      return false;
    }
  }

  /// `42883` é o "undefined_function" do Postgres; `PGRST202` é o equivalente
  /// do PostgREST quando a função não está no schema exposto.
  static bool _isMissingFunction(PostgrestException e) =>
      e.code == '42883' || e.code == 'PGRST202';

  /// Caminho anterior à RPC: marca só `meetings.status`.
  ///
  /// Não sincroniza o metadata dos cards — é exatamente a limitação que a RPC
  /// veio resolver —, mas garante que a reunião seja encerrada enquanto a
  /// migration não é aplicada.
  Future<bool> _endMeetingRoomLegacy(String roomId) async {
    try {
      await supabase.from('meetings').update({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', roomId);
      return true;
    } catch (e) {
      debugPrint('📞 Erro no encerramento legado: $e');
      return false;
    }
  }

  // ————— In-App Ringing (Web - sem CallKit) ——————————————————————————————

  bool _isWebDialogShowing = false;
  BuildContext? _webDialogContext;

  void _closeWebIncomingCallDialogIfNeeded() {
    if (kIsWeb && _isWebDialogShowing && _webDialogContext != null) {
      try {
        if (_webDialogContext!.mounted) {
          Navigator.of(_webDialogContext!).pop();
        }
      } catch (e) {
        debugPrint('📞 Erro ao fechar Web Dialog: $e');
      }
      _isWebDialogShowing = false;
      _webDialogContext = null;
    }
    // Fora do if: o toque pode estar ativo sem o diálogo na tela.
    if (kIsWeb) _stopWebIncomingAlert();
  }

  /// Cancela o toque e fecha notificação web se ativa
  void _stopWebIncomingAlert() {
    _webRingtonePlayer?.stop();
    _webRingtonePlayer?.dispose();
    _webRingtonePlayer = null;
    WebNotificationService.closeWebNotification('incoming_call');
  }

  /// Exibe um Dialog de chamada recebida no navegador.
  /// Chamado quando o listener do Supabase Realtime detecta status 'ringing'.
  void showWebIncomingCallDialog({
    required String callId,
    required String callerName,
    required String chatId,
    bool isVideo = false,
  }) {
    if (_isWebDialogShowing) return;

    // Sem contexto não há diálogo para atender nem recusar: antes o toque
    // começava assim mesmo e ficava em loop para sempre.
    final context = Globals.navigatorKey.currentContext;
    if (context == null) return;

    // Um player por chamada: o anterior (se sobrou) é liberado.
    _stopWebIncomingAlert();
    _webRingtonePlayer = AudioPlayer();
    _webRingtonePlayer?.setReleaseMode(ReleaseMode.loop);
    _webRingtonePlayer
        ?.play(UrlSource(
            'https://actions.google.com/sounds/v1/alarms/phone_ringing.ogg'))
        .catchError((e) {
      debugPrint('📞 Web Ringtone Player: Erro ao reproduzir ringtone: $e');
    });

    WebNotificationService.showWebNotification(
      'Chamada Recebida',
      '$callerName está te ligando...',
      tag: 'incoming_call',
    );

    _currentCallId = callId;
    _currentChannelName = 'call_$chatId';
    _isCurrentCallVideo = isVideo;

    _isWebDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _webDialogContext = ctx;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: const Color(0xFF1A1A2E),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                // Avatar pulsante
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade400, Colors.teal.shade700],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  callerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isVideo
                      ? 'Chamada de vídeo recebida...'
                      : 'Chamada de voz recebida...',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _updateCallStatus(_currentCallId, 'rejected');
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.shade600,
                        ),
                        child: const Icon(Icons.call_end,
                            color: Colors.white, size: 28),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final navigator =
                            Navigator.of(ctx, rootNavigator: true);
                        navigator.pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _acceptAndJoin(callerName, chatId, isVideo: isVideo);
                        });
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.shade600,
                        ),
                        child: const Icon(Icons.call,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isWebDialogShowing = false;
      _stopWebIncomingAlert();
    });
  }

  // ————— Handler de Chamada Recebida (Trigger Realtime) ——————————————————————————————

  Future<void> handleIncomingCall(String callerName, String chatId,
      {bool isVideo = false, String? callId, String? callerId}) async {
    if (_isInCall) {
      debugPrint(
          '📞 Já em chamada. Rejeitando chamada concorrente ($callId) automaticamente.');
      _updateCallStatus(callId, 'rejected',
          table: isVideo ? 'meetings' : 'calls');
      return;
    }

    _currentCallId = callId;
    _currentChannelName = 'call_$chatId';
    _isCurrentCallVideo = isVideo;
    _currentCallerName = callerName;

    if (kIsWeb) {
      showWebIncomingCallDialog(
        callId: callId ?? const Uuid().v4(),
        callerName: callerName,
        chatId: chatId,
        isVideo: isVideo,
      );
    } else {
      callkit.showIncomingCall(callerName, callerId ?? '',
          isVideo: isVideo, callId: callId, chatId: chatId);
    }
  }

  // ————— Utilitários ——————————————————————————————————————————————

  void _navigateToActiveCall(String remoteName, String chatId,
      {bool isVideo = false}) {
    _currentCallerName = remoteName;
    _isInCall = true;
    _notifyCallStateChanged();
    debugPrint('📞 ActiveCallScreen acionado globalmente via Overlay');
  }

  Future<void> _updateCallStatus(String? callId, String status,
      {String? table}) async {
    if (callId == null) return;
    debugPrint(
        '📞 _updateCallStatus: callId=$callId, status=$status, isVideo=$_isCurrentCallVideo');

    try {
      final data = <String, dynamic>{'status': status};

      final String targetTable;
      if (table != null) {
        targetTable = table;
      } else if (_currentChannelName?.startsWith('room_') == true) {
        targetTable = 'meetings';
      } else {
        targetTable = 'calls';
      }

      if (status == 'in_progress') {
        data['started_at'] = DateTime.now().toUtc().toIso8601String();
        data['answered_by'] = supabase.auth.currentUser?.id;
      } else if (status == 'ended' ||
          status == 'rejected' ||
          status == 'missed') {
        data['ended_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await supabase.from(targetTable).update(data).eq('id', callId);
      debugPrint('📞 _updateCallStatus: $targetTable atualizado');
    } catch (e) {
      debugPrint('📞 _updateCallStatus: ERRO: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
