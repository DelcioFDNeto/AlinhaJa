# Registro das Operações de Tratamento (ROPA) — AlinhaJá

**Versão 1.0.0 — vigente a partir de `[DATA DE VIGÊNCIA]`**

Registro exigido pelo **art. 37 da LGPD**. Documento interno, apresentável à ANPD
mediante requisição. Mantido pelo Encarregado, revisado a cada mudança relevante
de funcionalidade e, no mínimo, semestralmente.

**Controladora:** `[RAZÃO SOCIAL]` — CNPJ `[CNPJ]`
**Encarregado:** `[NOME DO ENCARREGADO]` — `[E-MAIL DO DPO]`
**Sistema:** AlinhaJá — plataforma corporativa de comunicação e gestão
**Última revisão:** `[DATA]`

---

## Convenções

- **BL** = base legal (artigo da Lei nº 13.709/2018)
- **Titulares**: COL = colaboradores · CAN = candidatos · TER = terceiros
  (dependentes, parceiros pessoa física)
- **Armazenamento**: todos os registros residem na infraestrutura descrita no
  [documento 11](11-suboperadores-e-transferencia-internacional.md)

---

## 1. Comunicação corporativa

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Troca de mensagens diretas e em canais, com arquivos e mídias |
| **Titulares** | COL |
| **Dados** | Conteúdo de mensagens, arquivos, imagens, áudios, vídeos, reações, confirmações de leitura, metadados de tráfego |
| **Finalidade** | Viabilizar a comunicação interna de trabalho |
| **BL** | Art. 7º, V |
| **Compartilhamento** | Infraestrutura de banco e armazenamento (operador) |
| **Transferência internacional** | Sim — hospedagem |
| **Retenção** | Configurável; atualmente indefinida — ver documento 08 |
| **Segurança** | Isolamento por linha no banco; arquivos em repositório privado com URL assinada temporária; TLS; auditoria de acesso administrativo |
| **Tabelas** | `messages`, `channel_messages`, `channels`, `channel_members`, `message_reactions`, `message_acknowledgements`, `message_actions`, `starred_messages` |

## 2. Chamadas e reuniões

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Chamadas de voz e vídeo, salas de reunião, transcrição quando ativada |
| **Titulares** | COL |
| **Dados** | Participantes, horário, duração, situação, sala, texto transcrito com identificação do falante |
| **Finalidade** | Comunicação síncrona e registro de reunião |
| **BL** | Art. 7º, V |
| **Compartilhamento** | Provedor de comunicação em tempo real (operador) |
| **Transferência internacional** | Sim |
| **Retenção** | A definir — ver documento 08 |
| **Segurança** | Token de acesso temporário por sala; acesso à transcrição restrito a participantes |
| **Tabelas** | `calls`, `meetings`, `meeting_transcriptions` |

## 3. Identidade, autenticação e acesso

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Cadastro, login, verificação em duas etapas, dispositivos confiáveis, perfis de permissão |
| **Titulares** | COL |
| **Dados** | Nome, e-mail, telefone, cargo, setor, filial, foto, hash de senha, segredo 2FA, códigos de uso único, identificador de dispositivo, IP, data e hora de acesso |
| **Finalidade** | Controle de acesso e segurança da conta |
| **BL** | Art. 7º, V e IX; art. 11, II, "g" |
| **Compartilhamento** | Serviço de autenticação (operador) |
| **Transferência internacional** | Sim |
| **Retenção** | Enquanto durar o vínculo; dispositivos confiáveis por 30 dias |
| **Segurança** | Senha apenas como hash; 2FA; expiração de sessão; privilégio de coluna sobre CPF, data de nascimento e sexo |
| **Tabelas** | `users`, `auth.users`, `user_trusted_devices`, `user_email_otp`, `rbac_*`, `departments`, `branches` |

## 4. Monitoramento, auditoria e moderação

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Acesso administrativo a conteúdo mediante justificativa; registro de ações |
| **Titulares** | COL |
| **Dados** | Conteúdo pesquisado, responsável pelo acesso, justificativa, escopo, data e hora |
| **Finalidade** | Cumprimento legal, apuração de conduta, segurança, defesa de direitos |
| **BL** | Art. 7º, II, VI e IX; art. 11, II, "d" |
| **Compartilhamento** | Autoridades, quando requisitado; auditoria e jurídico |
| **Transferência internacional** | Não, além da hospedagem |
| **Retenção** | A definir — ver documento 08 |
| **Segurança** | Função restrita a perfis administrativos; justificativa obrigatória; teto de resultados; registro imutável |
| **Tabelas** | `audit_log`, `rh_access_log`, `user_activities`, `user_activity_history` |

## 5. Geolocalização

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Rastreamento contínuo em atividade externa |
| **Titulares** | COL que consentiram |
| **Dados** | Latitude, longitude, horário, bateria, sinais de movimento |
| **Finalidade** | Coordenação e segurança de equipe externa |
| **BL** | **Art. 7º, I — consentimento**, com registro de versão e finalidade |
| **Compartilhamento** | Gestor e RH autorizados |
| **Transferência internacional** | Não, além da hospedagem |
| **Retenção** | `[7]` dias, expurgo automático diário |
| **Segurança** | Gravação bloqueada no banco sem consentimento ativo; titular lê e apaga o próprio histórico |
| **Tabelas** | `user_locations`, `location_tracking_settings` |

## 6. Controle de jornada

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Registro de ponto pelo aplicativo ou importação |
| **Titulares** | COL |
| **Dados** | Data, hora, tipo de marcação, posição do instante, informação do dispositivo, origem, situação |
| **Finalidade** | Controle de jornada e apuração de horas |
| **BL** | Art. 7º, II — art. 74 da CLT |
| **Compartilhamento** | RH, contabilidade, autoridades trabalhistas |
| **Transferência internacional** | Não, além da hospedagem |
| **Retenção** | 5 anos |
| **Segurança** | Acesso restrito a RH e ao próprio titular |
| **Tabelas** | `rh_ponto_registro` |

## 7. Administração de pessoal

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Ficha funcional, cargos e salários, benefícios, dependentes, documentos, onboarding, desempenho |
| **Titulares** | COL, TER (dependentes) |
| **Dados** | Vínculo, cargo, salário e histórico, admissão, experiência, benefícios, dependentes, documentos funcionais, avaliações, metas |
| **Dados sensíveis** | Condição de pessoa com deficiência e tipo de deficiência |
| **Finalidade** | Execução do contrato de trabalho e obrigações legais |
| **BL** | Art. 7º, II e V; art. 11, II, "a" (cota legal) |
| **Compartilhamento** | Contabilidade, órgãos públicos, operadoras de benefícios, instituições financeiras |
| **Transferência internacional** | Não, além da hospedagem |
| **Retenção** | Ver documento 08 |
| **Segurança** | RG, endereço, dados bancários, CPF e tipo de deficiência **criptografados** com chave por organização; acesso restrito a RH; log próprio de acesso |
| **Tabelas** | `funcionario`, `funcionario_dados_sensiveis`, `rh_dependente`, `rh_historico_cargo_salario`, `rh_beneficio`, `rh_funcionario_beneficio`, `rh_documento`, `onboarding_*`, `avaliacao*`, `rh_meta`, `periodo_experiencia`, `vinculo` |

## 8. Folha de pagamento

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Disponibilização de holerites e registros de remuneração |
| **Titulares** | COL |
| **Dados** | Remuneração, descontos, encargos, período |
| **Finalidade** | Obrigação legal e execução do contrato |
| **BL** | Art. 7º, II e V |
| **Compartilhamento** | Contabilidade, órgãos previdenciários e fiscais, instituições financeiras |
| **Retenção** | 10 anos |
| **Segurança** | Acesso restrito ao titular e ao RH |
| **Tabelas** | `rh_holerite` |

## 9. Afastamentos e saúde ocupacional

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Solicitação, análise e registro de férias, licenças e afastamentos |
| **Titulares** | COL |
| **Dados** | Tipo, período, justificativa, decisão, **atestados e licenças médicas anexados** |
| **Dados sensíveis** | Sim — dados de saúde |
| **Finalidade** | Obrigação legal trabalhista e previdenciária; gestão de ausências |
| **BL** | Art. 7º, II; **art. 11, II, "a" e "d"** |
| **Compartilhamento** | RH, contabilidade, INSS quando aplicável |
| **Retenção** | Ver documento 08 |
| **Segurança** | Acesso restrito a RH; anexos em repositório privado com URL assinada |
| **Tabelas** | `rh_ausencia`, `rh_periodo_aquisitivo` |

## 10. Recrutamento e seleção

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Portal público de vagas, cadastro de candidato, currículo, testes, pipeline, banco de talentos |
| **Titulares** | CAN |
| **Dados** | Nome, contato, currículo e conteúdo, formação, experiência, competências, respostas de teste, histórico do processo, credenciais do portal |
| **Dados sensíveis** | Eventualmente presentes em currículo — não solicitados |
| **Finalidade** | Condução do processo seletivo e formação de banco de talentos |
| **BL** | Art. 7º, V (pré-contratual); **art. 7º, I** para banco de talentos; art. 11, I ou II, "a" para sensíveis |
| **Compartilhamento** | Provedor de IA para estruturação do currículo (com remoção de identificadores) |
| **Transferência internacional** | Sim |
| **Retenção** | [24] meses, com **anonimização automática** |
| **Segurança** | Isolamento por organização; limitação de tentativas de acesso; arquivos em repositório privado |
| **Tabelas** | `candidato`, `candidato_*`, `vaga`, `questao`, `pipeline_etapa`, `rh_portal_rate_limit` |

## 11. Inteligência artificial

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Assistente de suporte, extração de currículo, geração de itens de avaliação |
| **Titulares** | COL, CAN |
| **Dados enviados** | Trecho de conversa com identificadores mascarados; texto de currículo sem nome, e-mail, telefone e CPF |
| **Finalidade** | Apoio operacional e estruturação de informação |
| **BL** | Art. 7º, V e IX |
| **Compartilhamento** | Provedores de IA (operadores) |
| **Transferência internacional** | **Sim — Estados Unidos** |
| **Retenção** | Registro de uso: ver documento 08. O conteúdo permanece na origem |
| **Segurança** | Remoção automática de identificadores; chave de API sob cofre; registro de cada chamada |
| **Tabelas** | `ia_usage_log` |
| **Decisão automatizada** | **Não** — art. 20 observado; decisão sempre humana |

## 12. Workflow, financeiro e suporte

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Quadros de tarefa; lançamentos financeiros; chamados internos |
| **Titulares** | COL, TER (parceiros pessoa física) |
| **Dados** | Responsáveis, comentários, histórico; identificação e dados de contato de parceiros; conteúdo de chamados |
| **Finalidade** | Gestão operacional, financeira e de suporte |
| **BL** | Art. 7º, II, V e IX |
| **Retenção** | Ver documento 08 |
| **Tabelas** | `workflow_*`, `fin_*`, `support_tickets`, `support_ticket_messages` |

## 13. Notificações

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Envio de notificações push e por e-mail |
| **Titulares** | COL, CAN |
| **Dados** | Token do dispositivo, e-mail, título e prévia do conteúdo notificado |
| **Finalidade** | Alertar sobre mensagens, chamadas e eventos operacionais |
| **BL** | Art. 7º, V |
| **Compartilhamento** | Serviço de notificação push e servidor de e-mail (operadores) |
| **Transferência internacional** | Sim — notificações push |
| **Retenção** | Enquanto a sessão do dispositivo existir |
| **Tabelas** | `user_fcm_tokens`, `org_smtp_config`, `rh_comunicacao_log`, `rh_email_template` |

## 14. Direitos do titular e aceites

| Campo | Conteúdo |
|-------|----------|
| **Operação** | Registro de aceite de políticas; exportação de dados; pedidos de eliminação, correção e informação |
| **Titulares** | COL |
| **Dados** | Tipo e versão da política, data e hora do aceite; conteúdo e situação dos pedidos |
| **Finalidade** | Cumprimento dos arts. 8º, § 2º, 18 e 20 e prestação de contas |
| **BL** | Art. 7º, II e VI |
| **Retenção** | Vínculo + 5 anos |
| **Segurança** | Escrita apenas por função do servidor; o aceite não pode ser forjado nem apagado pelo cliente |
| **Tabelas** | `policy_acceptance`, `titular_request` |

---

## Anexo A — Categorias de dados sensíveis tratados

| Categoria | Onde | BL (art. 11) | Proteção adicional |
|-----------|------|--------------|--------------------|
| Saúde — atestados e licenças | `rh_ausencia` | II, "a" e "d" | Acesso restrito a RH; anexo privado |
| Saúde — tipo de deficiência | `funcionario_dados_sensiveis` | II, "a" | **Criptografado** |
| Condição de PCD | `funcionario_dados_sensiveis` | II, "a" | Acesso restrito; necessário à cota legal |
| Eventuais em currículo | `candidato_curriculo` | I ou II, "a" | Não solicitados; removíveis a pedido |
| Eventuais em mensagens | `messages` | — | Não solicitados; orientação de não inserir |

## Anexo B — Pendências do registro

| # | Pendência |
|---|-----------|
| 1 | Definir prazos de retenção pendentes (documento 08) |
| 2 | Confirmar região de hospedagem e cláusulas dos fornecedores (documento 11) |
| 3 | Elaborar relatório de impacto (RIPD) para o rastreamento de localização e para o monitoramento de comunicações |
| 4 | Documentar formalmente o teste de proporcionalidade do legítimo interesse (art. 10, § 3º) |

---

*Base legal: art. 37 da Lei nº 13.709/2018. Documento de uso interno, sujeito a
apresentação à ANPD.*
