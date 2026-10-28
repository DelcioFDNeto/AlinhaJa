-- ============================================================
-- RH-23 / Fase 3 (fechamento) — Timer configurável na prova
-- (PLANO-RH-COMPLETO.md, seção 6: "N questões, timer configurável").
--
-- O que entra:
--   • avaliacao.limite_minutos / expira_em  → prazo carimbado no
--     servidor no momento em que a prova começa;
--   • avaliacao.questao_ids                 → o conjunto sorteado fica
--     registrado, o que permite RETOMAR a prova e impede o candidato
--     de enviar respostas de questões que não caíram para ele;
--   • rh_set_avaliacao_config / rh_get_avaliacao_config → o RH admin
--     configura quantidade e minutos (settings.avaliacao_qtd /
--     settings.avaliacao_minutos) sem tocar no banco.
--
-- A contagem no cliente é só conforto visual: quem decide se o prazo
-- estourou é a Edge Function, comparando com expira_em.
-- Migration 100% aditiva.
-- ============================================================

-- ── 1. Colunas de prazo e conjunto sorteado ──────────────────
ALTER TABLE public.avaliacao
  ADD COLUMN IF NOT EXISTS limite_minutos SMALLINT
    CHECK (limite_minutos IS NULL OR limite_minutos BETWEEN 1 AND 180),
  ADD COLUMN IF NOT EXISTS expira_em      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS questao_ids    UUID[];

COMMENT ON COLUMN public.avaliacao.limite_minutos IS
  'Minutos concedidos para a prova. NULL = sem limite de tempo.';
COMMENT ON COLUMN public.avaliacao.expira_em IS
  'Instante-limite carimbado no servidor ao iniciar. NULL = sem limite.';
COMMENT ON COLUMN public.avaliacao.questao_ids IS
  'Questões sorteadas para esta prova — permite retomar e valida o envio.';

-- Provas em andamento com prazo, para o job de expiração.
CREATE INDEX IF NOT EXISTS idx_avaliacao_expira
  ON public.avaliacao(expira_em)
  WHERE status = 'iniciada' AND expira_em IS NOT NULL;

-- ── 2. Config por org (quantidade + minutos) ─────────────────
-- Guardadas em organizations.settings, mesmo padrão das chaves de IA.
-- p_* NULL = mantém o valor atual; p_minutos = 0 remove o limite.
CREATE OR REPLACE FUNCTION public.rh_set_avaliacao_config(
  p_qtd     integer DEFAULT NULL,
  p_minutos integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem configurar a avaliação';
  END IF;

  IF p_qtd IS NOT NULL AND p_qtd NOT BETWEEN 1 AND 15 THEN
    RAISE EXCEPTION 'A quantidade de questões deve ficar entre 1 e 15';
  END IF;
  IF p_minutos IS NOT NULL AND p_minutos NOT BETWEEN 0 AND 180 THEN
    RAISE EXCEPTION 'O tempo da prova deve ficar entre 0 (sem limite) e 180 minutos';
  END IF;

  IF p_qtd IS NOT NULL THEN
    UPDATE public.organizations
       SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb),
                                '{avaliacao_qtd}', to_jsonb(p_qtd), true)
     WHERE id = v_org;
  END IF;

  IF p_minutos IS NOT NULL THEN
    UPDATE public.organizations
       SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb),
                                '{avaliacao_minutos}', to_jsonb(p_minutos), true)
     WHERE id = v_org;
  END IF;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'editou_avaliacao_config',
          jsonb_build_object('qtd', p_qtd, 'minutos', p_minutos));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_set_avaliacao_config(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_set_avaliacao_config(integer, integer) TO authenticated;

-- Leitura da config (o RH não lê organizations.settings direto).
CREATE OR REPLACE FUNCTION public.rh_get_avaliacao_config()
RETURNS TABLE (qtd integer, minutos integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Sem permissão para ler a configuração da avaliação';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE((o.settings ->> 'avaliacao_qtd')::int, 5),
    COALESCE((o.settings ->> 'avaliacao_minutos')::int, 0)
  FROM public.organizations o
  WHERE o.id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_get_avaliacao_config() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_get_avaliacao_config() TO authenticated;

-- ── 3. Varredura de provas abandonadas ───────────────────────
-- Quem estoura o prazo sem enviar fica 'expirada' com nota 0 — assim o
-- RH enxerga a tentativa e o candidato não refaz. É só faxina: quem
-- barra o envio fora do prazo é a Edge Function, que compara com
-- expira_em na hora do submit.
CREATE OR REPLACE FUNCTION public.rh_expirar_avaliacoes()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_qtd integer;
BEGIN
  WITH expiradas AS (
    UPDATE public.avaliacao
       SET status        = 'expirada',
           finalizada_em = COALESCE(finalizada_em, expira_em),
           acertos       = COALESCE(acertos, 0),
           nota          = COALESCE(nota, 0)
     WHERE status = 'iniciada'
       AND expira_em IS NOT NULL
       AND expira_em < NOW()
    RETURNING 1)
  SELECT count(*) INTO v_qtd FROM expiradas;
  RETURN v_qtd;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_expirar_avaliacoes() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.rh_expirar_avaliacoes() IS
  'Fecha provas cujo prazo venceu sem envio. Agendada de hora em hora.';

-- Agenda horária (o prazo é curto demais para o cron diário de RH).
-- Mesmo bloco tolerante das demais migrations: sem pg_cron habilitado,
-- a migration passa e o agendamento fica pendente.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('rh-expirar-avaliacoes')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rh-expirar-avaliacoes');
    PERFORM cron.schedule('rh-expirar-avaliacoes', '5 * * * *',
      $cron$ SELECT public.rh_expirar_avaliacoes(); $cron$);
  ELSE
    RAISE NOTICE 'pg_cron não habilitado: agende rh-expirar-avaliacoes manualmente após habilitar a extensão.';
  END IF;
END $$;
