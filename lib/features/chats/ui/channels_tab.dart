import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';
import 'package:alinha_ja/core/utils/icon_registry.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/channels/models/channel_model.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/providers/channels_list_provider.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/ui/responsive_layout.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:intl/intl.dart';

/// Aba de Canais com a listagem dos canais corporativos (Workspaces).
class ChannelsTab extends ConsumerStatefulWidget {
  const ChannelsTab({super.key});

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
  String _searchQuery = '';

  /// Chave da categoria selecionada (`_allCategories` = sem filtro). Usar a
  /// chave, e não o rótulo, permite que categorias novas criadas em presets
  /// (RH, Comercial, TI…) apareçam aqui sem edição de código.
  String _selectedCategory = _allCategories;
  static const String _allCategories = '__todos__';

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _categoryScrollCtrl = ScrollController();

  /// Só entram no filtro as categorias que realmente têm workspace — evita
  /// uma fileira de chips que não levam a lugar nenhum.
  List<String> _availableCategories(List<ChannelModel> channels) {
    final present = <String>{};
    for (final channel in channels) {
      final cat = channel.metadata?['category']?.toString();
      if (cat != null && cat.trim().isNotEmpty) present.add(cat);
    }

    final ordered = WorkspaceCategories.labels.keys
        .where(present.contains)
        .toList()
      ..addAll(present.where((c) => !WorkspaceCategories.labels.containsKey(c)));

    return [_allCategories, ...ordered];
  }

  bool _matchesFilters(ChannelModel channel) {
    final query = _searchQuery.toLowerCase();
    final matchesSearch = channel.name.toLowerCase().contains(query) ||
        (channel.description ?? '').toLowerCase().contains(query);
    if (!matchesSearch) return false;

    if (_selectedCategory == _allCategories) return true;
    return channel.metadata?['category']?.toString() == _selectedCategory;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _categoryScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsListProvider);
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).value;
    final canCreate = AppPermissions.canCreateChannel(user?.roleLevel);

    // Determina se o FAB de criação de canais deve ser exibido.
    // Ele só é mostrado se houver canais na lista após filtragem.
    bool showFab = false;
    if (canCreate && channelsAsync.hasValue) {
      showFab = (channelsAsync.value ?? []).any(_matchesFilters);
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar canais:\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ref.invalidate(channelsListProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (channels) {
          // Filtra a lista de canais com base na busca e categoria selecionada
          final filteredChannels = channels.where(_matchesFilters).toList();
          final categories = _availableCategories(channels);

          // A categoria selecionada pode ter deixado de existir (último
          // workspace dela removido) — volta para "Todos" em vez de mostrar
          // uma lista vazia sem chip correspondente.
          if (!categories.contains(_selectedCategory)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _selectedCategory = _allCategories);
              }
            });
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(channelsListProvider),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Cabeçalho Premium com filtros integrados
                SliverToBoxAdapter(
                  child: _buildHeaderView(context, theme),
                ),

                // Seção de Filtros por Categoria (Horizontal)
                if (categories.length > 1)
                  SliverToBoxAdapter(
                    child: _buildCategoryFilters(theme, categories),
                  ),

                // Lista/Grade de Canares
                if (filteredChannels.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.campaign_outlined,
                            size: 64,
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Nenhum canal encontrado'
                                : 'Você não está em nenhum canal desta categoria',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.outline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_searchQuery.isEmpty) ...[
                            Text(
                              'Explore novos canais públicos para participar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: () =>
                                      context.push('/channels/discover'),
                                  icon: const Icon(Icons.explore_outlined),
                                  label: const Text('Descobrir Canais'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                  ),
                                ),
                                if (canCreate)
                                  FilledButton.icon(
                                    onPressed: () =>
                                        context.push('/channel/create'),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Novo Fluxo'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          theme.colorScheme.secondary,
                                      foregroundColor:
                                          theme.colorScheme.onSecondary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  () {
                    final isMobile = MediaQuery.of(context).size.width < 600;
                    final isDesktop =
                        MediaQuery.of(context).size.width >= kDesktopBreakpoint;

                    if (isMobile) {
                      return SliverPadding(
                        padding: const EdgeInsets.only(top: 8, bottom: 120),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final channel = filteredChannels[index];
                              return _WorkspaceCardMobile(
                                channel: channel,
                                onTap: () {
                                  context
                                      .push('/channel/${channel.id}', extra: {
                                    'channelName': channel.name,
                                  });
                                },
                              );
                            },
                            childCount: filteredChannels.length,
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isDesktop ? 360 : 300,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          mainAxisExtent: isDesktop ? 180 : 170,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final channel = filteredChannels[index];
                            return _WorkspaceCard(
                              channel: channel,
                              onTap: () {
                                if (isDesktop) {
                                  ProviderScope.containerOf(context)
                                      .read(desktopSelectionProvider.notifier)
                                      .state = DesktopSelection.channel(
                                    channel.id,
                                    channel.name,
                                  );
                                } else {
                                  context
                                      .push('/channel/${channel.id}', extra: {
                                    'channelName': channel.name,
                                  });
                                }
                              },
                            );
                          },
                          childCount: filteredChannels.length,
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          );
        },
      ),
      floatingActionButton: showFab
          ? Padding(
              padding: EdgeInsets.only(
                  bottom: 72 + MediaQuery.of(context).padding.bottom),
              child: FloatingActionButton.extended(
                heroTag: 'channels_fab',
                onPressed: () => context.push('/channel/create'),
                backgroundColor: theme.colorScheme.primary,
                icon: Icon(Icons.add, color: theme.colorScheme.onPrimary),
                label: const Text('Novo Fluxo'),
              ),
            )
          : null,
    );
  }

  Widget _buildHeaderView(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Espaços de Trabalho',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AppPermissions.canCreateChannel(
                      ref.watch(currentUserProvider).value?.roleLevel))
                    IconButton.filledTonal(
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      tooltip: 'Presets de Workspace',
                      onPressed: () => context.push('/workspace-presets'),
                    ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.explore_outlined),
                    tooltip: 'Explorar Canais Públicos',
                    onPressed: () => context.push('/channels/discover'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Gerencie os fluxos operacionais, OS e avisos dos seus departamentos.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // Barra de Pesquisa Premium
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Pesquisar workspaces e canais...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilters(ThemeData theme, List<String> categories) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSuperNarrow = constraints.maxWidth < 280;

        return Container(
          height: 52,
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final double scrollDelta = pointerSignal.scrollDelta.dy != 0
                    ? pointerSignal.scrollDelta.dy
                    : pointerSignal.scrollDelta.dx;
                if (scrollDelta != 0) {
                  final newOffset = _categoryScrollCtrl.offset + scrollDelta;
                  _categoryScrollCtrl.jumpTo(
                    newOffset.clamp(0.0, _categoryScrollCtrl.position.maxScrollExtent),
                  );
                }
              }
            },
            child: RawScrollbar(
              controller: _categoryScrollCtrl,
              thumbVisibility: true,
              thumbColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              radius: const Radius.circular(8),
              thickness: 4,
              padding: const EdgeInsets.only(bottom: 2),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.builder(
                  controller: _categoryScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategory == cat;
                    final isAll = cat == _allCategories;
                    final label = isAll
                        ? 'Todos'
                        : WorkspaceCategories.label(cat);
                    final icon = isAll
                        ? Icons.grid_view_rounded
                        : IconRegistry.resolve(WorkspaceCategories.icons[cat]);

                  // Responsividade inteligente: em telas muito pequenas, oculta o texto se não estiver selecionado
                  final bool showText = !isSuperNarrow || isSelected;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        icon,
                        size: 16,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      label: showText
                          ? Text(
                              label,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            )
                          : const SizedBox.shrink(),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedCategory = cat);
                        }
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      showCheckmark: false,
                      selectedColor: theme.colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ), // closes ListView.builder
              ), // closes ScrollConfiguration
            ), // closes RawScrollbar
          ),
        ); // closes Container
      },
    );
  }
}

/// Card de Workspace Individual para Canais (Grade).
class _WorkspaceCard extends StatelessWidget {
  final ChannelModel channel;
  final VoidCallback onTap;

  const _WorkspaceCard({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = channel.unreadCount > 0;

    // Prioriza ícone e cor do metadata (salvo na criação do canal)
    IconData icon = channel.icon;
    Color seedColor = channel.metadataColor ?? theme.colorScheme.primary;

    // Fallback por nome SOMENTE se não houver ícone no metadata
    if (channel.iconCode == null) {
      String nameUpper = channel.name.toUpperCase();
      if (nameUpper.contains('FATURAMENTO') ||
          nameUpper.contains('FINANCEIRO') ||
          nameUpper.contains('CONTAS A PAGAR')) {
        seedColor = const Color(0xFF2E7D32);
        icon = Icons.receipt_long_rounded;
      } else if (nameUpper.contains('FAT MOTO') ||
          nameUpper.contains('PEDIDO') ||
          nameUpper.contains('LIBERAÇÃO')) {
        seedColor = const Color(0xFF7B1FA2);
        icon = Icons.fact_check_rounded;
      } else if (nameUpper.contains('EMPLACAMENTO') ||
          nameUpper.contains('DOCUMENTAÇÃO') ||
          nameUpper.contains('CADASTRO')) {
        seedColor = const Color(0xFF1565C0);
        icon = Icons.description_rounded;
      } else if (nameUpper.contains('OS') ||
          nameUpper.contains('SERVIÇO') ||
          nameUpper.contains('MANUTENÇÃO')) {
        seedColor = const Color(0xFFE65100);
        icon = Icons.build_circle_rounded;
      } else if (nameUpper.contains('PÓS VENDA') ||
          nameUpper.contains('SUPORTE')) {
        seedColor = const Color(0xFF1565C0);
        icon = Icons.support_agent_rounded;
      } else if (nameUpper.contains('AVISOS') || nameUpper.contains('GERAL')) {
        seedColor = const Color(0xFFC62828);
        icon = Icons.campaign_rounded;
      }
    }

    final catRaw = channel.metadata?['category']?.toString() ?? 'geral';
    final String catLabel = _mapCategoryToLabel(catRaw);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Container do Card Premium com visual de Glassmorphism Gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  seedColor.withValues(alpha: 0.15),
                  seedColor.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasUnread
                    ? seedColor.withValues(alpha: 0.8)
                    : seedColor.withValues(alpha: 0.22),
                width: hasUnread ? 2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: seedColor.withValues(alpha: hasUnread ? 0.12 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topo: Ícone + Categoria Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: seedColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: seedColor, size: 22),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: seedColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        catLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: seedColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Nome do Canal
                Text(
                  channel.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Descrição ou Último Atendimento
                Text(
                  channel.description ?? 'Sem descrição',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Indicador de data / rodapé
                if (channel.lastMessageAt != null)
                  Text(
                    'Ativo: ${DateFormat('dd/MM HH:mm').format(channel.lastMessageAt!.toLocal())}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    'Sem atividades recentes',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),

          // Insígnia Vermelha Flutuante (Top-Right)
          if (hasUnread)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  channel.unreadCount > 99 ? '99+' : '${channel.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _mapCategoryToLabel(String category) {
    switch (category.toLowerCase()) {
      case 'financeiro':
        return 'Financeiro';
      case 'operacional':
        return 'Operações';
      case 'faturamento':
        return 'Faturamento';
      case 'informativo':
        return 'Avisos';
      default:
        return 'Geral';
    }
  }
}

/// Card de Workspace Individual para Mobile (Lista).
class _WorkspaceCardMobile extends StatelessWidget {
  final ChannelModel channel;
  final VoidCallback onTap;

  const _WorkspaceCardMobile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = channel.unreadCount > 0;
    IconData icon = channel.icon;
    Color seedColor = channel.metadataColor ?? theme.colorScheme.primary;

    if (channel.iconCode == null) {
      String nameUpper = channel.name.toUpperCase();
      if (nameUpper.contains('FATURAMENTO') ||
          nameUpper.contains('FINANCEIRO') ||
          nameUpper.contains('CONTAS A PAGAR')) {
        seedColor = const Color(0xFF2E7D32);
        icon = Icons.receipt_long_rounded;
      } else if (nameUpper.contains('FAT MOTO') ||
          nameUpper.contains('PEDIDO') ||
          nameUpper.contains('LIBERAÇÃO')) {
        seedColor = const Color(0xFF7B1FA2);
        icon = Icons.fact_check_rounded;
      } else if (nameUpper.contains('EMPLACAMENTO') ||
          nameUpper.contains('DOCUMENTAÇÃO') ||
          nameUpper.contains('CADASTRO')) {
        seedColor = const Color(0xFF1565C0);
        icon = Icons.description_rounded;
      } else if (nameUpper.contains('OS') ||
          nameUpper.contains('SERVIÇO') ||
          nameUpper.contains('MANUTENÇÃO')) {
        seedColor = const Color(0xFFE65100);
        icon = Icons.build_circle_rounded;
      } else if (nameUpper.contains('PÓS VENDA') ||
          nameUpper.contains('SUPORTE')) {
        seedColor = const Color(0xFF1565C0);
        icon = Icons.support_agent_rounded;
      } else if (nameUpper.contains('AVISOS') || nameUpper.contains('GERAL')) {
        seedColor = const Color(0xFFC62828);
        icon = Icons.campaign_rounded;
      }
    }

    final catRaw = channel.metadata?['category']?.toString() ?? 'geral';
    final String catLabel = _mapCategoryToLabel(catRaw);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasUnread
              ? seedColor.withValues(alpha: 0.5)
              : seedColor.withValues(alpha: 0.15),
          width: hasUnread ? 1.5 : 1.0,
        ),
      ),
      elevation: 0,
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: seedColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: seedColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            channel.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: seedColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            catLabel,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: seedColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.description ?? 'Sem descrição',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (channel.lastMessageAt != null)
                    Text(
                      DateFormat('HH:mm')
                          .format(channel.lastMessageAt!.toLocal()),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Text(
                      'Sem ativo',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (hasUnread)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${channel.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 15),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _mapCategoryToLabel(String category) {
    switch (category.toLowerCase()) {
      case 'financeiro':
        return 'Financeiro';
      case 'operacional':
        return 'Operações';
      case 'faturamento':
        return 'Faturamento';
      case 'informativo':
        return 'Avisos';
      default:
        return 'Geral';
    }
  }
}
