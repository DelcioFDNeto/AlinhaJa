import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:google_fonts/google_fonts.dart';

class OrgStructureManagementSheet extends ConsumerStatefulWidget {
  const OrgStructureManagementSheet({super.key});

  @override
  ConsumerState<OrgStructureManagementSheet> createState() =>
      _OrgStructureManagementSheetState();
}

class _OrgStructureManagementSheetState
    extends ConsumerState<OrgStructureManagementSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Departamentos e Cargos',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Departamentos'),
            Tab(text: 'Cargos'),
          ],
        ),
      ),
      body: ResponsiveWidthContainer(
        child: TabBarView(
          controller: _tabController,
          children: const [
            _DepartmentsTab(),
            _JobPositionsTab(),
          ],
        ),
      ),
    );
  }
}

class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deptsAsync = ref.watch(allDepartmentsProvider);

    return Column(
      children: [
        Expanded(
          child: deptsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Erro: $err')),
            data: (depts) {
              if (depts.isEmpty) {
                return const Center(child: Text('Nenhum departamento cadastrado.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: depts.length,
                itemBuilder: (context, index) {
                  final dept = depts[index];
                  final bool isActive = dept['is_active'] == true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        dept['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive ? null : Colors.grey,
                          decoration: isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      trailing: Switch(
                        value: isActive,
                        onChanged: (val) async {
                          await ref
                              .read(orgStructureMutatorProvider)
                              .upsertDepartment(
                                id: dept['id'],
                                name: dept['name'],
                                isActive: val,
                              );
                        },
                      ),
                      onTap: () {
                        _showDeptDialog(context, ref, dept: dept);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _showDeptDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Novo Departamento'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeptDialog(BuildContext context, WidgetRef ref, {Map<String, dynamic>? dept}) {
    final nameCtrl = TextEditingController(text: dept?['name'] ?? '');
    bool isActive = dept?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(dept == null ? 'Novo Departamento' : 'Editar Departamento'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nome do Departamento'),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Ativo'),
                    value: isActive,
                    onChanged: (val) => setState(() => isActive = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await ref.read(orgStructureMutatorProvider).upsertDepartment(
                          id: dept?['id'],
                          name: nameCtrl.text.trim(),
                          isActive: isActive,
                        );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}

class _JobPositionsTab extends ConsumerWidget {
  const _JobPositionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(allJobPositionsProvider);
    final deptsAsync = ref.watch(allDepartmentsProvider);

    return Column(
      children: [
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Erro: $err')),
            data: (jobs) {
              if (jobs.isEmpty) {
                return const Center(child: Text('Nenhum cargo cadastrado.'));
              }
              return deptsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => const Center(child: Text('Erro carregando departamentos')),
                data: (depts) {
                  final deptMap = {for (var d in depts) d['id']: d['name']};

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      final bool isActive = job['is_active'] == true;
                      final deptIds = (job['department_ids'] as List?)?.cast<String>() ?? [];
                      final deptNames = deptIds.map((id) => deptMap[id] ?? 'Desconhecido').join(', ');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            job['name'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? null : Colors.grey,
                              decoration: isActive ? null : TextDecoration.lineThrough,
                            ),
                          ),
                          subtitle: Text(
                            deptNames.isEmpty ? 'Sem departamento' : deptNames,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Switch(
                            value: isActive,
                            onChanged: (val) async {
                              await ref
                                  .read(orgStructureMutatorProvider)
                                  .upsertJobPosition(
                                    id: job['id'],
                                    name: job['name'],
                                    departmentIds: deptIds,
                                    isActive: val,
                                  );
                            },
                          ),
                          onTap: () {
                            _showJobDialog(context, ref, job: job, allDepts: depts);
                          },
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: deptsAsync.maybeWhen(
            data: (depts) => FilledButton.icon(
              onPressed: () => _showJobDialog(context, ref, allDepts: depts),
              icon: const Icon(Icons.add),
              label: const Text('Novo Cargo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  void _showJobDialog(BuildContext context, WidgetRef ref, {Map<String, dynamic>? job, required List<Map<String, dynamic>> allDepts}) {
    final nameCtrl = TextEditingController(text: job?['name'] ?? '');
    bool isActive = job?['is_active'] ?? true;
    final List<String> selectedDepts = List<String>.from((job?['department_ids'] as List?)?.cast<String>() ?? []);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(job == null ? 'Novo Cargo' : 'Editar Cargo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nome do Cargo'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Departamentos', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: allDepts.map((d) {
                        final deptId = d['id'] as String;
                        final isSelected = selectedDepts.contains(deptId);
                        return FilterChip(
                          label: Text(d['name'] ?? ''),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                selectedDepts.add(deptId);
                              } else {
                                selectedDepts.remove(deptId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Ativo'),
                      value: isActive,
                      onChanged: (val) => setState(() => isActive = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await ref.read(orgStructureMutatorProvider).upsertJobPosition(
                          id: job?['id'],
                          name: nameCtrl.text.trim(),
                          departmentIds: selectedDepts,
                          isActive: isActive,
                        );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
