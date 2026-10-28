import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/web_utils.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/platform/providers/platform_provider.dart';

/// Seletor de empresa em atuação — visível SOMENTE para o dono da plataforma,
/// no app do tenant. Permite alternar o contexto de organização com o mesmo
/// login; ao trocar, recarrega o app para que todos os dados (RLS por
/// `fn_current_org()`) reflitam a empresa escolhida.
class PlatformOrgSwitcher extends ConsumerWidget {
  const PlatformOrgSwitcher({super.key, this.isExpanded = true});

  final bool isExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isPlatformOwnerProvider)) return const SizedBox.shrink();

    final orgsAsync = ref.watch(platformOrganizationsProvider);
    final currentOrgId =
        ref.watch(currentUserProvider).valueOrNull?.effectiveOrganizationId;

    return orgsAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (orgs) {
        if (orgs.length < 2) return const SizedBox.shrink();
        PlatformOrganization? current;
        for (final o in orgs) {
          if (o.id == currentOrgId) current = o;
        }
        final label = current?.name ?? 'Selecionar empresa';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Material(
            color: AppConstants.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openPicker(context, ref, orgs, currentOrgId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.apartment_rounded,
                        size: 20, color: AppConstants.primary),
                    if (isExpanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Empresa',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppConstants.secondaryText)),
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Icon(Icons.unfold_more_rounded,
                          size: 18, color: AppConstants.secondaryText),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    WidgetRef ref,
    List<PlatformOrganization> orgs,
    String? currentOrgId,
  ) async {
    final selected = await showModalBottomSheet<PlatformOrganization>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Atuar como empresa',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: orgs.length,
                itemBuilder: (_, i) {
                  final o = orgs[i];
                  final isCurrent = o.id == currentOrgId;
                  return ListTile(
                    leading: Icon(
                      isCurrent
                          ? Icons.check_circle_rounded
                          : Icons.apartment_outlined,
                      color: isCurrent
                          ? AppConstants.success
                          : AppConstants.secondaryText,
                    ),
                    title: Text(o.name),
                    subtitle: Text(
                      '/${o.slug} · ${o.userCount} usuário(s)'
                      '${o.isActive ? '' : ' · inativa'}',
                    ),
                    trailing: isCurrent
                        ? const Text('Atual',
                            style: TextStyle(
                                color: AppConstants.success,
                                fontWeight: FontWeight.w600))
                        : null,
                    onTap: isCurrent ? null : () => Navigator.pop(ctx, o),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || selected.id == currentOrgId) return;
    if (!context.mounted) return;
    await _switchTo(context, ref, selected);
  }

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    PlatformOrganization org,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await ref.read(platformRepositoryProvider).setActingOrg(org.id);
      ref.invalidate(currentUserProvider);
      ref.invalidate(platformOrganizationsProvider);
      if (kIsWeb) {
        // Recarrega para resetar realtime/caches sob a nova empresa.
        reloadApp();
        return;
      }
      // Mobile: sem reload nativo — reidrata o essencial e volta ao início.
      if (context.mounted) {
        Navigator.of(context).pop(); // fecha o loading
        context.go('/chats');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível trocar de empresa.\n$e')),
        );
      }
    }
  }
}
