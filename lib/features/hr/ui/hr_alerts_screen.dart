import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/hr/providers/onboarding_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

class HrAlertsScreen extends ConsumerWidget {
  const HrAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alertasAsync = ref.watch(rhAlertasProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Painel de Alertas RH',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(rhAlertasProvider),
          ),
        ],
      ),
      body: ResponsiveWidthContainer(
        child: alertasAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Erro: ${friendlyError(err)}')),
          data: (alertas) {
            if (alertas.isEmpty) {
              // Vazio aqui é boa notícia, não falta de configuração: o
              // texto diz o que o painel vigia, para a tela em branco não
              // parecer um recurso que não funciona.
              return const HrEmptyState(
                icone: Icons.check_circle_outline,
                titulo: 'Nenhum alerta pendente',
                descricao:
                    'Está tudo em dia. Este painel avisa sozinho quando '
                    'alguma coisa precisa de atenção do RH.',
                passos: [
                  'Documento vencido ou perto do vencimento.',
                  'Contrato de experiência chegando ao fim.',
                  'Onboarding parado com etapa atrasada.',
                  'Férias com período aquisitivo vencendo.',
                ],
                nota: 'Os alertas aparecem sozinhos — não há nada para '
                    'cadastrar nesta tela.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alertas.length,
              itemBuilder: (context, index) {
                final alerta = alertas[index];
                final isAlerta = alerta.isAlerta;
                final tokens = context.statusTokens;
                final sev = isAlerta ? tokens.warning : tokens.info;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: alerta.lido
                      ? theme.colorScheme.surface
                      : sev.withValues(alpha: 0.1),
                  elevation: alerta.lido ? 0 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: alerta.lido
                          ? theme.colorScheme.outlineVariant
                          : sev.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isAlerta ? Icons.warning_amber_rounded : Icons.info_outline,
                      color: sev,
                    ),
                    title: Text(
                      alerta.titulo,
                      style: TextStyle(
                        fontWeight:
                            alerta.lido ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (alerta.mensagem != null) ...[
                          const SizedBox(height: 4),
                          Text(alerta.mensagem!),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${alerta.createdAt.day.toString().padLeft(2, '0')}/${alerta.createdAt.month.toString().padLeft(2, '0')}/${alerta.createdAt.year}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    trailing: alerta.lido
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () async {
                              await ref
                                  .read(onboardingServiceProvider)
                                  .marcarAlertaLido(alerta.id);
                              // ignore: unused_result
                              ref.refresh(rhAlertasProvider);
                            },
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
