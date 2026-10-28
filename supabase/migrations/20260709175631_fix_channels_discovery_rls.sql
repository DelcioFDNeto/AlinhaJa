DROP POLICY IF EXISTS "Membros podem ver canais" ON channels;
CREATE POLICY "Todos autenticados podem ver canais" ON channels FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Ver membros do mesmo canal" ON channel_members;
CREATE POLICY "Todos autenticados podem ver membros de canais" ON channel_members FOR SELECT USING (auth.role() = 'authenticated');
