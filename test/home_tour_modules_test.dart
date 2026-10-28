import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';

/// O tour guiado precisa passar por todo módulo que o RBAC libera. No mobile
/// cada módulo tem de ter um ponto de entrada visível: aba da barra inferior
/// (Comunicação), ícone no header (Helpdesk) ou o menu "Módulos" (o resto).
/// Antes, Financeiro e Admin não apareciam em lugar nenhum do celular.
void main() {
  test('menu mobile traz todo módulo de painel, menos o Helpdesk', () {
    final menu = mobileMenuModules(kModuleRegistry);

    expect(
      menu,
      kModuleRegistry
          .where((m) =>
              m.activation == ModuleActivation.rightPanel &&
              m.section != ModuleSection.helpdesk)
          .toList(),
    );
    expect(
      menu.map((m) => m.section).toSet(),
      containsAll(
          [ModuleSection.rh, ModuleSection.financeiro, ModuleSection.admin]),
    );
  });

  test('todo módulo do registro tem entrada no mobile', () {
    for (final m in kModuleRegistry) {
      final entrada = m.section == ModuleSection.comunicacao ||
          m.section == ModuleSection.helpdesk ||
          mobileMenuModules([m]).isNotEmpty;
      expect(entrada, isTrue, reason: '${m.id} sem entrada no mobile');
    }
  });

  test('menu mobile respeita o RBAC: só o que foi liberado', () {
    final liberados = kModuleRegistry
        .where((m) => m.id == 'rh_funcionarios' || m.id == 'fin_pagar')
        .toList();

    expect(mobileMenuModules(liberados).map((m) => m.id),
        ['rh_funcionarios', 'fin_pagar']);
  });

  test('todo módulo tem texto próprio no tour e seção com rótulo', () {
    for (final m in kModuleRegistry) {
      expect(m.tourHint, isNotNull, reason: '${m.id} sem tourHint');
      expect(moduleSectionLabel(m.section), isNotEmpty);
    }
  });
}
