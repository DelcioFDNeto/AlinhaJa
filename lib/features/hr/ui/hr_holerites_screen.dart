import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/models/holerite_model.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Holerites (visão do RH): emissão (upload de PDF por
/// competência), consulta e recibo de leitura do colaborador.
class HrHoleritesScreen extends ConsumerStatefulWidget {
  const HrHoleritesScreen({super.key});

  @override
  ConsumerState<HrHoleritesScreen> createState() => _HrHoleritesScreenState();
}

class _HrHoleritesScreenState extends ConsumerState<HrHoleritesScreen> {
  String? _funcionarioId;
  int? _ano;

  HoleriteFilters get _filters =>
      HoleriteFilters(funcionarioId: _funcionarioId, ano: _ano);

  @override
  Widget build(BuildContext context) {
    final holerites = ref.watch(holeritesProvider(_filters));
    final canManage = ref.watch(rbacCanProvider((module: 'rh_holerites', action: 'manage')));
    final funcionarios = ref.watch(funcionariosLiteProvider);
    final anoAtual = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(title: const Text('Holerites')),
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context),
        icon: const Icon(Icons.upload_file),
        label: const Text('Emitir holerite'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 260,
                  child: funcionarios.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                    data: (list) => DropdownButtonFormField<String?>(
                      initialValue: _funcionarioId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Funcionário',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Todos')),
                        for (final f in list)
                          DropdownMenuItem(
                              value: f['id'] as String,
                              child: Text(f['nome'] as String? ?? '',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _funcionarioId = v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _ano,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (var a = anoAtual; a >= anoAtual - 4; a--)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) => setState(() => _ano = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: holerites.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
              data: (list) {
                if (list.isEmpty) {
                  return HrEmptyState(
                    icone: Icons.receipt_long,
                    titulo: 'Nenhum holerite emitido',
                    descricao:
                        'O holerite é publicado por competência (mês/ano). '
                        'Depois de emitido, o colaborador vê o PDF em "Meus '
                        'holerites" e o recibo de leitura volta para cá.',
                    passos: const [
                      'Toque em "Emitir holerite".',
                      'Escolha o funcionário, a competência e envie o PDF.',
                      'Acompanhe aqui quem já abriu o holerite — a situação '
                          'mostra o recibo de leitura.',
                    ],
                    acaoLabel: 'Emitir holerite',
                    acaoIcone: Icons.upload_file,
                    onAcao: () => _showUploadSheet(context),
                    nota: 'Se você aplicou filtros de funcionário ou ano, '
                        'pode haver holerites fora deste recorte.',
                    estrutura: const HrGhostList(
                      colunas: ['Funcionário', 'Competência', 'Situação'],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _HoleriteTile(
                    holerite: list[i],
                    onChanged: () =>
                        ref.invalidate(holeritesProvider(_filters)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UploadHoleriteSheet(onSaved: () {
        ref.invalidate(holeritesProvider(_filters));
      }),
    );
  }
}

class _HoleriteTile extends ConsumerWidget {
  const _HoleriteTile({required this.holerite, required this.onChanged});

  final HoleriteModel holerite;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final visualizado = holerite.dataVisualizacao != null;
    final canManage = ref.watch(rbacCanProvider((module: 'rh_holerites', action: 'manage')));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: const Icon(Icons.request_quote_outlined),
        title: Text(
          '${holerite.competencia} · ${holerite.funcionarioNome ?? 'Funcionário'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(visualizado
            ? 'Visualizado em ${fmt.format(holerite.dataVisualizacao!.toLocal())}'
            : 'Disponibilizado em ${fmt.format(holerite.dataDisponibilizacao.toLocal())}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(
              label: visualizado ? 'Visualizado' : 'Não visualizado',
              role: visualizado ? StatusRole.success : StatusRole.pending,
            ),
            if (holerite.arquivoPdfPath != null)
              IconButton(
                tooltip: 'Abrir PDF',
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  try {
                    final url = await ref
                        .read(peopleManagementServiceProvider)
                        .holeriteSignedUrl(holerite.arquivoPdfPath!);
                    await launchUrlString(url);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao abrir: ${friendlyError(e)}')));
                    }
                  }
                },
              ),
            if (canManage)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Excluir holerite?'),
                    content: Text(
                        'O holerite de ${holerite.competencia} será removido, incluindo o PDF.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Excluir')),
                    ],
                  ),
                );
                if (ok != true) return;
                await ref
                    .read(peopleManagementServiceProvider)
                    .deleteHolerite(holerite);
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadHoleriteSheet extends ConsumerStatefulWidget {
  const _UploadHoleriteSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_UploadHoleriteSheet> createState() =>
      _UploadHoleriteSheetState();
}

class _UploadHoleriteSheetState extends ConsumerState<_UploadHoleriteSheet> {
  String? _funcionarioId;
  int _mes = DateTime.now().month;
  int _ano = DateTime.now().year;
  PlatformFile? _arquivo;
  bool _isLoading = false;

  static const _meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _arquivo = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (_funcionarioId == null || _arquivo?.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione o funcionário e o PDF do holerite.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(peopleManagementServiceProvider).uploadHolerite(
            funcionarioId: _funcionarioId!,
            mes: _mes,
            ano: _ano,
            bytes: _arquivo!.bytes!,
            fileName: _arquivo!.name,
          );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final funcionarios = ref.watch(funcionariosLiteProvider);
    final anoAtual = DateTime.now().year;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Emitir holerite',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          funcionarios.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erro: ${friendlyError(e)}'),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _funcionarioId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Funcionário', border: OutlineInputBorder()),
              items: [
                for (final f in list)
                  DropdownMenuItem(
                      value: f['id'] as String,
                      child: Text(f['nome'] as String? ?? '',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _funcionarioId = v),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  initialValue: _mes,
                  decoration: const InputDecoration(
                      labelText: 'Mês', border: OutlineInputBorder()),
                  items: [
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                  ],
                  onChanged: (v) => setState(() => _mes = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: _ano,
                  decoration: const InputDecoration(
                      labelText: 'Ano', border: OutlineInputBorder()),
                  items: [
                    for (var a = anoAtual + 1; a >= anoAtual - 4; a--)
                      DropdownMenuItem(value: a, child: Text('$a')),
                  ],
                  onChanged: (v) => setState(() => _ano = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_arquivo?.name ?? 'Selecionar PDF do holerite'),
            onPressed: _pickFile,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator())
                : const Text('Emitir'),
          ),
        ],
      ),
    );
  }
}
