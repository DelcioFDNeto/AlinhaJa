import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/rbac/models/rbac_permission.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/rbac/services/rbac_repository.dart';

/// O app espelha a regra do banco (`fn_rh_pode`): `manage` implica `view`, e
/// admin comum tem tudo FORA do RH — o RH vem do perfil, como para qualquer
/// usuário. Antes o admin recebia todas as permissões e via menus de RH que o
/// banco, depois da unificação, negaria.
void main() {
  RbacPermission perm(String module, String action) => RbacPermission(
      id: '$module:$action', module: module, action: action);

  group('hasPermission', () {
    test('manage implica view', () {
      final perms = [perm('rh_holerites', 'manage')];
      expect(perms.hasPermission('rh_holerites', 'view'), isTrue);
      expect(perms.hasPermission('rh_holerites', 'manage'), isTrue);
    });

    test('view não implica manage', () {
      final perms = [perm('rh_holerites', 'view')];
      expect(perms.hasPermission('rh_holerites', 'manage'), isFalse);
    });

    test('permissão de um módulo não vale para outro', () {
      final perms = [perm('rh_ponto', 'manage')];
      expect(perms.hasPermission('rh_holerites', 'view'), isFalse);
    });

    test('outras ações não viram view', () {
      final perms = [perm('comunicacao_anuncios', 'create')];
      expect(perms.hasPermission('comunicacao_anuncios', 'view'), isFalse);
    });
  });

  group('adminEffectivePermissions', () {
    final all = [
      perm('admin_panel', 'manage'),
      perm('helpdesk', 'manage'),
      perm('rh_funcionarios', 'view'),
      perm('rh_funcionarios', 'manage'),
      perm('rh_holerites', 'manage'),
    ];

    test('sem perfil de RH, o admin não recebe nenhum módulo de RH', () {
      final eff = adminEffectivePermissions(all, const []);
      expect(eff.map((p) => p.module).toSet(), {'admin_panel', 'helpdesk'});
    });

    test('o RH do perfil soma ao resto, sem duplicar', () {
      final assigned = [perm('rh_holerites', 'manage'), perm('helpdesk', 'manage')];
      final eff = adminEffectivePermissions(all, assigned);
      expect(eff.map((p) => p.id).toSet(), {
        'admin_panel:manage',
        'helpdesk:manage',
        'rh_holerites:manage',
      });
      expect(eff.length, 3);
    });

    test('isHrModule reconhece só o prefixo rh_', () {
      expect(isHrModule('rh_ponto'), isTrue);
      expect(isHrModule('helpdesk'), isFalse);
      expect(isHrModule('admin_panel'), isFalse);
    });
  });
}
