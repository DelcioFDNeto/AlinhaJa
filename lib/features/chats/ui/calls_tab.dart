import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/chats/providers/call_history_provider.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

/// Aba de Chamadas — exibe o histórico profissional (DMs + Reuniões/Grupos)
class CallsTab extends ConsumerStatefulWidget {
  const CallsTab({super.key});

  @override
  ConsumerState<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends ConsumerState<CallsTab> {
  int _selectedFilter = 0; // 0 = Todas, 1 = Perdidas, 2 = Reuniões

  Future<void> _playRecording(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível reproduzir o áudio')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(callHistoryProvider);
    final currentUser = ref.watch(currentUserProvider).value;

    return Scaffold(
      body: Column(
        children: [
          // Filtros de Histórico movidos para o corpo do Scaffold
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surface,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Todas')),
                ButtonSegment(
                  value: 1,
                  label: Text('Perdidas'),
                  // Removemos o badge vermelho fixo pra manter limpo, ou podemos contar via filter
                ),
                ButtonSegment(value: 2, label: Text('Reuniões')),
              ],
              selected: {_selectedFilter},
              onSelectionChanged: (set) {
                setState(() => _selectedFilter = set.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Erro ao carregar histórico: $e')),
              data: (allCalls) {
                final calls = allCalls.where((c) {
                  if (_selectedFilter == 2) return c.isGroupOrChannel;
                  if (_selectedFilter == 1) {
                    final isMe = c.callerId == currentUser?.id;
                    return !isMe &&
                        (c.status == 'missed' || c.status == 'rejected');
                  }
                  return true;
                }).toList();

                if (calls.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedFilter == 2
                              ? Icons.groups_outlined
                              : (_selectedFilter == 1
                                  ? Icons.phone_missed
                                  : Icons.phone_disabled_outlined),
                          size: 80,
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedFilter == 2
                              ? 'Nenhuma reunião encontrada'
                              : (_selectedFilter == 1
                                  ? 'Nenhuma chamada perdida'
                                  : 'Nenhuma ligação no histórico'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            'O seu histórico de chamadas em grupo, canais e reuniões aparecerá aqui.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '↓ Puxe para baixo para atualizar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        '↓ Puxe para baixo para atualizar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(callHistoryProvider.future),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: calls.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final call = calls[index];
                            final isMe = call.callerId == currentUser?.id;
                            final isMissed = !isMe &&
                                (call.status == 'missed' ||
                                    call.status == 'rejected');
                            final isActive = call.status == 'in_progress' ||
                                call.status == 'ringing';

                            // Se for DM, o nome a exibir é o do parceiro.
                            // Se for grupo, exibe o chatName.
                            String title = call.chatName ?? 'Chat Desconhecido';
                            String? avatarUrl = call.callerAvatarUrl;
                            if (!call.isGroupOrChannel) {
                              title = isMe
                                  ? (call.partnerName ??
                                      call.chatName ??
                                      'Contato')
                                  : (call.callerName ?? 'Desconhecido');
                              avatarUrl = isMe
                                  ? call.partnerAvatarUrl
                                  : call.callerAvatarUrl;
                            }

                            // Ícone Principal
                            Widget leadingIcon;
                            Color iconColor;
                            if (call.isGroupOrChannel) {
                              leadingIcon =
                                  const Icon(Icons.groups_rounded, size: 24);
                              iconColor = theme.colorScheme.tertiary;
                            } else if (isMissed) {
                              leadingIcon = const Icon(
                                  Icons.phone_missed_rounded,
                                  size: 24);
                              iconColor = theme.colorScheme.error;
                            } else if (isMe) {
                              leadingIcon =
                                  const Icon(Icons.call_made_rounded, size: 24);
                              iconColor = theme.colorScheme.primary;
                            } else {
                              leadingIcon = const Icon(
                                  Icons.call_received_rounded,
                                  size: 24);
                              iconColor = Colors.green.shade600;
                            }

                            // Subtitle: Duração e Tempo
                            final timeStr = timeago.format(call.createdAt,
                                locale: 'pt_BR_short');
                            String subText = isMe ? 'Efetuada' : 'Recebida';
                            if (isMissed) subText = 'Perdida';
                            if (call.isGroupOrChannel) {
                              subText =
                                  'Reunião • ${call.callerName?.split(" ").first ?? "Alguém"}';
                            }

                            if (isActive) {
                              subText = 'Em andamento...';
                            } else if (call.duration != null &&
                                call.duration!.inSeconds > 0) {
                              final mins = call.duration!.inMinutes;
                              final secs = call.duration!.inSeconds % 60;
                              final durationStr =
                                  mins > 0 ? '$mins min' : '$secs s';
                              subText += ' • $durationStr';
                            }

                            return ListTile(
                              leading: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isActive
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : theme.colorScheme
                                            .surfaceContainerHighest,
                                    backgroundImage: avatarUrl != null
                                        ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                                        : null,
                                    child: avatarUrl == null
                                        ? IconTheme(
                                            data: IconThemeData(
                                                color: isActive
                                                    ? Colors.green
                                                    : iconColor),
                                            child: leadingIcon,
                                          )
                                        : null,
                                  ),
                                  if (avatarUrl != null)
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isMissed
                                            ? Icons.phone_missed_rounded
                                            : (isMe
                                                ? Icons.call_made_rounded
                                                : Icons.call_received_rounded),
                                        size: 14,
                                        color: isMissed
                                            ? theme.colorScheme.error
                                            : (isMe
                                                ? theme.colorScheme.primary
                                                : Colors.green.shade600),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: isActive || isMissed
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color:
                                      isMissed ? theme.colorScheme.error : null,
                                ),
                              ),
                              subtitle: Text(
                                '$subText • $timeStr',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isActive
                                      ? Colors.green
                                      : theme.colorScheme.outline,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Botão de reprodução de áudio se houver gravação
                                  if (call.hasRecording)
                                    IconButton(
                                      icon: Icon(
                                        Icons.play_circle_outline,
                                        color: theme.colorScheme.secondary,
                                      ),
                                      tooltip: 'Ouvir Gravação',
                                      onPressed: () =>
                                          _playRecording(call.audioUrl!),
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      call.isGroupOrChannel
                                          ? Icons.video_camera_front_rounded
                                          : Icons.call_rounded,
                                      color: theme.colorScheme.primary,
                                    ),
                                    tooltip: 'Retornar Ligação',
                                    onPressed: () async {
                                      if (currentUser == null) return;
                                      // Exige permissão antes de retornar a ligação
                                      final micStatus =
                                          await Permission.microphone.request();
                                      if (!micStatus.isGranted) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Permissão de Microfone necessária.')),
                                          );
                                        }
                                        return;
                                      }

                                      CallService.instance.startCall(
                                        chatId: call.chatId,
                                        callerName: currentUser.fullName,
                                        calleeName: title,
                                        isVideoEnabled: call.type == 'video',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
