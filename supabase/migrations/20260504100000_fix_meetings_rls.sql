-- Migration: Correção de Segurança RLS para a tabela meetings
-- Objetivo: Impedir que usuários com o cargo 'member' criem reuniões, conforme especificado no RBAC.

-- 1. Remover a política antiga permissiva
DROP POLICY IF EXISTS "Users can create meetings" ON public.meetings;

-- 2. Criar a nova política com validação de cargo (role_level)
CREATE POLICY "Apenas cargos gerenciais podem criar reuniões" 
ON public.meetings FOR INSERT 
WITH CHECK (
  host_id = auth.uid() AND 
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin', 'manager', 'director', 'ti_admin')
  )
);
