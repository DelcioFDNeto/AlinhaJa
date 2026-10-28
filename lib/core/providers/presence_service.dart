import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'presence_web_stub.dart'
    if (dart.library.js_interop) 'presence_web.dart';

/// Provedor global que guarda a lista de IDs de usuários atualmente online
final onlineUsersProvider = StateProvider<Set<String>>((ref) => {});

/// Gerencia o status de Presença e o ciclo de vida do App
final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService(ref);
  return service;
});

class PresenceService with WidgetsBindingObserver {
  final Ref _ref;
  RealtimeChannel? _presenceChannel;
  Timer? _heartbeatTimer;

  PresenceService(this._ref);

  bool _observing = false;
  bool _webListenersRegistered = false;

  /// Chamado no login (app.dart) e ao montar a tela principal. Registrar o
  /// observer (e os listeners da página, na web) a cada chamada duplicava
  /// cada evento de ciclo de vida — e somava mais um a cada login.
  void init() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _startPresence();

    // Sem usuário logado os callbacks não fazem nada: basta registrar uma vez.
    if (kIsWeb && !_webListenersRegistered) {
      _webListenersRegistered = true;
      registerWebPresenceListeners(
        onBeforeUnload: () {
          _markOffline();
          _stopPresence();
        },
        onVisible: () {
          _startPresence();
        },
        onHidden: () {
          _goOffline();
        },
      );
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    _stopPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // `inactive` não é sair: na web dispara a cada perda de foco da janela
    // (barra de endereço, outra janela) e no celular ao puxar a barra de
    // notificações. Tratar como offline fazia, a cada clique fora, duas
    // escritas em `users`, sair e reentrar no canal `online-users` — e todos
    // os clientes conectados reprocessarem a lista de quem está online.
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _goOffline();
    }
  }

  Future<void> _goOffline() async {
    await _stopPresence();
    await _markOffline();
  }

  Future<void> _startPresence() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    // Canal ativo = já online (o heartbeat cuida do last_seen). Gravar de
    // novo aqui era uma escrita em `users` a cada volta de foco.
    if (_presenceChannel != null) return;

    // Os callbacks usam ESTE canal: um "closed" atrasado do canal anterior
    // zerava a referência do novo, que ficava órfão no cliente.
    final channel = supabase.channel('online-users');
    _presenceChannel = channel;
    bool isCurrent() => identical(_presenceChannel, channel);

    channel.onPresenceSync((payload) {
      if (!isCurrent()) return;
      final states = channel.presenceState();
      final Set<String> onlineIds = {};

      for (final state in states) {
        for (final presence in state.presences) {
          if (presence.payload['user_id'] != null) {
            onlineIds.add(presence.payload['user_id'] as String);
          }
        }
      }

      _ref.read(onlineUsersProvider.notifier).state = onlineIds;
    }).subscribe((status, [error]) async {
      if (!isCurrent()) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({'user_id': myId});
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        _presenceChannel = null;
        unawaited(supabase.removeChannel(channel));
      }
    });

    // ── Heartbeat: atualiza last_seen_at a cada 1 min na Web ou 2 min no Mobile/Desktop ──
    _heartbeatTimer?.cancel();
    _markOnline();
    const heartbeatDuration =
        kIsWeb ? Duration(minutes: 1) : Duration(minutes: 2);
    _heartbeatTimer = Timer.periodic(heartbeatDuration, (_) {
      _updateLastSeen();
    });
  }

  Future<void> _markOnline() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    debugPrint('Presence: Marcando usuário $myId como online');
    try {
      await supabase.from('users').update({
        'is_online': true,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', myId);
      debugPrint('Presence: Usuário marcado como online com sucesso');
    } catch (e) {
      debugPrint('Erro ao marcar online: $e');
    }
  }

  Future<void> _stopPresence() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final channel = _presenceChannel;
    if (channel != null) {
      _presenceChannel =
          null; // Anula imediatamente para evitar reentrada/concorrência
      try {
        await channel.untrack();
      } catch (e) {
        debugPrint('Presence: Erro ao dar untrack: $e');
      }
      try {
        await supabase.removeChannel(channel);
      } catch (e) {
        debugPrint('Presence: Erro ao remover canal: $e');
      }
    }
  }

  Future<void> _updateLastSeen() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      await supabase.from('users').update({
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', myId);
    } catch (e) {
      debugPrint('Erro ao atualizar last_seen_at: $e');
    }
  }

  Future<void> _markOffline() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      await supabase.from('users').update({
        'is_online': false,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', myId);
    } catch (e) {
      debugPrint('Erro ao marcar offline: $e');
    }
  }
}
