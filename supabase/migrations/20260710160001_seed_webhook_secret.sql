-- Seed do webhook secret para a comunicação entre DB Triggers e Edge Functions
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'webhook_secret') THEN
    PERFORM vault.create_secret('alinhaja_super_secret_webhook_key_2026', 'webhook_secret', 'Chave para Webhooks internos');
  END IF;
END $$;
