import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/features/settings/providers/notification_settings_provider.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/core/services/push_notification_service.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notificações',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: settings.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Feedback bar
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'As alterações são salvas automaticamente no servidor.',
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.tertiary),
                        ),
                      ),
                    ],
                  ),
                ),

                // Navegador sem permissão não recebe push nenhum (web/PWA)
                if (kIsWeb) const _WebPushPermissionCard(),

                // Master Toggle
                _buildMasterToggle(context, settings, notifier),

                if (settings.notificationsEnabled) ...[
                  const Divider(height: 32),

                  // Tipos de Notificação
                  _SectionHeader(title: 'Tipos de Notificação', theme: theme),
                  _buildSwitchTile(
                    context,
                    icon: Icons.person_outline,
                    title: 'Mensagens Diretas',
                    subtitle: 'Notificações de conversas particulares',
                    value: settings.notifyDm,
                    onChanged: notifier.toggleDm,
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.group_outlined,
                    title: 'Grupos',
                    subtitle: 'Notificações de conversas em grupo',
                    value: settings.notifyGroups,
                    onChanged: notifier.toggleGroups,
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.campaign_outlined,
                    title: 'Canais',
                    subtitle: 'Notificações de canais oficiais',
                    value: settings.notifyChannels,
                    onChanged: notifier.toggleChannels,
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.checklist_outlined,
                    title: 'Workflow',
                    subtitle: 'Notificações de cards e atividades',
                    value: settings.notifyWorkflow,
                    onChanged: notifier.toggleWorkflow,
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.call_outlined,
                    title: 'Chamadas',
                    subtitle: 'Notificações de chamadas perdidas',
                    value: settings.notifyCalls,
                    onChanged: notifier.toggleCalls,
                  ),

                  // Módulos (broadcast de departamento) — derivados do registro.
                  if (modulesWithNotification.isNotEmpty) ...[
                    const Divider(height: 32),
                    _SectionHeader(title: 'Módulos', theme: theme),
                    for (final m in modulesWithNotification)
                      _buildSwitchTile(
                        context,
                        icon: m.icon,
                        title: m.title,
                        subtitle: m.notification!.description,
                        value: settings.isModuleEnabled(m.id),
                        onChanged: (v) => notifier.toggleModule(m.id, v),
                      ),
                  ],

                  const Divider(height: 32),

                  // Som e Vibração
                  _SectionHeader(title: 'Som e Vibração', theme: theme),
                  _buildSwitchTile(
                    context,
                    icon: Icons.volume_up_outlined,
                    title: 'Som',
                    subtitle: 'Reproduzir som ao receber notificação',
                    value: settings.soundEnabled,
                    onChanged: notifier.toggleSound,
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.vibration_outlined,
                    title: 'Vibração',
                    subtitle: 'Vibrar ao receber notificação',
                    value: settings.vibrationEnabled,
                    onChanged: notifier.toggleVibration,
                  ),

                  const Divider(height: 32),

                  // Privacidade
                  _SectionHeader(title: 'Privacidade', theme: theme),
                  _buildSwitchTile(
                    context,
                    icon: Icons.visibility_off_outlined,
                    title: 'Ocultar Preview',
                    subtitle: 'Não mostrar conteúdo na tela de bloqueio',
                    value: !settings.showPreview,
                    onChanged: (v) => notifier.togglePreview(!v),
                  ),

                  const Divider(height: 32),

                  // Horário Silencioso
                  _SectionHeader(title: 'Horário Silencioso', theme: theme),
                  _buildSwitchTile(
                    context,
                    icon: Icons.do_not_disturb_on_outlined,
                    title: 'Não Perturbe',
                    subtitle: 'Silenciar notificações em horário específico',
                    value: settings.doNotDisturbEnabled,
                    onChanged: notifier.toggleDoNotDisturb,
                  ),
                  if (settings.doNotDisturbEnabled) ...[
                    _buildTimeTile(
                      context,
                      title: 'Início',
                      icon: Icons.bedtime_outlined,
                      time: settings.dndStartTime,
                      onTap: () => _selectTime(context,
                          notifier.setDndStartTime, settings.dndStartTime),
                    ),
                    _buildTimeTile(
                      context,
                      title: 'Término',
                      icon: Icons.wb_sunny_outlined,
                      time: settings.dndEndTime,
                      onTap: () => _selectTime(
                          context, notifier.setDndEndTime, settings.dndEndTime),
                    ),
                  ],
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildMasterToggle(
      BuildContext context,
      NotificationSettingsState settings,
      NotificationSettingsNotifier notifier) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              settings.notificationsEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: settings.notificationsEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notificações',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  settings.notificationsEnabled
                      ? 'Você receberá notificações'
                      : 'Notificações desativadas',
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: settings.notificationsEnabled,
            onChanged: notifier.toggleNotifications,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
      ),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Widget _buildTimeTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          style: GoogleFonts.robotoMono(fontWeight: FontWeight.w500),
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _selectTime(
    BuildContext context,
    Future<void> Function(TimeOfDay) onSelect,
    TimeOfDay currentTime,
  ) async {
    final time = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );
    if (time != null) {
      onSelect(time);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Aviso e botão para liberar notificações do navegador.
///
/// Some quando a permissão já foi concedida. Quando o usuário bloqueou, o
/// navegador não deixa pedir de novo: o card explica onde desbloquear.
class _WebPushPermissionCard extends ConsumerStatefulWidget {
  const _WebPushPermissionCard();

  @override
  ConsumerState<_WebPushPermissionCard> createState() =>
      _WebPushPermissionCardState();
}

class _WebPushPermissionCardState
    extends ConsumerState<_WebPushPermissionCard> {
  AuthorizationStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status =
          await ref.read(pushNotificationServiceProvider).permissionStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Navegador sem suporte a push (ex.: Safari fora do PWA instalado).
      if (mounted) setState(() => _status = AuthorizationStatus.denied);
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      await ref.read(pushNotificationServiceProvider).enableFromUserGesture();
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || status == AuthorizationStatus.authorized) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final blocked = status == AuthorizationStatus.denied;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_outlined,
                  color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notificações do navegador desativadas',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            blocked
                ? 'O navegador bloqueou as notificações deste site. Libere '
                    'em Configurações do site (ícone ao lado do endereço). '
                    'No iPhone, instale o app na Tela de Início e abra por lá.'
                : 'Ative para receber mensagens e chamadas com o app fechado.',
            style: theme.textTheme.bodySmall,
          ),
          if (!blocked) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _enable,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: const Text('Ativar notificações'),
            ),
          ],
        ],
      ),
    );
  }
}
