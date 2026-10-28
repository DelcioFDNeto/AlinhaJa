-- ==============================================================================
-- FLEXY - Seed Database Script (Beta)
-- ==============================================================================
-- Este script é executado logo após as migrations completarem (npx supabase db reset).
-- Ele planta no banco de dados apenas os usuários base para teste.
-- Os canais serão criados dinamicamente pelos administradores no app.
-- ==============================================================================

-- 1. Criação de Usuários de Teste Essenciais (Senha Global: alinhaja25)
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  phone,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  created_at,
  updated_at
)
VALUES 
  -- TI (Admin Root)
  ('00000000-0000-0000-0000-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ti@alinhaja.com.br', extensions.crypt('alinhaja25', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name": "TI Administrador", "avatar_url": null}'::jsonb, '11111111111', '', '', '', '', now(), now()),
  -- Diretor Financeiro
  ('00000000-0000-0000-0000-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'diretoria@alinhaja.com.br', extensions.crypt('alinhaja25', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name": "Diretor AlinhaJá", "avatar_url": null}'::jsonb, '22222222222', '', '', '', '', now(), now()),
  -- Operacional de Loja
  ('00000000-0000-0000-0000-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'vendedor.teste@alinhaja.com.br', extensions.crypt('alinhaja25', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name": "Julio (Vendedor Padrão)", "avatar_url": null}'::jsonb, '33333333333', '', '', '', '', now(), now())
ON CONFLICT (id) DO NOTHING;

-- Inserção fundamental em auth.identities para o Supabase deixar a pessoa logar (Provider: Email)
INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
VALUES 
  (gen_random_uuid(), '00000000-0000-0000-0000-111111111111', '00000000-0000-0000-0000-111111111111', '{"sub": "00000000-0000-0000-0000-111111111111", "email": "ti@alinhaja.com.br", "email_verified": true}'::jsonb, 'email', now(), now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-222222222222', '00000000-0000-0000-0000-222222222222', '{"sub": "00000000-0000-0000-0000-222222222222", "email": "diretoria@alinhaja.com.br", "email_verified": true}'::jsonb, 'email', now(), now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-333333333333', '00000000-0000-0000-0000-333333333333', '{"sub": "00000000-0000-0000-0000-333333333333", "email": "vendedor.teste@alinhaja.com.br", "email_verified": true}'::jsonb, 'email', now(), now())
ON CONFLICT (provider_id, provider) DO NOTHING;

-- A trigger do DB cuidou de povoar a tabela public.users
-- Vamos aprovar explicitamente essas continhas de testes e atribuir níveis de acesso:
UPDATE public.users 
SET 
  is_active = true,
  role_level = CASE 
    WHEN id = '00000000-0000-0000-0000-111111111111' THEN 'super_admin'::user_role_level 
    WHEN id = '00000000-0000-0000-0000-222222222222' THEN 'admin'::user_role_level 
    ELSE 'member'::user_role_level 
  END
WHERE id IN (
  '00000000-0000-0000-0000-111111111111', 
  '00000000-0000-0000-0000-222222222222', 
  '00000000-0000-0000-0000-333333333333'
);

-- Tira o banimento inicial para que consigam logar (pois quem cadastra pelo app cai em limbo até aprovação, como inserimos por seed, liberamos).
UPDATE auth.users 
SET banned_until = NULL 
WHERE id IN (
  '00000000-0000-0000-0000-111111111111', 
  '00000000-0000-0000-0000-222222222222', 
  '00000000-0000-0000-0000-333333333333'
);

-- Canais/workflows base para ambiente local apos `supabase db reset`.
-- A funcao e criada pela migration 20260512180000_unified_workflow_channel_seed.sql.

-- A. Chats / Canais Auxiliares (para satisfazer constraints de DMs e do RPC)
INSERT INTO public.chats (id, type, name, created_by)
VALUES ('8a4e1311-2c07-4d10-9148-eb01253f1f72', 'channel', 'Avisos Gerais', '00000000-0000-0000-0000-111111111111')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.chat_members (chat_id, user_id, role)
VALUES 
  ('8a4e1311-2c07-4d10-9148-eb01253f1f72', '00000000-0000-0000-0000-111111111111', 'owner'),
  ('8a4e1311-2c07-4d10-9148-eb01253f1f72', '00000000-0000-0000-0000-222222222222', 'member'),
  ('8a4e1311-2c07-4d10-9148-eb01253f1f72', '00000000-0000-0000-0000-333333333333', 'member')
ON CONFLICT (chat_id, user_id) DO NOTHING;

-- B. Avisos e Comunicados Oficiais
-- Anúncio 1: Criado pelo TI (Comunicado da Nova Marca)
INSERT INTO public.messages (id, chat_id, sender_id, content, content_type, metadata, created_at)
VALUES 
  (
    '00000000-0000-0000-0000-aaaa11110001',
    '8a4e1311-2c07-4d10-9148-eb01253f1f72',
    '00000000-0000-0000-0000-111111111111', -- TI
    '🚨 [COMUNICADO IMPORTANTE] Nova Marca AlinhaJá 🚨

Prezada equipe,

É com grande orgulho que anunciamos a transição oficial da nossa identidade visual de Fluxy para AlinhaJá! Nossa paleta de cores agora assume o vermelho institucional (#D21A18), reforçando nosso compromisso com a velocidade, precisão e excelência operacional.

Todos os nossos canais, fluxos de trabalho e painéis de faturamento foram atualizados. Favor confirmar a leitura clicando em "Estou Ciente" abaixo.',
    'text'::public.content_type,
    '{"type": "announcement"}'::jsonb,
    NOW() - INTERVAL '2 hours'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.channel_messages (id, channel_id, sender_id, content, content_type, metadata, created_at)
VALUES 
  (
    '00000000-0000-0000-0000-aaaa11110001',
    '8a4e1311-2c07-4d10-9148-eb01253f1f72',
    '00000000-0000-0000-0000-111111111111', -- TI
    '🚨 [COMUNICADO IMPORTANTE] Nova Marca AlinhaJá 🚨

Prezada equipe,

É com grande orgulho que anunciamos a transição oficial da nossa identidade visual de Fluxy para AlinhaJá! Nossa paleta de cores agora assume o vermelho institucional (#D21A18), reforçando nosso compromisso com a velocidade, precisão e excelência operacional.

Todos os nossos canais, fluxos de trabalho e painéis de faturamento foram atualizados. Favor confirmar a leitura clicando em "Estou Ciente" abaixo.',
    'text',
    '{"type": "announcement"}'::jsonb,
    NOW() - INTERVAL '2 hours'
  )
ON CONFLICT (id) DO NOTHING;

-- Confirmados para o Anúncio 1 (Diretoria e Vendedor já deram ciente)
INSERT INTO public.message_actions (id, message_id, user_id, action_type, action_value, created_at)
VALUES 
  (gen_random_uuid(), '00000000-0000-0000-0000-aaaa11110001', '00000000-0000-0000-0000-222222222222', 'acknowledge', 'confirmed', NOW() - INTERVAL '1 hour'),
  (gen_random_uuid(), '00000000-0000-0000-0000-aaaa11110001', '00000000-0000-0000-0000-333333333333', 'acknowledge', 'confirmed', NOW() - INTERVAL '30 minutes')
ON CONFLICT (message_id, user_id, action_type) DO NOTHING;

-- Anúncio 2: Criado pelo Diretor (TI precisa confirmar/dar ciente)
INSERT INTO public.messages (id, chat_id, sender_id, content, content_type, metadata, created_at)
VALUES 
  (
    '00000000-0000-0000-0000-aaaa11110004',
    '8a4e1311-2c07-4d10-9148-eb01253f1f72',
    '00000000-0000-0000-0000-222222222222', -- Diretoria
    '⚠️ [IMPORTANTE] Nova Diretriz de Segurança e Backup ⚠️

Prezada equipe de TI,

Com a migração para a marca AlinhaJá, solicitamos que seja realizada uma auditoria completa nas políticas de backup de todos os bancos de dados de homologação e produção até o fim do dia de hoje.

Favor confirmar o recebimento e leitura desta instrução clicando em "Estou Ciente" abaixo.

Atenciosamente,
Diretoria AlinhaJá',
    'text'::public.content_type,
    '{"type": "announcement"}'::jsonb,
    NOW() - INTERVAL '15 minutes'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.channel_messages (id, channel_id, sender_id, content, content_type, metadata, created_at)
VALUES 
  (
    '00000000-0000-0000-0000-aaaa11110004',
    '8a4e1311-2c07-4d10-9148-eb01253f1f72',
    '00000000-0000-0000-0000-222222222222', -- Diretoria
    '⚠️ [IMPORTANTE] Nova Diretriz de Segurança e Backup ⚠️

Prezada equipe de TI,

Com a migração para a marca AlinhaJá, solicitamos que seja realizada uma auditoria completa nas políticas de backup de todos os bancos de dados de homologação e produção até o fim do dia de hoje.

Favor confirmar o recebimento e leitura desta instrução clicando em "Estou Ciente" abaixo.

Atenciosamente,
Diretoria AlinhaJá',
    'text',
    '{"type": "announcement"}'::jsonb,
    NOW() - INTERVAL '15 minutes'
  )
ON CONFLICT (id) DO NOTHING;

-- Confirmado para o Anúncio 2 (Apenas Vendedor deu ciente, TI pendente)
INSERT INTO public.message_actions (id, message_id, user_id, action_type, action_value, created_at)
VALUES 
  (gen_random_uuid(), '00000000-0000-0000-0000-aaaa11110004', '00000000-0000-0000-0000-333333333333', 'acknowledge', 'confirmed', NOW() - INTERVAL '5 minutes')
ON CONFLICT (message_id, user_id, action_type) DO NOTHING;

-- C. Tickets de Suporte / Helpdesk
INSERT INTO public.support_tickets (id, creator_id, assigned_to, title, description, category, priority, status, created_at, updated_at)
VALUES 
  (
    '00000000-0000-0000-0000-bbbb11110001', 
    '00000000-0000-0000-0000-333333333333', -- Vendedor
    '00000000-0000-0000-0000-111111111111', -- TI
    'Instabilidade na Sincronização de OS',
    'Ao finalizar a ordem de serviço no app, ocorre erro de timeout com o ERP. Preciso de suporte urgente pois temos faturamento pendente hoje.',
    'software'::public.support_ticket_category,
    'high'::public.support_ticket_priority,
    'in_progress'::public.support_ticket_status,
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '4 hours'
  ),
  (
    '00000000-0000-0000-0000-bbbb11110002', 
    '00000000-0000-0000-0000-222222222222', -- Diretoria
    '00000000-0000-0000-0000-111111111111', -- TI
    'Solicitação de Acesso ao Relatório Financeiro Consolidador',
    'Preciso de liberação de perfil de acesso externo para visualizar a consolidação de contas das filiais de PA e CE.',
    'external_access'::public.support_ticket_category,
    'medium'::public.support_ticket_priority,
    'new'::public.support_ticket_status,
    NOW() - INTERVAL '3 hours',
    NOW() - INTERVAL '3 hours'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.support_ticket_messages (id, ticket_id, sender_id, content, is_internal, created_at)
VALUES 
  ('00000000-0000-0000-0000-aaaa11110002', '00000000-0000-0000-0000-bbbb11110001', '00000000-0000-0000-0000-333333333333', 'Olá TI, estou com problemas ao tentar enviar a OS nº 4892 para o ERP. O sistema fica carregando e depois exibe um erro de timeout. Podem verificar?', false, NOW() - INTERVAL '4 hours'),
  ('00000000-0000-0000-0000-aaaa11110003', '00000000-0000-0000-0000-bbbb11110001', '00000000-0000-0000-0000-111111111111', 'Olá Julio, identificamos uma lentidão temporária no gateway de integração com o fornecedor. Já reiniciamos o serviço de comunicação e estamos monitorando. Pode tentar enviar novamente?', false, NOW() - INTERVAL '3 hours')
ON CONFLICT (id) DO NOTHING;

-- D. Localizações de GPS / Rastreamento
INSERT INTO public.user_locations (id, user_id, latitude, longitude, accuracy, altitude, speed, heading, device_info, battery_level, recorded_at)
VALUES 
  ('00000000-0000-0000-0000-cccc11110001', '00000000-0000-0000-0000-333333333333', -1.455756, -48.490180, 10.0, 12.0, 25.5, 90.0, '{"model": "Samsung Galaxy S23", "platform": "Android 13"}'::jsonb, 85, NOW()),
  ('00000000-0000-0000-0000-cccc11110002', '00000000-0000-0000-0000-222222222222', -1.365319, -48.384666, 15.0, 15.0, 0.0, 0.0, '{"model": "iPhone 15 Pro", "platform": "iOS 17"}'::jsonb, 92, NOW())
ON CONFLICT (id) DO NOTHING;

-- E. Reunião de Vídeo (MiroTalk) Ativa
INSERT INTO public.meetings (id, room_id, host_id, title, started_at, ended_at, is_recording, created_at, status, mirotalk_url, channel_id)
VALUES 
  (
    '00000000-0000-0000-0000-dddd11110001', 
    'alinha-reuniao-geral', 
    '00000000-0000-0000-0000-111111111111', 
    'Alinhamento Semanal de Faturamento - AlinhaJá', 
    NOW() - INTERVAL '10 minutes', 
    NULL, 
    false, 
    NOW() - INTERVAL '15 minutes', 
    'active', 
    'https://meet.jit.si/alinha-reuniao-geral', 
    '8a4e1311-2c07-4d10-9148-eb01253f1f72'
  )
ON CONFLICT (id) DO NOTHING;


-- ============================================================================
-- 4. Banco de Talentos (Candidatos)
-- ============================================================================
INSERT INTO public.candidato (
  id, organization_id, nome, email, telefone, cidade, estado, area_interesse, 
  cargo_pretendido, nivel, disponibilidade, pretensao_salarial, status, fonte, score_completude,
  consentimento_lgpd, consentimento_data
) VALUES
('00000000-0000-0000-0000-ca0000000001', 'a0000000-0000-4000-8000-000000000001', 'Ana Maria Silva', 'ana.silva@email.com', '11988887777', 'São Paulo', 'SP', 'Vendas', 'Vendedora Pleno', 'pleno', 'imediato', 3500.00, 'novo', 'portal', 85, true, NOW()),
('00000000-0000-0000-0000-ca0000000002', 'a0000000-0000-4000-8000-000000000001', 'Carlos Henrique', 'carlos.h@email.com', '11977776666', 'Campinas', 'SP', 'Administrativo', 'Assistente Administrativo', 'junior', 'imediato', 2200.00, 'em_analise', 'indicacao', 92, true, NOW()),
('00000000-0000-0000-0000-ca0000000003', 'a0000000-0000-4000-8000-000000000001', 'Fernanda Souza', 'fernanda.s@email.com', '21999995555', 'Rio de Janeiro', 'RJ', 'TI', 'Desenvolvedora Júnior', 'junior', 'aviso_previo', 4500.00, 'entrevista', 'upload_manual', 78, true, NOW()),
('00000000-0000-0000-0000-ca0000000004', 'a0000000-0000-4000-8000-000000000001', 'Roberto Almeida', 'roberto.almeida@email.com', '31988884444', 'Belo Horizonte', 'MG', 'Logística', 'Supervisor de Frota', 'senior', 'imediato', 6000.00, 'aprovado', 'portal', 95, true, NOW())
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 5. Funcionários e Vínculos
-- ============================================================================
DO $$
DECLARE
    v_org_id uuid := 'a0000000-0000-4000-8000-000000000001'; -- the default org id
    v_filial_matriz uuid;
    v_filial_norte uuid;
    v_filial_sul uuid;
BEGIN
    -- Get branches (assumes at least 3, if not fallback to the first one)
    SELECT id INTO v_filial_matriz FROM public.branches ORDER BY created_at ASC LIMIT 1;
    SELECT id INTO v_filial_norte FROM public.branches ORDER BY created_at ASC OFFSET 1 LIMIT 1;
    SELECT id INTO v_filial_sul FROM public.branches ORDER BY created_at ASC OFFSET 2 LIMIT 1;
    
    IF v_filial_norte IS NULL THEN v_filial_norte := v_filial_matriz; END IF;
    IF v_filial_sul IS NULL THEN v_filial_sul := v_filial_matriz; END IF;

    -- Limpar vínculos e funcionários existentes para rodar liso (apenas os de teste)
    DELETE FROM public.funcionario WHERE organization_id = v_org_id AND created_by IS NULL;

    -- Inserção de 15 funcionários diversos
    INSERT INTO public.funcionario (id, organization_id, nome, status) VALUES 
    ('00000000-0000-0000-0000-f00000000001', v_org_id, 'Marina Oliveira', 'ativo'),
    ('00000000-0000-0000-0000-f00000000002', v_org_id, 'Pedro Santos', 'ferias'),
    ('00000000-0000-0000-0000-f00000000003', v_org_id, 'Lucia Mendes', 'ativo'),
    ('00000000-0000-0000-0000-f00000000004', v_org_id, 'Jorge Costa', 'afastado'),
    ('00000000-0000-0000-0000-f00000000005', v_org_id, 'Amanda Rocha', 'desligado'),
    ('00000000-0000-0000-0000-f00000000006', v_org_id, 'Sérgio Nogueira', 'ativo'),
    ('00000000-0000-0000-0000-f00000000007', v_org_id, 'Carolina Batista', 'ativo'),
    ('00000000-0000-0000-0000-f00000000008', v_org_id, 'Thiago Meira', 'ferias'),
    ('00000000-0000-0000-0000-f00000000009', v_org_id, 'Roberto Carlos', 'ativo'),
    ('00000000-0000-0000-0000-f00000000010', v_org_id, 'Fernanda Silva', 'ativo'),
    ('00000000-0000-0000-0000-f00000000011', v_org_id, 'Carlos Magno', 'ativo'),
    ('00000000-0000-0000-0000-f00000000012', v_org_id, 'Beatriz Souza', 'afastado'),
    ('00000000-0000-0000-0000-f00000000013', v_org_id, 'Daniel Albuquerque', 'ativo'),
    ('00000000-0000-0000-0000-f00000000014', v_org_id, 'Mariana Nogueira', 'ativo'),
    ('00000000-0000-0000-0000-f00000000015', v_org_id, 'Lucas Fernandes', 'ativo'::public.funcionario_status)
    ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;

    -- E agora seus vínculos: mesclando filiais, departamentos e cargos
    INSERT INTO public.vinculo (id, funcionario_id, organization_id, tipo, data_admissao, matricula, filial_id, departamento_id, cargo_id, status) VALUES 
    -- Matriz / Administrativo, TI, Financeiro
    ('00000000-0000-0000-0000-b00000000001', '00000000-0000-0000-0000-f00000000001', v_org_id, 'clt', '2023-01-15', 'MAT-001', v_filial_matriz, 'ti', 'analista', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000002', '00000000-0000-0000-0000-f00000000002', v_org_id, 'clt', '2021-11-05', 'MAT-002', v_filial_matriz, 'financeiro', 'coordenador', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000003', '00000000-0000-0000-0000-f00000000003', v_org_id, 'pj', '2025-02-10', 'MAT-003', v_filial_matriz, 'rh', 'analista', 'experiencia'),
    ('00000000-0000-0000-0000-b00000000004', '00000000-0000-0000-0000-f00000000004', v_org_id, 'clt', '2019-07-22', 'MAT-004', v_filial_matriz, 'diretoria', 'diretor', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000005', '00000000-0000-0000-0000-f00000000005', v_org_id, 'estagio', '2024-05-13', 'MAT-005', v_filial_matriz, 'administrativo', 'auxiliar', 'desligado'),
    
    -- Filial Norte / Logistica, Comercial, Oficina
    ('00000000-0000-0000-0000-b00000000006', '00000000-0000-0000-0000-f00000000006', v_org_id, 'pj', '2022-09-01', 'MAT-006', v_filial_norte, 'logistica', 'supervisor', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000007', '00000000-0000-0000-0000-f00000000007', v_org_id, 'clt', '2025-10-10', 'MAT-007', v_filial_norte, 'comercial', 'vendedor', 'experiencia'),
    ('00000000-0000-0000-0000-b00000000008', '00000000-0000-0000-0000-f00000000008', v_org_id, 'aprendiz', '2024-01-20', 'MAT-008', v_filial_norte, 'oficina', 'mecanico', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000009', '00000000-0000-0000-0000-f00000000009', v_org_id, 'clt', '2020-03-01', 'MAT-009', v_filial_norte, 'logistica', 'motorista', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000010', '00000000-0000-0000-0000-f00000000010', v_org_id, 'clt', '2023-06-15', 'MAT-010', v_filial_norte, 'comercial', 'recepcionista', 'efetivo'),

    -- Filial Sul / Comercial, Oficina, Logistica
    ('00000000-0000-0000-0000-b00000000011', '00000000-0000-0000-0000-f00000000011', v_org_id, 'pj', '2021-08-20', 'MAT-011', v_filial_sul, 'comercial', 'gerente_loja', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000012', '00000000-0000-0000-0000-f00000000012', v_org_id, 'clt', '2024-05-10', 'MAT-012', v_filial_sul, 'oficina', 'tecnico', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000013', '00000000-0000-0000-0000-f00000000013', v_org_id, 'clt', '2025-02-12', 'MAT-013', v_filial_sul, 'logistica', 'estoquista', 'experiencia'),
    ('00000000-0000-0000-0000-b00000000014', '00000000-0000-0000-0000-f00000000014', v_org_id, 'clt', '2023-09-01', 'MAT-014', v_filial_sul, 'comercial', 'vendedor', 'efetivo'),
    ('00000000-0000-0000-0000-b00000000015', '00000000-0000-0000-0000-f00000000015', v_org_id, 'clt', '2025-07-01', 'MAT-015', v_filial_sul, 'pos_venda', 'analista', 'experiencia')
    ON CONFLICT (id) DO UPDATE SET 
      filial_id = EXCLUDED.filial_id,
      departamento_id = EXCLUDED.departamento_id,
      cargo_id = EXCLUDED.cargo_id;
END;
$$;
