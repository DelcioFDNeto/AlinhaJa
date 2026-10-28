-- Migration: RBAC para Ausencias
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('rh_ausencias', 'view', 'Pode visualizar solicitações de ausências e férias'),
  ('rh_ausencias', 'manage', 'Pode aprovar e rejeitar solicitações de ausências e férias')
ON CONFLICT (module, action) DO NOTHING;

INSERT INTO public.rbac_role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.rbac_roles r
CROSS JOIN public.rbac_permissions p
WHERE r.name = 'Super Admin' AND p.module = 'rh_ausencias'
ON CONFLICT DO NOTHING;

UPDATE public.organizations
SET settings = jsonb_set(
      settings,
      '{modules}',
      (settings->'modules') || '["rh_ausencias"]'::jsonb
    )
WHERE settings->'modules' IS NOT NULL
  AND NOT (settings->'modules' @> '["rh_ausencias"]'::jsonb)
  AND (settings->'modules' @> '["rh_funcionarios"]'::jsonb);
