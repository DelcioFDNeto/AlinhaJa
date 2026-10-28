-- ============================================================================
-- LIMPEZA — Remove o legado da Shineray (concessionária) do banco DuBairro
-- Projeto Supabase alvo: gpeemngsxvqjflasdody (AlinhaJá / DuBairro)
--
-- REGRA DE SEGURANÇA: só remove o que NÃO tem vínculo (usuários, cards,
-- mensagens). O que tiver vínculo é apenas reportado via RAISE NOTICE para
-- decisão humana — nada em uso é apagado.
--
-- Pré-requisitos:
--   1. Rodar 01_verificar_dados_shineray_dubairro.sql e revisar o relatório.
--   2. Fazer backup do projeto (Dashboard > Database > Backups) antes.
-- Idempotente: pode ser executado mais de uma vez sem efeito colateral.
-- ============================================================================

BEGIN;

-- ─── 1. FILIAIS da Shineray sem usuários vinculados ─────────────────────────
DO $$
DECLARE
  v_nomes TEXT[] := ARRAY[
    'Acará/PA','Ananindeua/PA','Barcarena/PA','Belém/PA','Bragança/PA',
    'Breves/PA','Cametá/PA','Capanema/PA','Capitão Poço/PA','Castanhal/PA',
    'Concórdia do Pará/PA','Curuçá/PA','Fortaleza (Aldeota)/CE','Icoaraci/PA',
    'Igarapé Miri/PA','Matriz','CD / Fábrica','Moju/PA','PDV Barcarena/PA',
    'PDV Paar/PA','São Miguel do Guamá/PA','Soure/PA','Tailândia/PA',
    'Tomé-Açu/PA','Matriz Corporativa','Matriz / CD'
  ];
  v_removidas INT;
  r RECORD;
BEGIN
  -- Reporta as que serão mantidas por terem usuários
  FOR r IN
    SELECT b.name, COUNT(u.id) AS qtd
    FROM public.branches b
    JOIN public.users u ON u.branch_id = b.id
    WHERE b.name = ANY(v_nomes)
    GROUP BY b.name
  LOOP
    RAISE NOTICE 'MANTIDA (tem % usuários): filial "%"', r.qtd, r.name;
  END LOOP;

  DELETE FROM public.branches b
  WHERE b.name = ANY(v_nomes)
    AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.branch_id = b.id);
  GET DIAGNOSTICS v_removidas = ROW_COUNT;
  RAISE NOTICE 'Filiais Shineray removidas: %', v_removidas;
END $$;

-- ─── 2. CARGOS de concessionária (migration 013) sem usuários ───────────────
DO $$
DECLARE
  v_ids TEXT[] := ARRAY[
    'diretor','gerente_geral','gerente_loja','coordenador','lider_loja',
    'supervisor','analista','assistente','vendedor','mecanico','tecnico',
    'auxiliar','recepcionista','estoquista','faturista','motorista'
  ];
  v_removidos INT;
  r RECORD;
BEGIN
  FOR r IN
    SELECT j.id, j.name, COUNT(u.id) AS qtd
    FROM public.job_positions j
    JOIN public.users u ON u.job_position_id = j.id
    WHERE j.id = ANY(v_ids)
    GROUP BY j.id, j.name
  LOOP
    RAISE NOTICE 'MANTIDO (tem % usuários): cargo "%" (%)', r.qtd, r.name, r.id;
  END LOOP;

  DELETE FROM public.job_positions j
  WHERE j.id = ANY(v_ids)
    AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.job_position_id = j.id);
  GET DIAGNOSTICS v_removidos = ROW_COUNT;
  RAISE NOTICE 'Cargos de concessionária removidos: %', v_removidos;
END $$;

-- ─── 3. DEPARTAMENTOS de concessionária sem usuários e não referenciados ────
-- Só os exclusivos de concessionária. Os genéricos (ti, financeiro, rh,
-- administrativo, diretoria) são reutilizados pelo DuBairro e ficam.
DO $$
DECLARE
  v_ids TEXT[] := ARRAY['comercial','pos_venda','oficina','logistica'];
  v_removidos INT;
  r RECORD;
BEGIN
  FOR r IN
    SELECT d.id, d.name, COUNT(u.id) AS qtd
    FROM public.departments d
    JOIN public.users u ON u.department_id = d.id
    WHERE d.id = ANY(v_ids)
    GROUP BY d.id, d.name
  LOOP
    RAISE NOTICE 'MANTIDO (tem % usuários): departamento "%" (%)', r.qtd, r.name, r.id;
  END LOOP;

  DELETE FROM public.departments d
  WHERE d.id = ANY(v_ids)
    AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.department_id = d.id)
    -- não remove se algum cargo em uso ainda aponta para este departamento
    AND NOT EXISTS (
      SELECT 1 FROM public.job_positions j
      WHERE d.id = ANY(j.department_ids)
        AND EXISTS (SELECT 1 FROM public.users u WHERE u.job_position_id = j.id)
    );
  GET DIAGNOSTICS v_removidos = ROW_COUNT;
  RAISE NOTICE 'Departamentos de concessionária removidos: %', v_removidos;
END $$;

-- ─── 4. CANAIS/WORKSPACES de concessionária vazios (tabela channels) ────────
-- Remove apenas canais SEM cards de workflow e SEM mensagens.
-- Canais com conteúdo são reportados para decisão manual (arquivar ou migrar).
DO $$
DECLARE
  v_nomes TEXT[] := ARRAY[
    'Liberação Contas a Pagar','Liberação Fat Moto','Emplacamento','Faturamento OS/Peças'
  ];
  v_removidos INT := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.id, c.name,
      (SELECT COUNT(*) FROM public.workflow_cards wc WHERE wc.channel_id = c.id) AS cards,
      (SELECT COUNT(*) FROM public.channel_messages m WHERE m.channel_id = c.id) AS msgs
    FROM public.channels c
    WHERE c.name = ANY(v_nomes)
       OR c.metadata->>'workspace' IN ('alinha_operations','shineray_operations')
  LOOP
    IF r.cards = 0 AND r.msgs = 0 THEN
      DELETE FROM public.workflow_status_config WHERE channel_id = r.id;
      DELETE FROM public.channel_members WHERE channel_id = r.id;
      DELETE FROM public.channels WHERE id = r.id;
      v_removidos := v_removidos + 1;
      RAISE NOTICE 'REMOVIDO canal vazio: "%"', r.name;
    ELSE
      RAISE NOTICE 'MANTIDO (tem % cards / % mensagens): canal "%" — decidir manualmente se arquiva', r.cards, r.msgs, r.name;
    END IF;
  END LOOP;
  RAISE NOTICE 'Canais de concessionária removidos (channels): %', v_removidos;
END $$;

-- ─── 5. Cópias legadas na tabela antiga (chats, type = 'channel') ───────────
DO $$
DECLARE
  v_nomes TEXT[] := ARRAY[
    'Liberação Contas a Pagar','Liberação Fat Moto','Emplacamento','Faturamento OS/Peças'
  ];
  v_removidos INT := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.id, c.name,
      (SELECT COUNT(*) FROM public.workflow_cards wc WHERE wc.channel_id = c.id) AS cards,
      (SELECT COUNT(*) FROM public.messages m WHERE m.chat_id = c.id) AS msgs
    FROM public.chats c
    WHERE c.type = 'channel'
      AND (c.name = ANY(v_nomes)
           OR c.metadata->>'workspace' IN ('alinha_operations','shineray_operations'))
  LOOP
    IF r.cards = 0 AND r.msgs = 0 THEN
      DELETE FROM public.chat_members WHERE chat_id = r.id;
      DELETE FROM public.chats WHERE id = r.id;
      v_removidos := v_removidos + 1;
      RAISE NOTICE 'REMOVIDO canal legado vazio (chats): "%"', r.name;
    ELSE
      RAISE NOTICE 'MANTIDO canal legado (tem % cards / % mensagens): "%"', r.cards, r.msgs, r.name;
    END IF;
  END LOOP;
  RAISE NOTICE 'Canais legados removidos (chats): %', v_removidos;
END $$;

COMMIT;

-- Após executar, rode novamente 01_verificar_dados_shineray_dubairro.sql:
-- o esperado é que as consultas 1-5 retornem apenas itens "MANTIDOS"
-- (com vínculos), que devem ser tratados manualmente caso a caso.
