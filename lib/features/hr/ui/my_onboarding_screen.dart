import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/onboarding_model.dart';
import 'package:alinha_ja/features/hr/providers/onboarding_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-25 / Fase 8 — Onboarding self-service.
///
/// O funcionário vinculado (F1.2) vê o próprio checklist e conclui os
/// itens que são responsabilidade dele. Itens de RH/gestor aparecem em
/// modo leitura, para ele saber o que falta e de quem depende.
class MyOnboardingScreen extends ConsumerWidget {
  const MyOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final execAsync = ref.watch(meuOnboardingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Onboarding')),
      body: execAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Aviso(
          icone: Icons.error_outline,
          titulo: 'Não foi possível carregar',
          texto: friendlyError(e),
        ),
        data: (exec) {
          if (exec == null) {
            return const _Aviso(
              icone: Icons.checklist,
              titulo: 'Nenhum onboarding em andamento',
              texto:
                  'Quando o RH iniciar o seu processo de integração, as etapas '
                  'aparecem aqui.',
            );
          }
          return _Checklist(execucao: exec);
        },
      ),
    );
  }
}

class _Checklist extends ConsumerWidget {
  const _Checklist({required this.execucao});

  final OnboardingExecucao execucao;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itensAsync = ref.watch(meusOnboardingItensProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(meuOnboardingProvider);
        await ref.read(meusOnboardingItensProvider.future);
      },
      child: itensAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Aviso(
          icone: Icons.error_outline,
          titulo: 'Não foi possível carregar as etapas',
          texto: friendlyError(e),
        ),
        data: (itens) {
          final meus = itens.where((i) => i.responsavel == 'funcionario').toList();
          final outros =
              itens.where((i) => i.responsavel != 'funcionario').toList();

          return HrContentColumn(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              children: [
                _Cabecalho(execucao: execucao, itens: itens),
                const SizedBox(height: 20),
                if (meus.isNotEmpty) ...[
                  const _TituloSecao(
                    titulo: 'Suas etapas',
                    subtitulo: 'Marque conforme for concluindo.',
                  ),
                  const SizedBox(height: 8),
                  for (final item in meus)
                    _ItemCard(item: item, editavel: true),
                ],
                if (outros.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _TituloSecao(
                    titulo: 'Etapas do RH e do gestor',
                    subtitulo: 'Acompanhamento — não exigem ação sua.',
                  ),
                  const SizedBox(height: 8),
                  for (final item in outros)
                    _ItemCard(item: item, editavel: false),
                ],
                if (itens.isEmpty)
                  const HrEmptyBlock(
                    icone: Icons.playlist_add_check,
                    titulo: 'Nenhuma etapa neste onboarding',
                    dica:
                        'O seu processo de integração foi iniciado, mas o '
                        'roteiro ainda não tem etapas. O RH monta a lista a '
                        'partir de um template — fale com quem cuida da sua '
                        'admissão.',
                    altura: 170,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Progresso geral + prazo previsto. Vira duas colunas quando há largura.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.execucao, required this.itens});

  final OnboardingExecucao execucao;
  final List<OnboardingItem> itens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final concluidos = itens.where((i) => i.concluido).length;
    final pendentesMeus = itens
        .where((i) => i.responsavel == 'funcionario' && !i.concluido)
        .length;
    final progresso = itens.isEmpty ? 0.0 : concluidos / itens.length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final resumo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(execucao.templateNome ?? 'Integração',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '$concluidos de ${itens.length} etapas concluídas',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 8,
                  ),
                ),
              ],
            );

            final avisos = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pendentesMeus > 0)
                  _Pilula(
                    icone: Icons.pending_actions,
                    cor: tokens.warning,
                    texto: pendentesMeus == 1
                        ? '1 etapa aguarda você'
                        : '$pendentesMeus etapas aguardam você',
                  )
                else
                  _Pilula(
                    icone: Icons.check_circle,
                    cor: tokens.success,
                    texto: 'Nenhuma etapa pendente sua',
                  ),
                if (execucao.dataPrevista != null) ...[
                  const SizedBox(height: 8),
                  _Pilula(
                    icone: Icons.event,
                    cor: theme.colorScheme.outline,
                    texto:
                        'Previsto para ${DateFormat('dd/MM/yyyy').format(execucao.dataPrevista!)}',
                  ),
                ],
              ],
            );

            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [resumo, const SizedBox(height: 16), avisos],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: resumo),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: avisos),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pilula extends StatelessWidget {
  const _Pilula({required this.icone, required this.cor, required this.texto});

  final IconData icone;
  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 16, color: cor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto,
              style: TextStyle(fontSize: 12.5, color: cor)),
        ),
      ],
    );
  }
}

class _TituloSecao extends StatelessWidget {
  const _TituloSecao({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        Text(subtitulo,
            style: TextStyle(fontSize: 12.5, color: theme.colorScheme.outline)),
      ],
    );
  }
}

class _ItemCard extends ConsumerStatefulWidget {
  const _ItemCard({required this.item, required this.editavel});

  final OnboardingItem item;

  /// Item do funcionário: pode marcar. Itens de RH/gestor são leitura.
  final bool editavel;

  @override
  ConsumerState<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends ConsumerState<_ItemCard> {
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final item = widget.item;
    final dispensado = item.status == 'nao_aplicavel';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: _salvando
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : widget.editavel && !dispensado
                      ? Checkbox(
                          value: item.concluido,
                          onChanged: (v) => _alternar(v ?? false),
                        )
                      : Icon(
                          dispensado
                              ? Icons.remove_circle_outline
                              : item.concluido
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                          color: dispensado
                              ? theme.colorScheme.outline
                              : item.concluido
                                  ? tokens.success
                                  : theme.colorScheme.outlineVariant,
                        ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    item.titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: item.concluido || dispensado
                          ? TextDecoration.lineThrough
                          : null,
                      color: dispensado ? theme.colorScheme.outline : null,
                    ),
                  ),
                  if ((item.descricao ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.descricao!,
                        style: TextStyle(
                            fontSize: 13, color: theme.colorScheme.outline)),
                  ],
                  const SizedBox(height: 8),
                  // Etiquetas quebram sozinhas em telas estreitas.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Etiqueta(
                        texto: OnboardingCategoria.label(item.categoria),
                        cor: theme.colorScheme.outline,
                      ),
                      if (!widget.editavel)
                        _Etiqueta(
                          texto:
                              'Responsável: ${OnboardingResponsavel.label(item.responsavel)}',
                          cor: theme.colorScheme.outline,
                        ),
                      if (item.obrigatorio)
                        _Etiqueta(texto: 'Obrigatório', cor: tokens.info),
                      if (item.prazo != null)
                        _Etiqueta(
                          texto: item.atrasado
                              ? 'Venceu em ${DateFormat('dd/MM').format(item.prazo!)}'
                              : 'Até ${DateFormat('dd/MM').format(item.prazo!)}',
                          cor: item.atrasado
                              ? tokens.danger
                              : theme.colorScheme.outline,
                        ),
                      if (dispensado)
                        _Etiqueta(
                            texto: 'Dispensado pelo RH',
                            cor: theme.colorScheme.outline),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _alternar(bool concluido) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _salvando = true);
    try {
      await ref.read(onboardingServiceProvider).concluirMeuItem(
            widget.item.id,
            concluido: concluido,
          );
      ref.invalidate(meuOnboardingProvider);
      ref.invalidate(meusOnboardingItensProvider);
    } catch (e) {
      if (mounted) setState(() => _salvando = false);
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Não foi possível atualizar: ${friendlyError(e)}')));
    }
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texto, style: TextStyle(fontSize: 11.5, color: cor)),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.texto,
  });

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: HrContentColumn(
        maxWidth: 460,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 64),
            Icon(icone, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(titulo,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
