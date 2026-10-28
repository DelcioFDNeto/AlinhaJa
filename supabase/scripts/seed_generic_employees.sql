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
