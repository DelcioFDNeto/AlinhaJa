import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';

import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/providers/vacancy_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-9 / Fase 4 — Gestão do Catálogo de Áreas e Cargos.
/// CRUD simples usado pela aba Ajustes da Central de Recrutamento.
/// A escrita passa pela RLS (papel RH) e a org é carimbada por trigger.
class CatalogManagementSheet extends ConsumerStatefulWidget {
  const CatalogManagementSheet({super.key});

  @override
  ConsumerState<CatalogManagementSheet> createState() =>
      _CatalogManagementSheetState();
}

class _CatalogManagementSheetState
    extends ConsumerState<CatalogManagementSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: TabBar(
            controller: _tab,
            tabs: const [Tab(text: 'Áreas'), Tab(text: 'Cargos')],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: const [_AreasTab(), _CargosTab()],
        ),
      ),
    );
  }
}

// ── Áreas ─────────────────────────────────────────────────────
class _AreasTab extends ConsumerWidget {
  const _AreasTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(areasProvider(false));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editArea(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova área'),
      ),
      body: areasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar áreas.\n${friendlyError(e)}')),
        data: (areas) {
          if (areas.isEmpty) {
            return HrEmptyState(
              icone: Icons.category_outlined,
              titulo: 'Nenhuma área cadastrada',
              descricao:
                  'Área é o agrupamento macro da empresa (Comercial, '
                  'Logística, Financeiro). Ela organiza os cargos, as vagas e '
                  'os gráficos por área do painel de RH.',
              passos: const [
                'Cadastre as áreas da empresa, uma por vez.',
                'Depois, na aba Cargos, crie os cargos e ligue cada um à sua '
                    'área.',
                'Vagas e fichas de funcionário passam a oferecer essas '
                    'opções nos formulários.',
              ],
              acaoLabel: 'Cadastrar primeira área',
              acaoIcone: Icons.add,
              onAcao: () => _editArea(context, ref),
              estrutura: const HrGhostList(
                comAvatar: false,
                colunas: ['Área', 'Cargos', 'Situação'],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            itemCount: areas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = areas[i];
              return ListTile(
                title: Text(a.nome),
                leading: Icon(Icons.category_outlined,
                    color: a.ativo
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline),
                subtitle: a.ativo ? null : const Text('Inativa'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: a.ativo,
                      onChanged: (v) => _setAtivo(context, ref, a, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editArea(context, ref, a),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _setAtivo(
      BuildContext context, WidgetRef ref, CatalogItem a, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(vacancyServiceProvider).updateArea(a.id, ativo: v);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    }
  }

  Future<void> _editArea(BuildContext context, WidgetRef ref,
      [CatalogItem? area]) async {
    final messenger = ScaffoldMessenger.of(context);
    final nome = await _promptNome(context,
        titulo: area == null ? 'Nova área' : 'Editar área',
        inicial: area?.nome ?? '');
    if (nome == null || nome.isEmpty) return;
    try {
      final svc = ref.read(vacancyServiceProvider);
      if (area == null) {
        await svc.createArea(nome);
      } else {
        await svc.updateArea(area.id, nome: nome);
      }
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
    }
  }
}

// ── Cargos ────────────────────────────────────────────────────
class _CargosTab extends ConsumerWidget {
  const _CargosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cargosAsync = ref.watch(cargosProvider(false));
    final areasAsync = ref.watch(areasProvider(false));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCargo(context, ref, areasAsync.valueOrNull ?? []),
        icon: const Icon(Icons.add),
        label: const Text('Novo cargo'),
      ),
      body: cargosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar cargos.\n${friendlyError(e)}')),
        data: (cargos) {
          if (cargos.isEmpty) {
            return HrEmptyState(
              icone: Icons.badge_outlined,
              titulo: 'Nenhum cargo cadastrado',
              descricao:
                  'O cargo é a função exercida (Vendedor, Analista Fiscal, '
                  'Motorista). É ele que aparece na ficha do funcionário, na '
                  'vaga publicada e na geração de questões por IA.',
              passos: const [
                'Se ainda não houver áreas, cadastre-as na aba anterior.',
                'Crie o cargo com nome e nível, e ligue-o à área '
                    'correspondente.',
                'Os formulários de vaga e de funcionário passam a listar '
                    'esse cargo.',
              ],
              acaoLabel: 'Cadastrar primeiro cargo',
              acaoIcone: Icons.add,
              onAcao: () =>
                  _editCargo(context, ref, areasAsync.valueOrNull ?? []),
              estrutura: const HrGhostList(
                comAvatar: false,
                colunas: ['Cargo', 'Área', 'Nível'],
              ),
            );
          }
          final areas = areasAsync.valueOrNull ?? [];
          final areaNome = {for (final a in areas) a.id: a.nome};
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            itemCount: cargos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = cargos[i];
              final sub = [
                if (c.areaId != null && areaNome[c.areaId] != null)
                  areaNome[c.areaId]!,
                if (!c.ativo) 'Inativo',
              ].join(' · ');
              return ListTile(
                title: Text(c.nome),
                leading: Icon(Icons.badge_outlined,
                    color: c.ativo
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline),
                subtitle: sub.isEmpty ? null : Text(sub),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: c.ativo,
                      onChanged: (v) => _setAtivo(context, ref, c, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editCargo(context, ref, areas, c),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _setAtivo(
      BuildContext context, WidgetRef ref, CatalogItem c, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(vacancyServiceProvider).updateCargo(c.id, ativo: v);
      ref.invalidate(cargosProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    }
  }

  Future<void> _editCargo(BuildContext context, WidgetRef ref,
      List<CatalogItem> areas,
      [CatalogItem? cargo]) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<_CargoResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CargoFormSheet(areas: areas, cargo: cargo),
    );
    if (result == null) return;
    try {
      final svc = ref.read(vacancyServiceProvider);
      if (cargo == null) {
        await svc.createCargo(result.nome, areaId: result.areaId);
      } else {
        await svc.updateCargo(cargo.id,
            nome: result.nome, areaId: result.areaId);
      }
      ref.invalidate(cargosProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
    }
  }
}

/// Diálogo simples de nome (usado para áreas).
Future<String?> _promptNome(BuildContext context,
    {required String titulo, String inicial = ''}) {
  final controller = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nome'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar')),
      ],
    ),
  );
}

class _CargoResult {
  final String nome;
  final String? areaId;
  const _CargoResult(this.nome, this.areaId);
}

/// Form de cargo — nome + área opcional.
class _CargoFormSheet extends StatefulWidget {
  const _CargoFormSheet({required this.areas, this.cargo});

  final List<CatalogItem> areas;
  final CatalogItem? cargo;

  @override
  State<_CargoFormSheet> createState() => _CargoFormSheetState();
}

class _CargoFormSheetState extends State<_CargoFormSheet> {
  late final TextEditingController _nome =
      TextEditingController(text: widget.cargo?.nome ?? '');
  late String? _areaId = widget.cargo?.areaId;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.cargo == null ? 'Novo cargo' : 'Editar cargo',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nome,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome do cargo'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _areaId,
            decoration: const InputDecoration(labelText: 'Área (opcional)'),
            items: [
              const DropdownMenuItem<String>(
                  value: null, child: Text('Nenhuma')),
              for (final a in widget.areas)
                DropdownMenuItem(value: a.id, child: Text(a.nome)),
            ],
            onChanged: (v) => setState(() => _areaId = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final nome = _nome.text.trim();
              if (nome.length < 2) return;
              Navigator.pop(context, _CargoResult(nome, _areaId));
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
