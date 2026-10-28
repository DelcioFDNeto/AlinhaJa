-- ============================================================
-- Contrato de organizations.settings
--
-- `settings` é um JSON livre: cada chave era lida em SQL e em Dart, com as
-- faixas válidas espalhadas pelas funções que gravam. Um valor fora da faixa
-- gravado direto no banco (painel do Supabase, script) passava sem aviso e
-- só aparecia como comportamento estranho nas rotinas de expurgo.
--
-- O contrato abaixo vale para TODA escrita, venha de onde vier, e usa as
-- mesmas faixas das funções de gravação já existentes. O modelo Dart
-- equivalente é `lib/core/models/org_settings.dart`.
--
-- POR QUE TRIGGER E NÃO CHECK
-- Uma CHECK valida a linha inteira a cada UPDATE. Se alguma empresa já tiver
-- um valor antigo fora da faixa, qualquer alteração dela — até gravar os
-- dados legais — passaria a falhar. O trigger valida só as chaves que MUDARAM
-- na operação. Chaves desconhecidas passam: o contrato cobre as conhecidas e
-- não trava recursos novos.
-- ============================================================

-- Inteiro em JSON: número inteiro ou texto só com dígitos (as rotinas atuais
-- leem com `NULLIF(x, '')::int`, então '' também é aceito como "padrão").
CREATE OR REPLACE FUNCTION public.fn_settings_inteiro(p_valor jsonb)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_valor IS NULL OR p_valor = 'null'::jsonb THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(p_valor) = 'number' THEN
    IF (p_valor #>> '{}') ~ '^-?\d+$' THEN
      RETURN (p_valor #>> '{}')::bigint;
    END IF;
    RAISE EXCEPTION 'deve ser um número inteiro';
  END IF;
  IF jsonb_typeof(p_valor) = 'string' THEN
    IF (p_valor #>> '{}') = '' THEN
      RETURN NULL;
    END IF;
    IF (p_valor #>> '{}') ~ '^\d+$' THEN
      RETURN (p_valor #>> '{}')::bigint;
    END IF;
  END IF;
  RAISE EXCEPTION 'deve ser um número inteiro';
END;
$$;

-- Valida uma chave. Devolve NULL quando o valor é aceito; senão, o motivo.
CREATE OR REPLACE FUNCTION public.fn_settings_erro(p_chave text, p_valor jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_n bigint;
  v_faixa int[];
BEGIN
  -- Remoção da chave (ou valor nulo) volta ao padrão: sempre aceita.
  IF p_valor IS NULL OR jsonb_typeof(p_valor) = 'null' THEN
    RETURN NULL;
  END IF;

  CASE p_chave
    WHEN 'modules' THEN
      IF jsonb_typeof(p_valor) <> 'array' OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(p_valor) e
            WHERE jsonb_typeof(e) <> 'string') THEN
        RETURN 'deve ser uma lista de identificadores de módulo';
      END IF;
      RETURN NULL;

    WHEN 'legal' THEN
      IF jsonb_typeof(p_valor) <> 'object' THEN
        RETURN 'deve ser um objeto';
      END IF;
      RETURN NULL;

    WHEN 'ai_provider' THEN
      IF jsonb_typeof(p_valor) <> 'string'
         OR (p_valor #>> '{}') NOT IN ('anthropic', 'openai', 'gemini', 'groq') THEN
        RETURN 'provedor não suportado (anthropic, openai, gemini ou groq)';
      END IF;
      RETURN NULL;

    ELSE
      v_faixa := CASE p_chave
        WHEN 'gps_retencao_dias'          THEN ARRAY[1, 180]
        WHEN 'candidato_retencao_meses'   THEN ARRAY[1, 120]
        WHEN 'msg_retencao_dias'          THEN ARRAY[0, 3650]
        WHEN 'backup_retencao_dias'       THEN ARRAY[7, 365]
        WHEN 'backup_max_por_dispositivo' THEN ARRAY[1, 30]
        WHEN 'backup_teto_mb'             THEN ARRAY[10, 256]
        WHEN 'avaliacao_qtd'              THEN ARRAY[1, 15]
        WHEN 'avaliacao_minutos'          THEN ARRAY[0, 180]
      END;
      IF v_faixa IS NULL THEN
        RETURN NULL;  -- chave desconhecida: fora do contrato
      END IF;
      BEGIN
        v_n := public.fn_settings_inteiro(p_valor);
      EXCEPTION WHEN OTHERS THEN
        RETURN 'deve ser um número inteiro';
      END;
      IF v_n IS NOT NULL AND (v_n < v_faixa[1] OR v_n > v_faixa[2]) THEN
        RETURN format('deve ficar entre %s e %s', v_faixa[1], v_faixa[2]);
      END IF;
      RETURN NULL;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_tg_validar_settings()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_novo  jsonb := COALESCE(NEW.settings, '{}'::jsonb);
  v_velho jsonb := CASE WHEN TG_OP = 'UPDATE'
                        THEN COALESCE(OLD.settings, '{}'::jsonb)
                        ELSE '{}'::jsonb END;
  v_chave text;
  v_erro  text;
BEGIN
  IF jsonb_typeof(v_novo) <> 'object' THEN
    RAISE EXCEPTION 'settings da empresa deve ser um objeto JSON'
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_chave IN SELECT jsonb_object_keys(v_novo)
  LOOP
    CONTINUE WHEN v_novo -> v_chave IS NOT DISTINCT FROM v_velho -> v_chave;
    v_erro := public.fn_settings_erro(v_chave, v_novo -> v_chave);
    IF v_erro IS NOT NULL THEN
      RAISE EXCEPTION 'Configuração inválida "%": %', v_chave, v_erro
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_settings ON public.organizations;
CREATE TRIGGER trg_validar_settings
  BEFORE INSERT OR UPDATE OF settings ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_validar_settings();
