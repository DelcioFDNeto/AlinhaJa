-- ============================================================================
-- VERIFICAÇÃO (somente leitura) — Dados da Shineray no banco DuBairro/AlinhaJá
-- Projeto Supabase alvo: gpeemngsxvqjflasdody (AlinhaJá / DuBairro)
-- NÃO altera nada. Rode antes e depois do script 02 para comparar.
-- ============================================================================

-- 1. Filiais da Shineray (semeadas pelas migrations 001/002/20260602)
--    e quantos usuários apontam para cada uma
SELECT 'FILIAL SHINERAY' AS tipo, b.name, COUNT(u.id) AS usuarios_vinculados
FROM public.branches b
LEFT JOIN public.users u ON u.branch_id = b.id
WHERE b.name IN (
  'Acará/PA','Ananindeua/PA','Barcarena/PA','Belém/PA','Bragança/PA',
  'Breves/PA','Cametá/PA','Capanema/PA','Capitão Poço/PA','Castanhal/PA',
  'Concórdia do Pará/PA','Curuçá/PA','Fortaleza (Aldeota)/CE','Icoaraci/PA',
  'Igarapé Miri/PA','Matriz','CD / Fábrica','Moju/PA','PDV Barcarena/PA',
  'PDV Paar/PA','São Miguel do Guamá/PA','Soure/PA','Tailândia/PA',
  'Tomé-Açu/PA','Matriz Corporativa','Matriz / CD'
)
GROUP BY b.name
ORDER BY b.name;

-- 2. Departamentos de concessionária (migration 013) e usuários vinculados
SELECT 'DEPTO CONCESSIONÁRIA' AS tipo, d.id, d.name, COUNT(u.id) AS usuarios_vinculados
FROM public.departments d
LEFT JOIN public.users u ON u.department_id = d.id
WHERE d.id IN ('comercial','pos_venda','oficina','logistica')
GROUP BY d.id, d.name
ORDER BY d.id;

-- 3. Cargos de concessionária (migration 013) e usuários vinculados
SELECT 'CARGO CONCESSIONÁRIA' AS tipo, j.id, j.name, COUNT(u.id) AS usuarios_vinculados
FROM public.job_positions j
LEFT JOIN public.users u ON u.job_position_id = j.id
WHERE j.id IN (
  'diretor','gerente_geral','gerente_loja','coordenador','lider_loja',
  'supervisor','analista','assistente','vendedor','mecanico','tecnico',
  'auxiliar','recepcionista','estoquista','faturista','motorista'
)
GROUP BY j.id, j.name
ORDER BY j.id;

-- 4. Canais/workspaces de concessionária (seeds 20260427152600 / 20260512*)
--    na tabela atual (channels) com contagem de cards e mensagens
SELECT 'CANAL CONCESSIONÁRIA (channels)' AS tipo, c.id, c.name,
       c.metadata->>'workspace' AS workspace,
       (SELECT COUNT(*) FROM public.workflow_cards wc WHERE wc.channel_id = c.id) AS cards,
       (SELECT COUNT(*) FROM public.channel_messages m WHERE m.channel_id = c.id) AS mensagens
FROM public.channels c
WHERE c.name IN ('Liberação Contas a Pagar','Liberação Fat Moto','Emplacamento','Faturamento OS/Peças')
   OR c.metadata->>'workspace' IN ('alinha_operations','shineray_operations')
ORDER BY c.name;

-- 5. Cópias legadas na tabela antiga (chats, type = 'channel')
SELECT 'CANAL LEGADO (chats)' AS tipo, c.id, c.name,
       (SELECT COUNT(*) FROM public.workflow_cards wc WHERE wc.channel_id = c.id) AS cards,
       (SELECT COUNT(*) FROM public.messages m WHERE m.chat_id = c.id) AS mensagens
FROM public.chats c
WHERE c.type = 'channel'
  AND (c.name IN ('Liberação Contas a Pagar','Liberação Fat Moto','Emplacamento','Faturamento OS/Peças')
       OR c.metadata->>'workspace' IN ('alinha_operations','shineray_operations'))
ORDER BY c.name;

-- 6. Visão geral: tudo que existe hoje em cada tabela organizacional
SELECT 'RESUMO' AS tipo, 'branches' AS tabela, COUNT(*) AS total FROM public.branches
UNION ALL SELECT 'RESUMO', 'departments', COUNT(*) FROM public.departments
UNION ALL SELECT 'RESUMO', 'job_positions', COUNT(*) FROM public.job_positions;
