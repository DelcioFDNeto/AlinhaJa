-- =============================================================
-- RH passa a obedecer o RBAC (2/7): políticas das tabelas
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- Cada política mantém o mesmo comando e as mesmas condições; a de
-- FOR ALL ganha um par "(leitura)" com `view`. Dados sensíveis
-- (dependentes, histórico salarial, logs) exigem `manage` até para ler.

-- avaliacao ← 20260717100000_rh12_avaliacao_tecnica.sql
DROP POLICY IF EXISTS "RH lê avaliacoes" ON public.avaliacao;
CREATE POLICY "RH lê avaliacoes" ON public.avaliacao
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org());

-- avaliacao_resposta ← 20260717100000_rh12_avaliacao_tecnica.sql
DROP POLICY IF EXISTS "RH lê respostas" ON public.avaliacao_resposta;
CREATE POLICY "RH lê respostas" ON public.avaliacao_resposta
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org());

-- candidato ← 20260708160000_rh1_banco_de_talentos.sql
DROP POLICY IF EXISTS "RH atualiza candidatos da própria org" ON public.candidato;
CREATE POLICY "RH atualiza candidatos da própria org" ON public.candidato
  FOR UPDATE
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

-- candidato ← 20260708160000_rh1_banco_de_talentos.sql
DROP POLICY IF EXISTS "RH insere candidatos na própria org" ON public.candidato;
CREATE POLICY "RH insere candidatos na própria org" ON public.candidato
  FOR INSERT
  WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org());

-- candidato ← 20260708160000_rh1_banco_de_talentos.sql
DROP POLICY IF EXISTS "RH lê candidatos da própria org" ON public.candidato;
CREATE POLICY "RH lê candidatos da própria org" ON public.candidato
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL);

-- candidato_mensagem ← 20260708190000_rh2_portal_candidato.sql
DROP POLICY IF EXISTS "RH acessa mensagens da própria org" ON public.candidato_mensagem;
CREATE POLICY "RH acessa mensagens da própria org" ON public.candidato_mensagem
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND EXISTS (
    SELECT 1 FROM public.candidato c
    WHERE c.id = candidato_mensagem.candidato_id
      AND c.organization_id = public.fn_current_org()))
  WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND autor = 'rh' AND EXISTS (
    SELECT 1 FROM public.candidato c
    WHERE c.id = candidato_mensagem.candidato_id
      AND c.organization_id = public.fn_current_org()));
DROP POLICY IF EXISTS "RH acessa mensagens da própria org (leitura)" ON public.candidato_mensagem;
CREATE POLICY "RH acessa mensagens da própria org (leitura)" ON public.candidato_mensagem
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND EXISTS (
    SELECT 1 FROM public.candidato c
    WHERE c.id = candidato_mensagem.candidato_id
      AND c.organization_id = public.fn_current_org()));

-- funcionario ← 20260709100000_rh4_ficha_funcionario.sql
DROP POLICY IF EXISTS "RH atualiza funcionários" ON public.funcionario;
CREATE POLICY "RH atualiza funcionários" ON public.funcionario
  FOR UPDATE
  USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

-- funcionario ← 20260709100000_rh4_ficha_funcionario.sql
DROP POLICY IF EXISTS "RH insere funcionários" ON public.funcionario;
CREATE POLICY "RH insere funcionários" ON public.funcionario
  FOR INSERT
  WITH CHECK ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());

-- ia_usage_log ← 20260708210000_rh3_ia_curriculo.sql
DROP POLICY IF EXISTS "RH admin lê uso de IA da própria org" ON public.ia_usage_log;
CREATE POLICY "RH admin lê uso de IA da própria org" ON public.ia_usage_log
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org());

-- org_smtp_config ← 20260724100000_rh19_automacoes_comunicacao.sql
DROP POLICY IF EXISTS "Admin manage org_smtp_config" ON public.org_smtp_config;
CREATE POLICY "Admin manage org_smtp_config" ON public.org_smtp_config
  FOR ALL
  USING (organization_id = public.fn_current_org() AND (public.fn_is_admin() OR (SELECT public.fn_rh_pode('rh_automacoes', 'manage'))));
DROP POLICY IF EXISTS "Admin manage org_smtp_config (leitura)" ON public.org_smtp_config;
CREATE POLICY "Admin manage org_smtp_config (leitura)" ON public.org_smtp_config
  FOR SELECT USING (organization_id = public.fn_current_org() AND (public.fn_is_admin() OR (SELECT public.fn_rh_pode('rh_automacoes', 'view'))));

-- pipeline_etapa ← 20260719100000_rh14_pipeline_etapas.sql
DROP POLICY IF EXISTS "Admin RH gerencia etapas" ON public.pipeline_etapa;
CREATE POLICY "Admin RH gerencia etapas" ON public.pipeline_etapa
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "Admin RH gerencia etapas (leitura)" ON public.pipeline_etapa;
CREATE POLICY "Admin RH gerencia etapas (leitura)" ON public.pipeline_etapa
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org());

-- questao ← 20260717100000_rh12_avaliacao_tecnica.sql
DROP POLICY IF EXISTS "RH gerencia questoes" ON public.questao;
CREATE POLICY "RH gerencia questoes" ON public.questao
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH gerencia questoes (leitura)" ON public.questao;
CREATE POLICY "RH gerencia questoes (leitura)" ON public.questao
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL);

-- rh_access_log ← 20260709100000_rh4_ficha_funcionario.sql
DROP POLICY IF EXISTS "RH admin lê log de acesso" ON public.rh_access_log;
CREATE POLICY "RH admin lê log de acesso" ON public.rh_access_log
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());

-- rh_alerta ← 20260709120000_rh5_onboarding.sql
DROP POLICY IF EXISTS "RH lê alertas" ON public.rh_alerta;
CREATE POLICY "RH lê alertas" ON public.rh_alerta
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_alertas', 'view')) AND organization_id = public.fn_current_org());

-- rh_alerta ← 20260709120000_rh5_onboarding.sql
DROP POLICY IF EXISTS "RH marca alertas como lido" ON public.rh_alerta;
CREATE POLICY "RH marca alertas como lido" ON public.rh_alerta
  FOR UPDATE
  USING ((SELECT public.fn_rh_pode('rh_alertas', 'view')) AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

-- rh_ausencia ← 20260722100000_rh17_ausencias.sql
DROP POLICY IF EXISTS "rh_ausencia_delete_self_or_rh" ON public.rh_ausencia;
CREATE POLICY "rh_ausencia_delete_self_or_rh" ON public.rh_ausencia
  FOR DELETE
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            (funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid()) AND status = 'pendente')
            OR (SELECT public.fn_rh_pode('rh_ausencias', 'manage'))
        )
    );

-- rh_ausencia ← 20260722100000_rh17_ausencias.sql
DROP POLICY IF EXISTS "rh_ausencia_insert_self" ON public.rh_ausencia;
CREATE POLICY "rh_ausencia_insert_self" ON public.rh_ausencia
  FOR INSERT
    WITH CHECK (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid())
            OR (SELECT public.fn_rh_pode('rh_ausencias', 'manage'))
        )
    );

-- rh_ausencia ← 20260722100000_rh17_ausencias.sql
DROP POLICY IF EXISTS "rh_ausencia_select_rh" ON public.rh_ausencia;
CREATE POLICY "rh_ausencia_select_rh" ON public.rh_ausencia
  FOR SELECT
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (SELECT public.fn_rh_pode('rh_ausencias', 'view'))
    );

-- rh_ausencia ← 20260722100000_rh17_ausencias.sql
DROP POLICY IF EXISTS "rh_ausencia_update_self_or_rh" ON public.rh_ausencia;
CREATE POLICY "rh_ausencia_update_self_or_rh" ON public.rh_ausencia
  FOR UPDATE
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            (funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid()) AND status = 'pendente')
            OR (SELECT public.fn_rh_pode('rh_ausencias', 'manage'))
        )
    );

-- rh_automacao ← 20260724100000_rh19_automacoes_comunicacao.sql
DROP POLICY IF EXISTS "RH manage rh_automacao" ON public.rh_automacao;
CREATE POLICY "RH manage rh_automacao" ON public.rh_automacao
  FOR ALL
  USING (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'manage')));
DROP POLICY IF EXISTS "RH manage rh_automacao (leitura)" ON public.rh_automacao;
CREATE POLICY "RH manage rh_automacao (leitura)" ON public.rh_automacao
  FOR SELECT USING (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'view')));

-- rh_avaliacao_360 ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
DROP POLICY IF EXISTS "RH cria convites 360" ON public.rh_avaliacao_360;
CREATE POLICY "RH cria convites 360" ON public.rh_avaliacao_360
  FOR INSERT
  WITH CHECK ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org());

-- rh_avaliacao_360 ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
DROP POLICY IF EXISTS "RH lê 360" ON public.rh_avaliacao_360;
CREATE POLICY "RH lê 360" ON public.rh_avaliacao_360
  FOR SELECT
  USING ((SELECT public.fn_rh_pode('rh_desempenho', 'view')) AND organization_id = public.fn_current_org());

-- rh_avaliacao_desempenho ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH acessa avaliacoes" ON public.rh_avaliacao_desempenho;
CREATE POLICY "RH acessa avaliacoes" ON public.rh_avaliacao_desempenho
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa avaliacoes (leitura)" ON public.rh_avaliacao_desempenho;
CREATE POLICY "RH acessa avaliacoes (leitura)" ON public.rh_avaliacao_desempenho
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_desempenho', 'view')) AND organization_id = public.fn_current_org());

-- rh_beneficio ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH insere beneficios" ON public.rh_beneficio;
CREATE POLICY "RH insere beneficios" ON public.rh_beneficio
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_beneficios', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH insere beneficios (leitura)" ON public.rh_beneficio;
CREATE POLICY "RH insere beneficios (leitura)" ON public.rh_beneficio
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_beneficios', 'view')) AND organization_id = public.fn_current_org());

-- rh_ciclo_avaliacao ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
DROP POLICY IF EXISTS "RH gerencia ciclos" ON public.rh_ciclo_avaliacao;
CREATE POLICY "RH gerencia ciclos" ON public.rh_ciclo_avaliacao
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH gerencia ciclos (leitura)" ON public.rh_ciclo_avaliacao;
CREATE POLICY "RH gerencia ciclos (leitura)" ON public.rh_ciclo_avaliacao
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_desempenho', 'view')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL);

-- rh_comunicacao_log ← 20260724100000_rh19_automacoes_comunicacao.sql
DROP POLICY IF EXISTS "RH insert rh_comunicacao_log" ON public.rh_comunicacao_log;
CREATE POLICY "RH insert rh_comunicacao_log" ON public.rh_comunicacao_log
  FOR INSERT
  WITH CHECK (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'manage')));

-- rh_comunicacao_log ← 20260724100000_rh19_automacoes_comunicacao.sql
DROP POLICY IF EXISTS "RH view rh_comunicacao_log" ON public.rh_comunicacao_log;
CREATE POLICY "RH view rh_comunicacao_log" ON public.rh_comunicacao_log
  FOR SELECT
  USING (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'view')));

-- rh_dependente ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH acessa dependentes" ON public.rh_dependente;
CREATE POLICY "RH acessa dependentes" ON public.rh_dependente
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa dependentes (leitura)" ON public.rh_dependente;
CREATE POLICY "RH acessa dependentes (leitura)" ON public.rh_dependente
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());

-- rh_documento ← 20260709140000_rh6_documentos.sql
DROP POLICY IF EXISTS "RH gerencia documentos" ON public.rh_documento;
CREATE POLICY "RH gerencia documentos" ON public.rh_documento
  FOR ALL
  USING (
    deleted_at IS NULL 
    AND organization_id = public.fn_current_org()
    AND (SELECT public.fn_rh_pode('rh_documentos', 'manage'))
  );
DROP POLICY IF EXISTS "RH gerencia documentos (leitura)" ON public.rh_documento;
CREATE POLICY "RH gerencia documentos (leitura)" ON public.rh_documento
  FOR SELECT USING (
    deleted_at IS NULL 
    AND organization_id = public.fn_current_org()
    AND (SELECT public.fn_rh_pode('rh_documentos', 'view'))
  );

-- rh_email_template ← 20260724100000_rh19_automacoes_comunicacao.sql
DROP POLICY IF EXISTS "RH manage rh_email_template" ON public.rh_email_template;
CREATE POLICY "RH manage rh_email_template" ON public.rh_email_template
  FOR ALL
  USING (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'manage')));
DROP POLICY IF EXISTS "RH manage rh_email_template (leitura)" ON public.rh_email_template;
CREATE POLICY "RH manage rh_email_template (leitura)" ON public.rh_email_template
  FOR SELECT USING (organization_id = public.fn_current_org() AND (SELECT public.fn_rh_pode('rh_automacoes', 'view')));

-- rh_funcionario_beneficio ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH acessa func_beneficios" ON public.rh_funcionario_beneficio;
CREATE POLICY "RH acessa func_beneficios" ON public.rh_funcionario_beneficio
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_beneficios', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa func_beneficios (leitura)" ON public.rh_funcionario_beneficio;
CREATE POLICY "RH acessa func_beneficios (leitura)" ON public.rh_funcionario_beneficio
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_beneficios', 'view')) AND organization_id = public.fn_current_org());

-- rh_historico_cargo_salario ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH lê e insere histórico" ON public.rh_historico_cargo_salario;
CREATE POLICY "RH lê e insere histórico" ON public.rh_historico_cargo_salario
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH lê e insere histórico (leitura)" ON public.rh_historico_cargo_salario;
CREATE POLICY "RH lê e insere histórico (leitura)" ON public.rh_historico_cargo_salario
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());

-- rh_holerite ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH acessa holerites" ON public.rh_holerite;
CREATE POLICY "RH acessa holerites" ON public.rh_holerite
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_holerites', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa holerites (leitura)" ON public.rh_holerite;
CREATE POLICY "RH acessa holerites (leitura)" ON public.rh_holerite
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_holerites', 'view')) AND organization_id = public.fn_current_org());

-- rh_meta ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
DROP POLICY IF EXISTS "RH gerencia metas" ON public.rh_meta;
CREATE POLICY "RH gerencia metas" ON public.rh_meta
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK ((SELECT public.fn_rh_pode('rh_desempenho', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH gerencia metas (leitura)" ON public.rh_meta;
CREATE POLICY "RH gerencia metas (leitura)" ON public.rh_meta
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_desempenho', 'view')) AND organization_id = public.fn_current_org());

-- rh_periodo_aquisitivo ← 20260801110000_rh26_ferias_saldo.sql
DROP POLICY IF EXISTS "RH gerencia períodos aquisitivos" ON public.rh_periodo_aquisitivo;
CREATE POLICY "RH gerencia períodos aquisitivos" ON public.rh_periodo_aquisitivo
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_ausencias', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK ((SELECT public.fn_rh_pode('rh_ausencias', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH gerencia períodos aquisitivos (leitura)" ON public.rh_periodo_aquisitivo;
CREATE POLICY "RH gerencia períodos aquisitivos (leitura)" ON public.rh_periodo_aquisitivo
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_ausencias', 'view')) AND organization_id = public.fn_current_org());

-- rh_ponto_registro ← 20260725100000_rh21_ficha_funcionario_expansao.sql
DROP POLICY IF EXISTS "RH acessa ponto" ON public.rh_ponto_registro;
CREATE POLICY "RH acessa ponto" ON public.rh_ponto_registro
  FOR ALL
USING ((SELECT public.fn_rh_pode('rh_ponto', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa ponto (leitura)" ON public.rh_ponto_registro;
CREATE POLICY "RH acessa ponto (leitura)" ON public.rh_ponto_registro
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_ponto', 'view')) AND organization_id = public.fn_current_org());

-- vaga ← 20260715110000_rh10_vagas.sql
DROP POLICY IF EXISTS "RH gerencia vagas" ON public.vaga;
CREATE POLICY "RH gerencia vagas" ON public.vaga
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH gerencia vagas (leitura)" ON public.vaga;
CREATE POLICY "RH gerencia vagas (leitura)" ON public.vaga
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL);

-- vinculo ← 20260709100000_rh4_ficha_funcionario.sql
DROP POLICY IF EXISTS "RH acessa vínculos" ON public.vinculo;
CREATE POLICY "RH acessa vínculos" ON public.vinculo
  FOR ALL
  USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org())
  WITH CHECK ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage')) AND organization_id = public.fn_current_org());
DROP POLICY IF EXISTS "RH acessa vínculos (leitura)" ON public.vinculo;
CREATE POLICY "RH acessa vínculos (leitura)" ON public.vinculo
  FOR SELECT USING ((SELECT public.fn_rh_pode('rh_funcionarios', 'view')) AND organization_id = public.fn_current_org());

