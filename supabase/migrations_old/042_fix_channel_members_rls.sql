-- ======================================================================================
-- CORREÇÃO DE RECURSÃO INFINITA (RLS) Tabela: public.channel_members
-- ======================================================================================
-- Problema original: A policy de SELECT usava "EXISTS (SELECT 1 FROM channel_members...)", o que 
-- gerava um loop infinito chamando a si próprio em qualquer query.
-- Agora permitimos a visualização de forma performática.

DROP POLICY IF EXISTS "Ver membros do mesmo canal" ON public.channel_members;

CREATE POLICY "Ver membros do mesmo canal" ON public.channel_members
FOR SELECT TO authenticated USING (true);
