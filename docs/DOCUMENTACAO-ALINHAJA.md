# PLATAFORMA ALINHAJÁ

**Documentação Oficial — Visão Comercial, Operacional e de Usuário Corporativo**

---

# PARTE 1 — APRESENTAÇÃO DA PLATAFORMA

O que é o AlinhaJá, como se organiza em módulos e quais são seus diferenciais.

## Introdução ao AlinhaJá

O **AlinhaJá** é uma plataforma corporativa completa que reúne, em um único sistema, **comunicação oficial, gestão de demandas (Kanban com SLA), central de chamados (Helpdesk), videoconferências, Recursos Humanos com Inteligência Artificial e rastreamento de equipes em campo (GPS)**.

Diferente de ferramentas de conversação convencionais — nas quais as tarefas se perdem entre mensagens, sem prazo e sem responsável definido — o AlinhaJá transforma solicitações em **cards acionáveis**: cada demanda nasce com um responsável explícito, um canal de conversa dedicado, um cronômetro de SLA (Acordo de Nível de Serviço) e um **histórico imutável**, pronto para auditoria.

A plataforma é **multiempresa por natureza**: cada organização opera em um ambiente totalmente isolado, com seus próprios usuários, dados, permissões, identidade visual e módulos contratados. Essa arquitetura atende desde uma única empresa até grupos com diversas unidades de negócio independentes.

### Os 4 Pilares do Sistema

- **Organização:** demandas operacionais, de TI e de RH estruturadas em fluxos configuráveis pela própria empresa, com formulários específicos para cada tipo de solicitação.
- **Transparência:** visibilidade completa sobre prioridades, responsáveis, andamento e tempo restante de SLA, sem necessidade de consultas paralelas.
- **Segurança:** auditoria de todas as ações, permissões por perfil e por módulo, autenticação em duas etapas, mídias em armazenamento privado e isolamento completo entre empresas e filiais.
- **Inteligência:** IA integrada à rotina — triagem de currículos, geração de avaliações técnicas e um assistente virtual interno, sempre com remoção de dados pessoais antes do processamento.

## Arquitetura Modular

O AlinhaJá é organizado em **módulos independentes**, agrupados por área de negócio. A empresa contrata apenas o que utiliza: módulos não licenciados permanecem invisíveis na interface, mantendo a experiência limpa para todos os usuários. Novos módulos podem ser habilitados a qualquer momento, sem reinstalação e sem interrupção do serviço.

### Base da Plataforma (incluída em todos os planos)

| Área | Módulos |
| --- | --- |
| **Comunicação** | Canais · Conversas · Chamadas |
| **Administração** | Painel Administrativo · Comunicação e Automações |

### Módulos Licenciáveis

| Área | Módulos |
| --- | --- |
| **Recursos Humanos** | Banco de Talentos · Funcionários · Documentos · Ausências e Férias · Onboarding · Alertas de RH · Holerites · Controle de Ponto · Benefícios · Desempenho |
| **Suporte** | Central de Ajuda · Helpdesk de TI |
| **Operações** | Workflow Kanban · Rastreamento GPS |

Cada módulo possui suas próprias permissões de **visualização** e **gerenciamento**, atribuídas por perfil de acesso — o que permite, por exemplo, que um gestor acompanhe o Controle de Ponto da equipe sem acessar Holerites ou o Banco de Talentos.

## Comunicação e Colaboração

A comunicação no AlinhaJá é separada da operação, mas totalmente integrada a ela.

- **Canais e Workspaces:** canais podem ser abertos à empresa, restritos a membros ou **privados** — um workspace privado não aparece para quem não participa, nem pelo nome, o que viabiliza espaços reservados para RH, jurídico ou diretoria. Em canais restritos e privados, a entrada ocorre apenas por convite ou por solicitação aprovada por quem administra aquele canal.
- **Canais de Aviso:** canais configurados como somente leitura, em que apenas administradores publicam. A regra é aplicada no servidor, não apenas na interface.
- **Conversas e Grupos:** mensagens diretas e grupos com gestão completa de participantes, foto e descrição — a praticidade de um aplicativo de mensagens, com a governança que a empresa exige.
- **Mensagens Completas:** texto com formatação, fotos, vídeos, mensagens de voz, documentos, enquetes, comunicados, eventos de agenda e cartões de contato com atalho para iniciar conversa.
- **Responder, Citar, Encaminhar e Editar:** qualquer mensagem pode ser respondida com citação ou encaminhada para outra conversa, grupo ou canal. Mensagens próprias em canais podem ser corrigidas e passam a exibir a marcação "editado".
- **Recibos de Entrega e Leitura:** indicadores de envio, entrega e leitura em tempo real. Em grupos e canais, a opção **Informações da Mensagem** mostra quem já leu, quem recebeu e quem ainda não recebeu.
- **Notificações Inteligentes:** foto de quem enviou, mensagens agrupadas por conversa, destaque quando o usuário é mencionado e opções de **responder ou marcar como lida direto na notificação**, sem abrir o aplicativo. Em cada canal, o usuário escolhe receber todas as mensagens, apenas menções ou nenhuma; as menções **@canal** e **@aqui** alcançam o grupo inteiro.
- **Quadro Branco Colaborativo:** lousa compartilhada em tempo real, com caneta, borracha, cores, inserção de imagens e arquivos e reposicionamento de elementos.
- **Busca Global:** a pesquisa encontra conversas, mensagens de canais e cards de demandas em um único lugar.
- **Mídias de Visualização Única:** fotos e vídeos enviados nesse modo são apagados do servidor logo após a primeira abertura.
- **Termo "Estou Ciente":** para comunicados críticos, gestores podem enviar avisos que permanecem em tela até que o usuário confirme formalmente a leitura, com registro de data e hora na auditoria.
- **Videoconferências Integradas:** chamadas individuais de áudio e vídeo (com toque e vibração no celular, inclusive em segundo plano) e **Salas de Reunião coletivas**, sem limite de participantes ou de duração. Inclui histórico de chamadas e aviso de chamadas perdidas.
- **Assistente Virtual (IA):** contato de sistema disponível na lista de conversas, que esclarece dúvidas sobre RH, TI e processos internos, resume conversas sob demanda e pode ser especializado por área. Dados pessoais, como CPF e e-mail, são removidos das mensagens antes do envio ao modelo de IA.

## Operações, Processos e Mobilidade

A estrutura operacional do AlinhaJá combina o acompanhamento de tarefas com o rastreamento de equipes externas.

- **Workflow Kanban:** cada tarefa é um cartão digital com formulário próprio por tipo de solicitação (por exemplo, pagamentos, faturamento, compras ou manutenção). O progresso é acompanhado em três modos: **Quadro** com arrastar e soltar, **Lista** com foco em prazos de SLA e **Compacta** para alto volume.
- **Workspaces Configuráveis:** a própria empresa cria **modelos de workspace** reutilizáveis — com identidade visual, formulário do card, modo de atribuição e etapas — e pode alterar as etapas de um fluxo a qualquer momento. Ao remover uma etapa que ainda contém cards, o sistema pergunta para onde movê-los e registra a mudança; nenhuma demanda fica perdida.
- **Etapas com Significado:** cada fluxo indica qual etapa abre, qual conclui e qual cancela a demanda, independentemente do nome escolhido, garantindo SLA e indicadores corretos.
- **Filas de Atendimento:** cada fluxo pode operar com um responsável fixo ou com uma equipe cujos operadores **assumem os atendimentos** a partir de uma fila — evitando distribuição aleatória e demandas sem responsável.
- **Minha Operação:** tela que reúne todos os cards atribuídos ao usuário em todos os workspaces, separados em atrasados, do dia e próximos.
- **SLA e Prioridades:** quatro níveis de prioridade, indicador visual de prazo excedido e painel operacional com totais, valores e situação de cada etapa.
- **Histórico à Prova de Atalhos:** toda mudança de etapa, troca de responsável ou arquivamento é registrada pelo próprio banco de dados, por qualquer caminho que a alteração percorra.
- **Central de Chamados (Helpdesk):** módulo dedicado a suporte de TI, manutenção e chamados corporativos. Cada ticket gera um chat exclusivo entre o solicitante e o técnico responsável.
- **GPS e Rastreamento de Campo:** para equipes externas, o aplicativo Android registra a localização em tempo real, apoiando a roteirização. O rastreamento depende do **consentimento explícito** do colaborador, que pode revogá-lo e solicitar a eliminação do histórico; o serviço suspende o envio de coordenadas quando o aparelho está parado, preservando a bateria.
- **Multiplataforma:** o AlinhaJá funciona no **Android** (aplicativo instalável), no **iPhone** (aplicativo web instalado na Tela de Início, com notificações), no navegador e em computadores, com layout adaptável a qualquer tela. Mensagens enviadas sem conexão entram em fila e são sincronizadas no retorno da internet, e as atualizações chegam automaticamente a todos.
- **Adoção Facilitada:** no primeiro acesso, um **tour guiado interativo** apresenta a plataforma módulo a módulo, exibindo apenas o que o perfil do usuário pode acessar. A **Central de Ajuda** reúne perguntas frequentes, guias passo a passo, manual pesquisável e abertura de chamados, e as mensagens de erro do sistema orientam o que fazer em linguagem clara.

## Recursos Humanos

Um departamento de RH completo dentro da plataforma — do anúncio da vaga à gestão do dia a dia do funcionário:

- **Central de Recrutamento:** hub único com visão geral (indicadores e gráficos), pipeline de seleção, divulgação, vagas, avaliações técnicas e configurações.
- **Divulgação e Portal de Vagas:** página de carreiras pública com a marca da empresa, link compartilhável por WhatsApp e e-mail e **QR Code** para materiais impressos, protegida contra tentativas automatizadas de acesso.
- **Pipeline de Seleção (ATS):** funil visual com **etapas configuráveis pela própria empresa**, responsável por candidato, alerta de tempo parado em etapa, pontuação, filtros e ações em massa.
- **Triagem com Inteligência Artificial:** currículos em PDF ou Word são lidos automaticamente; a IA extrai formação, experiências e habilidades e preenche a ficha do candidato.
- **Avaliação Técnica com IA:** banco de questões por cargo — criadas manualmente ou **geradas por IA** — com prova objetiva, **tempo limite configurável** e correção automática no servidor.
- **Portal do Candidato:** o candidato cria sua conta, acompanha as candidaturas em tempo real, reaproveita o currículo já enviado, recebe mensagens do RH e realiza avaliações.
- **Gestão de Pessoas:** controle de ponto com horário registrado pelo servidor, holerites com recibo de visualização, benefícios, **saldo de férias com calendário** e avaliações de desempenho por ciclos com metas e feedback 360°.
- **Ficha do Funcionário:** candidatos aprovados são convertidos em funcionários em uma única ação. Dados sensíveis (CPF, salário, dados bancários, histórico salarial, dependentes) são **criptografados**, e todo acesso a essas informações é registrado.
- **Onboarding Estruturado:** checklists de integração por modelo, com etapas atribuídas ao RH, ao gestor ou **ao próprio funcionário**, que conclui suas tarefas pelo aplicativo.
- **Documentos com Aceite:** documentos podem exigir **aceite eletrônico** do funcionário, com registro de quem aceitou, quando e de onde.
- **Comunicação Automatizada:** e-mails automáticos ao candidato a cada avanço no processo seletivo, com modelos personalizáveis e envio pelo servidor de e-mail da própria empresa.
- **Permissões por Módulo:** Banco de Talentos, Funcionários, Onboarding, Documentos, Ponto e Holerites têm permissões independentes de visualização e gestão.

## Privacidade e LGPD

A conformidade com a Lei Geral de Proteção de Dados é parte da plataforma, não um complemento.

- **Pacote Legal Completo:** doze documentos — Termos de Uso, Política de Privacidade, Monitoramento, Consentimento de Geolocalização, Aviso aos Candidatos, Cookies, Uso de IA, Retenção e Descarte, Resposta a Incidentes, Registro das Operações de Tratamento, Suboperadores e Termo de Ciência — **preenchidos automaticamente com os dados de cada empresa**. Enquanto faltar algum dado cadastral, o leitor sinaliza o campo pendente em vez de exibir um documento aparentemente completo.
- **Aceite Obrigatório Auditado:** o usuário só acessa o sistema após aceitar os termos vigentes, com registro da versão e do momento do aceite.
- **Central de Privacidade e Dados:** cada colaborador exporta seus próprios dados em um clique e abre solicitações formais de correção, eliminação ou informação, acompanhadas dentro do aplicativo com o prazo legal de resposta.
- **Consentimento de Geolocalização:** o rastreamento só ocorre com aceite do colaborador, que pode revogá-lo a qualquer momento; o gestor acompanha a situação dos consentimentos da equipe.
- **Retenção Configurável:** prazos de guarda para localização, candidatos e mensagens definidos pela empresa, com descarte automático por rotina diária.
- **Backup Cifrado de Ponta a Ponta:** cada usuário pode guardar uma cópia de suas conversas na nuvem, cifrada no próprio aparelho com uma senha que só ele conhece — nem a empresa nem o suporte conseguem abri-la. Aparelhos perdidos podem ser revogados, apagando no mesmo ato as cópias originadas deles.

## Segurança, Governança e Estrutura Corporativa

O AlinhaJá foi projetado para operações de grande escala, nas quais a governança de dados é requisito essencial.

- **Matriz de Permissões (RBAC) Configurável:** a visibilidade e as ações permitidas dependem do perfil do usuário (Super Admin, Administrador, Gestor, Colaborador e perfis personalizados, como RH). O administrador ajusta as permissões de cada perfil, módulo a módulo, em uma tela visual.
- **Módulos sob Contrato:** cada organização ativa apenas os módulos contratados — funcionalidades não licenciadas permanecem invisíveis para todos os usuários daquela empresa.
- **Autenticação em Duas Etapas (2FA):** login protegido por código de aplicativo autenticador, validado no servidor.
- **Acesso Exclusivamente Corporativo:** os usuários são provisionados pela empresa com senha temporária, **trocada obrigatoriamente no primeiro acesso**. Uma conta solicitada pelo próprio aplicativo só é liberada após a aprovação de um administrador. O desligamento de um funcionário revoga o acesso imediatamente em todos os dispositivos.
- **Sessão Protegida:** encerramento automático após 30 minutos de inatividade e limpeza dos dados guardados no aparelho ao sair da conta.
- **Mídias Privadas:** fotos, vídeos, áudios e documentos ficam em armazenamento privado e são entregues por links temporários, válidos apenas para quem participa da conversa.
- **Dados Pessoais Restritos:** CPF e telefone de colaboradores só são acessíveis pelo próprio titular ou por administradores, em consulta registrada na auditoria.
- **Organograma e Workspaces Isolados:** Filiais, Departamentos e Cargos são gerenciados pelo painel administrativo, garantindo que a comunicação e os dados de unidades diferentes não se misturem e que cada chamado chegue ao setor correto.
- **Isolamento Multiempresa:** empresas distintas na mesma plataforma jamais acessam dados umas das outras — o isolamento é garantido no servidor, em todas as camadas.
- **Identidade Própria (White-Label):** nome, cores, temas e identidade visual configuráveis por empresa.
- **Auditoria:** toda operação relevante — mudança de etapa, criação de canais, entrada e saída de membros, envio de arquivos, alteração de permissões, acesso a dados sensíveis, backups — é registrada em log protegido contra adulteração.

## Perguntas Frequentes

**O aplicativo funciona no iPhone?**
Sim. No iPhone, o AlinhaJá é instalado pelo Safari, na opção Compartilhar → Adicionar à Tela de Início, e passa a funcionar como aplicativo, com notificações. No Android, há aplicativo instalável; em computadores, o acesso é pelo navegador.

**O aplicativo Android consome muita bateria com o GPS ativo?**
Não. Quando o dispositivo permanece parado por mais de 5 minutos, o envio de coordenadas é suspenso e retomado automaticamente ao detectar movimento.

**O que acontece se um celular for perdido ou roubado?**
O administrador desativa o acesso do usuário, encerrando as sessões em todos os aparelhos — e, de todo modo, a sessão se encerra sozinha após 30 minutos sem uso. O próprio usuário também pode revogar o dispositivo, o que apaga as cópias de backup originadas dele.

**É necessário instalar atualizações manualmente?**
Não. A plataforma verifica novas versões automaticamente e orienta o usuário quando há atualização, garantindo que toda a equipe opere na mesma versão.

**A empresa precisa contratar todos os módulos?**
Não. Os módulos são licenciados individualmente. Comunicação e Administração acompanham qualquer contratação; os demais são habilitados conforme a necessidade e ficam ocultos quando não contratados.

**A IA acessa dados pessoais?**
Não. Antes de qualquer processamento, dados de identificação são removidos do texto — tanto nos currículos quanto nas mensagens ao assistente. A empresa escolhe **qual provedor de IA utilizar** (Claude, GPT, Gemini ou Llama), com a própria chave, mantendo controle e previsibilidade de custo.

**A empresa consegue ler o backup das conversas de um colaborador?**
Não. O backup é cifrado no aparelho com uma senha pessoal, e o servidor guarda apenas o arquivo ilegível. O acesso corporativo a conversas, quando necessário, ocorre pela Moderação, com justificativa registrada na auditoria.

> Regras de negócio específicas e guias avançados de configuração estão disponíveis na Central de Ajuda do sistema e no Assistente Virtual, dentro do próprio aplicativo.

---

# PARTE 2 — GUIA DO COLABORADOR

Comunicação, reuniões, chamados, demandas, privacidade e autoatendimento de RH.

## 1. Primeiro Acesso

- **Instalação:** no Android, instale o aplicativo fornecido pela empresa. No iPhone, abra o endereço no Safari e toque em **Compartilhar → Adicionar à Tela de Início** — é essa instalação que permite ao iPhone entregar notificações. Em computadores, use o navegador.
- **Troca de Senha:** a empresa entrega uma senha temporária. No primeiro login, o sistema exige o cadastro de uma senha pessoal antes de liberar o acesso.
- **Aceite dos Termos:** antes de usar o sistema, o colaborador lê e aceita os termos de uso e a política de privacidade da empresa. O aceite fica registrado.
- **Tour Guiado:** um tour interativo apresenta os módulos disponíveis para o seu perfil e pode ser revisto a qualquer momento pela Central de Ajuda.
- **Notificações:** no Android, aceite o pedido de permissão na primeira abertura. No navegador e no iPhone, use o botão **Ativar notificações** em Configurações → Notificações.

## 2. Perfil, Conta e Preferências

- **Redefinição de Senha:** a opção "Esqueci minha senha" envia o link de recuperação para o e-mail cadastrado.
- **Segurança em Duas Etapas (2FA):** em Configurações → Segurança, a verificação em duas etapas é ativada pela leitura de um QR Code com um aplicativo autenticador. A partir daí, o login solicita também um código de 6 dígitos.
- **Sessão:** por segurança, a sessão é encerrada após 30 minutos sem uso.
- **Temas:** Claro, Escuro ou Automático, além de dois estilos visuais de conversa.
- **Notificações:** configuração de alertas por tipo, opção de Não Perturbe e preferência individual por conversa ou canal.
- **Dados Corporativos:** a seção "Meu Perfil" apresenta Filial, Departamento e Cargo do usuário.

## 3. Comunicação, Reuniões e Colaboração

- **Conversas e Colegas:** a lista de colegas é organizada por Filial e Departamento e indica quem está online. Canais restritos aceitam **solicitação de entrada**; se o pedido for recusado, o solicitante é avisado.
- **Envio de Conteúdo:** textos, fotos, vídeos, documentos e mensagens de voz. As fotos recentes do celular aparecem em uma faixa de acesso rápido, com seleção múltipla e pré-visualização antes do envio.
- **Responder, Encaminhar e Editar:** tocar e segurar uma mensagem abre as opções de responder com citação, encaminhar, consultar quem leu e, em canais, editar o próprio texto.
- **Leitura e Entrega:** os indicadores mostram se a mensagem foi enviada, entregue e lida. Ao reabrir um canal, uma marcação indica onde a leitura parou.
- **Responder pela Notificação:** é possível responder ou marcar como lida direto na notificação, sem abrir o aplicativo.
- **Notificações por Canal:** no sino de cada canal, escolha entre todas as mensagens, apenas menções ou silenciado.
- **Quadro Branco:** lousa colaborativa em tempo real para desenhar, inserir imagens e organizar ideias com a equipe.
- **Avisos Importantes (Termo "Estou Ciente"):** comunicados críticos permanecem em tela até a confirmação de leitura, registrada eletronicamente.
- **Videoconferências:** chamadas de áudio ou vídeo iniciadas pelo chat privado e Salas de Reunião coletivas nos canais de equipe.

## 4. Assistente Virtual (IA)

O contato **Assistente IA** está disponível na lista de conversas:

- Esclarece dúvidas sobre RH, TI, processos e funcionamento do sistema.
- Resume conversas longas sob demanda.
- Em grupos, é acionado pela menção **@assistente** ou por resposta direta a uma de suas mensagens.
- Responde com objetividade e informa quando não possui a resposta.

## 5. Abertura de Solicitações (Helpdesk)

- **Abertura de Chamado:** no menu Helpdesk, a opção "Novo Ticket" registra a solicitação, com categoria, urgência e descrição da ocorrência.
- **Acompanhamento:** cada chamado ganha um chat exclusivo com o técnico responsável, até a resolução.

## 6. Acompanhamento de Demandas (Kanban)

- **Visualização:** os cards avançam pelas colunas do fluxo conforme o trabalho da equipe, indicando responsável e prazo restante. A visualização alterna entre Quadro, Lista e Compacta.
- **Minha Operação:** pelo menu da tela inicial, reúne em um só lugar tudo o que está sob sua responsabilidade, separado em atrasados, do dia e próximos.
- **Busca:** a pesquisa global encontra cards e mensagens de canais, além das conversas.

> **Observação:** a movimentação, edição e exclusão de cards são restritas às equipes operacionais e de gestão. Quem abriu a solicitação acompanha todo o andamento e pode comentar após a conclusão.

## 7. Autoatendimento de RH

- **Meu Ponto:** registro das batidas do dia pelo aplicativo, com o horário marcado pelo servidor e espelho dos últimos dias.
- **Meus Holerites:** acesso aos holerites em PDF por competência; a visualização fica registrada para a empresa.
- **Minhas Ausências e Férias:** solicitação e acompanhamento de férias, faltas e afastamentos, com consulta ao saldo de dias disponíveis.
- **Meus Documentos:** envio de documentos solicitados pelo RH, acompanhamento do status e **aceite eletrônico** quando exigido. Documentos com validade são monitorados, com aviso antes do vencimento.
- **Meu Onboarding:** acompanhamento do checklist de integração, com conclusão das etapas sob responsabilidade do colaborador.
- **Meu Desempenho:** consulta às avaliações recebidas, às metas do ciclo e ao resultado consolidado do feedback 360°, sempre anônimo quanto aos avaliadores.

## 8. Privacidade e Dados

Em **Configurações → Privacidade e Dados**:

- **Documentos Legais:** consulta aos termos e políticas vigentes da empresa.
- **Exportar Meus Dados:** arquivo com os dados pessoais, mensagens enviadas e histórico do titular, gerado em um clique.
- **Solicitações de Direitos:** abertura e acompanhamento de pedidos de correção, eliminação ou informação sobre os próprios dados.
- **Backup e Restauração:** cópia das conversas na nuvem, cifrada com uma senha pessoal. **Sem essa senha, o backup é irrecuperável** — nem a empresa nem o suporte conseguem abri-lo. O backup automático diário, apenas em Wi-Fi, é opcional e vem desligado.
- **Dispositivos:** consulta aos aparelhos que geraram backups e revogação de um deles em caso de perda ou furto.

## 9. Equipes em Campo (Rastreamento GPS)

- **Consentimento:** o rastreamento só começa após o aceite do colaborador, que pode revogá-lo a qualquer momento e solicitar a eliminação do histórico.
- **Ativação:** no menu lateral do aplicativo Android, aba Rastreamento.
- **Permissão Necessária:** para funcionar em segundo plano, a permissão de localização do AlinhaJá deve estar como **"Sempre Permitir"** nas configurações do Android.
- **Consumo de Bateria:** paradas superiores a 5 minutos suspendem o GPS temporariamente, que é reativado ao detectar movimento.

---

# PARTE 3 — MANUAL DO OPERADOR

Execução de demandas no Kanban e resolução de chamados no Helpdesk.

## 1. Gestão do Workflow (Painel Kanban)

O painel Kanban é o ambiente principal de trabalho do operador — onde as tarefas são criadas, executadas e finalizadas.

- **Criação de Demandas:** a opção "+ Novo Card" abre o formulário configurado para cada tipo de solicitação (por exemplo, um pedido de pagamento solicita fornecedor, valor e vencimento), garantindo que a demanda chegue completa. A prioridade é classificada como Baixa, Média, Alta ou Urgente.
- **Assumir Atendimento:** em fluxos operados por equipe, os novos cards entram em uma fila. Ao selecionar **"Assumir Atendimento"**, o operador torna-se o responsável formal pela demanda.
- **Aviso de Atribuição:** quando um card é atribuído ao operador, a notificação toca com som e abre o canal correspondente.
- **Movimentação e Histórico:** o card é arrastado para a coluna correspondente ao avanço do processo. Cada mudança é registrada automaticamente, com autor e horário.
- **Aguardando Solicitante:** quando falta informação de quem abriu a demanda, o card é movido para a etapa de espera e a pendência fica explícita.
- **Modos de Visualização:** **Quadro** para a operação diária; **Lista** para ordenar por prazo restante ou filtrar por responsável; **Compacta** para grandes volumes.
- **Minha Operação:** visão consolidada de todos os cards sob responsabilidade do operador, em todos os workspaces, separados em atrasados, do dia e próximos.
- **Produtividade:** filtros por status, prioridade e responsável; seleção múltipla para mover ou arquivar em lote; fixação de cards prioritários; busca global por cards.

## 2. Resolução de Chamados (Helpdesk)

- **Assumir um Ticket:** o painel de Helpdesk exibe os chamados pendentes. Ao assumir, o operador torna-se o responsável pela resolução.
- **Comunicação Direta:** cada chamado tem um chat exclusivo para solicitar detalhes, enviar atualizações e orientar o colaborador.
- **Finalização:** a conclusão do chamado encerra o tempo de SLA e fecha o ciclo de atendimento.

## 3. Anexos e Evidências

- A ação **"Finalizar com Anexo"** entrega o documento final da demanda e conclui o card em uma única etapa.
- Cada arquivo anexado é registrado no histórico da tarefa de forma permanente, disponível para auditorias futuras.

## 4. Recursos Gerais

- **Mensagens e Videoconferências:** conversas, grupos e reuniões, com resposta, encaminhamento e envio de mídia em lote.
- **Assistente Virtual:** esclarecimento de dúvidas sem sair do aplicativo.
- **Abertura de Solicitações:** demandas para outros setores pelo "Novo Ticket".

---

# PARTE 4 — MANUAL DA LIDERANÇA

Equipes em campo, prazos, comunicação oficial, moderação e governança dos workspaces.

## 1. Monitoramento de Equipes em Campo (GPS)

- **Mapa Administrativo:** a aba de Rastreamento apresenta a visão consolidada dos colaboradores em campo, com posição e rota percorrida ao longo do expediente.
- **Situação dos Consentimentos:** para administradores, o painel indica quem consentiu, quem revogou e quem ainda não respondeu — colaboradores sem consentimento não aparecem no mapa, e o painel evita que essa ausência passe despercebida.
- **Boa Prática:** se um colaborador deixar de aparecer no mapa, verifique primeiro o consentimento e a permissão de localização "Sempre Permitir" no aparelho.

## 2. Gestão de Prazos e Workflow (SLA)

- **Distribuição de Demandas:** acompanhamento das filas e **reatribuição de tarefas** entre operadores para equilibrar a operação.
- **Visão de Supervisão:** a visualização em Lista ordena os chamados pelo menor prazo restante, destacando o que está em risco de atraso.
- **Painel Operacional:** totais, valores, SLAs excedidos e volume por etapa, em tempo real.
- **Ajuste dos Fluxos:** etapas, cores, ícones e regras de cada workspace podem ser alteradas a qualquer momento pela tela de informações do canal, e modelos de workspace podem ser criados para padronizar novos fluxos.

## 3. Comunicação Oficial e Moderação

- **Comunicados com Confirmação ("Estou Ciente"):** avisos que permanecem em tela até a confirmação de leitura de cada colaborador, com registro formal.
- **Permissão de Anúncios:** definição de quem pode publicar anúncios oficiais em conversas e canais.
- **Moderação de Canais:** remoção de mensagens inadequadas e advertência aos autores, preservando o caráter corporativo das salas.
- **Controle de Entrada:** solicitações de acesso são aprovadas ou recusadas por quem administra aquele canal, com notificação imediata a cada pedido.
- **Workspaces Privados:** espaços reservados, invisíveis para não membros, para assuntos de RH, jurídico ou diretoria.
- **Sucessão de Administração:** o último administrador de um canal só pode sair após indicar quem assume, e a pessoa indicada é avisada — o canal nunca fica sem gestor.

## 4. Acompanhamento da Equipe

Conforme as permissões do perfil, a liderança acompanha registros de ponto, ausências e férias programadas e resultados de avaliações de desempenho da equipe.

## 5. Escalonamento de Helpdesk

A liderança pode assumir e intervir em chamados críticos escalonados pelos operadores, usando o chat do ticket para alinhar a resolução com o solicitante.

> **Observação:** criação e exclusão de usuários, logs de auditoria e configuração de permissões são restritas ao nível Super Admin.

---

# PARTE 5 — MANUAL DO RH

Recrutamento, seleção, contratação, integração e gestão de pessoas — com apoio de IA.

## 1. Central de Recrutamento

A Central de Recrutamento é organizada em abas: **Visão Geral, Pipeline, Divulgação, Vagas, Avaliações e Ajustes**.

- **Visão Geral (Indicadores):** candidatos totais, em processo e contratados, taxa de conversão, funil por etapa, origem dos candidatos, distribuição por nível, movimentação de pessoal dos últimos 12 meses e talentos com melhor pontuação.
- **Catálogo de Áreas e Cargos:** cadastro padronizado de áreas, cargos e competências, com sugestões iniciais das áreas e cargos mais comuns do mercado.
- **Guias Visuais:** as telas do módulo exibem orientações passo a passo enquanto ainda não há cadastros, facilitando a configuração inicial.

## 2. Divulgação e Vagas

- **Página de Carreiras:** endereço público com a marca da empresa, título e apresentação editáveis, podendo ser ativada ou pausada a qualquer momento.
- **Divulgação Facilitada:** link compartilhável por WhatsApp e e-mail e **QR Code** para materiais impressos, com métricas de inscrições, avanços no funil e contratações.
- **Publicação de Vagas:** título, área, cargo, nível, contrato, localidade, trabalho remoto, faixa salarial, requisitos, número de posições e prazo, com ciclo de status (rascunho, aberta, pausada, fechada).
- **Link por Vaga:** cada vaga possui link e QR Code próprios; candidaturas espontâneas também são aceitas.

## 3. Pipeline de Seleção (ATS)

- **Etapas Configuráveis:** etapas criadas, renomeadas, reordenadas e recoloridas pela empresa, respeitando as etapas fixas de entrada, contratação e descarte.
- **Responsável por Candidato** e filtro "Meus candidatos".
- **Alerta de Tempo em Etapa** para candidatos parados além do prazo.
- **Ações em Massa:** atribuir responsável, mover de etapa ou descartar candidatos em lote.

## 4. Triagem Inteligente de Currículos (IA)

- Currículos em PDF ou Word são lidos automaticamente, com extração de formação, experiências e habilidades.
- A extração registra apenas o que consta no documento, sem completar lacunas com suposições.
- Falhas de leitura são sinalizadas e podem ser **reprocessadas com um clique**.
- Os dados de identificação são removidos do texto antes do envio à IA.

## 5. Avaliação Técnica com IA

- **Banco de Questões** por cargo e nível, criadas manualmente ou **geradas por IA**.
- **Prova com Tempo Limite** controlado pelo servidor — o candidato pode retomar a prova sem ganhar tempo extra.
- **Correção Automática e Segura:** o gabarito nunca é exposto; a nota (0 a 100) fica registrada na ficha.

## 6. Portal do Candidato

- **Conta Própria** com senha e verificação por e-mail, protegida contra tentativas automatizadas.
- **Acompanhamento em Tempo Real** das candidaturas, com destaque da etapa atual.
- **Reaproveitamento de Currículo** em novas candidaturas.
- **Interação Completa:** mensagens do RH, envio de documentos e realização de avaliações.

## 7. Contratação e Ficha do Funcionário

- **Conversão Direta** do candidato aprovado em funcionário, com vínculo no organograma e início do onboarding.
- **Gestão do Vínculo:** tipo de contrato, situação, admissão, matrícula, carga horária e lotação editáveis na ficha.
- **Dados Protegidos:** informações sensíveis criptografadas, com **registro de cada acesso**.
- **Histórico e Dependentes:** histórico de cargos e salários e cadastro de dependentes.
- **Vínculo com o Aplicativo:** a ficha pode ser vinculada à conta de acesso do colaborador; empresas que já utilizam a plataforma podem converter os usuários existentes em fichas de funcionário em uma carga única.

## 8. Gestão de Pessoas

- **Controle de Ponto:** batidas registradas pelo aplicativo **com o horário do servidor**, impedindo ajuste pelo relógio do aparelho. O RH acompanha o espelho, lança registros manuais e aprova, ajusta ou rejeita batidas.
- **Holerites:** emissão por competência com upload do PDF e registro de visualização.
- **Benefícios:** catálogo e adesões por funcionário, com valores de desconto protegidos por criptografia.
- **Ausências e Férias:** solicitação pelo colaborador e aprovação pelo RH, com **calendário da equipe** e controle do **saldo de férias** — a aprovação sem saldo suficiente é bloqueada.
- **Desempenho por Ciclos:** ciclos de avaliação com **metas ponderadas**, avaliações de experiência, 1:1 e anuais, e **feedback 360°** consolidado e anônimo, com exibição de médias apenas a partir de um número mínimo de respostas.

## 9. Onboarding

- **Modelos de Checklist** com etapas obrigatórias e opcionais, gerados automaticamente a cada admissão.
- **Responsáveis por Etapa:** RH, gestor ou o próprio funcionário, que conclui suas tarefas em "Meu Onboarding".
- **Período de Experiência:** controle dos prazos de 45 + 45 dias, com alertas antes de cada vencimento.

## 10. Documentos, Aceites e Vencimentos

- **Envio e Aprovação** com motivo registrado em caso de recusa.
- **Aceite Eletrônico** com registro, no servidor, de quem aceitou, quando e de qual dispositivo.
- **Vencimentos Monitorados** diariamente, com alertas ao RH e ao funcionário.
- **Central de Alertas RH** com todas as pendências reunidas.

## 11. Comunicação e Automações

- **E-mails Automáticos por Etapa** do funil de seleção.
- **Modelos Personalizáveis** com variáveis como nome do candidato, empresa e etapa.
- **Servidor de E-mail da Empresa:** compatível com Office 365, Google Workspace, Amazon SES, SendGrid e servidores próprios, com conexão segura e teste de envio antes de ativar. As credenciais são armazenadas de forma criptografada.
- **Registro de Comunicação** de todos os envios.

## 12. LGPD no Recrutamento

- **Consentimento Registrado** em cada candidatura, com versão e data.
- **Retenção Configurável** para candidatos não contratados, com anonimização automática ao fim do prazo.
- **Direito ao Esquecimento:** anonimização dos dados pessoais em uma única ação, preservando o histórico estatístico.

---

# PARTE 6 — MANUAL DO SUPER ADMIN

Permissões, usuários, estrutura, dados legais, auditoria e operação multiempresa.

> **Recomendação:** em razão do impacto das ações executadas neste nível, o acesso de Super Admin deve ser restrito ao departamento de TI ou à alta direção.

## 1. Matriz de Permissões (RBAC Dinâmico)

A plataforma é entregue com quatro perfis prontos — **Super Admin, RH, Gestor e Colaborador** — e permite criar perfis personalizados. As permissões são atribuídas **módulo a módulo**, separando o que cada perfil pode **visualizar** e **gerenciar**.

| Funcionalidade | Super Admin | Administrador | Gestor | RH | Colaborador |
| --- | :---: | :---: | :---: | :---: | :---: |
| Criar usuários | Sim | Sim | Não | Não | Não |
| Configurar perfis e permissões | Sim | Não | Não | Não | Não |
| Logs de auditoria | Sim | Não | Não | Não | Não |
| Dados legais da empresa | Sim | Sim | Não | Não | Não |
| Chave de IA da empresa | Sim | Sim | Não | Não | Não |
| Recrutamento e Banco de Talentos | Sim | Config. | Config. | Sim | Não |
| Gestão de Pessoas (ponto, férias, holerites) | Sim | Config. | Config. | Sim | Não |
| Visualizar GPS | Sim | Sim | Sim | Não | Não |
| Moderação e relatórios | Sim | Sim | Não | Não | Não |
| Operar cards (Workflow) | Sim | Sim | Sim | Não | Não |
| Criar grupos e reuniões | Sim | Sim | Sim | Não | Não |
| Autoatendimento (meus dados de RH) | Sim | Sim | Sim | Sim | Sim |
| Abrir solicitações | Sim | Sim | Sim | Sim | Sim |

*A matriz representa a configuração padrão — cada empresa adapta as permissões à sua realidade.*

**Proteção hierárquica:** administradores comuns não podem alterar nem desativar contas de Super Admin.

## 2. Gestão de Usuários e Offboarding

- **Inclusão de Novos Membros:** o administrador cadastra o colaborador, vincula-o a filial, departamento e cargo e atribui o perfil de acesso. A conta nasce com senha temporária, **substituída obrigatoriamente no primeiro acesso**.
- **Offboarding:** a desativação da conta invalida a sessão **imediatamente em todos os dispositivos**, preservando o histórico corporativo para auditoria; fotos de perfil são removidas do armazenamento ao arquivar ou excluir o usuário.
- **Promoções e Transferências:** perfil, filial, departamento e cargo podem ser alterados a qualquer momento, com efeito imediato.

## 3. Dados Legais da Empresa

- **Aba Dados Legais** no Painel Administrativo: razão social, CNPJ, endereço, Encarregado (DPO), e-mail do Encarregado, data de vigência, comarca, região de hospedagem e telefone de plantão.
- **Preenchimento Automático:** os documentos legais passam a exibir esses dados no lugar dos campos genéricos, incluindo os prazos de retenção configurados.
- **Pendências Sinalizadas:** enquanto faltar algum dado, o leitor indica o campo ausente.

## 4. Organograma e Workspaces

- **Estrutura Organizacional** — filiais, departamentos e cargos — mantida pela interface administrativa.
- **Workspaces por Filial**, com comunicação e dados separados entre unidades.
- **Encaminhamento Automático** de chamados e demandas ao setor correto.
- **Fluxos Personalizados:** etapas, modo de atribuição e operadores autorizados definidos por canal operacional.

## 5. Governança, Auditoria e Moderação

- **Logs de Auditoria:** movimentação de cards, criação de canais, entrada e saída de membros, envio de arquivos, alteração de permissões e operações de backup, com data e hora, em registros protegidos contra adulteração.
- **Acesso a Dados Sensíveis:** consultas a CPF, telefone, salários e dados bancários geram registro próprio.
- **Moderação Global:** remoção de mensagens inadequadas em qualquer canal, com **justificativa registrada**.
- **Relatórios de Uso:** usuários ativos, mensagens e chamadas, com gráficos de evolução.

## 6. Inteligência Artificial da Empresa (Chave Própria)

- **Escolha do Provedor:** **Claude (Anthropic), GPT (OpenAI), Gemini (Google) ou Llama (Groq)**, com a chave da própria organização, usada na triagem de currículos e na geração de avaliações.
- **Cofre Criptografado:** as chaves não são exibidas a nenhum usuário e podem ser removidas definitivamente a qualquer momento.
- **Custo sob Controle:** cada uso de IA é registrado com o custo estimado.

## 7. Backup e Retenção

- **Cobertura da Organização:** a aba Backup do Painel Administrativo mostra quem mantém backup, de quantos aparelhos e há quanto tempo, além da política de retenção vigente.
- **Sem Acesso ao Conteúdo, por Desenho:** os backups das conversas são cifrados no aparelho de cada usuário. O painel não dá acesso ao seu conteúdo; o acesso corporativo a conversas ocorre pela Moderação, com justificativa e registro.
- **Retenção Automática:** os backups expiram no prazo definido pela organização (90 dias por padrão) e são eliminados por rotina diária, com registro como evidência de cumprimento da LGPD.
- **Continuidade da Infraestrutura:** na nuvem gerenciada, as cópias de segurança do banco de dados são realizadas pela fabricante; em servidor próprio, conforme o documento de requisitos de implantação.

## 8. Console de Plataforma (Operação Multiempresa)

Recursos destinados ao proprietário ou parceiro que administra a plataforma para várias empresas, em uma **versão administrativa dedicada** do aplicativo.

- **Cadastro de Empresas:** a criação de uma nova organização já exige os dados legais — razão social, CNPJ, endereço, Encarregado, e-mail do Encarregado e vigência —, de modo que os documentos de privacidade nascem preenchidos.
- **Alternador de Empresa:** o administrador da plataforma assume o contexto de qualquer empresa cliente para prestar suporte ou configurar módulos, e retorna à matriz sem senhas adicionais.
- **Módulos por Contrato:** habilitação individual por organização, conforme o plano contratado.
- **Consumo de IA por Empresa:** acompanhamento de uso e custo por organização — base para faturamento por consumo.
- **Isolamento Garantido:** cada empresa com seus próprios usuários, permissões, fluxos, nome e identidade visual.

---

*AlinhaJá — Documentação Oficial. Este documento apresenta a visão comercial e de usuário da plataforma; regras de negócio específicas e guias avançados de configuração estão disponíveis na Central de Ajuda do sistema.*
