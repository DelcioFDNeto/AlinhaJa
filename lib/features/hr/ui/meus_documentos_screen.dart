import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/hr/models/rh_documento_model.dart';
import 'package:alinha_ja/features/hr/providers/rh_documento_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/providers/meus_documentos_provider.dart';
import 'package:intl/intl.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

class MeusDocumentosScreen extends ConsumerWidget {
  const MeusDocumentosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funcionarioIdAsync = ref.watch(meuFuncionarioIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Meus Documentos',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      body: funcionarioIdAsync.when(
        data: (funcionarioId) {
          if (funcionarioId == null) {
            return const Center(child: Text('Ficha de funcionário não encontrada.'));
          }

          final docsAsync = ref.watch(rhDocumentosPorFuncionarioProvider(funcionarioId));

          return ResponsiveWidthContainer(
            child: docsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return HrEmptyState(
                    icone: Icons.folder_open,
                    titulo: 'Nenhum documento enviado',
                    descricao:
                        'Aqui ficam os seus documentos entregues ao RH — RG, '
                        'CPF, comprovante de residência, atestados — e a '
                        'situação de cada um.',
                    passos: const [
                      'Toque em "Enviar Documento".',
                      'Escolha o tipo e anexe a foto ou o PDF.',
                      'Acompanhe a situação: pendente enquanto o RH não '
                          'conferir, depois válido ou recusado.',
                    ],
                    acaoLabel: 'Enviar primeiro documento',
                    acaoIcone: Icons.upload_file,
                    onAcao: () =>
                        _uploadNovoDocumento(context, ref, funcionarioId),
                    estrutura: const HrGhostList(
                      comAvatar: false,
                      colunas: ['Documento', 'Enviado em', 'Situação'],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _DocumentoCard(doc: doc, funcionarioId: funcionarioId);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      ),
      floatingActionButton: funcionarioIdAsync.valueOrNull != null
          ? FloatingActionButton.extended(
              onPressed: () => _uploadNovoDocumento(context, ref, funcionarioIdAsync.valueOrNull!),
              icon: const Icon(Icons.upload_file),
              label: const Text('Enviar Documento'),
            )
          : null,
    );
  }

  Future<void> _uploadNovoDocumento(BuildContext context, WidgetRef ref, String funcionarioId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes == null) return;

      // Simplificando: vamos enviar como 'outro' e título igual ao nome do arquivo
      // Em uma versão mais completa, abriríamos um modal para escolher categoria e título.
      final orgId = ref.read(meuOrgIdProvider).valueOrNull;
      if (orgId == null) return;

      try {
        await ref.read(rhDocumentosPorFuncionarioProvider(funcionarioId).notifier).upload(
              orgId: orgId,
              titulo: file.name,
              categoria: DocumentoCategoria.outro,
              fileBytes: file.bytes!,
              fileName: file.name,
              mimeType: _getMimeType(file.extension ?? ''),
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Documento enviado para aprovação!')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
        }
      }
    }
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'doc':
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default: return 'application/octet-stream';
    }
  }
}

class _DocumentoCard extends ConsumerWidget {
  final RhDocumento doc;
  final String funcionarioId;

  const _DocumentoCard({required this.doc, required this.funcionarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.description_outlined,
              color: context.statusTokens.color(doc.status.role),
              size: 32,
            ),
            title: Text(doc.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categoria: ${doc.categoria.name.toUpperCase()}'),
                Text('Status: ${doc.status.label}'),
                if (doc.dataVencimento != null)
                  Text('Vence em: ${DateFormat('dd/MM/yyyy').format(doc.dataVencimento!)}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                try {
                  final url = await ref.read(rhDocumentoRepositoryProvider).getSignedUrl(doc.storagePath);
                  if (await canLaunchUrl(Uri.parse(url))) {
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao baixar: ${friendlyError(e)}')));
                  }
                }
              },
            ),
          ),
          // RH-24 — aceite eletrônico exigido pelo RH.
          if (doc.exigeAceite)
            _AceiteBar(doc: doc, funcionarioId: funcionarioId),
        ],
      ),
    );
  }

}

/// Faixa de aceite do documento: pendente vira ação, aceito vira recibo.
class _AceiteBar extends ConsumerStatefulWidget {
  const _AceiteBar({required this.doc, required this.funcionarioId});

  final RhDocumento doc;
  final String funcionarioId;

  @override
  ConsumerState<_AceiteBar> createState() => _AceiteBarState();
}

class _AceiteBarState extends ConsumerState<_AceiteBar> {
  bool _enviando = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    final doc = widget.doc;
    final pendente = doc.aceitePendente;
    final cor = pendente ? tokens.warning : tokens.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(pendente ? Icons.assignment_late : Icons.verified_user,
              size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pendente
                  ? 'Este documento precisa da sua ciência.'
                  : 'Ciência registrada em '
                      '${DateFormat('dd/MM/yyyy \'às\' HH:mm').format(doc.aceitoEm!.toLocal())}.',
              style: TextStyle(fontSize: 12.5, color: cor),
            ),
          ),
          if (pendente) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _enviando ? null : _confirmar,
              child: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Declarar ciência'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmar() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Declarar ciência?'),
        content: Text(
          'Você confirma que leu e está ciente do documento '
          '"${widget.doc.titulo}".\n\n'
          'A data, a hora e a origem do aceite ficam registradas.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviando = true);
    try {
      await ref
          .read(rhDocumentoRepositoryProvider)
          .aceitarDocumento(widget.doc.id);
      ref.invalidate(rhDocumentosPorFuncionarioProvider(widget.funcionarioId));
      messenger.showSnackBar(
          const SnackBar(content: Text('Ciência registrada.')));
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível registrar: ${friendlyError(e)}')));
    }
  }
}
