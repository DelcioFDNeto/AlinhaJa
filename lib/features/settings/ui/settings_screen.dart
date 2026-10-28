import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/theme_provider.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/constants.dart';

/// Tela de Configurações do Aplicativo.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeSettings = ref.watch(themeSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Configurações',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: ResponsiveWidthContainer(
        child: ListView(
          children: [
            // ── Seção: Aparência ──────────────────────────
            _SectionHeader(title: 'Aparência', theme: theme),

            // Modo do Tema
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _themeIcon(themeSettings.mode),
                  color: theme.colorScheme.primary,
                ),
              ),
              title: const Text('Tema',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                _themeLabel(themeSettings.mode),
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded, size: 18),
                  ),
                ],
                selected: {themeSettings.mode},
                onSelectionChanged: (modes) {
                  ref.read(themeSettingsProvider.notifier).setMode(modes.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            // Esquema de Cores
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.palette_outlined,
                    color: theme.colorScheme.tertiary),
              ),
              title: const Text('Esquema de Cores',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                themeSettings.scheme == AppThemeScheme.alinha
                    ? 'AlinhaJá (Padrão)'
                    : 'WhatsApp',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: DropdownButton<AppThemeScheme>(
                value: themeSettings.scheme,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(
                    value: AppThemeScheme.alinha,
                    child: Text(AppConstants.appName),
                  ),
                  DropdownMenuItem(
                    value: AppThemeScheme.whatsapp,
                    child: Text('WhatsApp'),
                  ),
                ],
                onChanged: (scheme) {
                  if (scheme != null) {
                    ref.read(themeSettingsProvider.notifier).setScheme(scheme);
                  }
                },
              ),
            ),

            const Divider(height: 32, indent: 16, endIndent: 16),

            // ── Seção: Conta ──────────────────────────
            _SectionHeader(title: 'Conta', theme: theme),

            // Notificações
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_outlined,
                    color: Colors.orange),
              ),
              title: const Text('Notificações',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Personalize suas notificações',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/settings/notifications'),
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person_outline_rounded,
                    color: theme.colorScheme.primary),
              ),
              title: const Text('Meu Perfil',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Nome, foto, cargo e status',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/profile'),
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.security_rounded, color: Colors.blue),
              ),
              title: const Text('Segurança e 2FA',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'App autenticador e dispositivos confiáveis',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/security-2fa'),
            ),

            // Gestão de Equipe — apenas TI Admin
            Builder(
              builder: (context) {
                final userAsync = ref.watch(currentUserProvider);
                final user = userAsync.valueOrNull;
                final isAdmin = AppPermissions.canAccessAdmin(user?.roleLevel);
                if (!isAdmin) return const SizedBox.shrink();
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.people_alt_rounded,
                        color: Colors.teal),
                  ),
                  title: const Text('Gestão de Equipe',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Arquivar, reativar e excluir colaboradores',
                    style: TextStyle(
                        color: theme.colorScheme.outline, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/employees'),
                );
              },
            ),

            // Histórico de Atividades do Usuário
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history, color: Colors.indigo),
              ),
              title: const Text('Meu Histórico',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Suas atividades recentes no app',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/profile/activity'),
            ),

            // Rastreamento de Localização — para todos os usuários e dispositivos
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.location_on_rounded, color: Colors.blue),
              ),
              title: const Text('Rastreamento',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'GPS e localização de colaboradores',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/settings/location'),
            ),

            // Central de Privacidade — exercício dos direitos do Art. 18 sem
            // depender de e-mail ao DPO.
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield,
                    color: Colors.green),
              ),
              title: const Text('Privacidade e Dados',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Termos, seus dados, exportação e pedidos LGPD',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/privacidade'),
            ),

            // ── Seção: Sobre ──────────────────────────
            _SectionHeader(title: 'Sobre', theme: theme),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome,
                    color: theme.colorScheme.primary),
              ),
              title: const Text('Novidades',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Notas de patch, melhorias e progresso do app',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/settings/changelog'),
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.help_outline_rounded, color: Colors.blue),
              ),
              title: const Text('Central de Ajuda',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Perguntas frequentes e dúvidas sobre o AlinhaJá',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/support/help'),
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.info_outline_rounded,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              title: const Text('Versão do App',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'AlinhaJá v${AppConstants.appVersion}',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
            ),

            const Divider(height: 32, indent: 16, endIndent: 16),

            // Sair
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sair do App'),
                      content: const Text(
                          'Tem certeza que deseja sair da sua conta?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent),
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await const AuthRepository().signOut();
                    if (context.mounted) context.go('/login');
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text('Sair do App',
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Escuro';
      case ThemeMode.system:
        return 'Automático (Sistema)';
    }
  }
}

// ─── Widget auxiliar de cabeçalho de seção ────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

