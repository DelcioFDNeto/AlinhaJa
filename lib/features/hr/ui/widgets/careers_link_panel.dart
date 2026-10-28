import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_stat_pill.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// F1.1 — Painel de Divulgação da Central de Recrutamento.
/// Link público + QR da página /carreiras/:slug, compartilhamento
/// (WhatsApp/e-mail), toggle de página ativa, textos da mini-landing
/// e métricas de inscrição via portal.
class CareersLinkPanel extends ConsumerWidget {
  const CareersLinkPanel({super.key});

  /// Host público da página de carreiras (ver [AppEnv.appBaseUrl]).
  /// Público para reuso no compartilhamento por vaga (RH-10).
  static String get publicHost => AppEnv.appBaseUrl;

  static String get _host => publicHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(portalConfigProvider);

    return config.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro ao carregar a divulgação.\n${friendlyError(e)}',
              textAlign: TextAlign.center),
        ),
      ),
      data: (org) => _PanelBody(org: org, host: _host),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({required this.org, required this.host});

  final Map<String, dynamic> org;
  final String host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final isAdmin = ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));

    final slug = (org['slug'] as String?) ?? '';
    final ativo = org['carreiras_ativo'] != false;
    final headline = (org['carreiras_headline'] as String?)?.trim() ?? '';
    final sobre = (org['carreiras_sobre'] as String?)?.trim() ?? '';
    final url = '$host/#/carreiras/$slug';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(portalConfigProvider);
        ref.invalidate(metricasDivulgacaoProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _MetricsRow(),
          const SizedBox(height: 16),

          // ── Estado da página ────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              secondary: Icon(
                ativo ? Icons.public : Icons.public_off,
                color: ativo ? tokens.success : tokens.danger,
              ),
              title: Text(
                  ativo ? 'Página de carreiras ativa' : 'Inscrições pausadas'),
              subtitle: Text(
                ativo
                    ? 'Candidatos podem se inscrever pelo link público.'
                    : 'A página continua no ar, mas novas candidaturas são recusadas.',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
              value: ativo,
              onChanged:
                  isAdmin ? (v) => _setAtivo(context, ref, v) : null,
            ),
          ),
          const SizedBox(height: 16),

          // ── Link público + ações ────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Link de inscrição',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Divulgue este endereço em redes sociais, WhatsApp ou material impresso.',
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(url,
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _copy(context, url),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar link'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _shareWhatsApp(url),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _shareEmail(url),
                        icon: const Icon(Icons.mail, size: 18),
                        label: const Text('E-mail'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(url),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Abrir página'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── QR code ─────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 110,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('QR code da página',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'Ideal para cartazes e material impresso — o candidato aponta a câmera e cai direto no formulário.',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _expandQr(context, url),
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('Expandir'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Mini-landing (headline + sobre) ─────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Texto da página',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      if (isAdmin)
                        TextButton.icon(
                          onPressed: () =>
                              _editTexts(context, ref, headline, sobre),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Editar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _TextPreview(
                      label: 'Chamada',
                      value: headline,
                      placeholder: 'Ex.: "Venha fazer parte do nosso time!"'),
                  const SizedBox(height: 8),
                  _TextPreview(
                      label: 'Sobre a empresa',
                      value: sobre,
                      placeholder:
                          'Apresente a empresa aos candidatos em poucas linhas.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _setAtivo(BuildContext context, WidgetRef ref, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(talentBankServiceProvider)
          .setCarreirasConfig(ativo: v);
      ref.invalidate(portalConfigProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(v
              ? 'Página de carreiras reativada.'
              : 'Inscrições pausadas — a página recusará novas candidaturas.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível alterar: ${friendlyError(e)}')));
    }
  }

  Future<void> _editTexts(BuildContext context, WidgetRef ref,
      String headline, String sobre) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditTextsSheet(headline: headline, sobre: sobre),
    );
    if (saved == true) ref.invalidate(portalConfigProvider);
  }

  void _copy(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copiado!')));
  }

  Future<void> _shareWhatsApp(String url) async {
    final text = Uri.encodeComponent(
        'Estamos contratando! Candidate-se pelo link: $url');
    await launchUrl(Uri.parse('https://wa.me/?text=$text'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _shareEmail(String url) async {
    final subject = Uri.encodeComponent('Trabalhe conosco');
    final body = Uri.encodeComponent(
        'Estamos contratando! Candidate-se pelo link: $url');
    await launchUrl(Uri.parse('mailto:?subject=$subject&body=$body'));
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _expandQr(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 280,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Métricas de divulgação — inscrições via portal e conversão.
class _MetricsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final m = ref.watch(metricasDivulgacaoProvider).valueOrNull;
    if (m == null) return const SizedBox.shrink();

    final total = m['portal_total'] ?? 0;
    final emProcesso = m['portal_em_processo'] ?? 0;
    final conv = total > 0 ? ((emProcesso * 100) / total).round() : 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          HrStatPill(
              icon: Icons.public,
              label: 'Inscrições (30 dias)',
              value: '${m['portal_30d'] ?? 0}',
              color: tokens.highlight),
          HrStatPill(
              icon: Icons.groups,
              label: 'Total pelo portal',
              value: '$total',
              color: tokens.info),
          HrStatPill(
              icon: Icons.trending_up,
              label: 'Avançaram no funil',
              value: '$conv%',
              color: tokens.progress),
          HrStatPill(
              icon: Icons.verified,
              label: 'Contratados',
              value: '${m['portal_contratados'] ?? 0}',
              color: tokens.success),
        ],
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({
    required this.label,
    required this.value,
    required this.placeholder,
  });

  final String label;
  final String value;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = value.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.outline)),
        const SizedBox(height: 2),
        Text(
          empty ? placeholder : value,
          style: TextStyle(
            fontSize: 14,
            fontStyle: empty ? FontStyle.italic : FontStyle.normal,
            color: empty
                ? theme.colorScheme.outline
                : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Sheet de edição da chamada e do "sobre" da página de carreiras.
class _EditTextsSheet extends ConsumerStatefulWidget {
  const _EditTextsSheet({required this.headline, required this.sobre});

  final String headline;
  final String sobre;

  @override
  ConsumerState<_EditTextsSheet> createState() => _EditTextsSheetState();
}

class _EditTextsSheetState extends ConsumerState<_EditTextsSheet> {
  late final _headline = TextEditingController(text: widget.headline);
  late final _sobre = TextEditingController(text: widget.sobre);
  bool _saving = false;

  @override
  void dispose() {
    _headline.dispose();
    _sobre.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      // String vazia limpa o campo no banco (contrato da RPC).
      await ref.read(talentBankServiceProvider).setCarreirasConfig(
            headline: _headline.text.trim(),
            sobre: _sobre.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Texto da página de carreiras',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Aparece para o candidato em /carreiras.',
              style:
                  TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _headline,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Chamada',
              hintText: 'Venha fazer parte do nosso time!',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sobre,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Sobre a empresa',
              hintText: 'Quem somos, cultura, benefícios…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
