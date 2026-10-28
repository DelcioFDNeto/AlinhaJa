-- ============================================================
-- Multi-tenant SaaS — Seed de módulos licenciáveis por empresa
-- Popula organizations.settings.modules para os tenants JÁ existentes
-- (ex.: DuBairro) que ainda não têm a chave configurada, para que a
-- introdução do gate de entitlement não esconda módulos que hoje já
-- estão em uso. Empresas novas são semeadas pelo app no cadastro.
--
-- Baseline (Comunicação/Admin) NÃO é gated e por isso não entra aqui.
-- A lista abaixo espelha os ids licenciáveis atuais de kModuleRegistry
-- (lib/core/modules/module_registry.dart).
-- Ref: 20260713100000_platform_owner.sql (platform_set_org_modules).
-- ============================================================

UPDATE public.organizations
   SET settings = jsonb_set(
         COALESCE(settings, '{}'::jsonb),
         '{modules}',
         '["rh_banco_talentos","rh_funcionarios","rh_documentos","rh_onboarding","rh_alertas","helpdesk"]'::jsonb,
         true)
 WHERE settings -> 'modules' IS NULL;
