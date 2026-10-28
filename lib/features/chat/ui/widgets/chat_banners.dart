import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';

// ─── Provider de Chamada Ativa para Chat Específico ───────────
final activeCallForChatProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, chatId) {
  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> checkForActiveCall() async {
    final callsResult = await supabase
        .from('calls')
        .select('*')
        .eq('chat_id', chatId)
        .inFilter('status', ['ringing', 'in_progress'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (callsResult != null) {
      controller.add({...callsResult, 'type': 'call'});
      return;
    }

    final meetingsResult = await supabase
        .from('meetings')
        .select('*')
        .eq('chat_id', chatId)
        .inFilter('status', ['ringing', 'in_progress'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (meetingsResult != null) {
      controller.add({...meetingsResult, 'type': 'meeting'});
      return;
    }

    controller.add(null);
  }

  checkForActiveCall();

  final callsChannel = supabase.channel('public:calls_$chatId');
  callsChannel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'calls',
        callback: (_) => checkForActiveCall(),
      )
      .subscribe();

  final meetingsChannel = supabase.channel('public:meetings_$chatId');
  meetingsChannel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'meetings',
        callback: (_) => checkForActiveCall(),
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    supabase.removeChannel(callsChannel);
    supabase.removeChannel(meetingsChannel);
  });

  return controller.stream;
});

class ChatBanners extends ConsumerWidget {
  final String chatId;
  final String chatName;

  const ChatBanners({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Banner de chamada ativa (estilo Discord) ──────────
        Consumer(
          builder: (context, ref, child) {
            final activeCallAsync =
                ref.watch(activeCallForChatProvider(chatId));
            final activeCall = activeCallAsync.valueOrNull;

            if (activeCall == null) return const SizedBox.shrink();

            final isVideo = activeCall['type'] == 'meeting';
            final channelName =
                activeCall['room_id'] ?? activeCall['provider_room_id'] ?? '';

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade700, Colors.green.shade500],
                ),
              ),
              child: Row(
                children: [
                  Icon(isVideo ? Icons.videocam : Icons.call,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isVideo
                          ? 'Videochamada em andamento'
                          : 'Chamada em andamento',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!CallService.instance.isInCall) {
                        await CallService.instance.joinChannel(
                          channelName,
                          isVideoEnabled: isVideo,
                        );
                      }
                      if (context.mounted) {
                        context.push('/call/$chatId', extra: {
                          'callerName': chatName,
                          'isVideo': isVideo
                        });
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Entrar',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        ),

        // ── Banner de Reconexão ──────────
        Consumer(
          builder: (context, ref, child) {
            final state = ref.watch(chatProvider(ChatArgs(chatId: chatId)));
            if (!state.isReconnecting) return const SizedBox.shrink();

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.orange.shade800,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Reconectando stream...',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
