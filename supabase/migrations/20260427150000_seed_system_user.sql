-- ============================================================================
-- SEED SYSTEM USER
-- Garante que existe pelo menos um usuário no banco para que as migrations
-- subsequentes de seed de canais (que dependem de um owner_id) não falhem.
-- ============================================================================

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  recovery_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-111111111111',
  'authenticated',
  'authenticated',
  'ti@alinhaja.com.br',
  -- Conta de sistema (dona dos canais semeados), não um login: senha
  -- aleatória que ninguém conhece. Ver 20261028120100.
  extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf', 10)),
  NOW(),
  NULL,
  NULL,
  '{"provider":"email","providers":["email"]}',
  '{"full_name": "TI Administrador", "avatar_url": null}',
  NOW(),
  NOW(),
  '',
  '',
  '',
  ''
) ON CONFLICT (id) DO NOTHING;
