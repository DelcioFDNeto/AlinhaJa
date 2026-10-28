import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/providers/vacancy_provider.dart';
import 'package:alinha_ja/features/hr/ui/vacancy_form_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/careers_link_panel.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-10 / Fase 2 — Aba Vagas da Central de Recrutamento:
/// CRUD de vagas publicáveis, transições de status, contadores de
/// candidatos e compartilhamento de link/QR por vaga.
class VacanciesTab extends ConsumerWidget {
  const VacanciesTab({super.key, required this.onVerCandidatos});

  /// Chamado ao tocar em "ver candidatos": o pai (Central) aplica o
  /// filtro por vaga no pipeline e troca de aba.
  final void Function(VagaModel vaga) onVerCandidatos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vagasAsync = ref.watch(vagasProvider);

    return vagasAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro ao carregar as vagas.\n${friendlyError(e)}',
              textAlign: TextAlign.center),
        ),
      ),
      data: (vagas) {
        if (vagas.isEmpty) {
          return HrEmptyState(
            icone: Icons.work_outline,
            titulo: 'Nenhuma vaga cadastrada',
            descricao:
                'A aba Vagas é o anúncio de cada posição aberta. Toda vaga '
                'com status "aberta" vira uma página pública de carreiras, e '
                'quem se candidata por ali cai direto no Banco de Talentos.',
            passos: const [
              'Crie a vaga com título, área, cargo e nível.',
              'Publique: o status "aberta" libera a vaga na página de '
                  'carreiras e gera o link para compartilhar.',
              'Acompanhe os candidatos pelo botão "ver candidatos" do card '
                  'da vaga — eles entram no funil do Banco de Talentos.',
            ],
            acaoLabel: 'Criar primeira vaga',
            acaoIcone: Icons.add,
            onAcao: () => _criarVaga(context, ref),
            estrutura: const HrGhostList(
              comAvatar: false,
              colunas: ['Vaga', 'Nível', 'Candidatos'],
            ),
            nota: 'Sem vaga cadastrada, a página de carreiras da empresa fica '
                'no ar mas sem nenhuma posição para receber currículo.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(vagasProvider),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: vagas.length,
            itemBuilder: (context, i) => _VagaCard(
              vaga: vagas[i],
              onVerCandidatos: () => onVerCandidatos(vagas[i]),
            ),
          ),
        );
      },
    );
  }

  /// Abre o formulário de criação a partir do estado vazio.
  ///
  /// A aba não tem FAB próprio (ele mora na Central de Recrutamento), então
  /// sem este atalho o passo 1 do texto não teria onde ser executado.
  static Future<void> _criarVaga(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const VacancyFormSheet(),
    );
    if (saved == true) ref.invalidate(vagasProvider);
  }
}

class _VagaCard extends ConsumerWidget {
  const _VagaCard({required this.vaga, required this.onVerCandidatos});

  final VagaModel vaga;
  final VoidCallback onVerCandidatos;

  static final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final statusColor = tokens.color(VagaStatus.role(vaga.status));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(context, ref),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(vaga.titulo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                              label: vaga.expirada &&
                                      vaga.status == VagaStatus.aberta
                                  ? 'Expirada'
                                  : VagaStatus.label(vaga.status),
                              role: vaga.expirada &&
                                      vaga.status == VagaStatus.aberta
                                  ? VagaStatus.role(VagaStatus.pausada)
                                  : VagaStatus.role(vaga.status)),
                          if (ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage'))))
                            _menu(context, ref),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if ((vaga.cargoNome ?? '').isNotEmpty)
                            _chip(theme, Icons.badge_outlined,
                                vaga.cargoNome!),
                          if ((vaga.areaNome ?? '').isNotEmpty)
                            _chip(theme, Icons.category_outlined,
                                vaga.areaNome!),
                          if ((vaga.nivel ?? '').isNotEmpty)
                            _chip(theme, Icons.stairs_outlined,
                                _nivelLabel(vaga.nivel!)),
                          if (vaga.remoto)
                            _chip(theme, Icons.laptop, 'Remoto')
                          else if ((vaga.localidade ?? '').isNotEmpty)
                            _chip(theme, Icons.place, vaga.localidade!),
                          if ((vaga.faixaSalarial ?? '').isNotEmpty)
                            _chip(theme, Icons.payments,
                                vaga.faixaSalarial!),
                          if (vaga.vagasQtd != null)
                            _chip(theme, Icons.tag,
                                '${vaga.vagasQtd} posição${vaga.vagasQtd! > 1 ? 'ões' : ''}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.groups,
                              size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 6),
                          Text(
                            '${vaga.candidatosTotal} candidato${vaga.candidatosTotal == 1 ? '' : 's'}'
                            '${vaga.candidatosEmProcesso > 0 ? ' · ${vaga.candidatosEmProcesso} em processo' : ''}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          if (vaga.expiraEm != null)
                            Text('Expira ${_dateFmt.format(vaga.expiraEm!)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: vaga.expirada
                                        ? tokens.danger
                                        : theme.colorScheme.outline)),
                        ],
                      ),
                      if (vaga.candidatosTotal > 0) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero),
                            onPressed: onVerCandidatos,
                            icon: const Icon(Icons.filter_alt, size: 16),
                            label: const Text('Ver candidatos no pipeline'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'editar':
            _edit(context, ref);
          case 'compartilhar':
            _share(context, ref);
          case 'excluir':
            _delete(context, ref);
          default:
            _setStatus(context, ref, v);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        for (final s in VagaStatus.transicoesDe(vaga.status))
          PopupMenuItem(
              value: s,
              child: Text(s == VagaStatus.aberta &&
                      vaga.status == VagaStatus.fechada
                  ? 'Reabrir'
                  : s == VagaStatus.aberta
                      ? 'Publicar (abrir)'
                      : 'Marcar como ${VagaStatus.label(s)}')),
        if (vaga.status == VagaStatus.aberta)
          const PopupMenuItem(
              value: 'compartilhar', child: Text('Compartilhar vaga')),
        const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VacancyFormSheet(vaga: vaga),
    );
    if (saved == true) ref.invalidate(vagasProvider);
  }

  Future<void> _setStatus(
      BuildContext context, WidgetRef ref, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(vacancyServiceProvider).setStatus(vaga.id, status);
      ref.invalidate(vagasProvider);
      messenger.showSnackBar(SnackBar(
          content:
              Text('${vaga.titulo} → ${VagaStatus.label(status)}')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível alterar: ${friendlyError(e)}')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir vaga?'),
        content: Text(
            'A vaga "${vaga.titulo}" sai das listagens e do portal. '
            'Os candidatos já vinculados permanecem no pipeline.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(vacancyServiceProvider).softDelete(vaga.id);
      ref.invalidate(vagasProvider);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível excluir: ${friendlyError(e)}')));
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    // Slug da org vem da mesma fonte do painel de Divulgação.
    final org = await ref.read(portalConfigProvider.future);
    final slug = (org['slug'] as String?) ?? '';
    final url =
        '${CareersLinkPanel.publicHost}/#/carreiras/$slug/vaga/${vaga.id}';
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(vaga.titulo,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Link da vaga copiado!')));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final text = Uri.encodeComponent(
                          'Vaga aberta: ${vaga.titulo} — candidate-se em $url');
                      launchUrl(Uri.parse('https://wa.me/?text=$text'),
                          mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _chip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  static String _nivelLabel(String nivel) {
    const labels = {
      'estagio': 'Estágio',
      'junior': 'Júnior',
      'pleno': 'Pleno',
      'senior': 'Sênior',
      'lideranca': 'Liderança/Gestão',
    };
    return labels[nivel] ?? nivel;
  }
}
