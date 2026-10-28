import 'package:flutter/material.dart';

import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';

/// Estado vazio das telas de RH.
///
/// ## Por que existe
/// O módulo tem ~30 telas e quase todas nascem sem dado nenhum: empresa que
/// acabou de assinar não tem vaga, ciclo de avaliação, benefício nem holerite.
/// O que aparecia era uma frase solta ("Nenhuma vaga cadastrada") no meio de
/// uma tela branca — que informa que está vazio e não informa **o que a tela
/// faz**, **por que está vazia** nem **qual é o próximo passo**. Sem isso, a
/// pessoa fecha a tela e nunca descobre o recurso.
///
/// ## O que este componente mostra
/// 1. O nome e o propósito da função, em uma frase.
/// 2. Os passos concretos para sair do zero, numerados.
/// 3. O botão que executa o primeiro passo, quando existe um.
/// 4. Opcionalmente, o **esqueleto** da tela cheia ([estrutura]) — as colunas
///    da tabela, os cards do funil —, para a pessoa reconhecer o formato do
///    que vai aparecer ali.
///
/// ## Vazio por filtro é outra coisa
/// "Não existe nada" e "seu filtro não achou nada" pedem respostas diferentes:
/// no segundo caso o passo a passo de cadastro é ruído, e o que ajuda é
/// limpar o filtro. Use [HrEmptyState.semResultado] para esse caso.
class HrEmptyState extends StatelessWidget {
  const HrEmptyState({
    super.key,
    required this.icone,
    required this.titulo,
    required this.descricao,
    this.passos = const [],
    this.acaoLabel,
    this.acaoIcone,
    this.onAcao,
    this.acaoSecundariaLabel,
    this.onAcaoSecundaria,
    this.estrutura,
    this.nota,
  });

  /// Variante para busca/filtro sem resultado.
  ///
  /// Aqui o cadastro já existe — insistir em "crie o primeiro" mandaria a
  /// pessoa duplicar o registro que ela está justamente procurando.
  factory HrEmptyState.semResultado({
    Key? key,
    String titulo = 'Nenhum resultado para esta busca',
    String descricao =
        'Os registros existem, mas nenhum deles atende aos filtros atuais.',
    VoidCallback? onLimparFiltros,
    String? nota,
  }) {
    return HrEmptyState(
      key: key,
      icone: Icons.search_off,
      titulo: titulo,
      descricao: descricao,
      acaoLabel: onLimparFiltros == null ? null : 'Limpar filtros',
      acaoIcone: Icons.filter_alt_off,
      onAcao: onLimparFiltros,
      nota: nota,
    );
  }

  final IconData icone;
  final String titulo;

  /// Uma frase dizendo para que serve a tela — não "está vazio".
  final String descricao;

  /// Passo a passo para sair do zero. Vira lista numerada.
  final List<String> passos;

  final String? acaoLabel;
  final IconData? acaoIcone;
  final VoidCallback? onAcao;

  final String? acaoSecundariaLabel;
  final VoidCallback? onAcaoSecundaria;

  /// Esqueleto do que a tela mostra quando tem dado (ver [HrGhostList]).
  final Widget? estrutura;

  /// Observação de rodapé: pré-requisito, permissão que falta, aviso de RBAC.
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            vertical: constraints.isCompact ? 24 : 40,
          ),
          child: HrContentColumn(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone,
                        size: 32, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  descricao,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (passos.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _PassoAPasso(passos: passos),
                ],
                if (onAcao != null && acaoLabel != null) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton.icon(
                      onPressed: onAcao,
                      icon: Icon(acaoIcone ?? Icons.add, size: 18),
                      label: Text(acaoLabel!),
                    ),
                  ),
                ],
                if (onAcaoSecundaria != null &&
                    acaoSecundariaLabel != null) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: onAcaoSecundaria,
                      child: Text(acaoSecundariaLabel!),
                    ),
                  ),
                ],
                if (estrutura != null) ...[
                  const SizedBox(height: 24),
                  _RotuloEsqueleto(theme: theme),
                  const SizedBox(height: 10),
                  // O esqueleto é ilustração: deixá-lo clicável faria a
                  // pessoa tocar em linhas que não existem.
                  IgnorePointer(child: Opacity(opacity: 0.55, child: estrutura!)),
                ],
                if (nota != null) ...[
                  const SizedBox(height: 20),
                  _Nota(texto: nota!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RotuloEsqueleto extends StatelessWidget {
  const _RotuloEsqueleto({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.visibility_outlined,
            size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Text(
          'Prévia: é assim que a tela fica com dados',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// Passo a passo numerado.
class _PassoAPasso extends StatelessWidget {
  const _PassoAPasso({required this.passos});

  final List<String> passos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como começar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < passos.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    passos[i],
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 15, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

/// Esqueleto de uma lista/tabela, para o estado vazio mostrar o formato do
/// que vai aparecer ali.
///
/// Não é `shimmer`: shimmer significa "carregando, já vem". Aqui não vem nada
/// até alguém cadastrar, e a prévia é estática de propósito.
class HrGhostList extends StatelessWidget {
  const HrGhostList({
    super.key,
    this.linhas = 3,
    this.colunas = const ['Nome', 'Situação', 'Data'],
    this.comAvatar = true,
  });

  final int linhas;

  /// Cabeçalho da tabela — é o que ensina quais informações a tela guarda.
  final List<String> colunas;

  final bool comAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ghost = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
            child: Row(
              children: [
                if (comAvatar) const SizedBox(width: 34),
                for (var i = 0; i < colunas.length; i++)
                  Expanded(
                    flex: i == 0 ? 2 : 1,
                    child: Text(
                      colunas[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var linha = 0; linha < linhas; linha++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  if (comAvatar) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration:
                          BoxDecoration(color: ghost, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                  ],
                  for (var i = 0; i < colunas.length; i++)
                    Expanded(
                      flex: i == 0 ? 2 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          height: 9,
                          decoration: BoxDecoration(
                            color: ghost,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Esqueleto de um funil/quadro por colunas (pipeline de vagas, ciclos).
class HrGhostBoard extends StatelessWidget {
  const HrGhostBoard({
    super.key,
    required this.colunas,
    this.cartoesPorColuna = 2,
  });

  final List<String> colunas;
  final int cartoesPorColuna;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ghost = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final coluna in colunas)
            Container(
              width: 130,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coluna,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < cartoesPorColuna; i++)
                    Container(
                      height: 34,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ghost),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Estado vazio de um bloco pequeno (card de dashboard, gráfico, aba interna).
///
/// A versão completa ocupa uma tela; dentro de um card de 120px de altura ela
/// não caberia, e um card sem explicação nenhuma volta ao problema original.
class HrEmptyBlock extends StatelessWidget {
  const HrEmptyBlock({
    super.key,
    required this.icone,
    required this.titulo,
    this.dica,
    this.altura = 132,
    this.acaoLabel,
    this.onAcao,
  });

  final IconData icone;
  final String titulo;

  /// O que fazer para o bloco deixar de ficar vazio.
  final String? dica;

  final double altura;
  final String? acaoLabel;
  final VoidCallback? onAcao;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: altura,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 26, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (dica != null) ...[
                const SizedBox(height: 4),
                Text(
                  dica!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              if (onAcao != null && acaoLabel != null) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onAcao,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(acaoLabel!,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
