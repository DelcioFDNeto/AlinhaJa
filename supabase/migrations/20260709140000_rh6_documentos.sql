-- ==============================================================================
-- Migration: 20260709140000_rh6_documentos.sql
-- Description: Módulo RH-6 - Documentos do Funcionário e RLS de Storage.
-- ==============================================================================

-- 1. Enums
DO $$ BEGIN
  CREATE TYPE public.rh_documento_categoria AS ENUM (
    'contrato',
    'identidade',
    'certificacao',
    'atestado',
    'holerite',
    'aso',
    'outro'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.rh_documento_status AS ENUM (
    'pendente_aprovacao',
    'valido',
    'proximo_vencimento',
    'vencido',
    'rejeitado'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- 2. Tabela de Documentos
CREATE TABLE IF NOT EXISTS public.rh_documento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  funcionario_id uuid NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  titulo text NOT NULL,
  descricao text,
  categoria public.rh_documento_categoria NOT NULL DEFAULT 'outro',
  storage_path text NOT NULL,
  data_emissao date,
  data_vencimento date,
  status public.rh_documento_status NOT NULL DEFAULT 'pendente_aprovacao',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_rh_documento_org_func ON public.rh_documento(organization_id, funcionario_id);
CREATE INDEX IF NOT EXISTS idx_rh_documento_status ON public.rh_documento(status);

-- 3. Triggers para updated_at
CREATE OR REPLACE FUNCTION public.handle_rh_documento_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rh_documento_updated_at ON public.rh_documento;
CREATE TRIGGER trg_rh_documento_updated_at
BEFORE UPDATE ON public.rh_documento
FOR EACH ROW EXECUTE FUNCTION public.handle_rh_documento_updated_at();

-- 4. RLS da Tabela public.rh_documento
ALTER TABLE public.rh_documento ENABLE ROW LEVEL SECURITY;

-- RH: visão total (da sua organização)
CREATE POLICY "RH gerencia documentos"
  ON public.rh_documento FOR ALL
  USING (
    deleted_at IS NULL 
    AND organization_id = public.fn_current_org()
    AND public.fn_is_rh()
  );

-- Funcionário: pode ver os próprios documentos
CREATE POLICY "Funcionario ve proprios documentos"
  ON public.rh_documento FOR SELECT
  USING (
    deleted_at IS NULL 
    AND organization_id = public.fn_current_org()
    AND funcionario_id IN (
      SELECT id FROM public.funcionario       WHERE user_id = auth.uid()
    )
  );

-- Funcionário: pode inserir documentos pendentes de aprovação para si mesmo
CREATE POLICY "Funcionario envia proprios documentos"
  ON public.rh_documento FOR INSERT
  WITH CHECK (
    organization_id = public.fn_current_org()
    AND status = 'pendente_aprovacao'
    AND funcionario_id IN (
      SELECT id FROM public.funcionario       WHERE user_id = auth.uid()
    )
  );

-- Funcionário: pode deletar apenas se estiver pendente_aprovacao ou rejeitado (soft delete seria via UPDATE, então limitamos UPDATE)
CREATE POLICY "Funcionario atualiza proprios documentos"
  ON public.rh_documento FOR UPDATE
  USING (
    deleted_at IS NULL 
    AND organization_id = public.fn_current_org()
    AND funcionario_id IN (
      SELECT id FROM public.funcionario       WHERE user_id = auth.uid()
    )
    AND status IN ('pendente_aprovacao', 'rejeitado')
  );

-- 5. RLS Storage (bucket rh-documentos)
-- O bucket rh-documentos já foi criado na migration rh1. O RH já tem acesso total a ele.
-- Precisamos permitir que o funcionário insira/leia no seu diretório.
-- A estrutura de pastas será: rh-documentos / <funcionario_id> / <arquivo>
CREATE POLICY "Funcionario acessa storage rh-documentos"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'rh-documentos'
    AND (auth.uid() IS NOT NULL)
    AND (
      (string_to_array(name, '/'))[1] IN (
        SELECT id::text FROM public.funcionario         WHERE user_id = auth.uid()
      )
    )
  );

-- 6. RPC para Cron de Vencimento
-- Esta função será chamada diariamente via cron job.
CREATE OR REPLACE FUNCTION public.rh_atualizar_status_documentos()
RETURNS void AS $$
BEGIN
  -- 1. Passar para 'proximo_vencimento' documentos validos que vencem em 30 dias ou menos
  UPDATE public.rh_documento
  SET status = 'proximo_vencimento'
  WHERE status = 'valido'
    AND data_vencimento IS NOT NULL
    AND deleted_at IS NULL
    AND data_vencimento <= CURRENT_DATE + INTERVAL '30 days'
    AND data_vencimento >= CURRENT_DATE;

  -- 2. Passar para 'vencido' documentos que já passaram da data
  UPDATE public.rh_documento
  SET status = 'vencido'
  WHERE status IN ('valido', 'proximo_vencimento')
    AND data_vencimento IS NOT NULL
    AND deleted_at IS NULL
    AND data_vencimento < CURRENT_DATE;

  -- Idealmente, poderíamos inserir alertas no rh_alerta, mas
  -- como a view de alertas já busca os dados ativamente, 
  -- alterar o status já é suficiente para aparecer na lista gerencial.
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
