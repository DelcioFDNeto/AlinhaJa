import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/providers/avaliacao_provider.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/ui/convert_candidate_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/responsavel_picker.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-1.2 — Ficha completa do candidato.
class CandidateDetailScreen extends ConsumerWidget {
  const CandidateDetailScreen({super.key, required this.candidatoId});

  final String candidatoId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Candidato?'),
        content: const Text('Tem certeza que deseja excluir este candidato? Esta ação removerá o candidato das listagens.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      try {
        await ref.read(talentBankServiceProvider).softDelete(candidatoId);
        ref.invalidate(boardColumnProvider);
        ref.invalidate(talentListProvider);
        ref.invalidate(talentStatusCountsProvider);

        if (!context.mounted) return;
        messenger.showSnackBar(
            const SnackBar(content: Text('Candidato excluído com sucesso.')));
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/rh'); // Banco de Talentos
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Erro ao excluir: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(candidateDetailProvider(candidatoId));
    final canManage = ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha do Candidato'),
        actions: [
          if (canManage)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Excluir Candidato',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro ao carregar a ficha.\n${friendlyError(e)}',
                textAlign: TextAlign.center),
          ),
        ),
        data: (detail) => _DetailBody(detail: detail),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final CandidateDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = detail.candidato;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final canManage = ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));
    // Converter cria a ficha do funcionário: exige os dois módulos.
    final canConvert = canManage && ref.watch(rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));
    // Etapas da org (RH-14); labels/transições dirigidas por dados.
    final pipe =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Cabeçalho ────────────────────────────────────────
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage:
                  c.fotoUrl != null ? CachedNetworkImageProvider(c.fotoUrl!, maxWidth: 320) : null,
              child: c.fotoUrl == null
                  ? Text(c.initials, style: const TextStyle(fontSize: 24))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.nome, style: theme.textTheme.titleLarge),
                  if ((c.cargoPretendido ?? '').isNotEmpty)
                    Text(c.cargoPretendido!,
                        style: TextStyle(color: theme.colorScheme.outline)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(pipe.label(c.status)),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text(CandidateSource.label(c.fonte)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Vaga vinculada (RH-10) ────────────────────────────
        if (c.vagaId != null && (c.vagaTitulo ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
              ),
              child: ListTile(
                leading: Icon(Icons.work_outline,
                    color: theme.colorScheme.primary),
                title: Text(c.vagaTitulo!,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Vaga vinculada'),
                dense: true,
              ),
            ),
          ),

        // ── Responsável (RH-13) ───────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              leading: Icon(Icons.person_pin_circle_outlined,
                  color: theme.colorScheme.primary),
              title: Text((c.responsavelNome ?? '').isNotEmpty
                  ? c.responsavelNome!
                  : 'Sem responsável'),
              subtitle: const Text('Responsável pelo candidato'),
              trailing: !canManage
                  ? null
                  : TextButton(
                onPressed: () => _atribuirResponsavel(context, ref),
                child: Text((c.responsavelNome ?? '').isNotEmpty
                    ? 'Alterar'
                    : 'Atribuir'),
              ),
              dense: true,
            ),
          ),
        ),

        // Última etapa antes de "contratado" (no funil padrão, Aprovado).
        if (canConvert && pipe.prontoParaContratar(c.status))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: () => _convert(context, ref),
              icon: const Icon(Icons.how_to_reg_rounded),
              label: const Text('Contratar (converter em funcionário)'),
            ),
          ),

        // ── Mudança de status (transições permitidas) ────────
        if (pipe.transicoesDe(c.status).isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final s in pipe.transicoesDe(c.status))
                ActionChip(
                  avatar: Icon(
                    s == pipe.descartado.slug
                        ? Icons.block_rounded
                        : Icons.arrow_forward_rounded,
                    size: 16,
                  ),
                  label: Text(pipe.label(s)),
                  onPressed: () => _changeStatus(context, ref, s),
                ),
            ],
          ),
        const Divider(height: 32),

        // ── Contato ──────────────────────────────────────────
        _Section(
          title: 'Contato',
          child: Column(
            children: [
              _InfoRow(icon: Icons.mail_outline_rounded, value: c.email),
              if ((c.telefone ?? '').isNotEmpty)
                _InfoRow(icon: Icons.phone_outlined, value: c.telefone!),
              if (c.localidade.isNotEmpty)
                _InfoRow(
                    icon: Icons.location_on_outlined, value: c.localidade),
              if ((c.nivel ?? '').isNotEmpty)
                _InfoRow(icon: Icons.stairs_outlined, value: 'Nível: ${c.nivel}'),
              if ((c.areaInteresse ?? '').isNotEmpty)
                _InfoRow(
                    icon: Icons.interests_outlined,
                    value: 'Área: ${c.areaInteresse}'),
            ],
          ),
        ),

        // ── Avaliação técnica (RH-12) ────────────────────────
        _AvaliacoesSection(candidatoId: c.id),

        // ── Análise da IA ────────────────────────────────────
        if (c.resumoExecutivo != null || c.scoreCompletude != null)
          _Section(
            title: 'Análise da IA',
            trailing: c.scoreCompletude != null
                ? Chip(
                    label: Text('Score ${c.scoreCompletude}/100'),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.resumoExecutivo ?? 'Sem resumo gerado.'),
                // Extração bem-sucedida também precisa poder ser refeita: o
                // erro caro não é a que falha (o RH vê e preenche à mão), é a
                // que "deu certo" com dado errado. Sem este botão, corrigir
                // uma ficha assim exigia editar tudo na mão.
                if (detail.curriculos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reprocessar currículo'),
                      onPressed: () => _retryExtraction(
                          context, ref, detail.curriculos.first.id),
                    ),
                  ),
              ],
            ),
          )
        else if (c.extracao == 'pendente' || c.extracao == 'falhou')
          _Section(
            title: 'Análise da IA',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.extracao == 'falhou'
                      ? 'A extração automática falhou — preencha os dados manualmente.'
                      : 'Currículo aguardando processamento pela IA.',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
                if (c.extracao == 'falhou')
                  _ExtractionErrorHint(candidatoId: c.id),
                if (canManage &&
                    c.extracao == 'falhou' &&
                    detail.curriculos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar extração novamente'),
                      onPressed: () => _retryExtraction(context, ref, detail.curriculos.first.id),
                    ),
                  ),
              ],
            ),
          ),

        // ── Habilidades ──────────────────────────────────────
        if (detail.habilidades.isNotEmpty)
          _Section(
            title: 'Habilidades',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in detail.habilidades)
                  Chip(
                    label: Text(h.nome),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),

        // ── Experiências ─────────────────────────────────────
        if (detail.experiencias.isNotEmpty)
          _Section(
            title: 'Experiência profissional',
            child: Column(
              children: [
                for (final e in detail.experiencias)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.work_outline_rounded),
                    title: Text(e.cargo ?? 'Cargo não informado'),
                    subtitle: Text([
                      if ((e.empresa ?? '').isNotEmpty) e.empresa!,
                      if (e.dataInicio != null)
                        '${DateFormat('MM/yyyy').format(e.dataInicio!)} — '
                            '${e.dataFim != null ? DateFormat('MM/yyyy').format(e.dataFim!) : 'atual'}',
                    ].join(' · ')),
                  ),
              ],
            ),
          ),

        // ── Formação ─────────────────────────────────────────
        if (detail.formacoes.isNotEmpty)
          _Section(
            title: 'Formação',
            child: Column(
              children: [
                for (final f in detail.formacoes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school_outlined),
                    title: Text(f.curso ?? 'Curso não informado'),
                    subtitle: Text([
                      if ((f.instituicao ?? '').isNotEmpty) f.instituicao!,
                      if (f.anoFim != null) 'Conclusão: ${f.anoFim}',
                    ].join(' · ')),
                  ),
              ],
            ),
          ),

        // ── Currículos ───────────────────────────────────────
        if (detail.curriculos.isNotEmpty)
          _Section(
            title: 'Currículo',
            child: Column(
              children: [
                for (final cv in detail.curriculos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(cv.tipoArquivo == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.description_outlined),
                    title: Text(
                        'Currículo (${cv.tipoArquivo.toUpperCase()}, '
                        '${(cv.tamanhoBytes / 1024).toStringAsFixed(0)} KB)'),
                    subtitle:
                        Text('Enviado em ${dateFmt.format(cv.createdAt.toLocal())}'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _openResume(ref, cv.arquivoUrl),
                  ),
              ],
            ),
          ),

        // ── Mensagens com o candidato (RH-2.8) ───────────────
        _Section(
          title: 'Mensagens com o candidato',
          child: _MessagesPanel(candidatoId: c.id),
        ),

        // ── Histórico ────────────────────────────────────────
        Builder(
          builder: (context) {
            final combinedHistory = <dynamic>[
              ...detail.historico,
              ...detail.emails,
            ];
            combinedHistory.sort((a, b) {
              final d1 = a is CandidateHistoryEntry ? a.createdAt : (a as CandidateEmailLog).enviadoEm;
              final d2 = b is CandidateHistoryEntry ? b.createdAt : (b as CandidateEmailLog).enviadoEm;
              return d2.compareTo(d1);
            });

            return _Section(
              title: 'Histórico',
              child: Column(
                children: [
                  _CommentField(candidatoId: c.id),
                  const SizedBox(height: 8),
                  if (combinedHistory.isEmpty)
                    Text('Sem eventos registrados.',
                        style: TextStyle(color: theme.colorScheme.outline)),
                  for (final item in combinedHistory)
                    if (item is CandidateHistoryEntry)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          item.acao == 'comentario'
                              ? Icons.chat_bubble_outline_rounded
                              : Icons.timeline_rounded,
                          size: 20,
                        ),
                        title: Text(item.descricao),
                        subtitle: Text([
                          if (item.usuarioNome != null) item.usuarioNome!,
                          dateFmt.format(item.createdAt.toLocal()),
                        ].join(' · ')),
                      )
                    else if (item is CandidateEmailLog)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          item.status == 'erro' ? Icons.error_outline : Icons.mark_email_read_outlined,
                          color: item.status == 'erro' ? Colors.red : null,
                          size: 20,
                        ),
                        title: Text('E-mail enviado: ${item.assunto ?? "Sem assunto"}'),
                        subtitle: Text([
                          'Automação',
                          dateFmt.format(item.enviadoEm.toLocal()),
                          if (item.status == 'erro') 'Erro: ${item.erroDetalhe}'
                        ].join(' · ')),
                      ),
                ],
              ),
            );
          }
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final funcionarioId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConvertCandidateSheet(candidato: detail.candidato),
    );
    if (funcionarioId == null) return;
    ref.invalidate(candidateDetailProvider(detail.candidato.id));
    ref.invalidate(talentListProvider);
    ref.invalidate(talentStatusCountsProvider);
    if (context.mounted) {
      context.push('/rh/funcionario/$funcionarioId');
    }
  }

  Future<void> _atribuirResponsavel(
      BuildContext context, WidgetRef ref) async {
    final userId = await ResponsavelPicker.show(context);
    if (userId == null) return; // cancelado
    try {
      await ref.read(talentBankServiceProvider).atribuirResponsavel(
          [detail.candidato.id], userId.isEmpty ? null : userId);
      ref.invalidate(candidateDetailProvider(detail.candidato.id));
      ref.invalidate(talentListProvider);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível atribuir: ${friendlyError(e)}');
    }
  }

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, String status) async {
    final pipe =
        ref.read(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterar status'),
        content: Text('Mover o candidato para "${pipe.label(status)}"?'),
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
    if (confirmed != true) return;

    try {
      await ref
          .read(talentBankServiceProvider)
          .updateStatus(detail.candidato.id, status);
      ref.invalidate(candidateDetailProvider(detail.candidato.id));
      ref.invalidate(talentListProvider);
      ref.invalidate(talentStatusCountsProvider);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível alterar o status: ${friendlyError(e)}');
    }
  }

  Future<void> _openResume(WidgetRef ref, String path) async {
    try {
      final url =
          await ref.read(talentBankServiceProvider).signedResumeUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível abrir o currículo: ${friendlyError(e)}');
    }
  }

  Future<void> _retryExtraction(
      BuildContext context, WidgetRef ref, String curriculoId) async {
    try {
      await ref.read(talentBankServiceProvider).retryExtraction(curriculoId);
      ref.invalidate(candidateDetailProvider(detail.candidato.id));
      ref.invalidate(candidateExtractionErrorProvider(detail.candidato.id));
      Globals.showSuccessSnackBar('Reprocessamento iniciado. Aguarde...');
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível reenfileirar: ${friendlyError(e)}');
    }
  }
}

/// Mostra o motivo real da última falha de extração (lido de ia_usage_log),
/// traduzido para uma mensagem acionável. Visível só para quem a RLS permite.
class _ExtractionErrorHint extends ConsumerWidget {
  const _ExtractionErrorHint({required this.candidatoId});

  final String candidatoId;

  static String _humanize(String erro) {
    if (erro.startsWith('missing_api_key')) {
      return 'Motivo: a organização não possui chave de IA configurada. '
          'Configure em Dashboard Administrativo → Chaves de IA — '
          'tentar novamente não resolve sem a chave.';
    }
    if (erro.contains('texto extraído insuficiente')) {
      return 'Motivo: o arquivo parece ser escaneado/imagem, sem texto '
          'extraível. Peça um PDF gerado digitalmente ou preencha manualmente.';
    }
    return 'Motivo técnico: $erro';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final errorAsync = ref.watch(candidateExtractionErrorProvider(candidatoId));
    final erro = errorAsync.valueOrNull;
    if (erro == null || erro.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _humanize(erro),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resultados de avaliação técnica do candidato (RH-12). Só aparece
/// quando há ao menos uma avaliação registrada.
class _AvaliacoesSection extends ConsumerWidget {
  const _AvaliacoesSection({required this.candidatoId});

  final String candidatoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(avaliacoesCandidatoProvider(candidatoId));
    final avals = async.valueOrNull ?? const [];
    final finalizadas = avals.where((a) => a.status == 'finalizada').toList();
    if (finalizadas.isEmpty) return const SizedBox.shrink();

    final tokens = context.statusTokens;
    return _Section(
      title: 'Avaliação técnica',
      child: Column(
        children: [
          for (final a in finalizadas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.quiz_outlined, color: tokens.info),
              title: Text('${a.acertos ?? 0}/${a.totalQuestoes} acertos'),
              subtitle: (a.vagaTitulo ?? '').isNotEmpty
                  ? Text(a.vagaTitulo!)
                  : (a.nivel ?? '').isNotEmpty
                      ? Text('Nível: ${a.nivel}')
                      : null,
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ((a.nota ?? 0) >= 60 ? tokens.success : tokens.warning)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${a.nota ?? 0}/100',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            (a.nota ?? 0) >= 60 ? tokens.success : tokens.warning)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MessagesPanel extends ConsumerStatefulWidget {
  const _MessagesPanel({required this.candidatoId});

  final String candidatoId;

  @override
  ConsumerState<_MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends ConsumerState<_MessagesPanel> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(talentBankServiceProvider)
          .sendMessageToCandidate(widget.candidatoId, texto);
      _controller.clear();
      ref.invalidate(candidateMessagesProvider(widget.candidatoId));
    } catch (e) {
      Globals.showErrorSnackBar('Erro ao enviar mensagem: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachment(String path) async {
    try {
      final url =
          await ref.read(talentBankServiceProvider).signedDocumentUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível abrir o anexo: ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messagesAsync =
        ref.watch(candidateMessagesProvider(widget.candidatoId));
    final dateFmt = DateFormat('dd/MM HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        messagesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Erro ao carregar mensagens: ${friendlyError(e)}',
              style: TextStyle(color: theme.colorScheme.error)),
          data: (mensagens) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mensagens.isEmpty)
                const HrEmptyBlock(
                  icone: Icons.forum_outlined,
                  titulo: 'Nenhuma mensagem trocada',
                  dica:
                      'Use o campo abaixo para falar com o candidato sem sair '
                      'do sistema: ele lê a mensagem no portal e recebe um '
                      'aviso por e-mail. Tudo fica no histórico da ficha.',
                  altura: 140,
                ),
              for (final m in mensagens)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    m['autor'] == 'rh'
                        ? Icons.support_agent_rounded
                        : Icons.person_outline_rounded,
                    size: 20,
                  ),
                  title: Text((m['texto'] as String?) ?? ''),
                  subtitle: Text([
                    m['autor'] == 'rh' ? 'RH' : 'Candidato',
                    dateFmt.format(
                        DateTime.parse(m['created_at'] as String).toLocal()),
                  ].join(' · ')),
                  trailing: m['anexo_url'] != null
                      ? IconButton(
                          icon: const Icon(Icons.attach_file_rounded),
                          tooltip: m['anexo_nome'] as String? ?? 'Anexo',
                          onPressed: () =>
                              _openAttachment(m['anexo_url'] as String),
                        )
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            hintText: 'Enviar mensagem ao candidato…',
            isDense: true,
            suffixIcon: IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              onPressed: _send,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentField extends ConsumerStatefulWidget {
  const _CommentField({required this.candidatoId});

  final String candidatoId;

  @override
  ConsumerState<_CommentField> createState() => _CommentFieldState();
}

class _CommentFieldState extends ConsumerState<_CommentField> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(talentBankServiceProvider)
          .addComment(widget.candidatoId, texto);
      _controller.clear();
      ref.invalidate(candidateDetailProvider(widget.candidatoId));
    } catch (e) {
      Globals.showErrorSnackBar('Erro ao registrar comentário: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _send(),
      decoration: InputDecoration(
        hintText: 'Adicionar comentário…',
        isDense: true,
        suffixIcon: IconButton(
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          onPressed: _send,
        ),
      ),
    );
  }
}
