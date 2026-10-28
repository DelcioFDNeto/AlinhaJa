# PLATAFORMA ALINHAJÁ

**Cronograma Oficial de Implantação**

Documento de planejamento e acompanhamento do processo de implantação da plataforma AlinhaJá, com as etapas, prazos, responsáveis, entregáveis e fatores de risco.

| | |
| --- | --- |
| **Destinatário** | Equipe de implantação e responsáveis pelo projeto na contratante |
| **Modelo de referência** | Nuvem gerenciada, até 300 usuários, com os módulos de Comunicação, Operações e Helpdesk |
| **Duração padrão** | 25 dias úteis (5 semanas) do kickoff ao encerramento assistido |
| **Contagem de prazos** | Em dias úteis a partir do kickoff (D1), independentemente da data de início |

---

## 1. Estrutura da Implantação

A implantação é organizada em **seis fases**. As fases 2 e 3 correm parcialmente em paralelo, pois tratam de frentes independentes: enquanto a equipe técnica carrega usuários, a área de negócio define os fluxos de trabalho.

| Fase | Período | Objetivo |
| --- | :---: | --- |
| **0. Preparação e Alinhamento** | D1 – D3 | Definir escopo, responsáveis e coletar os dados obrigatórios |
| **1. Provisionamento e Parametrização** | D4 – D8 | Criar o ambiente da empresa e configurar a estrutura organizacional |
| **2. Acessos e Carga de Dados** | D9 – D12 | Criar usuários, perfis de acesso e importar dados existentes |
| **3. Configuração dos Módulos** | D10 – D14 | Configurar fluxos operacionais, helpdesk e demais módulos contratados |
| **4. Validação e Capacitação** | D15 – D19 | Testar com usuários reais e treinar as equipes |
| **5. Go-Live e Acompanhamento** | D20 – D25 | Liberar para toda a empresa e prestar suporte assistido |

---

## 2. Detalhamento das Etapas

### Fase 0 — Preparação e Alinhamento (D1 – D3)

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 0.1 | **Reunião de kickoff** — apresentação do processo, definição dos pontos focais de cada lado e do canal de comunicação do projeto | Conjunto | 1 dia | Ata com responsáveis e calendário |
| 0.2 | **Levantamento de escopo** — módulos contratados, número de usuários, filiais e departamentos envolvidos | Conjunto | 1 dia | Escopo aprovado |
| 0.3 | **Coleta dos dados legais (LGPD)** — razão social, CNPJ, endereço, Encarregado (DPO), e-mail do Encarregado, data de vigência e confirmação dos prazos de retenção | Cliente | 2 dias | Formulário de dados LGPD preenchido |
| 0.4 | **Coleta da identidade visual** — nome de exibição, logotipo e cores da marca | Cliente | 1 dia | Arquivos da marca |
| 0.5 | **Verificação de pré-requisitos** — lista de usuários com e-mails corporativos, aparelhos dos usuários de campo, servidor de e-mail e conectividade | Cliente | 2 dias | Checklist da seção 5 respondido |

> **Marco 1 (D3):** dados obrigatórios recebidos. *Sem esta entrega, todas as fases seguintes deslizam na mesma proporção.*

### Fase 1 — Provisionamento e Parametrização (D4 – D8)

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 1.1 | **Criação do ambiente da empresa** — provisionamento da organização isolada na plataforma | AlinhaJá | 1 dia | Ambiente ativo |
| 1.2 | **Habilitação dos módulos contratados** | AlinhaJá | 1 dia | Módulos visíveis conforme contrato |
| 1.3 | **Aplicação da identidade visual (white-label)** | AlinhaJá | 1 dia | Ambiente com a marca da empresa |
| 1.4 | **Preenchimento dos dados legais** — publicação dos 12 documentos de privacidade já preenchidos | AlinhaJá | 1 dia | Documentos legais em vigor |
| 1.5 | **Cadastro da estrutura organizacional** — filiais, departamentos e cargos | Conjunto | 2 dias | Organograma cadastrado |
| 1.6 | **Verificação de parâmetros gerais** — prazos de retenção, políticas de notificação e preferências do sistema | AlinhaJá | 1 dia | Relatório de parâmetros conferidos |

> **Marco 2 (D8):** ambiente configurado e documentos legais publicados.

### Fase 2 — Acessos e Carga de Dados (D9 – D12)

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 2.1 | **Definição dos perfis de acesso** — quais permissões cada perfil terá em cada módulo | Conjunto | 1 dia | Matriz de permissões aprovada |
| 2.2 | **Ajuste dos perfis no sistema** — configuração dos perfis padrão e criação de perfis personalizados | AlinhaJá | 1 dia | Perfis configurados |
| 2.3 | **Criação dos logins** — cadastro dos usuários vinculados a filial, departamento, cargo e perfil | AlinhaJá | 2 dias | Usuários criados e credenciais entregues |
| 2.4 | **Importação de dados existentes** — quando aplicável: base de funcionários, candidatos ou histórico operacional | AlinhaJá | 2 dias | Dados importados e conferidos |
| 2.5 | **Conferência da carga** — validação por amostragem com a área responsável | Conjunto | 1 dia | Relatório de conferência |

> **Marco 3 (D12):** todos os usuários criados e dados importados.

### Fase 3 — Configuração dos Módulos (D10 – D14)

Executada em paralelo à Fase 2, com a participação das áreas de negócio.

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 3.1 | **Canais e workspaces de comunicação** — criação dos canais por filial, departamento e finalidade | Conjunto | 1 dia | Canais criados com membros |
| 3.2 | **Fluxos de trabalho (Kanban)** — definição das etapas de cada fluxo, modo de atribuição, operadores e prazos de SLA | Conjunto | 2 dias | Fluxos operacionais ativos |
| 3.3 | **Central de chamados (Helpdesk)** — categorias, filas e responsáveis por área | Conjunto | 1 dia | Helpdesk configurado |
| 3.4 | **Módulo de RH** *(se contratado)* — catálogo de áreas e cargos, etapas do funil, modelos de onboarding, catálogo de benefícios e página de carreiras | Conjunto | 3 dias | Módulo de RH configurado |
| 3.5 | **Integrações** — servidor de e-mail, chave de Inteligência Artificial e automações de comunicação | Conjunto | 1 dia | Integrações testadas |
| 3.6 | **Rastreamento por GPS** *(se aplicável)* — definição das funções sujeitas a rastreamento e do termo de consentimento | Conjunto | 1 dia | Rastreamento parametrizado |

> **Marco 4 (D14):** todos os módulos contratados configurados e operacionais.

### Fase 4 — Validação e Capacitação (D15 – D19)

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 4.1 | **Testes internos** — verificação de acesso, permissões por perfil, notificações, chamadas e fluxos ponta a ponta | AlinhaJá | 2 dias | Relatório de testes |
| 4.2 | **Piloto assistido** — grupo reduzido de usuários-chave opera o sistema em situação real | Conjunto | 3 dias | Registro de ajustes solicitados |
| 4.3 | **Ajustes decorrentes do piloto** | AlinhaJá | 2 dias | Ajustes aplicados |
| 4.4 | **Treinamento por perfil** — sessões separadas para administradores, gestores, operadores, RH e colaboradores | AlinhaJá | 2 dias | Equipes treinadas |
| 4.5 | **Validação formal do cliente** — aceite das configurações antes da liberação geral | Cliente | 1 dia | Termo de validação assinado |

> **Marco 5 (D19):** sistema validado e equipes treinadas. *Este é o ponto de decisão do go-live.*

### Fase 5 — Go-Live e Acompanhamento (D20 – D25)

| # | Etapa | Responsável | Duração | Entregável |
| :---: | --- | --- | :---: | --- |
| 5.1 | **Comunicado interno de lançamento** — anúncio oficial aos colaboradores, com orientações de primeiro acesso | Cliente | 1 dia | Comunicado enviado |
| 5.2 | **Distribuição do aplicativo** — liberação do acesso web e instalação do aplicativo nos dispositivos | Conjunto | 1 dia | Aplicativo distribuído |
| 5.3 | **Liberação geral (go-live)** — abertura do sistema a todos os usuários | AlinhaJá | 1 dia | Sistema em produção |
| 5.4 | **Suporte assistido** — acompanhamento reforçado nos primeiros dias de operação | AlinhaJá | 5 dias | Registro de atendimentos |
| 5.5 | **Reunião de encerramento** — indicadores de adoção, pendências e transição para o suporte de rotina | Conjunto | 1 dia | Relatório de encerramento |

> **Marco 6 (D25):** implantação encerrada e projeto transferido para o suporte de rotina.

---

## 3. Cronograma Consolidado

| Etapa | Sem. 1 | Sem. 2 | Sem. 3 | Sem. 4 | Sem. 5 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Fase 0 — Preparação e alinhamento | ███ | | | | |
| Fase 1 — Provisionamento e parametrização | ██ | ███ | | | |
| Fase 2 — Acessos e carga de dados | | ███ | ██ | | |
| Fase 3 — Configuração dos módulos | | ██ | ███ | | |
| Fase 4 — Validação e capacitação | | | ██ | ███ | |
| Fase 5 — Go-live e acompanhamento | | | | ██ | ███ |

**Entregas por semana:**

| Semana | Entrega ao cliente |
| :---: | --- |
| 1 | Escopo aprovado e ambiente da empresa criado |
| 2 | Documentos legais publicados e estrutura organizacional cadastrada |
| 3 | Usuários com acesso e módulos configurados |
| 4 | Sistema validado no piloto e equipes treinadas |
| 5 | Sistema em produção e projeto encerrado |

---

## 4. Matriz de Responsabilidades

| Frente | AlinhaJá | Cliente |
| --- | --- | --- |
| Provisionamento do ambiente e módulos | Executa | Aprova o escopo |
| Dados legais e LGPD | Aplica no sistema | **Fornece e valida** |
| Estrutura organizacional | Cadastra | **Define e confere** |
| Perfis de acesso e permissões | Configura | **Define quem acessa o quê** |
| Criação de usuários | Executa | **Fornece a lista com e-mails corporativos** |
| Importação de dados | Executa | **Fornece as bases e confere** |
| Fluxos de trabalho e helpdesk | Configura e orienta | **Define as regras do negócio** |
| Testes e piloto | Conduz | **Disponibiliza os usuários-chave** |
| Treinamento | Ministra | **Garante a presença das equipes** |
| Comunicação interna aos colaboradores | Fornece o material | **Divulga internamente** |
| Distribuição do aplicativo | Disponibiliza | **Instala nos dispositivos** |
| Suporte pós-go-live | Presta | Aciona pelos canais definidos |

---

## 5. Pré-Requisitos a Cargo do Cliente

Os itens abaixo são condições para o início ou o avanço das fases. Os marcados como **bloqueantes** interrompem o cronograma enquanto não forem atendidos.

| Item | Necessário até | Situação |
| --- | :---: | :---: |
| **Dados legais e LGPD** (razão social, CNPJ, endereço, Encarregado, e-mail do Encarregado, vigência) — *bloqueante* | D3 | ( ) |
| **Confirmação dos prazos de retenção** de dados | D3 | ( ) |
| **Identidade visual** (logotipo e cores) | D3 | ( ) |
| **Lista de usuários** com nome, e-mail corporativo, filial, departamento e cargo — *bloqueante* | D8 | ( ) |
| **Definição da estrutura organizacional** (filiais, departamentos e cargos) — *bloqueante* | D6 | ( ) |
| **Indicação dos administradores** do sistema | D6 | ( ) |
| **Bases de dados a importar** (funcionários, candidatos ou histórico), em formato tabular | D10 | ( ) |
| **Definição dos fluxos de trabalho** e das categorias de chamados | D10 | ( ) |
| **Credenciais do servidor de e-mail** (SMTP), se a comunicação usar o domínio próprio | D12 | ( ) |
| **Chave de Inteligência Artificial**, se os recursos de IA forem utilizados | D12 | ( ) |
| **Indicação dos usuários-chave** para o piloto | D14 | ( ) |
| **Agenda de treinamento** confirmada com as equipes | D14 | ( ) |
| **Dispositivos dos usuários de campo** com sistema atualizado e espaço disponível | D18 | ( ) |

---

## 6. Fatores que Podem Impactar o Cronograma

| Fator | Impacto | Como mitigar |
| --- | :---: | --- |
| **Atraso no envio dos dados legais** | Alto — impede a publicação dos documentos e o go-live | Solicitar na reunião de kickoff, com prazo formal em D3 |
| **Lista de usuários incompleta ou com e-mails inválidos** | Alto — impede a criação dos acessos | Validar o arquivo antes da carga; exigir e-mail corporativo por usuário |
| **Indefinição do Encarregado (DPO)** | Alto — bloqueia a vigência dos documentos | Antecipar a decisão com a diretoria já no kickoff |
| **Estrutura organizacional indefinida ou em reformulação** | Alto — o roteamento de chamados e demandas depende dela | Congelar a estrutura vigente para a implantação; ajustes ficam para depois |
| **Regras de negócio não decididas** (etapas dos fluxos, responsáveis, prazos) | Médio — atrasa a configuração dos módulos | Definir com a área de negócio antes da Fase 3 |
| **Bases de dados inconsistentes** (duplicidades, campos faltantes) | Médio — exige tratamento antes da importação | Conferência prévia por amostragem |
| **Indisponibilidade dos usuários-chave** no piloto | Médio — compromete a validação | Reservar as agendas na Fase 0 |
| **Baixa adesão ao treinamento** | Médio — gera chamados evitáveis após o go-live | Presença registrada; material de apoio disponível no próprio sistema |
| **Restrições de rede ou bloqueio de aplicativos** | Médio — impede acesso ou notificações | Levantar com a TI do cliente na Fase 0 |
| **Dispositivos sem permissão de localização em segundo plano** | Médio — afeta apenas o rastreamento de campo | Orientação na instalação e conferência no piloto |
| **Ausência de servidor de e-mail configurado** | Baixo — afeta apenas as comunicações automáticas | Uso do serviço padrão até a liberação do domínio próprio |
| **Período de pico operacional ou férias coletivas** | Médio — reduz a disponibilidade das equipes | Evitar go-live em fechamento de mês ou pico sazonal |

---

## 7. Governança e Comunicação

O acompanhamento do cliente é contínuo e formalizado nos seguintes rituais:

| Ritual | Frequência | Participantes | Conteúdo |
| --- | :---: | --- | --- |
| **Reunião de kickoff** | Única, em D1 | Diretoria, TI e áreas envolvidas | Escopo, responsáveis, calendário e pré-requisitos |
| **Relatório de progresso** | Semanal | Ponto focal do cliente | Etapas concluídas, próximas etapas, pendências e riscos |
| **Reunião de checkpoint** | Ao fim de cada fase | Pontos focais | Validação do marco e liberação da fase seguinte |
| **Canal do projeto** | Contínuo | Equipe de implantação | Dúvidas e solicitações do dia a dia |
| **Comunicado de go-live** | Única, em D20 | Todos os colaboradores | Anúncio oficial e orientações de primeiro acesso |
| **Reunião de encerramento** | Única, em D25 | Diretoria e pontos focais | Indicadores de adoção, pendências e transição ao suporte |

**Registro de pendências:** cada solicitação identificada durante a implantação é registrada com responsável e prazo, e acompanhada até a conclusão no relatório semanal.

---

## 8. Critérios para Liberação do Go-Live

A liberação geral do sistema ocorre somente quando todos os critérios abaixo estiverem atendidos:

- [ ] Documentos legais publicados e em vigor
- [ ] Estrutura organizacional cadastrada e conferida
- [ ] Todos os usuários criados, com perfil de acesso atribuído
- [ ] Dados importados e validados por amostragem
- [ ] Fluxos de trabalho e categorias de chamados configurados
- [ ] Testes de acesso, permissões e notificações aprovados
- [ ] Piloto concluído, com os ajustes aplicados
- [ ] Equipes treinadas, com registro de participação
- [ ] Aplicativo distribuído aos usuários
- [ ] Validação formal do cliente registrada

---

## 9. Variações de Prazo

O cronograma padrão considera a implantação em nuvem, com os módulos de Comunicação, Operações e Helpdesk. As situações abaixo alteram a duração:

| Situação | Impacto no prazo |
| --- | --- |
| Módulo de RH completo (recrutamento, gestão de pessoas e onboarding) | + 5 a 10 dias úteis |
| Importação de base histórica volumosa ou com tratamento necessário | + 3 a 5 dias úteis |
| Mais de 500 usuários ou mais de 5 filiais | + 5 dias úteis |
| Implantação em servidor próprio (on-premise) | + 15 a 25 dias úteis |
| Distribuição para dispositivos Apple (iOS) | + 5 dias úteis |
| Implantação por filial, em etapas sucessivas | + 3 a 5 dias úteis por filial |

---

*AlinhaJá — Cronograma Oficial de Implantação. As datas são expressas em dias úteis a partir do kickoff e podem ser convertidas em calendário na reunião de abertura do projeto.*
