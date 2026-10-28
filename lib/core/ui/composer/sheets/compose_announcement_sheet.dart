import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:alinha_ja/core/ui/composer/composer_media.dart';

/// Anúncio pronto para publicar: o texto e tudo que o card precisa.
class AnnouncementDraft {
  final String content;
  final AnnouncementSpec spec;

  /// Arquivo escolhido que ainda precisa subir — o envio resolve a URL antes
  /// de gravar a mensagem.
  final XFile? pendingAttachment;

  const AnnouncementDraft({
    required this.content,
    required this.spec,
    this.pendingAttachment,
  });
}

/// Composição de um anúncio oficial.
///
/// Substitui o antigo botão de liga/desliga: um anúncio agora tem peso,
/// validade, público e ação, em vez de ser só "mensagem em laranja".
class ComposeAnnouncementSheet extends ConsumerStatefulWidget {
  /// Nome da conversa de destino, exibido no cabeçalho.
  final String destinationName;

  const ComposeAnnouncementSheet({super.key, required this.destinationName});

  static Future<AnnouncementDraft?> show(
    BuildContext context, {
    required String destinationName,
  }) {
    return showModalBottomSheet<AnnouncementDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComposeAnnouncementSheet(destinationName: destinationName),
    );
  }

  @override
  ConsumerState<ComposeAnnouncementSheet> createState() =>
      _ComposeAnnouncementSheetState();
}

class _ComposeAnnouncementSheetState
    extends ConsumerState<ComposeAnnouncementSheet> {
  final _contentCtrl = TextEditingController();
  final _actionLabelCtrl = TextEditingController();
  final _actionValueCtrl = TextEditingController();

  AnnouncementPriority _priority = AnnouncementPriority.important;
  DateTime? _validUntil;
  bool _pinned = true;
  bool _requiresAck = false;

  final Set<AudienceTarget> _departments = {};
  final Set<AudienceTarget> _jobPositions = {};
  final Set<AudienceTarget> _branches = {};

  XFile? _attachment;
  AnnouncementActionKind _actionKind = AnnouncementActionKind.none;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _actionLabelCtrl.dispose();
    _actionValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Válido até',
      cancelText: 'Cancelar',
      confirmText: 'Definir',
    );
    if (date != null && mounted) {
      // Vale o dia inteiro: expira no fim da data escolhida, não às 00:00.
      setState(() => _validUntil =
          DateTime(date.year, date.month, date.day, 23, 59, 59));
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = ComposerMedia.toXFiles(result.files);
    if (files.isEmpty || !mounted) return;

    setState(() => _attachment = files.first);
  }

  void _publish() {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escreva o texto do anúncio.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    AnnouncementAction? action;
    if (_actionKind != AnnouncementActionKind.none) {
      final label = _actionLabelCtrl.text.trim();
      final value = _actionValueCtrl.text.trim();
      final needsValue = _actionKind != AnnouncementActionKind.confirmPresence;

      if (label.isEmpty || (needsValue && value.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preencha o rótulo e o destino do botão de ação.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      action = AnnouncementAction(
        kind: _actionKind,
        label: label,
        value: needsValue ? value : null,
      );
    }

    Navigator.of(context).pop(AnnouncementDraft(
      content: content,
      pendingAttachment: _attachment,
      spec: AnnouncementSpec(
        priority: _priority,
        validUntil: _validUntil,
        pinned: _pinned,
        requiresAck: _requiresAck,
        audience: AnnouncementAudience(
          departments: _departments.toList(),
          jobPositions: _jobPositions.toList(),
          branches: _branches.toList(),
        ),
        action: action,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                children: [
                  _buildContentField(theme),
                  const SizedBox(height: 20),
                  _buildPrioritySelector(theme),
                  const SizedBox(height: 20),
                  _buildValiditySection(theme),
                  const SizedBox(height: 8),
                  _buildAudienceSection(theme),
                  const SizedBox(height: 20),
                  _buildAttachmentSection(theme),
                  const SizedBox(height: 20),
                  _buildActionSection(theme),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _publish,
                    icon: const Icon(Icons.campaign_rounded, size: 20),
                    label: const Text('Publicar anúncio',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    style: FilledButton.styleFrom(
                      backgroundColor: announcementPriorities[_priority]!.color,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final style = announcementPriorities[_priority]!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          Icon(style.icon, color: style.color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anúncio oficial',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'em ${widget.destinationName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildContentField(ThemeData theme) {
    return TextField(
      controller: _contentCtrl,
      autofocus: true,
      maxLines: 5,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Texto do comunicado...',
        alignLabelWithHint: true,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPrioritySelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Prioridade', theme: theme),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in announcementPriorities.entries)
              ChoiceChip(
                selected: _priority == entry.key,
                onSelected: (_) => setState(() => _priority = entry.key),
                avatar: Icon(
                  entry.value.icon,
                  size: 17,
                  color: _priority == entry.key
                      ? Colors.white
                      : entry.value.color,
                ),
                label: Text(entry.value.label),
                selectedColor: entry.value.color,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _priority == entry.key
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          announcementPriorities[_priority]!.hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildValiditySection(ThemeData theme) {
    final formatted = _validUntil == null
        ? null
        : DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(_validUntil!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Validade e destaque', theme: theme),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy_rounded),
          title: Text(formatted == null ? 'Sem prazo' : 'Válido até $formatted'),
          subtitle: const Text(
            'Depois do prazo o anúncio fica marcado como encerrado',
            style: TextStyle(fontSize: 12),
          ),
          trailing: _validUntil == null
              ? TextButton(
                  onPressed: _pickValidUntil, child: const Text('Definir'))
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remover prazo',
                  onPressed: () => setState(() => _validUntil = null),
                ),
          onTap: _pickValidUntil,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
          secondary: const Icon(Icons.push_pin_outlined),
          title: const Text('Fixar no topo da conversa'),
          subtitle: const Text('Enquanto estiver válido',
              style: TextStyle(fontSize: 12)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _requiresAck,
          onChanged: (v) => setState(() => _requiresAck = v),
          secondary: const Icon(Icons.how_to_reg_outlined),
          title: const Text('Exigir confirmação de leitura'),
          subtitle: const Text('Você vê quem confirmou e quem falta',
              style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildAudienceSection(ThemeData theme) {
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final positions =
        ref.watch(jobPositionsProvider(null)).valueOrNull ?? const [];
    final branches = ref.watch(branchesProvider).valueOrNull ?? const [];

    final total = _departments.length + _jobPositions.length + _branches.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Público-alvo', theme: theme),
        Text(
          total == 0
              ? 'Todos da conversa devem confirmar'
              : 'Confirmação esperada de $total grupo(s)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _AudienceGroup(
          title: 'Setores',
          options: departments,
          selected: _departments,
          onToggle: (target) => setState(() => _departments.contains(target)
              ? _departments.remove(target)
              : _departments.add(target)),
        ),
        _AudienceGroup(
          title: 'Cargos',
          options: positions,
          selected: _jobPositions,
          onToggle: (target) => setState(() => _jobPositions.contains(target)
              ? _jobPositions.remove(target)
              : _jobPositions.add(target)),
        ),
        _AudienceGroup(
          title: 'Filiais',
          options: branches,
          selected: _branches,
          onToggle: (target) => setState(() => _branches.contains(target)
              ? _branches.remove(target)
              : _branches.add(target)),
        ),
      ],
    );
  }

  Widget _buildAttachmentSection(ThemeData theme) {
    final attachment = _attachment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Anexo', theme: theme),
        const SizedBox(height: 4),
        if (attachment == null)
          OutlinedButton.icon(
            onPressed: _pickAttachment,
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('Anexar documento'),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(attachment.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remover anexo',
              onPressed: () => setState(() => _attachment = null),
            ),
          ),
      ],
    );
  }

  Widget _buildActionSection(ThemeData theme) {
    const labels = {
      AnnouncementActionKind.none: 'Nenhum',
      AnnouncementActionKind.link: 'Abrir link',
      AnnouncementActionKind.document: 'Abrir documento',
      AnnouncementActionKind.confirmPresence: 'Confirmar presença',
    };
    final needsValue = _actionKind != AnnouncementActionKind.none &&
        _actionKind != AnnouncementActionKind.confirmPresence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Botão de ação', theme: theme),
        const SizedBox(height: 8),
        DropdownButtonFormField<AnnouncementActionKind>(
          initialValue: _actionKind,
          isDense: true,
          decoration: InputDecoration(
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            for (final entry in labels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (kind) =>
              setState(() => _actionKind = kind ?? AnnouncementActionKind.none),
        ),
        if (_actionKind != AnnouncementActionKind.none) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _actionLabelCtrl,
            decoration: InputDecoration(
              labelText: 'Texto do botão',
              hintText: 'Ex: Ler política completa',
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (needsValue) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _actionValueCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'URL de destino',
                hintText: 'https://...',
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final ThemeData theme;

  const _SectionLabel(this.text, {required this.theme});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      );
}

/// Linha de chips selecionáveis de um eixo do público-alvo.
class _AudienceGroup extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final Set<AudienceTarget> selected;
  final ValueChanged<AudienceTarget> onToggle;

  const _AudienceGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                Builder(builder: (context) {
                  final target = AudienceTarget(
                    id: option['id']?.toString() ?? '',
                    name: option['name']?.toString() ?? '—',
                  );
                  if (target.id.isEmpty) return const SizedBox.shrink();

                  return FilterChip(
                    selected: selected.contains(target),
                    onSelected: (_) => onToggle(target),
                    label: Text(target.name,
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}
