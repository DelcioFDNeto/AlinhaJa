import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/hr/models/rh_documento_model.dart';
import 'package:alinha_ja/features/hr/providers/rh_todos_documentos_provider.dart';
import 'package:alinha_ja/features/hr/providers/rh_documento_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

class HrDocumentosScreen extends ConsumerWidget {
  const HrDocumentosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(rhTodosDocumentosProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Gestão de Documentos', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
      ),
      body: ResponsiveWidthContainer(
        child: docsAsync.when(
          data: (docs) {
            if (docs.isEmpty) {
              return const HrEmptyState(
                icone: Icons.folder_open,
                titulo: 'Nenhum documento enviado ainda',
                descricao:
                    'Esta tela reúne os documentos que os colaboradores '
                    'enviam (RG, CPF, comprovante de residência, atestado) '
                    'para o RH conferir e marcar como válido ou recusado.',
                passos: [
                  'Peça ao colaborador que envie pelo app, em "Meus '
                      'documentos".',
                  'O documento chega aqui com a situação "pendente".',
                  'Abra, confira o arquivo e marque como válido ou recusado '
                      '— a pessoa é avisada da decisão.',
                ],
                nota: 'O envio parte do colaborador: o RH confere e decide, '
                    'mas não sobe documento pelo colaborador nesta tela.',
                estrutura: HrGhostList(
                  colunas: ['Colaborador', 'Documento', 'Situação'],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                return _AdminDocumentCard(doc: doc);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        ),
      ),
    );
  }
}

class _AdminDocumentCard extends ConsumerStatefulWidget {
  final RhDocumento doc;
  const _AdminDocumentCard({required this.doc});

  @override
  ConsumerState<_AdminDocumentCard> createState() => _AdminDocumentCardState();
}

class _AdminDocumentCardState extends ConsumerState<_AdminDocumentCard> {
  bool _isUpdating = false;

  Future<void> _updateStatus(DocumentoStatus status) async {
    setState(() => _isUpdating = true);
    try {
      await ref.read(rhDocumentoRepositoryProvider).updateStatus(widget.doc.id, status);
      ref.invalidate(rhTodosDocumentosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status atualizado!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  /// RH-24 — liga/desliga a exigência de ciência do funcionário.
  /// Desligar não apaga um aceite já registrado (a trilha é preservada).
  Future<void> _toggleExigeAceite(bool exige) async {
    setState(() => _isUpdating = true);
    try {
      await ref
          .read(rhDocumentoRepositoryProvider)
          .setExigeAceite(widget.doc.id, exige);
      ref.invalidate(rhTodosDocumentosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(exige
                ? 'O funcionário verá o pedido de ciência em Meus Documentos.'
                : 'Ciência não é mais exigida neste documento.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  /// Rejeição exige motivo (S098): pergunta a razão e chama a RPC.
  Future<void> _rejectWithReason() async {
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar documento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo da rejeição',
            hintText: 'Explique por que o documento foi recusado',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.isEmpty) return;

    setState(() => _isUpdating = true);
    try {
      await ref
          .read(rhDocumentoRepositoryProvider)
          .rejeitarDocumento(widget.doc.id, motivo);
      ref.invalidate(rhTodosDocumentosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Documento rejeitado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_documentos', action: 'manage')));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, color: context.statusTokens.color(widget.doc.status.role), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.doc.titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text('Categoria: ${widget.doc.categoria.name.toUpperCase()}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.statusTokens.color(widget.doc.status.role).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.statusTokens.color(widget.doc.status.role)),
                  ),
                  child: Text(
                    widget.doc.status.label,
                    style: TextStyle(color: context.statusTokens.color(widget.doc.status.role), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // RH-24 — exigir (e acompanhar) a ciência do funcionário.
            if (canManage)
            _AceiteControl(
              doc: widget.doc,
              onChanged: _toggleExigeAceite,
              busy: _isUpdating,
            ),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.doc.dataVencimento != null)
                  Text('Vencimento: ${DateFormat('dd/MM/yyyy').format(widget.doc.dataVencimento!)}')
                else
                  const Text('Sem validade definida', style: TextStyle(fontStyle: FontStyle.italic)),

                Wrap(
                  spacing: 0,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final url = await ref.read(rhDocumentoRepositoryProvider).getSignedUrl(widget.doc.storagePath);
                          if (await canLaunchUrl(Uri.parse(url))) {
                            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
                        }
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Ver / Baixar'),
                    ),
                    if (canManage && widget.doc.status == DocumentoStatus.pendenteAprovacao) ...[
                      const SizedBox(width: 8),
                      if (_isUpdating)
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      else ...[
                        FilledButton.tonal(
                          onPressed: _rejectWithReason,
                          style: FilledButton.styleFrom(backgroundColor: context.statusTokens.danger.withValues(alpha: 0.1), foregroundColor: context.statusTokens.danger),
                          child: const Text('Rejeitar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _updateStatus(DocumentoStatus.valido),
                          style: FilledButton.styleFrom(backgroundColor: context.statusTokens.success),
                          child: const Text('Aprovar'),
                        ),
                      ]
                    ]
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

/// RH-24 — controle de ciência no card do RH: alterna a exigência e,
/// quando já houve aceite, mostra o recibo (quem declarou e quando).
class _AceiteControl extends StatelessWidget {
  const _AceiteControl({
    required this.doc,
    required this.onChanged,
    required this.busy,
  });

  final RhDocumento doc;
  final ValueChanged<bool> onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: doc.exigeAceite,
          onChanged: busy ? null : onChanged,
          title: const Text('Exigir ciência do funcionário',
              style: TextStyle(fontSize: 14)),
          subtitle: Text(
            'O funcionário confirma a leitura em Meus Documentos.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (doc.exigeAceite)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Row(
              children: [
                Icon(
                  doc.aceitePendente
                      ? Icons.hourglass_empty
                      : Icons.verified_user,
                  size: 16,
                  color: doc.aceitePendente ? tokens.warning : tokens.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    doc.aceitePendente
                        ? 'Aguardando a ciência do funcionário.'
                        : 'Ciência registrada em '
                            '${DateFormat('dd/MM/yyyy \'às\' HH:mm').format(doc.aceitoEm!.toLocal())}.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color:
                          doc.aceitePendente ? tokens.warning : tokens.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
