-- ============================================================================
-- CARGA EM MASSA — Usuários do app → fichas de funcionário
-- ============================================================================
-- ⚠️  RODAR SOMENTE NO PROJETO SUPABASE DO ALINHAJÁ (DuBairro).
--     Confirme o ref do projeto antes (supabase/.temp/project-ref).
--
-- Cria, para cada usuário ATIVO da organização, uma ficha em `funcionario`
-- já vinculada à conta (funcionario.user_id) + o `vinculo` correspondente.
-- Evita cadastrar um por um; quem não tem conta no app entra depois pela
-- tela normal de cadastro (Central de Pessoas → Novo funcionário).
--
-- ⚠️  DUPLICAÇÃO NO DUBAIRRO — LEIA ANTES DE RODAR
--     O DuBairro já teve ~178 funcionários carregados de planilha. Essas
--     fichas podem NÃO estar vinculadas a uma conta (user_id nulo). Este
--     script só evita recriar ficha para um usuário que JÁ tem ficha com o
--     seu user_id — ele NÃO reconhece a mesma pessoa numa ficha de planilha
--     sem vínculo, e criaria uma SEGUNDA ficha. Rode a "Conferência 0"
--     abaixo primeiro: se houver fichas sem user_id, vincule-as (ficha →
--     Acesso ao app → Vincular usuário) antes desta carga, ou aceite os
--     duplicados e mescle depois.
--
-- DE ONDE VEM CADA CAMPO
--   nome, foto        ← users.full_name / users.avatar_url
--   filial/depto/cargo← users.branch_id / department_id / job_position_id
--                       (dado real, já cadastrado na conta do usuário)
--   telefone/nascim.  ← users.phone / users.data_nascimento (opcional, ver
--                       c_copiar_contato)
--   data de admissão  ← c_data_admissao — NÃO É DADO REAL, é a data de corte
--                       definida abaixo. Ver o aviso.
--
-- ⚠️  AVISO SOBRE A DATA DE ADMISSÃO
--     `vinculo.data_admissao` é NOT NULL e é de onde rh_ferias_saldo calcula
--     o período aquisitivo de férias. Como não temos as admissões reais, todo
--     mundo entra com a MESMA data de corte — o saldo de férias fica errado
--     de forma uniforme até o RH corrigir ficha a ficha (Ficha do Funcionário
--     → Vínculo → Editar) ou em lote via SQL. A consulta 3 no fim deste
--     arquivo lista quem ainda está com a data de corte.
--
-- NÃO copia CPF: `funcionario_dados_sensiveis.cpf_encrypted` exige a chave
-- por org (fn_rh_encrypt) e `cpf_hash` é único por organização — importar em
-- massa arriscaria colidir com fichas já existentes. Preencha pela ficha.
--
-- Idempotente: rodar de novo só cria o que faltou (não duplica nada).
-- Rodar via Dashboard → SQL Editor (ou psql/service role).
-- ============================================================================

-- ── Conferência 0 (RODAR ISOLADA PRIMEIRO) — fichas de planilha sem conta ─
-- Se retornar linhas, são pessoas já cadastradas como funcionário mas sem
-- user_id: vincule-as pela ficha (Acesso ao app → Vincular usuário) ANTES de
-- rodar a carga, senão a carga cria uma segunda ficha para a mesma pessoa.
-- Zero linhas = pode seguir direto para o bloco DO abaixo.
SELECT f.id AS funcionario_id, f.nome, f.status
  FROM public.funcionario f
  JOIN public.organizations o ON o.id = f.organization_id
 WHERE o.slug = 'dubairro'
   AND f.user_id IS NULL
   AND f.deleted_at IS NULL
 ORDER BY f.nome;

DO $$
DECLARE
  -- ── Ajuste antes de rodar ────────────────────────────────────────────
  c_org_slug       TEXT    := 'dubairro';       -- org alvo
  c_data_admissao  DATE    := DATE '2026-01-01';-- data de corte (ver aviso)
  c_vinculo_tipo   public.vinculo_tipo   := 'clt';
  c_vinculo_status public.vinculo_status := 'efetivo';
  c_copiar_contato BOOLEAN := true;             -- telefone + nascimento
  -- ─────────────────────────────────────────────────────────────────────

  -- Contas técnicas: nunca viram ficha de funcionário
  c_bot     UUID := '00000000-0000-0000-0000-000000000001'; -- Fluxy Bot
  c_sistema UUID := '00000000-0000-0000-0000-111111111111'; -- TI Administrador

  v_org      UUID;
  v_fichas   INT;
  v_vinculos INT;
  v_contatos INT := 0;
BEGIN
  SELECT id INTO v_org
    FROM public.organizations
   WHERE slug = c_org_slug;

  IF v_org IS NULL THEN
    RAISE EXCEPTION
      'Organização com slug "%" não existe neste banco. Projeto errado?',
      c_org_slug;
  END IF;

  -- ── 1. Ficha para cada usuário ativo que ainda não tem ──────────────
  -- O índice uq_funcionario_user garante o 1:1; o NOT EXISTS evita que a
  -- segunda execução tente reinserir e estourar o índice.
  WITH novas AS (
    INSERT INTO public.funcionario
      (organization_id, nome, foto_url, status, user_id)
    SELECT v_org, trim(u.full_name), u.avatar_url, 'ativo', u.id
      FROM public.users u
     WHERE u.organization_id = v_org
       AND u.is_active = true
       AND u.id <> c_bot
       AND u.id <> c_sistema
       -- funcionario.nome tem CHECK char_length >= 3
       AND char_length(trim(coalesce(u.full_name, ''))) >= 3
       AND NOT EXISTS (
             SELECT 1 FROM public.funcionario f
              WHERE f.user_id = u.id AND f.deleted_at IS NULL)
    RETURNING id
  )
  SELECT count(*) INTO v_fichas FROM novas;

  -- ── 2. Vínculo das fichas vinculadas a usuário que ainda não têm ────
  -- Alcança tanto as fichas criadas acima quanto as de uma execução
  -- anterior que tenha parado no meio.
  WITH novos AS (
    INSERT INTO public.vinculo
      (funcionario_id, organization_id, tipo, data_admissao, status,
       filial_id, departamento_id, cargo_id)
    SELECT f.id, v_org, c_vinculo_tipo, c_data_admissao, c_vinculo_status,
           u.branch_id, u.department_id, u.job_position_id
      FROM public.funcionario f
      JOIN public.users u ON u.id = f.user_id
     WHERE f.organization_id = v_org
       AND f.deleted_at IS NULL
       AND NOT EXISTS (
             SELECT 1 FROM public.vinculo v WHERE v.funcionario_id = f.id)
    RETURNING id
  )
  SELECT count(*) INTO v_vinculos FROM novos;

  -- ── 3. Contato já conhecido da conta (opcional) ─────────────────────
  -- Colunas planas (não cifradas) de funcionario_dados_sensiveis.
  IF c_copiar_contato THEN
    WITH novos AS (
      INSERT INTO public.funcionario_dados_sensiveis
        (funcionario_id, organization_id, telefone, data_nascimento)
      SELECT f.id, v_org, u.phone, u.data_nascimento
        FROM public.funcionario f
        JOIN public.users u ON u.id = f.user_id
       WHERE f.organization_id = v_org
         AND f.deleted_at IS NULL
         AND (u.phone IS NOT NULL OR u.data_nascimento IS NOT NULL)
      ON CONFLICT (funcionario_id) DO NOTHING
      RETURNING funcionario_id
    )
    SELECT count(*) INTO v_contatos FROM novos;
  END IF;

  RAISE NOTICE 'Fichas criadas: % | Vínculos criados: % | Contatos copiados: %',
    v_fichas, v_vinculos, v_contatos;
END $$;

-- ── Conferência 1: o que existe agora ───────────────────────────────────
SELECT count(*) FILTER (WHERE f.user_id IS NOT NULL) AS fichas_com_conta,
       count(*) FILTER (WHERE f.user_id IS NULL)     AS fichas_sem_conta,
       count(*)                                      AS total_fichas
  FROM public.funcionario f
  JOIN public.organizations o ON o.id = f.organization_id
 WHERE o.slug = 'dubairro' AND f.deleted_at IS NULL;

-- ── Conferência 2: usuários que ficaram DE FORA e por quê ───────────────
SELECT u.email,
       u.full_name,
       CASE
         WHEN u.id IN ('00000000-0000-0000-0000-000000000001',
                       '00000000-0000-0000-0000-111111111111')
              THEN 'conta técnica (bot/sistema) — ignorada de propósito'
         WHEN u.is_active = false
              THEN 'conta inativa'
         WHEN char_length(trim(coalesce(u.full_name, ''))) < 3
              THEN 'nome com menos de 3 letras — corrija o cadastro e rode de novo'
         ELSE 'já tinha ficha'
       END AS motivo
  FROM public.users u
  JOIN public.organizations o ON o.id = u.organization_id
 WHERE o.slug = 'dubairro'
   AND NOT EXISTS (SELECT 1 FROM public.funcionario f
                    WHERE f.user_id = u.id AND f.deleted_at IS NULL)
 ORDER BY 3, 1;

-- ── Conferência 3: quem ainda está com a data de corte ──────────────────
-- Use esta lista para acertar as admissões reais (pela ficha, no app, ou
-- em lote aqui mesmo com um UPDATE por matrícula/e-mail).
SELECT f.nome, u.email, v.data_admissao, v.tipo, v.status
  FROM public.vinculo v
  JOIN public.funcionario f ON f.id = v.funcionario_id
  LEFT JOIN public.users u  ON u.id = f.user_id
  JOIN public.organizations o ON o.id = v.organization_id
 WHERE o.slug = 'dubairro'
   AND v.data_admissao = DATE '2026-01-01'   -- = c_data_admissao
   AND f.deleted_at IS NULL
 ORDER BY f.nome;
