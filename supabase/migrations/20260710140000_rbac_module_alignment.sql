-- ==============================================================================
-- Migration: 20260710140000_rbac_module_alignment.sql
-- Description: Alinha o vocabulário de módulos do RBAC ao registro de módulos
--              do app (lib/core/modules/module_registry.dart). Apenas semeia
--              permissões faltantes — não altera schema.
--
-- Contexto: a fatiação do app em módulos usa `rbac_permissions.module` como
-- fonte de verdade. Os módulos de Workflow e Localização ainda dependiam de
-- checagens por peso de role (AppPermissions); esta migração torna-os
-- permissões RBAC atribuíveis, deixando o banco 1:1 com o registro.
-- ==============================================================================

INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('workflow', 'view',   'Pode visualizar quadros e cards de workflow'),
  ('workflow', 'manage', 'Pode operar cards (assumir, mover, finalizar) e gerenciar workflow'),

  ('location', 'view',   'Pode visualizar o rastreamento de localização da equipe'),
  ('location', 'manage', 'Pode configurar e administrar o rastreamento de localização')
ON CONFLICT (module, action) DO NOTHING;

-- Vincula as novas permissões a todos os perfis "Super Admin" já existentes,
-- para que administradores não fiquem sem acesso após o seed (espelha a
-- lógica de fn_setup_default_roles).
INSERT INTO public.rbac_role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.rbac_roles r
CROSS JOIN public.rbac_permissions p
WHERE r.name = 'Super Admin'
  AND r.is_system = true
  AND p.module IN ('workflow', 'location')
ON CONFLICT DO NOTHING;
