import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/providers/absences_provider.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Meus Holerites (visão do colaborador): lista os próprios
/// recibos e abre o PDF (a visualização é carimbada — recibo de
/// leitura para o RH).
class MyPayslipsScreen extends ConsumerWidget {
  const MyPayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funcionarioId = ref.watch(myFuncionarioIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus Holerites')),
      body: funcionarioId.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (id) {
          if (id == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Seu usuário ainda não está vinculado a um funcionário.\n'
                  'Fale com o RH para acessar seus holerites.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _PayslipsList(funcionarioId: id);
        },
      ),
    );
  }
}

class _PayslipsList extends ConsumerWidget {
  const _PayslipsList({required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = HoleriteFilters(funcionarioId: funcionarioId);
    final holerites = ref.watch(holeritesProvider(filters));
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return holerites.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (list) {
        if (list.isEmpty) {
          return const HrEmptyState(
            icone: Icons.receipt_long,
            titulo: 'Nenhum holerite disponível',
            descricao:
                'Quando o RH publicar o seu holerite do mês, ele aparece '
                'aqui em PDF, pronto para abrir ou baixar.',
            passos: [
              'O RH emite o holerite por competência (mês/ano).',
              'Você recebe o aviso e abre o arquivo por esta tela.',
              'A abertura gera um recibo de leitura para o RH — não '
                  'precisa confirmar nada à parte.',
            ],
            nota: 'Não encontrou um holerite que deveria estar aqui? Fale '
                'com o RH: pode ser que a sua ficha ainda não esteja '
                'vinculada ao seu usuário.',
            estrutura: HrGhostList(
              comAvatar: false,
              colunas: ['Competência', 'Emitido em', 'Situação'],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final h = list[i];
            final visualizado = h.dataVisualizacao != null;
            return Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: Text(h.competencia,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Disponível desde ${fmt.format(h.dataDisponibilizacao.toLocal())}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusBadge(
                      label: visualizado ? 'Visualizado' : 'Novo',
                      role: visualizado
                          ? StatusRole.neutral
                          : StatusRole.highlight,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new, size: 18),
                  ],
                ),
                onTap: h.arquivoPdfPath == null
                    ? null
                    : () async {
                        final service =
                            ref.read(peopleManagementServiceProvider);
                        try {
                          final url = await service
                              .holeriteSignedUrl(h.arquivoPdfPath!);
                          await service.marcarHoleriteVisualizado(h.id);
                          ref.invalidate(holeritesProvider(filters));
                          await launchUrlString(url);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Erro ao abrir: ${friendlyError(e)}')));
                          }
                        }
                      },
              ),
            );
          },
        );
      },
    );
  }
}
