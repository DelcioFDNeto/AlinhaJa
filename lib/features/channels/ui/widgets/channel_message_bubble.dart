import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/ui/message_cards/announcement_card.dart';
import 'package:alinha_ja/core/ui/message_cards/structured_message_card.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_reply_quote.dart';
import 'package:alinha_ja/features/chat/data/chat_repository.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:intl/intl.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Provider que verifica se o usuário atual já fez acknowledge de uma mensagem
///
/// Mensagem de canal grava em `channel_message_id`: a coluna `message_id`
/// referencia `messages`, que não guarda mensagem de canal nenhuma.
final messageAcknowledgedProvider =
    FutureProvider.family<bool, String>((ref, messageId) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final result = await supabase
      .from('message_actions')
      .select('id')
      .eq('channel_message_id', messageId)
      .eq('user_id', myId)
      .eq('action_type', 'acknowledge')
      .maybeSingle();

  return result != null;
});

/// Situação de uma sala de reunião, resolvida uma única vez por `roomId`.
///
/// Antes o card montava um `FutureBuilder` com o `future:` criado dentro do
/// `build()`: a lista de mensagens rebuilda a cada evento de realtime, e cada
/// rebuild refazia a consulta a `meetings` para todo card de reunião na tela.
/// Como `FutureProvider.family`, o Riverpod guarda o resultado e a consulta
/// acontece uma vez por sala.
final meetingStatusProvider =
    FutureProvider.family<({bool ended, bool expired}), String>(
        (ref, roomId) async {
  final row = await supabase
      .from('meetings')
      .select('status, created_at')
      .eq('id', roomId)
      .maybeSingle();

  // Sala ausente = encerrada (o registro pode ter sido removido).
  if (row == null) return (ended: true, expired: false);

  final status = row['status']?.toString();
  if (status == 'ended') return (ended: true, expired: false);

  // Auto-expiração: sem o host clicar em "Encerrar", a sala não fica aberta
  // para sempre.
  final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
  if (createdAt != null &&
      DateTime.now().toUtc().difference(createdAt).inHours >= 2) {
    // Reflete no banco sem bloquear a UI; falha aqui é irrelevante porque o
    // cálculo por tempo já vale para esta renderização.
    unawaited(supabase
        .from('meetings')
        .update({'status': 'ended'})
        .eq('id', roomId)
        .catchError((_) {}));
    return (ended: true, expired: true);
  }

  return (ended: false, expired: false);
});

/// Provider que busca info de acknowledge do anúncio via RPC
/// Versão future para uso interno (não stream)
final announcementAckInfoProviderFuture =
    FutureProvider.family<Map<String, dynamic>, String>((ref, messageId) async {
  try {
    final response = await supabase.rpc('get_announcement_stats', params: {
      'p_message_id': messageId,
    });
    return response as Map<String, dynamic>;
  } catch (e) {
    debugPrint('Erro ao obter stats via RPC: $e');
    return {};
  }
});

/// Alias para announcementAckInfoProviderFuture para compatibilidade com código existente
final announcementAckInfoProvider = announcementAckInfoProviderFuture;

/// Provider que busca todos os users que fizeram acknowledge numa mensagem
final messageAcknowlegdersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, messageId) async {
  final result = await supabase
      .from('message_actions')
      .select('user_id, created_at')
      .eq('channel_message_id', messageId)
      .eq('action_type', 'acknowledge')
      .order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(result);
});

// Votação de enquete mora em core/ui/message_cards/message_action_providers.dart,
// compartilhada com o chat 1:1.

class ChannelMessageBubble extends ConsumerWidget {
  final ChannelMessageModel message;
  final bool isMe;
  final String senderName;
  final VoidCallback? onTapThread;

  /// Mensagem original, quando esta é uma resposta. Nula quando a original não
  /// pôde ser resolvida — a citação ainda é desenhada em estado neutro.
  final ChannelMessageModel? quoted;
  final String? quotedSenderName;

  const ChannelMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.senderName,
    this.onTapThread,
    this.quoted,
    this.quotedSenderName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = message.replyCount;
    final timeStr = DateFormat.Hm().format(message.createdAt.toLocal());
    final avatarLetter =
        senderName.isNotEmpty ? senderName[0].toUpperCase() : '?';

    // Se for anúncio, renderiza layout especial
    if (message.isAnnouncement) {
      return _buildAnnouncementBubble(
          context, ref, theme, timeStr, avatarLetter);
    }

    // Enquete, evento, localização e contato: card compartilhado
    if (message.metadata.isStructuredCard) {
      return _buildStructuredBubble(context, theme, timeStr, avatarLetter);
    }

    // Se for reunião, renderiza layout de Meeting Card
    if (message.metadata.isMeeting) {
      return _buildMeetingBubble(context, ref, theme, timeStr, avatarLetter);
    }

    return _buildStandardBubble(context, theme, timeStr, avatarLetter, count);
  }

  /// Enquete, evento, localização e contato usam a mesma moldura: cabeçalho com
  /// autor/hora e, dentro, o card compartilhado com o chat 1:1.
  Widget _buildStructuredBubble(
      BuildContext context, ThemeData theme, String timeStr, String avatarLetter) {
    const double maxBubbleWidth = 440;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: maxBubbleWidth),
        margin: EdgeInsets.only(
          bottom: 12,
          left: isMe ? 48 : 12,
          right: isMe ? 12 : 48,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          color: isMe
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surfaceContainerHigh,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    avatarLetter,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    senderName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StructuredMessageCard(
              message: MessageRef.channel(message.id),
              metadata: message.metadata.toMap(),
              content: message.content,
              maxWidth: maxBubbleWidth - 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingBubble(BuildContext context, WidgetRef ref,
      ThemeData theme, String timeStr, String avatarLetter) {
    final roomId = message.metadata.roomId;
    final meetingName =
        (message.content ?? '').replaceAll('Sala de Reunião: ', '');
    final currentUser = supabase.auth.currentUser;
    final fullName = currentUser?.userMetadata?['full_name'] ?? 'Usuário';

    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00BFA5).withValues(alpha: 0.3)),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00BFA5).withValues(alpha: 0.15),
                  const Color(0xFF1DE9B6).withValues(alpha: 0.08),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(0xFF00BFA5),
                  child: Icon(Icons.videocam, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reunião de $senderName',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.8))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meetingName,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                if (roomId != null)
                  Builder(
                    builder: (context) {
                      // O metadata do card é a fonte barata: desde a RPC
                      // `end_meeting_room` ele é gravado junto com
                      // `meetings.status`, então uma reunião encerrada nem
                      // chega a consultar o banco.
                      final metaEnded =
                          message.metadata.raw['status'] == 'ended';

                      final remote = metaEnded
                          ? null
                          : ref.watch(meetingStatusProvider(roomId)).valueOrNull;

                      final isExpiredByTime = remote?.expired ?? false;
                      // Enquanto a consulta não volta, mantém o botão ativo:
                      // desabilitar por padrão bloquearia uma reunião em curso.
                      final isEnded = metaEnded || (remote?.ended ?? false);

                      return SizedBox(
                        width: double.infinity,
                        child: isEnded
                            ? OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.outline,
                                  side: BorderSide(
                                      color: theme.colorScheme.outlineVariant),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: null,
                                icon: const Icon(Icons.videocam_off, size: 18),
                                label: Text(
                                  isExpiredByTime
                                      ? 'Reunião Expirada (tempo limite)'
                                      : 'Reunião Encerrada',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              )
                            : FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF00BFA5),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  CallService.instance.joinMeetingRoom(
                                    roomId: roomId,
                                    userName: fullName,
                                  );
                                },
                                icon: const Icon(Icons.video_call),
                                label: const Text('Entrar na Reunião',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                      );
                    },
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.outline,
                        side:
                            BorderSide(color: theme.colorScheme.outlineVariant),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.videocam_off, size: 18),
                      label: const Text('Sala indisponível',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Anúncio oficial: moldura da conversa + card compartilhado com o grupo.
  ///
  /// Toda a personalização (prioridade, prazo, público, anexo, ação) vem do
  /// metadata via [AnnouncementSpec] — antes daqui só existia "mensagem
  /// destacada em azul" com confirmação de leitura.
  Widget _buildAnnouncementBubble(BuildContext context, WidgetRef ref,
      ThemeData theme, String timeStr, String avatarLetter) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnnouncementCard(
            message: MessageRef.channel(message.id),
            spec: AnnouncementSpec.fromMetadata(message.metadata.toMap()),
            content: message.content,
            senderName: senderName,
            isMine: isMe,
            onShowAckDetails: isMe
                ? () => _showAckDetailsSheet(context, ref, theme)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              timeStr,
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  void _showAckDetailsSheet(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final ackInfoAsync = ref.read(announcementAckInfoProvider(message.id));
    final ackInfo = ackInfoAsync.valueOrNull;
    if (ackInfo == null) return;

    final acknowledgedUsers = (ackInfo['acknowledged_users'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final pendingUsers = (ackInfo['pending_users'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final viewedUsers = (ackInfo['viewed_users'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final notViewedUsers = (ackInfo['not_viewed_users'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.analytics, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Status do Anúncio',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (ackInfoAsync.valueOrNull?['is_sender'] == true)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteAnnouncement(context, ref),
                      tooltip: 'Excluir Anúncio',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatChip(
                    icon: Icons.visibility,
                    label: '${viewedUsers.length} visualizações',
                    color: Colors.blue,
                  ),
                  _buildStatChip(
                    icon: Icons.check_circle,
                    label: '${acknowledgedUsers.length} confirmaram',
                    color: Colors.green,
                  ),
                  _buildStatChip(
                    icon: Icons.pending,
                    label: '${pendingUsers.length} pendentes',
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: theme.colorScheme.outlineVariant),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      indicatorColor: theme.colorScheme.primary,
                      tabs: [
                        Tab(
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          text: 'Leitura (${viewedUsers.length})',
                        ),
                        Tab(
                          icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                          text: 'Ciência (${acknowledgedUsers.length}/${acknowledgedUsers.length + pendingUsers.length})',
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: Visualizações (Visualizaram vs Não Visualizaram)
                          ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            children: [
                              if (viewedUsers.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Visualizaram (${viewedUsers.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                                ...viewedUsers.map((user) => ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: user['avatar_url'] != null
                                            ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 320)
                                            : null,
                                        child: user['avatar_url'] == null
                                            ? Text(user['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 12))
                                            : null,
                                      ),
                                      title: Text(user['full_name'] ?? 'Usuário', style: const TextStyle(fontSize: 13)),
                                      trailing: Icon(Icons.visibility, color: Colors.blue.shade700, size: 16),
                                    )),
                              ],
                              if (notViewedUsers.isNotEmpty) ...[
                                const Divider(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Não Visualizaram (${notViewedUsers.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                ...notViewedUsers.map((user) => ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: user['avatar_url'] != null
                                            ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 320)
                                            : null,
                                        child: user['avatar_url'] == null
                                            ? Text(user['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 12))
                                            : null,
                                      ),
                                      title: Text(user['full_name'] ?? 'Usuário', style: const TextStyle(fontSize: 13)),
                                      trailing: Icon(Icons.visibility_off, color: Colors.grey.shade600, size: 16),
                                    )),
                              ],
                            ],
                          ),

                          // Tab 2: Confirmação de Ciência (Confirmados vs Pendentes)
                          ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            children: [
                              if (acknowledgedUsers.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Confirmados (${acknowledgedUsers.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ),
                                ...acknowledgedUsers.map((user) => ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: user['avatar_url'] != null
                                            ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 320)
                                            : null,
                                        child: user['avatar_url'] == null
                                            ? Text(user['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 12))
                                            : null,
                                      ),
                                      title: Text(user['full_name'] ?? 'Usuário', style: const TextStyle(fontSize: 13)),
                                      trailing: Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 16),
                                    )),
                              ],
                              if (pendingUsers.isNotEmpty) ...[
                                if (acknowledgedUsers.isNotEmpty) const Divider(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Pendentes de Confirmação (${pendingUsers.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                                ...pendingUsers.map((user) => ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: user['avatar_url'] != null
                                            ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 320)
                                            : null,
                                        child: user['avatar_url'] == null
                                            ? Text(user['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 12))
                                            : null,
                                      ),
                                      title: Text(user['full_name'] ?? 'Usuário', style: const TextStyle(fontSize: 13)),
                                      trailing: Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700, size: 16),
                                    )),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAnnouncement(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Anúncio'),
        content: const Text(
            'Tem certeza que deseja excluir este anúncio? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      debugPrint(
          '🗑️ Solicitando exclusão da mensagem (id: ${message.id}) via Repositório...');

      // O backend cuidará de fazer CASCADE DELETE das actions/acknowledgements
      // Graças a constraint ON DELETE CASCADE em message_actions.
      await ref.read(chatRepositoryProvider).hardDeleteMessage(message.id);

      // Forçar refresh das mensagens
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: message.channelId)));

      // Mapeamento de limpeza adicional se necessário
      ref.invalidate(messageAcknowledgedProvider(message.id));
      ref.invalidate(messageAcknowlegdersProvider(message.id));
      ref.invalidate(announcementAckInfoProvider(message.id));

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anúncio excluído com sucesso')),
        );
      }
    } catch (e) {
      debugPrint('🗑️ ERRO ao excluir anúncio: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao excluir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStandardBubble(BuildContext context, ThemeData theme,
      String timeStr, String avatarLetter, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isMe
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : theme.colorScheme.secondaryContainer,
            foregroundColor: isMe
                ? theme.colorScheme.primary
                : theme.colorScheme.onSecondaryContainer,
            child: Text(
              avatarLetter,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (message.replyTo != null)
                  ChannelReplyQuote(
                    quoted: quoted,
                    senderName: quotedSenderName,
                    accentColor: theme.colorScheme.primary,
                    textColor: theme.colorScheme.onSurface,
                  ),
                _buildMessageBody(context, theme),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onTapThread,
                  child: Container(
                    padding: count > 0
                        ? const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6)
                        : const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: count > 0
                            ? Colors.transparent
                            : theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (count > 0) ...[
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: theme.colorScheme.primary,
                            child: const Icon(Icons.person,
                                size: 10, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count Respostas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 14,
                              color: theme.colorScheme.onPrimaryContainer),
                        ] else ...[
                          Icon(Icons.reply_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            'Responder em Tópico',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBody(BuildContext context, ThemeData theme) {
    Widget mediaWidget;
    switch (message.contentType) {
      case 'image':
        mediaWidget = _buildImageBody(context);
        break;
      case 'video':
        mediaWidget = _buildVideoBody(context);
        break;
      case 'audio':
        mediaWidget = _buildAudioBody(context);
        break;
      case 'file':
        mediaWidget = _buildFileBody(context);
        break;
      case 'text':
      default:
        return Text(
          message.content ?? '',
          style: TextStyle(
              fontSize: 15, color: theme.colorScheme.onSurface, height: 1.3),
        );
    }

    // Se houver texto associado ao arquivo/imagem (ex: legenda), renderiza embaixo
    final hasText = message.contentType != 'text' &&
        message.content != null &&
        message.content!.trim().isNotEmpty &&
        message.contentType != 'file';

    if (hasText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          mediaWidget,
          const SizedBox(height: 6),
          Text(
            message.content!,
            style: TextStyle(
                fontSize: 15, color: theme.colorScheme.onSurface, height: 1.3),
          ),
        ],
      );
    }

    return mediaWidget;
  }

  Widget _buildImageBody(BuildContext context) {
    final heroTag = 'hero_image_channel_${message.id}';

    return GestureDetector(
      onTap: () {
        final hasLocal =
            message.localFilePath != null && message.localFilePath!.isNotEmpty;
        final hasRemote =
            message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
        if (!hasLocal && !hasRemote) return;

        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              iconTheme: const IconThemeData(color: Colors.white),
              elevation: 0,
            ),
            extendBodyBehindAppBar: true,
            body: Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: (!message.isOptimistic &&
                          message.mediaUrl != null &&
                          message.mediaUrl!.isNotEmpty)
                      ? SignedNetworkImage(
                          storedUrl: message.mediaUrl!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                        )
                      : (hasLocal
                          ? (kIsWeb
                              ? Image.network(message.localFilePath!,
                                  fit: BoxFit.contain)
                              : Image.file(File(message.localFilePath!),
                                  fit: BoxFit.contain))
                          : (message.mediaUrl != null
                              ? SignedNetworkImage(
                                  storedUrl: message.mediaUrl!,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white)),
                                )
                              : const SizedBox.shrink())),
                ),
              ),
            ),
          ),
        ));
      },
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 200,
            height: 200,
            child: message.isOptimistic && message.localFilePath != null
                ? (kIsWeb
                    ? Image.network(message.localFilePath!, fit: BoxFit.cover)
                    : Image.file(File(message.localFilePath!),
                        fit: BoxFit.cover))
                : (message.mediaUrl != null
                    ? _buildNetworkImage(message.mediaUrl!)
                    : Container(color: Colors.black12)),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String url) {
    if (kIsWeb) {
      return SignedNetworkImage(
        storedUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.black12,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      );
    }

    // Já resolvido nesta sessão: pinta direto, sem voltar ao spinner do
    // `FutureBuilder` a cada rebuild da régua do canal.
    final cached = MediaCacheManager.cachedFileFor(url);
    if (cached != null) {
      return Image.file(cached, fit: BoxFit.cover);
    }

    return FutureBuilder<File?>(
      future: MediaCacheManager.getOrDownloadMedia(
        mediaUrl: url,
        messageId: message.id,
        chatId: message.channelId,
        mediaType: 'image',
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(snapshot.data!, fit: BoxFit.cover);
        }
        // Fallback
        return SignedNetworkImage(
          storedUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
        );
      },
    );
  }

  Widget _buildVideoBody(BuildContext context) {
    return _ChannelVideoPlayerWidget(message: message);
  }

  Widget _buildAudioBody(BuildContext context) {
    return _ChannelAudioPlayerWidget(message: message);
  }

  Widget _buildFileBody(BuildContext context) {
    final fileName = message.content ?? 'Documento';
    final fileSize = message.metadata.formattedSize;

    final theme = Theme.of(context);
    final isOS = fileName.toUpperCase().contains('OS') ||
        fileName.toUpperCase().contains('ORDEM');
    final isInvoice = fileName.toUpperCase().contains('FATURA') ||
        fileName.toUpperCase().contains('BOLETO') ||
        fileName.toUpperCase().contains('RECIBO');

    final baseColor = theme.colorScheme.onSurface;
    Color iconBgColor = baseColor.withValues(alpha: 0.08);
    Color iconColor = theme.colorScheme.primary;

    if (isOS) {
      iconBgColor = const Color(0xFFE65100).withValues(alpha: 0.1);
      iconColor = const Color(0xFFFF9800);
    } else if (isInvoice) {
      iconBgColor = const Color(0xFF2E7D32).withValues(alpha: 0.1);
      iconColor = const Color(0xFF4CAF50);
    }

    return GestureDetector(
      // Documento vive no bucket: assina antes de abrir/baixar no navegador ou aplicativo.
      onTap: (message.mediaUrl != null || message.localFilePath != null)
          ? () async {
              final rawUrl = message.mediaUrl ?? message.localFilePath;
              if (rawUrl == null || rawUrl.isEmpty) return;
              try {
                final url = await MediaUrlResolver.resolve(
                  rawUrl,
                  downloadFileName: fileName,
                );
                final uri = Uri.parse(url);
                bool launched = false;
                try {
                  launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  );
                } catch (_) {}

                if (!launched) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.platformDefault,
                    webOnlyWindowName: '_blank',
                  );
                }
              } catch (e) {
                debugPrint('Erro ao abrir documento no canal: $e');
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(fileName),
                color: iconColor,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOS || isInvoice)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: iconColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        isOS ? 'ORDEM DE SERVIÇO' : 'FINANCEIRO',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: iconColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    fileName,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileSize.isNotEmpty)
                    Text(
                      fileSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            if (message.mediaUrl != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.download_rounded,
                size: 18,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.article_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

class _ChannelAudioPlayerWidget extends StatefulWidget {
  final ChannelMessageModel message;
  const _ChannelAudioPlayerWidget({required this.message});

  @override
  State<_ChannelAudioPlayerWidget> createState() =>
      _ChannelAudioPlayerWidgetState();
}

class _ChannelAudioPlayerWidgetState extends State<_ChannelAudioPlayerWidget> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
    _setSource();
  }

  void _setSource() async {
    if (widget.message.localFilePath != null) {
      await _audioPlayer.setSourceDeviceFile(widget.message.localFilePath!);
    } else if (widget.message.mediaUrl != null) {
      // Áudio no bucket privado exige URL assinada.
      final url = await MediaUrlResolver.resolve(widget.message.mediaUrl!);
      await _audioPlayer.setSourceUrl(url);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: baseColor,
                size: 32),
            onPressed: () async {
              if (_isPlaying) {
                await _audioPlayer.pause();
              } else {
                await _audioPlayer.resume();
              }
            },
          ),
          SizedBox(
            width: 120,
            child: Slider(
              value: _position.inSeconds.toDouble(),
              min: 0.0,
              max: _duration.inSeconds.toDouble() > 0
                  ? _duration.inSeconds.toDouble()
                  : 1.0,
              onChanged: (val) {
                _audioPlayer.seek(Duration(seconds: val.toInt()));
              },
              activeColor: baseColor,
              inactiveColor: baseColor.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelVideoPlayerWidget extends StatefulWidget {
  final ChannelMessageModel message;
  const _ChannelVideoPlayerWidget({required this.message});

  @override
  State<_ChannelVideoPlayerWidget> createState() =>
      _ChannelVideoPlayerWidgetState();
}

class _ChannelVideoPlayerWidgetState extends State<_ChannelVideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (widget.message.localFilePath != null && !kIsWeb) {
      _controller =
          VideoPlayerController.file(File(widget.message.localFilePath!));
    } else if (widget.message.mediaUrl != null) {
      // O player recebe a URL direto (sem passar pelo MediaCacheManager na
      // web), então precisa da versão assinada.
      final signedUrl =
          await MediaUrlResolver.resolve(widget.message.mediaUrl!);
      if (kIsWeb) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(signedUrl));
      } else {
        final cachedFile = await MediaCacheManager.getOrDownloadMedia(
          mediaUrl: widget.message.mediaUrl!,
          messageId: widget.message.id,
          chatId: widget.message.channelId,
          mediaType: 'video',
        );
        if (cachedFile != null) {
          _controller = VideoPlayerController.file(cachedFile);
        } else {
          _controller = VideoPlayerController.networkUrl(Uri.parse(signedUrl));
        }
      }
    }

    if (_controller != null) {
      await _controller!.initialize();
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _controller!.value.isPlaying
              ? _controller!.pause()
              : _controller!.play();
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 200,
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                if (!_controller!.value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 40),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
