# PLATAFORMA ALINHAJÁ

**Documento Oficial — Modelos de Implantação e Requisitos Técnicos**

Este documento apresenta os dois modelos de implantação disponíveis para a plataforma AlinhaJá — **Nuvem Gerenciada (SaaS)** e **Servidor Próprio (On-Premise)** —, com a recomendação técnica e comercial da fabricante, os requisitos completos de infraestrutura para operação em ambiente próprio e as responsabilidades de cada parte.

Destina-se a diretores de tecnologia, gestores de infraestrutura e áreas de compliance responsáveis pela decisão de arquitetura.

---

# PARTE 1 — MODELOS DE IMPLANTAÇÃO

## 1.1 Resumo Executivo

A plataforma AlinhaJá foi desenvolvida como uma solução **multiempresa (multi-tenant) desde a sua concepção**. Cada organização opera em um ambiente logicamente isolado, com seus próprios usuários, dados, permissões, módulos contratados e identidade visual — mesmo quando compartilha a mesma infraestrutura de nuvem com outras empresas.

Essa arquitetura permite oferecer dois modelos de implantação:

| Modelo | Descrição | Perfil indicado |
| --- | --- | --- |
| **Nuvem Gerenciada (SaaS)** | A plataforma é operada, monitorada, atualizada e mantida pela fabricante. O cliente utiliza o sistema sem qualquer infraestrutura própria. | Recomendado para a maioria das organizações |
| **Híbrido (dados no cliente)** | Os dados corporativos residem na infraestrutura do cliente; os serviços de apoio permanecem na nuvem gerenciada. | Organizações que precisam manter os dados em rede própria sem assumir toda a operação — ver seção 3.11 |
| **Servidor Próprio (On-Premise)** | Toda a plataforma é instalada na infraestrutura do cliente, sob sua responsabilidade operacional. | Casos com exigência regulatória ou grande porte com TI dedicada |

> **Recomendação da fabricante:** a modalidade **Nuvem Gerenciada** é a indicada para praticamente todos os cenários. O modelo em servidor próprio é oferecido como opção Enterprise, para situações específicas descritas na seção 1.4.

## 1.2 Comparativo entre os Modelos

| Critério | Nuvem Gerenciada | Servidor Próprio |
| --- | --- | --- |
| Investimento inicial em infraestrutura | Nenhum | Servidores, armazenamento, rede e licenças |
| Equipe técnica exigida do cliente | Nenhuma | Equipe de infraestrutura/DevOps dedicada |
| Prazo de disponibilização | Imediato | Projeto de implantação (semanas) |
| Atualizações e correções | Automáticas, para todos ao mesmo tempo | Sob agendamento, versão por cliente |
| Backup e recuperação de desastres | Incluídos e testados | Responsabilidade do cliente |
| Monitoramento e disponibilidade | Incluídos | Responsabilidade do cliente |
| Certificados TLS e segurança de borda | Incluídos | Responsabilidade do cliente |
| Isolamento dos dados | Lógico, por organização, com controle no banco de dados | Físico, em rede própria |
| Videoconferência e notificações | Operacionais desde o primeiro acesso | Exigem serviços adicionais no ambiente do cliente |
| Recursos de Inteligência Artificial | Disponíveis imediatamente | Exigem servidor de inferência com GPU ou acesso externo |
| Custo total de propriedade | Previsível, por assinatura | Infraestrutura + equipe + suporte dedicado |

## 1.3 Por Que a Nuvem Gerenciada é a Melhor Escolha

**Isolamento equivalente, sem o custo da separação física.**
O AlinhaJá aplica controle de acesso no próprio banco de dados: cada registro pertence a uma organização e as políticas de segurança impedem, no servidor, que qualquer consulta atravesse essa fronteira. O isolamento não depende da aplicação nem da disciplina de programação — é uma regra do banco de dados, aplicada a todas as tabelas de conteúdo. Compartilhar infraestrutura não significa compartilhar dados.

**Nenhum investimento em infraestrutura.**
Não há servidores a adquirir, contratos de datacenter a manter, equipe de DevOps a contratar, rotinas de backup a construir, monitoramento a configurar, certificados a renovar ou atualizações de segurança do sistema operacional a acompanhar. A organização passa a consumir o sistema como serviço, com custo previsível.

**Atualizações imediatas para todos.**
Novas funcionalidades e correções entram em produção simultaneamente para todos os clientes. Em ambientes próprios, cada cliente permanece na versão instalada até a próxima janela de atualização — o que, ao longo do tempo, produz um parque fragmentado, com comportamentos distintos e suporte mais lento.

**Complexidade operacional concentrada em quem a domina.**
Uma instalação completa envolve a orquestração de sete categorias de serviços — o núcleo de dados e autenticação (composto por sete componentes independentes), servidor de videoconferência, servidor de mídia STUN/TURN, servidor de e-mail, automações, notificações push e, quando aplicável, inferência de Inteligência Artificial. Manter esse conjunto disponível, atualizado e seguro é uma operação contínua, não uma instalação única.

**Aplicativo único, sem builds paralelos.**
Os endereços dos serviços são definidos no momento da compilação do aplicativo. Cada instalação em servidor próprio exige, portanto, uma **compilação dedicada** para Web e Android — com assinatura digital, distribuição e ciclo de atualização próprios. Na nuvem gerenciada, todos os clientes utilizam o mesmo aplicativo, sempre atualizado.

## 1.4 Quando o Servidor Próprio se Justifica

A modalidade On-Premise é apropriada quando pelo menos uma das condições abaixo estiver presente:

- **Exigência regulatória ou contratual** que impeça o armazenamento de dados fora da rede interna ou do território nacional — como órgãos públicos, defesa, instituições financeiras sob regime específico e serviços de saúde com dados sensíveis.
- **Organizações de grande porte** (a partir de 5.000 usuários) que já operam datacenter próprio, com equipe de infraestrutura e processos maduros de disponibilidade, backup e segurança.
- **Contratos Enterprise** cujo escopo e valor comportem implantação assistida, ambiente dedicado e suporte técnico especializado.

Fora dessas situações, o modelo em servidor próprio tende a elevar o custo total e reduzir a velocidade de evolução do sistema, sem ganho equivalente de segurança.

## 1.5 Modalidades Comerciais

| Modalidade | Modelo de operação | Público |
| --- | --- | --- |
| **Standard** | Nuvem gerenciada, multiempresa | Recomendado para a maioria das organizações |
| **Enterprise** | Servidor próprio, ambiente dedicado | Grandes corporações e casos com exigência regulatória |

A modalidade Enterprise é orçada por projeto e considera implantação assistida, homologação do ambiente, compilação dedicada do aplicativo, treinamento da equipe técnica do cliente e suporte especializado — custos que não incidem sobre a modalidade Standard.

---

# PARTE 2 — NUVEM GERENCIADA (MODALIDADE RECOMENDADA)

## 2.1 O Que Está Incluído

- Infraestrutura completa da plataforma, com monitoramento e alta disponibilidade.
- Banco de dados gerenciado, com backups automáticos e política de retenção.
- Servidores de videoconferência e de notificações em operação.
- Certificados de segurança (TLS) e proteção de borda.
- Atualizações de funcionalidades e correções de segurança sem custo adicional.
- Aplicativo Web (PWA) e Android sempre na versão mais recente.
- Suporte técnico ao administrador da organização.

## 2.2 Isolamento entre Organizações

- Cada registro do sistema pertence a uma organização, e as políticas de segurança do banco de dados **restringem toda consulta ao contexto da organização do usuário autenticado**.
- As áreas de armazenamento de arquivos (mídias de conversas, currículos e documentos de RH) seguem o mesmo controle.
- Os módulos contratados são habilitados individualmente por organização; funcionalidades não licenciadas não são exibidas nem acessíveis.
- O acesso administrativo da fabricante é segregado em uma versão administrativa distinta do aplicativo, com registro de auditoria das ações executadas.

## 2.3 Divisão de Responsabilidades

| Responsabilidade | Nuvem Gerenciada | Servidor Próprio |
| --- | --- | --- |
| Disponibilidade da infraestrutura | Fabricante | Cliente |
| Backup e recuperação | Fabricante | Cliente |
| Atualizações da plataforma | Fabricante | Cliente (com apoio da fabricante) |
| Segurança do sistema operacional e da rede | Fabricante | Cliente |
| Gestão de usuários e permissões | Cliente | Cliente |
| Conteúdo e dados corporativos | Cliente | Cliente |
| Suporte funcional aos usuários | Fabricante | Fabricante |

---

# PARTE 3 — REQUISITOS PARA SERVIDOR PRÓPRIO (ON-PREMISE)

Esta parte descreve os requisitos técnicos para operar a plataforma integralmente na infraestrutura do cliente. Destina-se à equipe de infraestrutura responsável pela avaliação de viabilidade.

## 3.1 Visão Geral da Arquitetura

A plataforma depende de sete categorias de serviços. Quatro são integralmente instaláveis em ambiente próprio, duas são híbridas (funcionam localmente mediante adaptação) e uma é exclusivamente de nuvem, devendo ser substituída.

| Serviço | Função na plataforma | Instalável no cliente | Providência necessária |
| --- | --- | :---: | --- |
| **Núcleo de dados e aplicação** | Banco de dados, autenticação, arquivos, tempo real e funções de servidor | Sim | Instalação da stack completa em contêineres |
| **Servidor de videoconferência** | Reuniões em grupo | Sim | Contêiner dedicado com servidor de mídia |
| **Servidor de e-mail (SMTP)** | Verificação em duas etapas e automações de RH | Sim | Uso do servidor corporativo existente |
| **Automações e webhooks** | Integrações e transcrição de áudio | Sim | Contêiner dedicado |
| **Notificações push** | Alertas em Android e Web | Parcial | Serviço de retransmissão gratuito ou substituição |
| **Inteligência Artificial** | Assistente virtual, triagem de currículos e geração de questões | Parcial | Servidor de inferência com GPU ou acesso externo |
| **Chamadas individuais** | Áudio e vídeo 1:1 | Não | Substituição pelo servidor de videoconferência próprio |

## 3.2 Núcleo de Dados e Aplicação

É o componente central da plataforma. Reúne o banco de dados, a autenticação, o armazenamento de arquivos, a comunicação em tempo real e as funções de servidor.

**Componentes que precisam estar em operação:**

| Componente | Porta padrão | Função |
| --- | :---: | --- |
| Banco de dados PostgreSQL 15+ | 5432 | Dados da aplicação, políticas de segurança e gatilhos |
| API de dados | 3000 | Interface de acesso ao banco |
| Serviço de autenticação | 9999 | Login, verificação em duas etapas e emissão de credenciais |
| Serviço de tempo real | 4000 | Atualização instantânea de mensagens e telas |
| Serviço de armazenamento | 5000 | Arquivos de conversas, currículos e documentos |
| Gateway de API | 8000 / 8443 | Ponto único de entrada e roteamento |
| Painel de administração técnica | 3001 | Manutenção do banco (opcional) |
| Ambiente de execução de funções | 8081 | Execução das funções de servidor |

**Cargas a aplicar na implantação:**

- **145+ scripts de estrutura de banco de dados**, aplicados em ordem, criando tabelas, políticas de segurança, funções, gatilhos, rotinas de auditoria e os controles de privacidade e direitos do titular (LGPD). O número exato acompanha a versão contratada e é informado no levantamento técnico.
- **12 funções de servidor** (mais bibliotecas compartilhadas), responsáveis por notificações de mensagens, chamadas, módulos e demandas; assistente virtual; extração de currículos; geração de questões; automações de RH; portal público de candidaturas; verificação em duas etapas; emissão de credenciais de chamada; e recepção de webhooks externos.
- **Quatro áreas de armazenamento** de arquivos: mídias de conversas, fotos de perfil, currículos e documentos de RH.

**Parâmetros a configurar:** endereço interno do serviço, chave pública da aplicação, chave administrativa, segredo de autenticação de gatilhos internos e lista de domínios autorizados.

## 3.3 Notificações Push (Firebase Cloud Messaging)

A plataforma utiliza o **Firebase Cloud Messaging (FCM)**, do Google, para entregar notificações a dispositivos Android e a navegadores. Este é o único componente que **não pode ser integralmente internalizado** sem alteração no aplicativo: em dispositivos Android com serviços Google, o encaminhamento de notificações em segundo plano é feito exclusivamente pelo canal do próprio sistema operacional. O mesmo se aplica a dispositivos Apple, que utilizam o serviço APNs.

**O que trafega pelo Firebase:** apenas o **identificador do dispositivo** (token) e o **conteúdo do alerta** (por exemplo, o nome do remetente e a prévia da mensagem, conforme configuração de privacidade da organização). Nenhum dado corporativo é armazenado no Firebase, e o banco de dados, os arquivos e os registros permanecem integralmente no ambiente do cliente.

**Configuração necessária:** projeto Firebase com conta de serviço, chave de API Web, identificador do aplicativo, identificador do remetente, identificador do projeto e chave de Web Push (VAPID). O plano gratuito do Firebase atende integralmente a esse uso, sem custo.

| Estratégia | Esforço | Cobertura |
| --- | :---: | --- |
| **Projeto Firebase gratuito como retransmissor** | Apenas configuração | Android e Web |
| Substituição por solução de código aberto (ntfy, Gotify ou equivalente) | Médio — exige alteração no aplicativo e nas funções de servidor | Android e Web |
| Uso exclusivo de conexão persistente | Alto — exige reescrita da camada de notificações | Apenas Web |

**Recomendação:** manter um projeto Firebase gratuito, dedicado exclusivamente ao encaminhamento das notificações. Organizações com política que vede qualquer serviço externo devem prever, no escopo do projeto, a substituição da camada de notificações por solução de código aberto — com a ressalva de que, nesse cenário, a entrega em segundo plano no Android passa a depender de o aplicativo permanecer autorizado a executar em segundo plano em cada aparelho.

## 3.4 Videoconferência e Chamadas

O servidor de videoconferência utilizado para reuniões em grupo é instalável em ambiente próprio, em contêiner dedicado.

**Requisitos:**

- Porta 443 (HTTPS) e faixa 40000–49999 (UDP) para tráfego de mídia.
- Servidor STUN/TURN próprio quando houver tradução de endereços ou firewall restritivo (porta 3478).
- Chave de API do servidor configurada no aplicativo.

**Chamadas individuais (1:1):** o serviço atualmente utilizado é exclusivamente de nuvem e não pode ser internalizado. Para operação em servidor próprio, as chamadas individuais devem ser migradas para o mesmo servidor de videoconferência já integrado à plataforma — adaptação que integra o escopo do projeto de implantação.

## 3.5 Inteligência Artificial

A plataforma opera com o modelo de **chave própria do cliente**, permitindo a escolha do provedor de Inteligência Artificial. Para operação sem saída de dados da rede interna, é necessário um servidor de inferência local.

| Solução | Requisito de hardware |
| --- | --- |
| Servidor de inferência de código aberto (modelos abertos) | GPU NVIDIA com 24 GB de memória ou superior |
| Servidor de inferência de alto desempenho | GPU NVIDIA A100 / H100 |
| Servidor compatível com API padrão de mercado | GPU NVIDIA com 16 GB de memória ou superior |

As funções de assistente virtual, extração de currículos e geração de questões passam a apontar para o endereço interno do servidor de inferência. Sem esse componente, os recursos de IA permanecem indisponíveis ou dependem de acesso externo autorizado.

## 3.6 E-mail e Automações

- **Servidor de e-mail (SMTP):** utilizado para verificação em duas etapas e para as comunicações automáticas do funil de recrutamento. Pode ser o servidor corporativo já existente (Exchange, Postfix ou equivalente) ou um serviço de retransmissão autorizado. Requer host, porta, usuário e senha configurados.
- **Automações e webhooks:** contêiner dedicado (porta padrão 5678), utilizado para integrações externas e transcrição de áudio.

## 3.7 Requisitos de Hardware

### Servidor único — até 500 usuários

| Recurso | Mínimo | Recomendado |
| --- | --- | --- |
| Processador | 8 vCPUs | 16 vCPUs |
| Memória | 16 GB | 32 GB |
| Armazenamento | 200 GB SSD | 500 GB NVMe |
| Rede | 100 Mbps | 1 Gbps |
| GPU (somente se usar IA local) | — | NVIDIA com 24 GB de memória |
| Sistema operacional | Ubuntu 22.04 LTS ou Debian 12 | Ubuntu 24.04 LTS |

### Ambiente distribuído — acima de 500 usuários

| Componente | Instâncias | Recursos por nó |
| --- | :---: | --- |
| Banco de dados (primário e réplica) | 2 | 8 vCPU · 32 GB RAM · 500 GB NVMe |
| Serviços de aplicação (API, autenticação, tempo real, arquivos) | 2 a 3 | 4 vCPU · 16 GB RAM |
| Videoconferência e servidor de mídia | 1 a 2 | 4 vCPU · 8 GB RAM |
| Inferência de Inteligência Artificial | 1 | GPU A100 80 GB ou 2× A10G |
| Balanceador de carga | 1 | 2 vCPU · 4 GB RAM |

## 3.8 Rede, Segurança e Continuidade

| Requisito | Detalhamento |
| --- | --- |
| Domínio | Domínio interno ou público com resolução de nomes na rede corporativa |
| Certificado TLS | Emissor público ou autoridade certificadora interna |
| Portas TCP | 443 (HTTPS), 8000 e 8443 (gateway), 5432 (banco de dados, uso interno) |
| Portas UDP | 40000–49999 (mídia de videoconferência), 3478 (STUN/TURN) |
| Firewall | Permitir conexões persistentes de tempo real (WebSocket) |
| Backup | Cópia diária do banco de dados e das áreas de armazenamento, com teste periódico de restauração |
| Monitoramento | Ferramenta de métricas e alertas com acompanhamento de disponibilidade |
| Registro de auditoria | Retenção conforme política interna e exigências regulatórias |

## 3.9 Aplicativo Dedicado e Distribuição

Os endereços dos serviços são definidos na compilação do aplicativo. Cada instalação em servidor próprio requer, portanto, **versões dedicadas do aplicativo**, com ciclo de atualização próprio: cada nova versão da plataforma exige nova compilação, homologação e redistribuição no ambiente do cliente.

| Plataforma | Distribuição | Requisitos adicionais |
| --- | --- | --- |
| **Web (PWA)** | Publicação no servidor web do cliente | Certificado TLS válido no domínio |
| **Android** | Arquivo APK assinado, distribuído por loja corporativa (MDM) ou canal interno | Certificado de assinatura do cliente |
| **iOS (iPhone e iPad)** | Arquivo IPA distribuído internamente | Programa Apple Developer Enterprise e geração da versão iOS — ver abaixo |

### Distribuição em iOS

A versão iOS não integra o pacote padrão da plataforma e é produzida sob demanda, quando o parque de dispositivos do cliente incluir iPhone ou iPad. Nesse caso, o projeto de implantação deve prever:

- **Geração e homologação da versão iOS** do aplicativo, com os testes correspondentes.
- **Apple Developer Enterprise Program** (custo aproximado de **US$ 299 por ano**, pago pelo cliente diretamente à Apple), que autoriza a distribuição interna do arquivo IPA aos colaboradores da organização **sem publicação na App Store pública**. O programa exige que a empresa comprove ser uma organização legalmente constituída, com identificador D-U-N-S.
- **Alternativa:** distribuição pelo Apple Developer Program convencional (US$ 99 por ano) via App Store ou TestFlight — opção que expõe o aplicativo ao processo de revisão da Apple e, no caso da App Store, à listagem pública.
- **Certificados e perfis de provisionamento** próprios do cliente, com renovação anual — a expiração interrompe a execução do aplicativo nos dispositivos.
- **Notificações push em iOS** utilizam o serviço APNs, da Apple, integrado ao projeto Firebase por meio de uma chave de autenticação gerada na conta de desenvolvedor do cliente.

> **Observação:** o endereço do servidor de videoconferência é definido no código-fonte da aplicação, o que reforça a necessidade de compilação dedicada por instalação.

## 3.10 Checklist de Implantação

**Infraestrutura**
- [ ] Servidores provisionados com plataforma de contêineres instalada
- [ ] Domínios internos configurados e certificados TLS instalados
- [ ] Regras de firewall aplicadas (TCP, UDP e conexões persistentes)

**Plataforma**
- [ ] Núcleo de dados e aplicação em operação, com todos os componentes ativos
- [ ] Scripts de estrutura de banco de dados aplicados na ordem correta (145+ na versão corrente)
- [ ] 12 funções de servidor implantadas e respondendo
- [ ] Áreas de armazenamento criadas com as respectivas políticas de acesso
- [ ] Parâmetros e segredos configurados

**Serviços complementares**
- [ ] Servidor de videoconferência em operação, com STUN/TURN
- [ ] Chamadas individuais migradas para o servidor próprio
- [ ] Servidor de e-mail configurado e testado
- [ ] Automações e webhooks em operação (se aplicável)
- [ ] Projeto Firebase criado e conta de serviço configurada (notificações push)
- [ ] Servidor de inferência de IA em operação (se aplicável)

**Aplicativo**
- [ ] Versão Web compilada com os endereços do cliente
- [ ] Aplicativo Android compilado e assinado
- [ ] Versão iOS gerada e conta Apple Developer Enterprise ativa (se houver iPhone/iPad no parque)
- [ ] Canal de distribuição definido (loja corporativa, MDM ou distribuição interna)

**Homologação e operação**
- [ ] Testes de ponta a ponta: acesso, conversas, chamadas, demandas, notificações e módulos de RH
- [ ] Rotina de backup automatizada e restauração testada
- [ ] Monitoramento e alertas ativos
- [ ] Equipe do cliente treinada na operação do ambiente

## 3.11 Modelo Híbrido — Dados no Cliente, Serviços na Nuvem

É comum que a organização deseje manter **apenas os dados corporativos** em sua própria infraestrutura, sem assumir a operação de todos os serviços da plataforma. Esse arranjo é possível e representa o melhor equilíbrio entre soberania sobre os dados e simplicidade operacional.

### O que reside no cliente

> **Esclarecimento técnico importante:** o banco de dados **não pode ser isolado sozinho**. A autenticação, o armazenamento de arquivos, a comunicação em tempo real e as funções de servidor operam acoplados ao banco de dados — e a plataforma gerenciada da fabricante não pode apontar para um banco de dados externo. A menor unidade que pode residir na infraestrutura do cliente é, portanto, o **núcleo completo** descrito na seção 3.2.

Nesse modelo, permanecem integralmente no ambiente do cliente:

- Banco de dados, com todas as mensagens, demandas, registros de RH e trilhas de auditoria.
- Arquivos enviados: mídias de conversas, fotos de perfil, currículos e documentos de RH.
- Autenticação e credenciais de acesso dos usuários.
- Funções de servidor e regras de segurança.

### O que permanece na nuvem gerenciada

| Serviço | Justificativa | Dados que trafegam |
| --- | --- | --- |
| **Videoconferência** | Evita servidor de mídia, STUN/TURN e faixa UDP dedicada na rede do cliente | Áudio e vídeo em tempo real, criptografados e não armazenados |
| **Notificações push (Firebase)** | Dependência do sistema operacional dos dispositivos | Identificador do dispositivo e texto do alerta |
| **Inteligência Artificial** | Dispensa servidor com GPU | Conteúdo submetido à análise, com remoção prévia dos dados de identificação nos currículos |

Caso a política interna vede também esses fluxos, cada um pode ser internalizado conforme as seções 3.3 a 3.5 — o que caracteriza a implantação integral em servidor próprio.

### Requisitos reduzidos

Sem videoconferência e sem inferência de IA no ambiente do cliente, o dimensionamento é significativamente menor:

| Recurso | Até 500 usuários | Acima de 500 usuários |
| --- | --- | --- |
| Processador | 6 vCPUs | 8 a 12 vCPUs |
| Memória | 12 GB | 24 GB |
| Armazenamento | 200 GB SSD (conforme volume de anexos) | 500 GB NVMe ou superior |
| GPU | Não necessária | Não necessária |
| Portas UDP para mídia | Não necessárias | Não necessárias |

Permanecem obrigatórios: certificado TLS, rotina de backup com teste de restauração, monitoramento e a compilação dedicada do aplicativo (seção 3.9).

### Divisão de responsabilidades no modelo híbrido

| Responsabilidade | Responsável |
| --- | --- |
| Servidor, sistema operacional e rede do núcleo | Cliente |
| Backup e restauração dos dados | Cliente |
| Atualizações da plataforma no núcleo | Cliente, com apoio da fabricante |
| Videoconferência, notificações e IA | Fabricante |
| Compilação e distribuição do aplicativo | Fabricante (compilação) e cliente (distribuição) |
| Suporte funcional aos usuários | Fabricante |

---

# PARTE 4 — CONDIÇÕES DA MODALIDADE ENTERPRISE

## 4.1 Responsabilidades do Cliente

Na modalidade em servidor próprio, o cliente assume integralmente:

- Aquisição, provisionamento e manutenção de servidores, armazenamento e rede.
- Disponibilidade do ambiente, incluindo energia, refrigeração e redundância.
- Execução, verificação e teste de restauração das rotinas de backup.
- Monitoramento, resposta a incidentes e atualizações de segurança do sistema operacional.
- Gestão de certificados digitais e da configuração de rede e firewall.
- Alocação de equipe técnica capacitada para operar o ambiente.

## 4.2 Escopo do Projeto de Implantação

O projeto conduzido pela fabricante contempla:

- Levantamento e validação técnica do ambiente proposto.
- Instalação assistida da plataforma e aplicação das cargas de banco de dados.
- Adaptação das chamadas individuais para o servidor de videoconferência próprio.
- Compilação e assinatura das versões dedicadas do aplicativo.
- Homologação funcional com a equipe do cliente.
- Transferência de conhecimento e documentação operacional do ambiente.

## 4.3 Pré-Requisitos para Elaboração de Proposta

Para dimensionamento e orçamento da modalidade Enterprise, são necessárias as seguintes informações:

- Número total de usuários e projeção de crescimento.
- Justificativa da exigência de ambiente próprio (regulatória, contratual ou de política interna).
- Modelo pretendido: servidor próprio integral ou híbrido, com apenas os dados no cliente (seção 3.11).
- Plataformas a distribuir: Web, Android e/ou iOS — informando, no caso de iOS, se a organização já possui conta Apple Developer Enterprise.
- Descrição da infraestrutura disponível e da equipe técnica responsável.
- Necessidade de recursos de Inteligência Artificial em ambiente interno.
- Requisitos de disponibilidade, janela de manutenção e tempo de resposta esperado.
- Política de atualização pretendida (frequência de novas versões).

## 4.4 Considerações Finais

A plataforma AlinhaJá opera integralmente em ambiente próprio, e este documento reúne todos os requisitos para essa implantação. Cabe registrar, entretanto, que **a modalidade em nuvem gerenciada oferece o mesmo produto, com o mesmo nível de isolamento de dados, sem investimento em infraestrutura, sem necessidade de equipe técnica dedicada e com atualizações contínuas**.

A recomendação da fabricante é adotar a modalidade em nuvem gerenciada, reservando a implantação em servidor próprio às situações em que exigências regulatórias, contratuais ou de porte a tornem indispensável.

---

*AlinhaJá — Documento Oficial de Requisitos de Implantação. As informações técnicas refletem a versão corrente da plataforma e podem ser revisadas em novas versões. Para avaliação da modalidade Enterprise, consulte a área comercial.*
