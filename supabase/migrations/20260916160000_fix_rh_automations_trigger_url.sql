-- ============================================================
-- Correção: URL do trigger das automações de RH (16/09/2026 — v1.3.9)
--
-- `fn_tg_rh_automacao_notify` montava `<edge_base_url>/rh-automations`. O
-- segredo `edge_base_url` guarda a URL raiz do projeto (docs/SECRETS-RH.md),
-- e todos os outros triggers acrescentam `/functions/v1/<função>`. Sem esse
-- trecho a chamada ia para uma rota inexistente (404) e os e-mails automáticos
-- por mudança de etapa do recrutamento nunca saíam — sem erro visível, porque
-- `net.http_post` é assíncrono.
--
-- Corpo idêntico ao de 20260727100000, trocando só a montagem da URL.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_tg_rh_automacao_notify()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_url text;
BEGIN
  IF NEW.acao <> 'mudanca_status' THEN
    RETURN NEW;
  END IF;

  SELECT c.organization_id INTO v_org
  FROM public.candidato c WHERE c.id = NEW.candidato_id;
  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rh_automacao a
    WHERE a.organization_id = v_org
      AND a.ativo AND a.evento = 'mudanca_etapa'
  ) THEN
    RETURN NEW;
  END IF;

  -- Sem `/functions/v1` a chamada caía em 404 e nenhuma automação de e-mail
  -- por mudança de etapa era disparada.
  v_url := regexp_replace(public.get_edge_base_url(), '/+(functions/v1/*)?$', '')
    || '/functions/v1/rh-automations';
  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'candidato_historico',
      'organization_id', v_org,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Falha no webhook nunca pode abortar a mudança de etapa
  RETURN NEW;
END;
$$;
