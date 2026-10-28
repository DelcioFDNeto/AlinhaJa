import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/absence_model.dart';

/// RH-26 — cartão de saldo de um período aquisitivo de férias.
///
/// Usado nas duas pontas: na lista do RH (com o nome do funcionário) e
/// na tela do próprio funcionário (sem o nome, que seria redundante).
class FeriasSaldoCard extends StatelessWidget {
  const FeriasSaldoCard({
    super.key,
    required this.saldo,
    this.mostrarNome = false,
    this.onAbono,
  });

  final FeriasSaldo saldo;
  final bool mostrarNome;

  /// Ação de abono pecuniário — só o RH recebe.
  final VoidCallback? onAbono;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;

    final (corAviso, aviso) = saldo.vencido
        ? (tokens.danger, 'Prazo de gozo vencido em ${_data.format(saldo.limiteGozo)}')
        : saldo.venceEmBreve
            ? (tokens.warning, 'Vence em ${_data.format(saldo.limiteGozo)}')
            : (null, null);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mostrarNome) ...[
              Text(saldo.funcionarioNome,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
            ],
            Text(
              'Período ${_data.format(saldo.inicio)} — ${_data.format(saldo.fim)}',
              style: TextStyle(
                  fontSize: 12.5, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 14),
            // Os números quebram em duas linhas quando falta largura,
            // em vez de espremer ou estourar.
            LayoutBuilder(
              builder: (context, constraints) {
                final blocos = <Widget>[
                  _Numero(
                    valor: saldo.diasDisponiveis,
                    rotulo: 'disponíveis',
                    cor: saldo.diasDisponiveis > 0
                        ? tokens.success
                        : theme.colorScheme.outline,
                    destaque: true,
                  ),
                  _Numero(valor: saldo.diasGozados, rotulo: 'gozados'),
                  if (saldo.diasReservados > 0)
                    _Numero(
                        valor: saldo.diasReservados,
                        rotulo: 'aguardando',
                        cor: tokens.warning),
                  if (saldo.diasAbonados > 0)
                    _Numero(valor: saldo.diasAbonados, rotulo: 'abonados'),
                  _Numero(valor: saldo.diasDireito, rotulo: 'de direito'),
                ];
                return Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: blocos,
                );
              },
            ),
            if (aviso != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: corAviso),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(aviso,
                        style: TextStyle(fontSize: 12.5, color: corAviso)),
                  ),
                ],
              ),
            ],
            if (onAbono != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAbono,
                  icon: const Icon(Icons.paid_outlined, size: 18),
                  label: const Text('Abono pecuniário'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({
    required this.valor,
    required this.rotulo,
    this.cor,
    this.destaque = false,
  });

  final int valor;
  final String rotulo;
  final Color? cor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = cor ?? theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$valor',
          style: TextStyle(
            fontSize: destaque ? 26 : 20,
            fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
            color: c,
            height: 1.1,
          ),
        ),
        Text(rotulo,
            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline)),
      ],
    );
  }
}
