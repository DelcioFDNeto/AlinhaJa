-- Migration 007: Arquivamento de Usuários (Soft Delete) e Bloqueio de Acesso
-- ==============================================================================

-- 1. Adicionar flag de inativação lógica na tabela pública de usuários
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- 2. Atualizar a Política RLS para garantir que inativos não façam bagunça?
-- Na verdade, a política padrão do app permite Selects/Inserts de autenticados,
-- mas podemos deixar a flag `is_active` governar a UI. O DB não negará leitura, 
-- mas a UI vai chutar ele. Para bloqueio definitivo do Supabase, usaremos a RPC.

-- 3. Função RPC Segura para o Admin alternar o status do funcionário (Arquivar/Desarquivar)
-- Quando arquivamos (is_active = false), nós também cravamos um banimento no auth.users
CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_target_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verifica se quem tá chamando é da Alta Gestão (TI ou Diretor)
  SELECT role_level INTO v_caller_role 
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('ti_admin', 'director') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas TI ou Diretores podem arquivar contas.';
  END IF;

  -- 2. Não permite que a pessoa se auto-bloqueie por engano
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar o próprio status de arquivamento.';
  END IF;

  -- 3. Atualiza a flag na nossa tabela pública
  UPDATE public.users SET is_active = p_is_active WHERE id = p_target_user_id;

  -- 4. Atualiza a restrição de login profundo no Supabase Auth
  -- Se p_is_active for FALSE, banimos ele até o ano 3000 (Bloqueio Total).
  -- Se p_is_active for TRUE, tiramos o banimento (NULL).
  IF p_is_active = FALSE THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = p_target_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;
  END IF;

END;
$$;
