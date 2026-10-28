-- Habilitar inserção, atualização e exclusão para a tabela departments
CREATE POLICY "Admin manage departments" 
ON departments 
FOR ALL 
TO authenticated 
USING (organization_id = fn_current_org()) 
WITH CHECK (organization_id = fn_current_org());

-- Habilitar inserção, atualização e exclusão para a tabela job_positions
CREATE POLICY "Admin manage job_positions" 
ON job_positions 
FOR ALL 
TO authenticated 
USING (organization_id = fn_current_org()) 
WITH CHECK (organization_id = fn_current_org());
