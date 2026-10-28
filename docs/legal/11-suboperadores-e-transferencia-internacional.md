# Suboperadores e Transferência Internacional de Dados — AlinhaJá

**Versão 1.0.0 — vigente a partir de `[DATA DE VIGÊNCIA]`**

Relação dos fornecedores que tratam dados pessoais **em nome e sob instrução** da
`[RAZÃO SOCIAL]` (operadores, art. 5º, VII, da LGPD), com indicação de país de
destino e salvaguardas, para cumprimento dos arts. 33 a 36 e 39 da LGPD.

Este anexo integra a [Política de Privacidade](02-politica-de-privacidade.md) e o
[Aviso de Privacidade — Candidatos](05-aviso-de-privacidade-candidatos.md). Deve
ser atualizado **antes** de qualquer mudança de fornecedor entrar em produção.

> Itens marcados `[CONFIRMAR]` dependem de verificação contratual pelo jurídico e
> pela TI. Enquanto não confirmados, não devem ser apresentados a titulares ou à
> ANPD como garantias.

---

## 1. Fornecedores

### 1.1 Supabase — banco de dados, autenticação, arquivos e funções

| Item | Conteúdo |
|------|----------|
| **Serviço** | Banco de dados PostgreSQL, autenticação, armazenamento de arquivos, funções de servidor, tempo real |
| **Dados tratados** | **Todos** os dados pessoais da Plataforma |
| **Papel** | Operador |
| **País** | `[REGIÃO DE HOSPEDAGEM]` `[CONFIRMAR]`. Há região no Brasil (São Paulo) disponível; verificar a região efetiva do projeto |
| **Transferência internacional** | `[CONFIRMAR — depende da região]` |
| **Salvaguardas** | Termos de serviço com anexo de proteção de dados; criptografia em trânsito e em repouso; isolamento por organização implementado pela aplicação |
| **Contrato de operador (art. 39)** | `[CONFIRMAR — assinar ou aceitar DPA do fornecedor]` |
| **Comunicação de incidente** | `[CONFIRMAR — exigir 24h]` |

> **Ação prioritária.** Se a região do projeto for fora do Brasil, toda a base de
> dados está sob transferência internacional — inclusive dados sensíveis de RH.
> Confirmar a região e registrar a decisão é o item mais urgente deste anexo.

### 1.2 Google — Firebase Cloud Messaging e Hosting

| Item | Conteúdo |
|------|----------|
| **Serviço** | Notificações push; hospedagem da versão web e do site |
| **Dados tratados** | Token do dispositivo, identificador do usuário, **título e prévia do conteúdo** notificado; dados de acesso ao site |
| **Papel** | Operador |
| **País** | Estados Unidos e infraestrutura global |
| **Transferência internacional** | **Sim** |
| **Salvaguardas** | Termos de processamento de dados do Google Cloud, com cláusulas contratuais padrão |
| **Observação** | A prévia da notificação pode conter trecho de mensagem. Avaliar reduzir a prévia para dados sensíveis `[AVALIAR]` |

### 1.3 Groq — assistente de IA

| Item | Conteúdo |
|------|----------|
| **Serviço** | Inferência do assistente de suporte (Llama 3.3 70B) |
| **Dados tratados** | Trecho recente da conversa, **com CPF, CNPJ, cartão, e-mail e telefone mascarados** antes do envio |
| **Papel** | Operador |
| **País** | **Estados Unidos** |
| **Transferência internacional** | **Sim** |
| **Salvaguardas** | Termos de API comercial; chave sob segredo de plataforma; minimização automática na origem |
| **Uso para treinamento** | `[CONFIRMAR nos termos comerciais vigentes]` |
| **Retenção pelo fornecedor** | `[CONFIRMAR]` |

### 1.4 Anthropic — extração de currículo (provedor padrão)

| Item | Conteúdo |
|------|----------|
| **Serviço** | Estruturação de dados de currículo (Claude Haiku) |
| **Dados tratados** | Texto do currículo **sem nome, e-mail, telefone e CPF** |
| **Papel** | Operador |
| **País** | **Estados Unidos** |
| **Transferência internacional** | **Sim** |
| **Salvaguardas** | Termos comerciais de API; chave por organização, guardada em cofre; minimização automática na origem |
| **Uso para treinamento** | `[CONFIRMAR]` |

### 1.5 OpenAI, Google Gemini e Groq — extração de currículo (alternativos)

Provedores selecionáveis por organização, com a mesma minimização e o mesmo
regime do item anterior. País: **Estados Unidos** (e infraestrutura global, no
caso do Gemini). `[CONFIRMAR]` termos de cada um antes de habilitar.

### 1.6 Agora — chamadas de voz e vídeo

| Item | Conteúdo |
|------|----------|
| **Serviço** | Transporte de áudio e vídeo em tempo real |
| **Dados tratados** | Fluxo de áudio e vídeo em trânsito, identificador de canal e de participante |
| **Papel** | Operador |
| **País** | Estados Unidos e infraestrutura global |
| **Transferência internacional** | **Sim** |
| **Salvaguardas** | Acesso por token temporário emitido pelo servidor da empresa; mídia não é gravada por padrão |
| **Gravação** | `[CONFIRMAR se há gravação em nuvem habilitada]` |

### 1.7 MiroTalk SFU — salas de reunião

| Item | Conteúdo |
|------|----------|
| **Serviço** | Salas de videoconferência |
| **Dados tratados** | Fluxo de áudio e vídeo, nome de exibição, identificador de sala |
| **Papel** | Operador |
| **País** | `[CONFIRMAR]` |
| **Transferência internacional** | Provável — `[CONFIRMAR]` |
| **Risco identificado** | A configuração atual aponta para um **servidor público compartilhado** (`sfu.mirotalk.com`), não para instância dedicada da empresa. Reunião corporativa em servidor de terceiro compartilhado, sem contrato de operador, é exposição relevante |
| **Ação recomendada** | Contratar instância dedicada, hospedar servidor próprio, ou substituir por solução com contrato — **antes** de tratar assunto confidencial em reunião |

### 1.8 Servidor de e-mail (SMTP)

| Item | Conteúdo |
|------|----------|
| **Serviço** | Envio de códigos de verificação, notificações e comunicações de RH |
| **Dados tratados** | E-mail do destinatário, nome, conteúdo da mensagem |
| **Papel** | Operador |
| **Fornecedor e país** | `[CONFIRMAR — configurável por organização]` |
| **Salvaguardas** | Credenciais sob segredo; conexão criptografada `[CONFIRMAR]` |

### 1.9 Webhook de transcrição

| Item | Conteúdo |
|------|----------|
| **Serviço** | Orquestração de transcrição de reuniões |
| **Dados tratados** | Áudio de reunião e texto transcrito |
| **Papel** | Operador |
| **Fornecedor e país** | `[CONFIRMAR — endpoint configurável]` |
| **Situação** | Habilitar apenas após contrato de operador e definição de retenção |

---

## 2. Resumo de transferência internacional

| Fornecedor | Destino | Dados | Fundamento (art. 33) |
|------------|---------|-------|----------------------|
| Supabase | `[CONFIRMAR]` | Todos | Cláusulas contratuais padrão — Res. CD/ANPD nº 19/2024 `[CONFIRMAR]` |
| Google (FCM/Hosting) | EUA | Token, prévia de notificação | Cláusulas contratuais padrão |
| Groq | EUA | Trecho de conversa mascarado | Cláusulas contratuais `[CONFIRMAR]` |
| Anthropic | EUA | Currículo sem identificadores | Cláusulas contratuais `[CONFIRMAR]` |
| OpenAI / Gemini | EUA / global | Currículo sem identificadores | Cláusulas contratuais `[CONFIRMAR]` |
| Agora | EUA / global | Áudio e vídeo em trânsito | Cláusulas contratuais `[CONFIRMAR]` |
| MiroTalk | `[CONFIRMAR]` | Áudio e vídeo em trânsito | **Sem contrato identificado** |

**Fundamento legal aplicável.** A transferência internacional apoia-se no art.
33, II, "a", da LGPD — cláusulas contratuais específicas ou padrão contratuais
aprovadas pela ANPD (Resolução CD/ANPD nº 19/2024). Não há, no momento, decisão
de adequação da ANPD quanto aos países de destino envolvidos.

---

## 3. Cláusulas exigidas de todo operador (art. 39)

Todo contrato com fornecedor que trate dados pessoais em nome da empresa deve
conter:

1. Tratamento **exclusivamente** conforme instruções documentadas da controladora;
2. Vedação de uso dos dados para finalidade própria do fornecedor, inclusive
   treinamento de modelos, sem autorização expressa;
3. Vedação de subcontratação sem autorização prévia, com repasse das mesmas
   obrigações ao subcontratado;
4. Medidas técnicas e administrativas de segurança compatíveis (art. 46);
5. Confidencialidade estendida a empregados e prepostos;
6. **Comunicação de incidente em até 24 horas** da detecção;
7. Cooperação no atendimento a pedidos de titulares e a requisições da ANPD;
8. Direito de auditoria pela controladora ou por terceiro indicado, mediante
   aviso prévio;
9. Devolução ou eliminação dos dados ao término do contrato, com declaração;
10. Manutenção de registro das operações realizadas (art. 37);
11. Indicação de ponto de contato para assuntos de proteção de dados;
12. Para fornecedores no exterior: cláusulas contratuais padrão da Resolução
    CD/ANPD nº 19/2024 ou garantias equivalentes.

---

## 4. Plano de regularização

| # | Ação | Prioridade | Responsável |
|---|------|------------|-------------|
| 1 | Confirmar a região de hospedagem do banco de dados e registrar a decisão | **Alta** | TI |
| 2 | Formalizar contrato/DPA com o fornecedor de infraestrutura | **Alta** | Jurídico |
| 3 | Resolver a situação do servidor de reuniões compartilhado | **Alta** | TI + Diretoria |
| 4 | Verificar termos de uso para treinamento em cada provedor de IA | Média | Jurídico |
| 5 | Confirmar fornecedor e criptografia do serviço de e-mail | Média | TI |
| 6 | Avaliar redução da prévia de conteúdo nas notificações push | Média | TI |
| 7 | Definir situação do webhook de transcrição antes de habilitá-lo | Média | TI |
| 8 | Elaborar RIPD para transferência internacional de dados sensíveis | Média | Encarregado |

---

## 5. Controle de alterações

| Data | Versão | Mudança | Responsável |
|------|--------|---------|-------------|
| `[DATA]` | 1.0.0 | Elaboração inicial a partir do inventário técnico | `[NOME]` |

Qualquer inclusão, exclusão ou troca de fornecedor exige nova versão deste anexo
e avaliação de necessidade de comunicação aos titulares.

---

*Base legal: arts. 33 a 36, 39 e 46 da Lei nº 13.709/2018; Resolução CD/ANPD nº
19/2024. Pendente de revisão por advogado habilitado antes da vigência.*
