import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/hr/providers/onboarding_provider.dart';
import 'package:alinha_ja/features/hr/ui/onboarding_template_form_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

class OnboardingTemplatesScreen extends ConsumerWidget {
  const OnboardingTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(onboardingTemplatesProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_onboarding', action: 'manage')));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Templates de Onboarding',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: ResponsiveWidthContainer(
        child: templatesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Erro: ${friendlyError(err)}')),
          data: (templates) {
            if (templates.isEmpty) {
              return HrEmptyState(
                icone: Icons.checklist,
                titulo: 'Nenhum template de onboarding',
                descricao:
                    'Um template é o roteiro de integração: a lista de '
                    'etapas que toda pessoa nova precisa cumprir (entregar '
                    'documentos, assinar contrato, receber cracha, fazer os '
                    'treinamentos). Ele é aplicado a cada admissão.',
                passos: const [
                  'Crie o template com um nome (ex.: "Admissão — Loja").',
                  'Liste as etapas na ordem em que devem acontecer, com o '
                      'responsável e o prazo de cada uma.',
                  'Marque um deles como padrão: ele passa a ser aplicado '
                      'automaticamente em toda admissão.',
                  'Acompanhe o andamento pela ficha do funcionário.',
                ],
                acaoLabel: 'Criar primeiro template',
                acaoIcone: Icons.add,
                onAcao: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const OnboardingTemplateFormSheet(),
                  ).then((_) {
                    // ignore: unused_result
                    ref.refresh(onboardingTemplatesProvider);
                  });
                },
                estrutura: const HrGhostList(
                  comAvatar: false,
                  colunas: ['Template', 'Etapas', 'Padrão'],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final tpl = templates[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tpl.nome,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (tpl.padrao)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Padrão',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                        '${tpl.itensCount} itens${tpl.descricao != null ? '\n${tpl.descricao}' : ''}'),
                    isThreeLine: tpl.descricao != null,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: !canManage
                        ? null
                        : () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => OnboardingTemplateFormSheet(
                          templateId: tpl.id,
                        ),
                      ).then((_) {
                        // ignore: unused_result
                        ref.refresh(onboardingTemplatesProvider);
                      });
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const OnboardingTemplateFormSheet(),
          ).then((_) {
            // ignore: unused_result
            ref.refresh(onboardingTemplatesProvider);
          });
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo Template'),
      ),
    );
  }
}
