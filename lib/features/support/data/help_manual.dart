import 'package:flutter/material.dart';

import 'package:alinha_ja/core/constants.dart';

/// Artigos do **Manual / Documentação de referência** (aba "Manual" da
/// Central de Ajuda).
///
/// O corpo de cada artigo é Markdown (renderizado com `flutter_markdown`).
/// Imagens referenciam `assets/images/help/…`; tabelas usam GFM; as caixas de
/// destaque são blockquotes com emoji no título.
///
/// Enquanto os **Guias** ensinam a fazer (roteiro numerado), o **Manual**
/// explica as regras: o que cada campo significa, quem pode o quê e como o
/// módulo se comporta.
class ManualArticle {
  final String category;
  final String id;
  final String title;
  final IconData icon;
  final String markdown;

  /// Termos extras para a busca (além de título e categoria).
  final String keywords;

  const ManualArticle({
    required this.category,
    required this.id,
    required this.title,
    required this.icon,
    required this.markdown,
    required this.keywords,
  });
}

/// Capturas novas (mesmas da página institucional).
const String _shot = 'assets/images/help/shots/';

/// Capturas herdadas da primeira versão do manual.
const String _img = 'assets/images/help/';

/// Nome da marca desta build — nunca escreva o literal na UI.
const String _app = AppConstants.appName;

/// Documentação completa da plataforma, agrupada por categoria.
const List<ManualArticle> kManualArticles = [
  // ══════════════════ 1. Guia de Início Rápido ══════════════════
  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'intro',
    title: 'O que é o $_app',
    icon: Icons.info_outline,
    keywords:
        'introducao inicio o que e pilares comecar plataforma visao geral modulos areas',
    markdown: '''
## O que é o $_app

O **$_app** é uma plataforma corporativa unificada: comunicação, operação, recursos humanos, recrutamento, financeiro e administração no mesmo login, com o mesmo controle de permissão e a mesma trilha de auditoria.

A diferença em relação a um grupo de mensagens comum é simples: aqui a conversa **não morre no chat**. Uma solicitação vira card com responsável, etapa e prazo; um aviso da diretoria vira comunicado com confirmação de leitura; um problema de equipamento vira chamado com SLA.

![Navegação por módulos](${_shot}nav-modulos.webp)

> **💡 O que sustenta a plataforma**
>
> Toda demanda tem responsável explícito, uma conversa dedicada, um prazo visível e um histórico imutável de transições.

### As áreas do sistema

| Área | O que resolve |
| --- | --- |
| Comunicação | Canais, conversas diretas, grupos, chamadas e reuniões |
| Operação | Espaços de trabalho, Workflow Kanban e Helpdesk |
| Pessoas & RH | Funcionários, documentos, ausências, ponto, holerites, benefícios, desempenho e onboarding |
| Recrutamento | Vagas, página de carreiras, pipeline de candidatos e provas com IA |
| Financeiro | Contas a pagar, a receber e fluxo de caixa |
| Administração | Perfis e permissões, usuários, auditoria, moderação, relatórios e backup |

Você enxerga apenas os módulos liberados para o seu perfil de acesso. Um item ausente no menu quase sempre é permissão — fale com o TI antes de supor que o recurso não existe.
''',
  ),
  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'acesso',
    title: 'Acesso, login e segurança da conta',
    icon: Icons.login_rounded,
    keywords:
        'login entrar senha esqueci redefinir 2fa mfa autenticacao dispositivos confiaveis aprovacao pwa apk instalar',
    markdown: '''
## Acesso, login e segurança da conta

O $_app roda em **navegador (desktop)** e em **aplicativo Android**. O app pode ser instalado como PWA pela página inicial ou pelo APK oficial distribuído pelo TI — a versão instalada é a que recebe notificações em tempo real de forma confiável.

![Tela de login](${_img}login.webp)

### Como entrar

1. Informe o **e-mail corporativo** cadastrado.
2. Informe a **senha** entregue pelo TI (ou a que você definiu).
3. Toque em **Entrar**.

### Situações comuns no login

| Mensagem | O que significa | O que fazer |
| --- | --- | --- |
| Conta aguardando aprovação | O cadastro existe, mas o TI ainda não liberou | Aguardar a liberação e tentar novamente |
| Credenciais inválidas | E-mail ou senha incorretos | Conferir o e-mail; usar "Esqueci minha senha" |
| Pede código de verificação | A conta tem 2FA ativo | Informar o código do app autenticador ou do e-mail |

### Redefinir a senha

Na tela de login, toque em **Esqueci minha senha**, informe o e-mail cadastrado e siga o link enviado. O link é de uso único e expira.

### Verificação em duas etapas (2FA)

Em **Configurações > Segurança e 2FA** você ativa a verificação em duas etapas por aplicativo autenticador e gerencia os **dispositivos confiáveis** — aparelhos em que você já validou o segundo fator e não precisa repetir a cada acesso.

> **🔐 Recomendação**
>
> Ative o 2FA no primeiro acesso e revise a lista de dispositivos confiáveis periodicamente, removendo aparelhos que você não usa mais.
''',
  ),
  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'navegacao',
    title: 'Navegação, módulos e permissões visíveis',
    icon: Icons.dashboard_outlined,
    keywords:
        'navegacao menu sidebar modulos abas painel desktop mobile drawer busca notificacoes',
    markdown: '''
## Navegação e módulos

![Menu lateral com os módulos](${_shot}nav-modulos.webp)

O menu lateral agrupa os módulos por seção. No desktop ele fica fixo à esquerda com o painel de conteúdo à direita; no mobile o mesmo menu abre pelo ícone de sanduíche.

### Seções do menu

- **Comunicação** — Canais, Conversas e Chamadas. São abas do painel esquerdo: alternam a lista sem sair da tela.
- **Recursos Humanos** — Banco de Talentos, Funcionários, Documentos, Ausências e Férias, Onboarding, Alertas RH, Holerites, Controle de Ponto, Benefícios e Desempenho.
- **Financeiro** — Visão Geral, Contas a Pagar, Contas a Receber e Fluxo de Caixa.
- **Helpdesk** — Central de Ajuda (abrir e acompanhar chamados) e Helpdesk TI (fila de atendimento).
- **Administração** — Painel Admin e Comunicação e Automações.

### Atalhos do topo

| Ícone | Função |
| --- | --- |
| Bússola | Descobrir canais públicos que você ainda não segue |
| Lupa | Busca global por pessoas, canais e conversas |
| Interrogação | Abre esta Central de Ajuda |
| Fone | Suporte T.I. — abre um chamado |

> **👁️ Por que não vejo um módulo?**
>
> O menu é montado a partir das suas permissões. Se o item não aparece, o seu perfil não tem a chave "Visualizar" daquele módulo — veja *Perfis e permissões (RBAC)*.
''',
  ),
  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'configuracoes',
    title: 'Configurações do aplicativo',
    icon: Icons.settings_outlined,
    keywords:
        'configuracoes tema claro escuro automatico esquema de cores notificacoes perfil seguranca gestao de equipe historico rastreamento novidades changelog sair',
    markdown: '''
## Configurações do aplicativo

![Tela de configurações](${_shot}configuracoes.webp)

### Aparência

- **Tema** — Claro, Escuro ou Automático (acompanha o sistema do aparelho).
- **Esquema de Cores** — paleta da interface.

### Conta

| Item | O que faz |
| --- | --- |
| Notificações | Escolhe quais módulos podem notificar você (documentos, onboarding, alertas de RH, helpdesk…) |
| Meu Perfil | Nome, foto, cargo, status e atalhos de RH |
| Segurança e 2FA | App autenticador e dispositivos confiáveis |
| Gestão de Equipe | Arquivar, reativar e excluir colaboradores (perfis com permissão) |
| Meu Histórico | Suas atividades recentes no aplicativo |
| Rastreamento | GPS e localização de colaboradores |

### Sobre

- **Novidades** — notas de versão, melhorias e correções entregues.
- **Central de Ajuda** — esta tela.
- **Sair** — encerra a sessão no aparelho.
''',
  ),

  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'como-usar-a-ajuda',
    title: 'Como usar esta Central de Ajuda',
    icon: Icons.help_center_outlined,
    keywords:
        'ajuda central guia manual chamado busca pesquisa tutorial tour academia aba diferenca onde procurar',
    markdown: '''
## Como usar esta Central de Ajuda

![Central de Ajuda](${_shot}ajuda-central.webp)

A ajuda do $_app é organizada em quatro abas, em ordem crescente de profundidade. Saber qual usar economiza tempo:

| Aba | Use quando | Formato |
| --- | --- | --- |
| **Central de Ajuda** | Você tem uma dúvida pontual e quer a resposta em 30 segundos | Pergunta e resposta curta |
| **Guias** | Você quer aprender a executar um fluxo do início ao fim | Roteiro numerado com captura de tela |
| **Manual** | Você quer entender a regra: campos, status, permissões, comportamento | Documentação de referência |
| **Meus Chamados** | Você já pediu ajuda ao TI e quer acompanhar | Lista dos seus tickets |

### Atalhos do topo

- **Rever tutorial** — reinicia a introdução guiada da navegação.
- **Guias passo a passo** / **Manual completo** — saltam para as abas correspondentes.
- **Abrir chamado** — cria um ticket para o Suporte T.I.
- **Meus chamados** — acompanha o que você já abriu.

### Sobre a busca

As três primeiras abas têm busca própria e independente:

- Na **Central de Ajuda**, a busca varre título, resposta e etiquetas.
- Nos **Guias**, varre título, descrição, palavras-chave **e o texto de cada passo** — procurar "holerite" encontra o passo mesmo que a palavra não esteja no título do guia.
- No **Manual**, varre o corpo inteiro do artigo.

> **🔍 Comece genérico**
>
> Termos amplos ("card", "ponto", "permissão") trazem mais resultados úteis do que a frase exata do seu problema. Vá refinando a partir do que aparecer.

### As capturas de tela

Toda captura nos Guias e no Manual é clicável: toque para abrir em tela cheia, com zoom e arrasto, quando precisar ler o rótulo de um botão.
''',
  ),

  ManualArticle(
    category: '1. Guia de Início Rápido',
    id: 'instalar-e-atualizar',
    title: 'Instalar o app, usar no navegador e manter atualizado',
    icon: Icons.install_mobile_outlined,
    keywords:
        'instalar apk android pwa navegador iphone tela de inicio atualizar versao nova versao recarregar offline sem internet',
    markdown: '''
## Instalar o app, usar no navegador e manter atualizado

O $_app funciona de três jeitos, com a mesma conta e os mesmos dados:

| Onde | Como usar | Observação |
| --- | --- | --- |
| **Android** | Instale o APK distribuído pelo TI | Recebe notificações com o app fechado e chamadas em tela cheia |
| **Navegador** (computador) | Abra o endereço da empresa | Ideal para quem passa o dia no escritório |
| **iPhone / PWA** | No Safari, toque em **Compartilhar → Adicionar à Tela de Início** e abra pelo ícone criado | Sem instalar pela Tela de Início, o iPhone não entrega notificações |

### Atualizações

- **Navegador e PWA:** quando sai uma versão nova, aparece o aviso *"Nova versão do aplicativo disponível! Recarregue a página."* Recarregue quando terminar o que está fazendo — nada se perde.
- **Android:** o TI distribui o APK novo. A versão instalada aparece em **Configurações → Sobre** e em **Configurações → Novidades**, que lista o que mudou em cada versão.

### Sem internet

O $_app continua abrindo as conversas já carregadas no aparelho. Mensagens de texto enviadas sem conexão entram numa **fila** e saem sozinhas quando a internet volta. Fotos e arquivos precisam de conexão: sem ela, a mensagem fica marcada com erro para você reenviar.

> **💡 Dica**
>
> Se algo parecer desatualizado no navegador, recarregue a página. No Android, puxe a lista para baixo para atualizar.
''',
  ),
  // ══════════════════ 2. Comunicação ══════════════════
  ManualArticle(
    category: '2. Comunicação',
    id: 'canais',
    title: 'Canais, espaços de trabalho e comunicados',
    icon: Icons.campaign_outlined,
    keywords:
        'canais espacos de trabalho workspace comunicado aviso estou ciente confirmacao leitura anuncio oficial thread categoria publico privado notificacao silenciar mencao arroba canal aqui editar apagar mensagem novas mensagens',
    markdown: '''
## Canais e espaços de trabalho

![Espaços de trabalho](${_shot}workspaces.webp)

Um **canal** é o espaço oficial de um departamento ou processo. Diferente de uma conversa, ele tem categoria, pode ter um funil de trabalho associado e é moderável pela administração.

### Categorias de canal

| Categoria | Uso típico |
| --- | --- |
| Financeiro | Liberações, pagamentos e aprovações de valor |
| Faturamento | Emissão e correção de notas, OS e produtos |
| Operacional | Rotina de campo, logística, manutenção |
| Informativo | Comunicados e avisos gerais |
| RH | Assuntos de pessoal e processos do RH |
| Comercial | Vendas, metas e relacionamento com o cliente |
| TI | Sistemas, infraestrutura e suporte técnico |

Use a busca e os filtros de categoria para reduzir a lista. A barra de categorias mostra apenas as que têm canal — ela não oferece filtro que não leva a lugar nenhum. O ícone de bússola abre a descoberta de canais públicos que você ainda não segue.

## Escolhendo quanto o canal te notifica

O ícone de sino, na barra do canal, define quanto aquele espaço te interrompe. A mesma opção fica em **Informações do canal → Minhas notificações**.

| Opção | Quando usar |
| --- | --- |
| **Todas as mensagens** | Canal do seu dia a dia, onde tudo importa |
| **Somente menções** | Canal que você acompanha, mas onde só precisa reagir quando é chamado |
| **Silenciado** | Canal de consulta: continua na sua lista, sem notificar |

É uma preferência **sua**: não muda nada para os outros membros, e quem administra o canal não a controla.

> **💡 Prefira silenciar o canal a desligar o app**
>
> Um canal movimentado notificando tudo costuma acabar com o colaborador desligando a notificação do sistema inteiro — e aí ele perde o que era urgente. Ajustar canal a canal resolve sem esse custo.

### Chamando o canal inteiro

Digite **@** e escolha **@canal** ou **@aqui** no topo da lista de sugestões. Essas menções alcançam **inclusive quem está em "somente menções"**, e a notificação chega destacada para quem foi citado.

> **📣 Use com parcimônia**
>
> `@canal` é a ferramenta que fura o silêncio que as pessoas escolheram. Reserve para o que realmente precisa de atenção agora; usado à toa, elas passam a silenciar o canal por completo.

Dentro de um tópico as menções coletivas não aparecem — uma resposta em thread não deve virar aviso geral.

## Corrigindo e removendo o que você enviou

Toque e segure a mensagem para abrir as ações:

- **Editar** — corrige o texto; a bolha passa a mostrar **"editado"**. Anúncios e enquetes não são editáveis, porque já carregam confirmações de leitura e votos.
- **Apagar** — remove para todos. Quem administra o workspace também pode apagar mensagem de terceiro, e a ação fica registrada na auditoria.

### Onde você parou

Ao reabrir um canal com mensagens novas, uma régua **"Novas mensagens"** marca o ponto em que sua leitura parou.

## Comunicados com "Estou Ciente"

![Comunicado com confirmação de leitura](${_shot}comunicados.webp)

Comunicados oficiais aparecem marcados como **ANÚNCIO OFICIAL**. Quando o autor exige confirmação, a mensagem traz o botão **Estou Ciente** no rodapé.

- Para o colaborador: leia e toque no botão. A confirmação grava nome, data e hora.
- Para o gestor: o cabeçalho do canal mostra o percentual de ciência coletado, e o detalhe do comunicado lista quem confirmou e quem está pendente.

> **📢 Quando usar**
>
> Reserve o "Estou Ciente" para o que exige prova de comunicação: mudança de política, diretriz de segurança, alteração de processo. Usado em excesso, vira ruído e as pessoas param de ler.

### Threads

Para discutir um ponto específico, responda **em thread**. A discussão sai do fluxo principal e o canal continua legível para quem não participa daquele assunto.
''',
  ),
  ManualArticle(
    category: '2. Comunicação',
    id: 'conversas',
    title: 'Conversas diretas, grupos e assistente de IA',
    icon: Icons.forum_outlined,
    keywords:
        'conversa dm mensagem direta grupo administrador anexo midia favoritos estrela criptografia assistente ia contatos filtro departamento',
    markdown: '''
## Conversas diretas e grupos

![Lista de conversas](${_shot}conversas.webp)

As conversas do $_app são de dois tipos:

1. **Mensagens diretas (1:1)** — bate-papo privado entre duas pessoas, **criptografado de ponta a ponta**.
2. **Grupos** — conversas coletivas cuja administração é independente do cargo global: quem cria administra e pode promover ou remover administradores do próprio grupo.

### Encontrar pessoas

![Contatos por departamento](${_img}novo-chat-por-departamento.webp)

A lista de contatos é agrupada por filial e departamento (Faturamento, Comercial/Vendas, Diretoria, RH, TI…), o que evita depender de agenda telefônica para falar com um colega.

### Recursos da conversa

| Recurso | Descrição |
| --- | --- |
| Anexos | Fotos, documentos e áudios enviados direto do chat |
| Favoritos | Mensagens marcadas com estrela, reencontradas sem rolar o histórico |
| Encaminhar | Repassa uma mensagem para outra conversa ou canal |
| Busca | Localiza mensagens dentro da conversa |

### Assistente de IA

O **Assistente de IA** é uma conversa como outra qualquer, usada para tirar dúvidas de processo e de uso do sistema. O histórico é individual e pode ser apagado pelo próprio usuário. A credencial que alimenta o assistente é configurada pelo TI no Painel Admin.
''',
  ),
  ManualArticle(
    category: '2. Comunicação',
    id: 'chamadas',
    title: 'Chamadas de voz, vídeo e reuniões',
    icon: Icons.videocam_outlined,
    keywords:
        'chamada ligacao voz video reuniao sala grupo compartilhar tela perdidas historico bloqueio biometria keyguard',
    markdown: '''
## Chamadas e reuniões

![Histórico de chamadas](${_shot}chamadas.webp)

A aba **Chamadas** guarda o histórico em três filtros: **Todas**, **Perdidas** e **Reuniões**.

### Modalidades

- **Chamada 1:1** — iniciada no cabeçalho de uma conversa direta. O aparelho do destinatário toca e vibra mesmo com o app em segundo plano.
- **Sala de reunião (grupo)** — iniciada no cabeçalho de um canal ou grupo. O sistema cria a sala e publica o convite no próprio chat; quem quiser entra com um toque.

### Durante a chamada

A barra inferior oferece: alternar câmera, silenciar microfone, compartilhar tela, abrir o chat da reunião e ajustar a qualidade do vídeo conforme a conexão.

> **🔒 Proteção de tela bloqueada**
>
> Se você atende com o celular bloqueado, minimizar a chamada ou voltar ao app exige biometria ou senha do aparelho. É o que impede que conversas fiquem expostas em um celular perdido.
''',
  ),

  ManualArticle(
    category: '2. Comunicação',
    id: 'notificacoes',
    title: 'Notificações no celular e no navegador',
    icon: Icons.notifications_active_outlined,
    keywords:
        'notificacao notificacoes push alerta responder marcar como lida silenciar mencao nao chega nao recebo iphone navegador ativar bateria horario silencioso',
    markdown: '''
## Notificações no celular e no navegador

As notificações do $_app seguem o formato dos mensageiros que você já usa: **uma notificação por conversa**, com a foto e o nome de quem enviou e as últimas mensagens empilhadas.

### No celular (Android)

| Você vê | O que significa |
| --- | --- |
| Foto e nome do remetente | Em grupos e canais, o nome do grupo fica no topo e cada linha mostra quem escreveu |
| **Mencionou você** | Alguém citou você com @ seu nome |
| Resumo "5 mensagens de 2 conversas" | Agrupa tudo que chegou enquanto você estava fora |

Direto da notificação, sem abrir o app:

- **Responder** — escreva e envie. A resposta aparece na própria notificação como "Você: …". Se não der para enviar (sem internet, sem permissão no canal), a linha vira **"⚠️ Não enviada"**.
- **Marcar como lida** — zera a conversa e tira a notificação da bandeja.

Abrir a conversa também remove a notificação dela.

### No navegador e no PWA

1. Vá em **Configurações → Notificações**.
2. Se aparecer o aviso **Notificações do navegador desativadas**, toque em **Ativar notificações** e aceite o pedido do navegador.
3. No iPhone, isso só funciona com o app instalado pela Tela de Início.

Com a janela do $_app em primeiro plano, a mensagem aparece como aviso dentro do app. Com o $_app aberto atrás de outra janela, ou fechado, aparece a notificação do sistema.

### Chamadas

Chamadas tocam em tela cheia no Android, mesmo com o aparelho bloqueado, e ignoram o horário silencioso. Uma chamada que não foi atendida em 1 minuto não toca mais depois.

### Quanto cada conversa te avisa

| Onde ajustar | Opções |
| --- | --- |
| **Configurações → Notificações** | Liga/desliga geral, por tipo (diretas, grupos, canais, workflow) e horário silencioso |
| Dentro de um **canal** | **Todas as mensagens**, **Somente menções** ou **Silenciado** |
| Dentro de uma **conversa** | **Silenciar notificações** (menu da conversa) |

> **⚠️ Não estou recebendo**
>
> Confira, nesta ordem: (1) permissão de notificação do $_app nas configurações do celular ou do navegador; (2) o liga/desliga geral e o horário silencioso em **Configurações → Notificações**; (3) se a conversa ou o canal está silenciado; (4) no Android, se a **otimização de bateria** não está restringindo o $_app — alguns fabricantes fecham apps em segundo plano. Persistindo, abra um chamado para o TI.
''',
  ),
  ManualArticle(
    category: '2. Comunicação',
    id: 'recursos-mensagem',
    title: 'Recursos das mensagens: anexos, leitura, favoritos e mais',
    icon: Icons.touch_app_outlined,
    keywords:
        'anexo galeria camera documento localizacao contato enquete evento quadro anuncio encaminhar favoritar favoritas copiar excluir fixar informacoes lida recebida quem leu mencao editar apagar',
    markdown: '''
## Recursos das mensagens

### O que dá para enviar

Toque no **+** ao lado do campo de texto:

| Opção | Para quê |
| --- | --- |
| **Galeria** / **Câmera** | Fotos e vídeos, com legenda |
| **Documento** | PDF, planilhas e outros arquivos |
| **Localização** | Compartilhar onde você está |
| **Contato** | Enviar os dados de uma pessoa |
| **Enquete** | Votação rápida no grupo ou canal |
| **Evento** | Convite com data e hora |
| **Quadro** | Abrir um quadro branco colaborativo (veja o artigo próprio) |
| **Anúncio** | Comunicado oficial com "Estou Ciente" — aparece só para quem tem permissão de publicar anúncios |

### Ações sobre uma mensagem

Toque e segure a mensagem para selecionar. A barra de seleção oferece **Encaminhar**, **Favoritar**, **Copiar** e **Excluir** — dá para selecionar várias de uma vez.

| Ação | Como funciona |
| --- | --- |
| **Responder** | Cita a mensagem original acima da sua resposta |
| **Editar** | Corrige o texto; a mensagem passa a mostrar "editado" |
| **Apagar** | A mensagem vira "mensagem apagada" para todos |
| **Encaminhar** | Envia a mensagem para outra conversa ou canal |
| **Fixar** | Mantém a mensagem no topo da conversa |
| **Favoritar** | Guarda em **Mensagens Favoritas** (menu ⋮ da tela inicial) |
| **Informações** | Mostra quem recebeu e quem leu, com horário |

### Quem leu minha mensagem?

Em **Informações**, a mensagem mostra quantas pessoas **leram**, **receberam** ou ainda estão **pendentes**, com o nome de cada uma. Em conversas diretas, aparece quando foi recebida e quando foi lida.

### Menções

Escreva **@** seguido do nome completo para chamar uma pessoa. **@canal** ou **@aqui** chamam todos os membros — inclusive quem deixou o canal em "somente menções". Use com moderação.

> **💡 Dica**
>
> Em canais, quem administra o espaço pode apagar mensagens de outros membros para moderação. Essa ação fica registrada na auditoria.
''',
  ),
  ManualArticle(
    category: '2. Comunicação',
    id: 'quadro-branco',
    title: 'Quadro branco colaborativo',
    icon: Icons.draw_outlined,
    keywords:
        'quadro branco lousa desenhar caneta marca texto borracha espessura anexo imagem pdf colaborativo desfazer limpar',
    markdown: '''
## Quadro branco colaborativo

O quadro branco é uma lousa compartilhada dentro de uma conversa ou canal: **todo mundo da conversa desenha junto**, em tempo real, por cima de imagens e arquivos anexados. Serve para explicar um trajeto, marcar um defeito numa foto ou rabiscar uma ideia numa reunião.

### Criar e abrir

No **+** do campo de mensagem, escolha **Quadro** e dê um nome. O quadro vira um cartão na conversa; toque em **Abrir quadro** para entrar. Só membros da conversa ou do canal acessam.

### Ferramentas

| Ferramenta | Uso |
| --- | --- |
| **Caneta** | Traço sólido |
| **Marca-texto** | Destaque translúcido, por cima de texto ou imagem |
| **Borracha** | Apaga traços |
| **Espessura** | Fino (2px), Médio (4px), Grosso (8px) ou Muito grosso (16px) |
| **Desfazer meu último traço** | Desfaz só o que **você** desenhou — não mexe no traço dos outros |
| **Limpar traços** | Remove os desenhos do quadro (pede confirmação) |

### Anexos

Adicione uma **imagem da galeria**, **tire uma foto** ou anexe um **arquivo** (PDF, planilha, documento) e desenhe por cima. Com **Mover anexos** ativo, dá para arrastar e redimensionar; para tirar um anexo, use **Remover anexo do quadro**.

> **💡 Dica**
>
> Para marcar um problema num equipamento, tire a foto direto pelo quadro e circule o ponto com a caneta: a equipe vê a marcação na hora.
''',
  ),
  // ══════════════════ 3. Operação ══════════════════
  ManualArticle(
    category: '3. Operação',
    id: 'kanban-builder',
    title: 'Presets, criação e edição do espaço de trabalho',
    icon: Icons.dashboard_customize_outlined,
    keywords:
        'kanban builder canal novo fluxo etapas funil categoria tipo workflow preset modelo duplicar editar workspace icone cor etapa inicial final cancelamento mover cards',
    markdown: '''
## Montando um espaço de trabalho

![Criação de canal com Kanban Builder](${_shot}canal-builder.webp)

Ao criar um canal (**Canais > Novo Fluxo**), você define:

1. **Preset** — o modelo de partida (ver abaixo).
2. **Nome e descrição** — o que aquele espaço resolve.
3. **Aparência** — ícone e cor do workspace.
4. **Categoria** — Financeiro, Faturamento, Operacional, Informativo, RH, Comercial ou TI.
5. **Etapas** — as colunas do Kanban.
6. **Membros e operadores** — quem participa e quem atende.

O preset é só o ponto de partida: **tudo continua ajustável** antes de confirmar, e também depois de o canal existir.

## Presets: seus próprios modelos

Os modelos deixaram de ser uma lista fixa do sistema. O ícone de modelos, no topo da aba **Canais**, abre a biblioteca de presets.

| Ação | Como |
| --- | --- |
| Usar | Escolha o preset na faixa horizontal ao criar o canal |
| Criar | Botão **Novo Preset** na biblioteca |
| Editar | Toque no preset da empresa e altere o que precisar |
| Duplicar | Menu do preset → **Duplicar**; abre uma cópia editável já preenchida |
| Excluir | Menu do preset → **Excluir** (os canais já criados não são afetados) |
| Salvar o que você montou | Ícone de marcador na tela de criação ou de edição do workspace |

Um preset guarda a identidade (nome, ícone, cor, categoria), o formulário do card, o modo de atribuição e todas as etapas do funil.

> **📌 Modelos do sistema são somente leitura**
>
> Os modelos que vêm de fábrica não podem ser alterados nem excluídos — use **Duplicar** para criar a sua versão. Isso evita que um ajuste local quebre o padrão de quem ainda depende dele.

Um preset pode ser **compartilhado com a empresa** (qualquer gestor usa) ou **privado** (só você enxerga). A escolha fica no fim do editor.

## Editando as etapas

Na seção **Etapas do Kanban**:

- **Arraste pelo ícone ☰** para reordenar.
- **Toque no ícone** da etapa para trocar o desenho; **na paleta**, para trocar a cor.
- **Escreva no nome** para renomear.
- **Menu ⋮ da etapa** para marcá-la como inicial, de conclusão ou de cancelamento, e para removê-la.

### O que cada marcação significa

| Marcação | Efeito |
| --- | --- |
| **Inicial** | É onde os cards novos nascem |
| **Conclusão** | Fecha o card e alimenta os indicadores |
| **Cancelamento** | Sai do funil, não conta para o SLA e vai para a aba Cancelados |

> **⚠️ Marque a etapa de cancelamento, não confie no nome**
>
> Antes, o sistema reconhecia o cancelamento pela palavra "Cancelado". Se o seu funil usa "Recusado", "Encerrado" ou "Reprovado", **marque a etapa pelo menu ⋮** — sem isso ela seria tratada como uma coluna comum do quadro.

## Editando o workspace depois de pronto

O lápis ao lado do nome, em **Informações do canal**, abre a edição completa: nome, descrição, ícone, cor, categoria, permissão de publicação, ligar/desligar o workflow e as etapas do Kanban.

### Removendo uma etapa que tem cards

Cada etapa mostra quantos cards estão nela. Ao remover uma etapa ocupada, o sistema **pergunta para onde mover os cards** e só então conclui. A mudança fica registrada no histórico de cada card.

> **🔒 Nenhum card fica órfão**
>
> Se o destino escolhido também for removido na mesma edição, a operação é recusada por inteiro — nada é salvo pela metade.

Renomear uma etapa é seguro: os cards que estavam nela acompanham o novo nome automaticamente.

> **👤 Membros e operadores**
>
> Continuam sendo geridos na tela de **Informações do canal**, não no editor — a definição de quem opera o workflow exige permissão mais alta do que a de editar o espaço.
''',
  ),
  ManualArticle(
    category: '3. Operação',
    id: 'workflow',
    title: 'Ciclo de vida do card, SLA e responsabilidades',
    icon: Icons.view_kanban_outlined,
    keywords:
        'card demanda solicitacao operador solicitante assumir atendimento fila pool sla prioridade urgente anexo historico visualizacao board lista compacta',
    markdown: '''
## Ciclo de vida do card

![Quadro Kanban](${_img}workflow-kanban.webp)

1. **Abertura** — qualquer membro do canal cria o card com título, descrição, prioridade, valores (quando houver) e anexos.
2. **Atribuição** — se o canal tem operador fixo, o card já nasce atribuído; se opera em fila, fica disponível até alguém tocar em **Assumir Atendimento**.
3. **Movimentação** — o operador arrasta o card entre as colunas. Cada transição grava autor, horário e o tempo que o card passou na etapa anterior.
4. **Conclusão** — o operador anexa o comprovante e finaliza. O card é arquivado com todo o histórico preservado.

### Prioridades

| Prioridade | Quando usar |
| --- | --- |
| Baixa | Sem impacto imediato na operação |
| Média | Rotina normal do processo |
| Alta | Impacta prazo ou cliente |
| Urgente | Operação parada, precisa de ação agora |

### Quem pode o quê

| Ação | Solicitante | Operador / Gestor |
| --- | :---: | :---: |
| Abrir o card | Sim | Sim |
| Acompanhar o progresso | Sim | Sim |
| Assumir o atendimento | Não | Sim |
| Mover de etapa | Não | Sim |
| Anexar comprovante conclusivo | Não | Sim |
| Finalizar ou arquivar | Não | Sim |

> **⏸️ "Aguardando Solicitante"**
>
> É um status de pausa: use quando a tratativa depende de um documento ou informação que só o solicitante pode fornecer. Deixa explícito que a bola está do outro lado.

### Visualizações

- **Quadro (Kanban)** — colunas verticais, melhor para acompanhamento visual.
- **Lista** — volume alto, ordenação por prazo e filtro por responsável.
- **Compacta** — telas pequenas ou dezenas de chamados simultâneos; mostra só título, status e prazo.
''',
  ),
  ManualArticle(
    category: '3. Operação',
    id: 'helpdesk',
    title: 'Helpdesk: chamados de TI e manutenção',
    icon: Icons.confirmation_number_outlined,
    keywords:
        'helpdesk chamado ticket suporte ti categoria prioridade status novo em andamento pendente fornecedor resolvido cancelado sla fila atendimento',
    markdown: '''
## Helpdesk

O Helpdesk tem dois lados sobre a mesma base:

- **Central de Ajuda** — onde você abre e acompanha os seus chamados.
- **Helpdesk TI** — a fila de atendimento, visível só para quem tem permissão de resolver.

![Fila de chamados do Helpdesk](${_shot}helpdesk.webp)

### Categorias de chamado

| Categoria | Exemplos |
| --- | --- |
| Sistema / Software | Erro no app, lentidão, comportamento inesperado |
| Equipamentos / Hardware | Computador, impressora, leitor de ponto |
| Internet / Rede | Queda de conexão, Wi-Fi, VPN |
| Acessos / Credenciais | Liberação de módulo, senha, permissão |
| Dúvida Geral | Como fazer algo no sistema |
| Outro | O que não se encaixa acima |

### Prioridades

Baixa · Normal · Alta · Urgente. Marcar tudo como Urgente faz o filtro perder o sentido — use a prioridade que reflete o impacto real na operação.

### Status do chamado

| Status | Significado |
| --- | --- |
| Novo | Aberto, ainda sem atendente designado |
| Em Andamento | Técnico trabalhando no caso |
| Pendente Fornecedor | Depende de terceiro (garantia, operadora, fabricante) |
| Resolvido | Encerrado com solução aplicada |
| Cancelado | Encerrado sem tratativa |

### Conversa do chamado

![Conversa dentro do chamado](${_shot}helpdesk-ticket.webp)

Cada ticket abre uma thread própria entre solicitante e técnico. Mensagens, fotos e arquivos ficam presos àquele chamado e não se misturam com os outros chats. O cabeçalho mostra status, categoria, prioridade, há quanto tempo está aberto e quem é o responsável.

> **📎 Chamado com evidência resolve mais rápido**
>
> Anexe print da tela, foto do equipamento ou o texto exato do erro. Descrição vaga é a principal causa de idas e vindas.
''',
  ),

  ManualArticle(
    category: '3. Operação',
    id: 'minha-operacao',
    title: 'Minha Operação: tudo que está com você',
    icon: Icons.assignment_ind_outlined,
    keywords:
        'minha operacao meus cards atribuidos atrasados hoje proximos sem prazo concluidos prazo responsavel todos os workspaces',
    markdown: '''
## Minha Operação

A tela **Minha Operação** responde uma pergunta simples: *o que está comigo agora?* Ela reúne os cards atribuídos a você **em todos os espaços de trabalho**, sem precisar abrir quadro por quadro.

Abra pelo menu **⋮** da tela inicial → **Minha Operação**.

### Como os cards são organizados

| Grupo | O que entra |
| --- | --- |
| **Em atraso** | Prazo já passou e o card não foi concluído |
| **Para hoje** | Vence hoje |
| **Próximos** | Vence nos próximos dias |
| **Sem prazo** | Card sem data de entrega |
| **Concluídos** | Já estão na etapa final ou foram cancelados |

Cada card mostra o espaço de trabalho de onde veio. Toque para abrir esse espaço de trabalho e agir no card por lá.

### O que não aparece

- Cards arquivados.
- Cards que você **abriu** como solicitante mas que estão com outra pessoa — eles continuam no quadro do workspace.
- Cards de workspaces dos quais você não é mais membro.

> **💡 Dica**
>
> Comece o dia por aqui: resolva **Em atraso** e **Para hoje** antes de abrir os quadros.
''',
  ),
  // ══════════════════ 4. Pessoas & RH ══════════════════
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'funcionarios',
    title: 'Funcionários e ficha cadastral',
    icon: Icons.contact_page_outlined,
    keywords:
        'funcionario colaborador diretorio ficha matricula vinculo clt pj aprendiz situacao ativo ferias afastado desligado dependente historico salario admissao',
    markdown: '''
## Funcionários

![Diretório de funcionários](${_shot}rh-funcionarios.webp)

O diretório é a fonte de verdade sobre o quadro de pessoal. O topo resume por situação: **Total**, **Ativo**, **Férias**, **Afastado** e **Desligado**.

Cada linha mostra filial, departamento, cargo, matrícula e tempo de casa, com etiquetas de **vínculo** (CLT, PJ, Aprendiz) e de **situação**.

### O que a ficha guarda

| Bloco | Conteúdo |
| --- | --- |
| Dados pessoais | Nome, documentos, contato |
| Dados funcionais | Filial, departamento, cargo, matrícula, admissão |
| Vínculo | CLT, PJ, Aprendiz e situação atual |
| Dependentes | Para benefícios e informações de folha |
| Histórico | Mudanças de cargo e salário ao longo do tempo |

### Vínculo com a conta de acesso

A ficha de RH e o usuário do aplicativo são registros distintos e precisam ser **vinculados**. É esse vínculo que faz holerites, documentos, ponto, onboarding e desempenho aparecerem em "Meu espaço" do colaborador.

> **🔗 Sem vínculo, não chega**
>
> Um funcionário cadastrado mas não vinculado existe no RH e não recebe nada no app. É a causa mais comum de "o holerite não apareceu para ele".

As **áreas e cargos** disponíveis no cadastro vêm do Catálogo mantido no módulo de Recrutamento — mantê-lo limpo evita cargos duplicados com nomes diferentes.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'documentos',
    title: 'Documentos digitais e controle de validade',
    icon: Icons.folder_shared_outlined,
    keywords:
        'documento aso cnh certificacao identidade validade vencimento vencido valido ciencia confirmacao leitura upload download meus documentos',
    markdown: '''
## Documentos digitais

![Gestão de documentos](${_shot}rh-documentos.webp)

Cada documento tem categoria (ASO, Identidade, Certificação…), dono, arquivo anexado e **data de vencimento** — é ela que gera a etiqueta de situação.

### Estados de validade

| Etiqueta | Significado |
| --- | --- |
| Válido | Dentro do prazo |
| Próximo do Vencimento | Entra na janela de alerta |
| Vencido | Prazo expirado — exige ação imediata |

### Exigir ciência do funcionário

A chave **"Exigir ciência do funcionário"** faz o documento pedir confirmação de leitura em **Meus Documentos**. A confirmação fica registrada com data e hora, servindo como prova de entrega.

### Fluxo completo

1. O RH cadastra o documento, informa o vencimento e anexa o arquivo.
2. Se necessário, liga a exigência de ciência.
3. O colaborador acessa **Meu Perfil > Meus Documentos**, baixa o arquivo e confirma a leitura.
4. Documentos vencidos e a vencer aparecem automaticamente em **Alertas RH**.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'ausencias',
    title: 'Ausências, férias e saldo aquisitivo',
    icon: Icons.event_busy_outlined,
    keywords:
        'ausencia falta atestado folga ferias saldo periodo aquisitivo aprovacao recusa calendario equipe comprovante afastamento',
    markdown: '''
## Ausências e férias

![Calendário de ausências](${_shot}rh-ausencias.webp)

O módulo tem três abas:

| Aba | Para que serve |
| --- | --- |
| Solicitações | Fila de pedidos enviados pelos colaboradores, com comprovante anexado |
| Calendário | Visão mensal das ausências da equipe |
| Saldos de férias | Período aquisitivo e dias disponíveis por pessoa |

### Legenda do calendário

- **Férias** — período de férias aprovado.
- **Atestado** — afastamento com comprovante médico.
- **Folga** — compensação ou folga concedida.
- **Aguardando aprovação** — pedido ainda pendente de decisão.

### Fluxo de aprovação

1. O colaborador abre o pedido em **Meu Perfil > Minhas Ausências e Férias** e anexa o comprovante pelo celular.
2. O RH recebe na aba Solicitações, confere e aprova ou recusa.
3. Aprovado, o período entra no calendário e no histórico oficial; recusado, o colaborador é notificado.

> **📅 Olhe o calendário antes de aprovar**
>
> A visão mensal existe para evitar aprovar duas saídas simultâneas no mesmo setor e descobrir isso só no dia.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'ponto',
    title: 'Controle de ponto e ajustes',
    icon: Icons.access_time_outlined,
    keywords:
        'ponto batida entrada saida espelho periodo horas extras banco de horas lancamento manual ajuste correcao auditoria regular',
    markdown: '''
## Controle de ponto

![Registros de ponto por período](${_shot}rh-ponto.webp)

A tela filtra por **intervalo de datas** e por **funcionário** (ou "Todos"). Os registros vêm agrupados por dia, cada linha com horário, tipo de batida (Entrada/Saída), nome do colaborador e a marcação de origem do registro.

### Lançamento manual

Quando há falha de marcação, use **Lançar registro** informando funcionário, data, hora e tipo. O menu de três pontos em cada linha permite editar ou excluir uma batida incorreta.

> **🧾 Todo ajuste é auditável**
>
> Lançamentos e correções manuais ficam registrados com autor e horário. É o que permite defender o espelho de ponto em uma verificação.

### Lado do colaborador

Em **Meu Perfil > Meu Ponto**, a pessoa consulta o próprio espelho do período e identifica divergências antes do fechamento da folha — o que reduz a correção de última hora.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'holerites',
    title: 'Holerites e comprovação de entrega',
    icon: Icons.request_quote_outlined,
    keywords:
        'holerite contracheque recibo pagamento folha competencia pdf emitir visualizado notificacao segunda via',
    markdown: '''
## Holerites

![Distribuição de holerites](${_shot}rh-holerites.webp)

O RH emite o holerite selecionando **funcionário** e **competência** (mês/ano) e anexando o PDF. O colaborador recebe notificação assim que o arquivo é publicado.

### Comprovação de entrega

Cada linha exibe a etiqueta **Visualizado** com data e hora da abertura. Essa marca é a prova de que o contracheque foi disponibilizado e acessado — substitui a assinatura de recebimento em papel.

### Filtros

Os seletores de **Funcionário** e **Ano** no topo reduzem a lista para auditar uma competência específica ou reenviar um documento.

### Lado do colaborador

Em **Meu Perfil > Meus Holerites**, a pessoa acessa o histórico completo e baixa o PDF do celular, sem precisar solicitar segunda via ao RH.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'beneficios',
    title: 'Benefícios: catálogo e adesões',
    icon: Icons.card_giftcard_outlined,
    keywords:
        'beneficio vale refeicao alimentacao plano saude odontologico operadora adesao desconto folha criptografado encerrar',
    markdown: '''
## Benefícios

O módulo tem duas abas: **Catálogo** (o que a empresa oferece) e **Adesões** (quem usa o quê).

### Catálogo

![Catálogo de benefícios](${_shot}rh-beneficios.webp)

Cada benefício tem nome, tipo (refeição, alimentação, saúde…) e operadora. Use **Novo benefício** para cadastrar e o lápis para editar ou desativar um plano descontinuado.

### Adesões

![Registro de adesão](${_shot}rh-desempenho.webp)

Em **Nova adesão** você escolhe o funcionário e o benefício, informa a **data de adesão** e, opcionalmente, o **desconto em folha**.

> **🔐 Valor sensível**
>
> O desconto em folha é armazenado criptografado por organização.

Adesões encerradas mantêm o histórico: o registro não é apagado, apenas deixa de estar ativo.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'desempenho',
    title: 'Desempenho: ciclos e avaliações 1:1',
    icon: Icons.insights_outlined,
    keywords:
        'desempenho ciclo avaliacao 360 autoavaliacao gestor pares subordinados nota feedback historico meta 1:1 competencia',
    markdown: '''
## Desempenho

O módulo tem duas abas: **Ciclos** e **Avaliações 1:1**.

### Ciclos

Um ciclo é a janela em que a avaliação acontece. Ele organiza as diferentes perspectivas dentro do mesmo período:

| Perspectiva | Quem avalia |
| --- | --- |
| Autoavaliação | O próprio colaborador |
| Gestor | O líder direto |
| Pares | Colegas do mesmo nível |
| Subordinados | Quem é liderado pela pessoa |

### Avaliações 1:1

![Avaliações 1:1](${_shot}rh-avaliacoes.webp)

Cada registro guarda o colaborador, a **nota**, o **papel de quem avaliou**, a data e o texto do feedback. O seletor de Funcionário filtra a lista e revela a evolução ao longo do tempo.

### Lado do colaborador

Em **Meu Perfil > Meu Desempenho**, a pessoa acompanha as próprias notas e devolutivas e responde a autoavaliação enquanto o ciclo está aberto.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'onboarding',
    title: 'Onboarding e checklists de integração',
    icon: Icons.assignment_outlined,
    keywords:
        'onboarding integracao checklist template padrao time primeiro dia equipamento treinamento experiencia',
    markdown: '''
## Onboarding

![Templates de onboarding](${_shot}rh-onboarding.webp)

Um **template** é um checklist reutilizável de integração. O template marcado como **Padrão** vale para todo novo colaborador; os demais são específicos por time (ex.: Integração Comercial).

### O que costuma entrar no checklist

- Criação de e-mail corporativo e acessos aos sistemas
- Entrega de equipamento, crachá e uniforme
- Treinamentos obrigatórios e leitura de políticas
- Apresentação à equipe e ao gestor direto
- Conferência de documentos admissionais

### Como funciona na prática

1. O RH cria ou escolhe o template.
2. Vincula o template ao novo funcionário.
3. Cada item vira uma tarefa acompanhada, com responsável e conclusão.
4. O colaborador vê a própria lista em **Meu Perfil > Meu Onboarding** e marca o que concluiu.

> **⏱️ Feche antes do fim da experiência**
>
> Deixar itens de onboarding abertos até o fim do contrato de experiência é a origem clássica de pendência de documento e de acesso.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'alertas',
    title: 'Alertas de RH',
    icon: Icons.warning_amber_rounded,
    keywords:
        'alerta vencimento documento contrato experiencia aniversario pendencia prazo notificacao preventivo',
    markdown: '''
## Alertas de RH

O módulo reúne automaticamente tudo que tem prazo e costuma passar despercebido:

| Alerta | Origem |
| --- | --- |
| Documento vencido ou a vencer | Módulo Documentos |
| Fim de contrato de experiência | Data de admissão na ficha do funcionário |
| Aniversariantes do mês | Ficha do funcionário |
| Pendências de aprovação | Ausências, documentos e onboarding |

Cada alerta leva direto ao registro de origem, para resolver sem procurar em outro módulo.

### Receber no celular

Em **Configurações > Notificações**, ative o canal **Alertas RH** para ser avisado sem depender de abrir o painel. Este canal usa prioridade alta por padrão, já que trata de prazos.
''',
  ),
  ManualArticle(
    category: '4. Pessoas & RH',
    id: 'meu-espaco',
    title: 'Meu espaço: autoatendimento do colaborador',
    icon: Icons.badge_outlined,
    keywords:
        'meu perfil meus documentos minhas ausencias meu ponto meus holerites meu onboarding meu desempenho autoatendimento organizacional filial cargo',
    markdown: '''
## Meu espaço (autoatendimento)

![Meu perfil](${_shot}meu-perfil.webp)

**Meu Perfil** concentra o que é seu, sem depender do RH para consultar:

### Informações organizacionais

Filial de lotação, departamento/setor, cargo/função e nível de acesso. Esses campos definem em quais canais e filas você aparece.

### Atalhos de Recursos Humanos

| Atalho | O que você faz lá |
| --- | --- |
| Meus Documentos | Consultar, baixar e dar ciência |
| Meu Onboarding | Acompanhar e marcar itens da integração |
| Minhas Ausências e Férias | Abrir pedidos e anexar comprovantes |
| Meu Ponto | Consultar o espelho do período |
| Meus Holerites | Baixar contracheques |
| Meu Desempenho | Ver notas e responder autoavaliação |

### Suporte T.I.

O bloco no topo do perfil leva à Central de Ajuda e, para quem atende, ao Painel Helpdesk.

> **ℹ️ Não vejo meus holerites/documentos**
>
> Quase sempre a ficha de RH ainda não foi vinculada à sua conta de acesso. Abra um chamado para o RH ou o TI verificar o vínculo.
''',
  ),

  // ══════════════════ 5. Recrutamento ══════════════════
  ManualArticle(
    category: '5. Recrutamento',
    id: 'recrutamento-visao',
    title: 'Central de Recrutamento e pipeline',
    icon: Icons.person_search_outlined,
    keywords:
        'recrutamento central visao geral funil conversao candidato fonte nivel pipeline etapa aderencia pretensao exportar csv',
    markdown: '''
## Central de Recrutamento

A central tem seis abas: **Visão Geral**, **Pipeline**, **Divulgação**, **Vagas**, **Avaliações** e **Ajustes**.

### Visão Geral

![Visão geral do recrutamento](${_shot}recrut-visao-geral.webp)

Indicadores do topo: **Candidatos**, **Em processo**, **Contratados**, **Conversão** e **Contratações 30d**. Abaixo, o funil por etapa e a distribuição de candidatos por fonte e por nível. **Exportar CSV** leva os dados para fora quando é preciso relatório externo.

### Pipeline

![Pipeline de candidatos](${_shot}recrut-pipeline.webp)

Lista os candidatos por etapa, cada um com cargo pretendido, localidade, pretensão salarial, origem e percentual de aderência. A busca aceita nome, e-mail ou cargo; o filtro **Meus candidatos** mostra só os que estão sob sua responsabilidade.

### Etapas padrão do funil

| Etapa | Natureza |
| --- | --- |
| Novo | Entrada — onde toda candidatura cai |
| Em análise | Triagem de currículo |
| Entrevista | Conversa com o time |
| Aprovado | Aprovado, aguardando formalização |
| Contratado | Terminal — vira funcionário |
| Descartado | Terminal — encerra o processo |

### Conversão em funcionário

Ao mover o candidato para **Contratado**, use a conversão para criar a ficha de funcionário aproveitando os dados já preenchidos na candidatura — sem redigitar.
''',
  ),
  ManualArticle(
    category: '5. Recrutamento',
    id: 'carreiras',
    title: 'Vagas e página pública de carreiras',
    icon: Icons.public_outlined,
    keywords:
        'vaga publicar carreiras pagina publica link inscricao qr code whatsapp email divulgacao portal candidato texto chamada',
    markdown: '''
## Vagas e página de carreiras

![Divulgação e página de carreiras](${_shot}recrut-carreiras.webp)

### Publicar a vaga

Na aba **Vagas**, cadastre título, área, cargo, nível, local e faixa salarial. A vaga publicada passa a aparecer na página pública de carreiras.

### Divulgação

A aba **Divulgação** controla o canal público:

| Recurso | Uso |
| --- | --- |
| Página de carreiras ativa | Liga ou desliga a inscrição pública |
| Link de inscrição | Endereço para redes sociais, WhatsApp e material impresso |
| Copiar / WhatsApp / E-mail | Compartilhamento rápido do link |
| QR code | Cartaz e material impresso — o candidato aponta a câmera |
| Texto da página | Chamada e apresentação da empresa, editáveis |

Os indicadores do topo acompanham **inscrições nos últimos 30 dias**, **total pelo portal**, **quantos avançaram no funil** e **contratados** — é como você mede se a divulgação está trazendo gente qualificada.

> **🌐 Desligar a página não apaga candidaturas**
>
> Desativar a página apenas fecha novas inscrições. Os candidatos já registrados continuam no pipeline.
''',
  ),
  ManualArticle(
    category: '5. Recrutamento',
    id: 'provas-ia',
    title: 'Avaliações e provas geradas por IA',
    icon: Icons.auto_awesome_outlined,
    keywords:
        'prova questao ia inteligencia artificial multipla escolha gabarito cargo nivel quantidade banco questoes teste candidato',
    markdown: '''
## Avaliações e provas com IA

![Geração de questões com IA](${_shot}recrut-ia-questoes.webp)

Na aba **Avaliações** você monta o banco de questões aplicado aos candidatos.

### Gerar com IA

1. Toque em **Gerar com IA**.
2. Escolha o **cargo** e o **nível** (Júnior, Pleno, Sênior…).
3. Ajuste a **quantidade de questões** no controle deslizante.
4. Toque em **Gerar questões** e **revise** o resultado antes de aplicar.

> **🔒 O gabarito nunca vai ao candidato**
>
> A resposta correta fica só do lado da empresa. O candidato vê apenas o enunciado e as alternativas.

### Questões manuais

**Nova questão** permite escrever perguntas próprias e misturá-las com as geradas — útil para conteúdo específico do seu negócio, que a IA não conhece.

### Configuração da prova

O resumo abaixo dos botões mostra como a prova está montada (quantidade de questões e limite de tempo). Use **Ajustar** para alterar. O filtro **Filtrar por cargo** permite manter bancos distintos por posição.

> **✅ Sempre revise**
>
> A IA acerta muito, mas não conhece o contexto da sua empresa. Revisar a prova antes de aplicar evita questão ambígua ou fora da realidade da vaga.
''',
  ),
  ManualArticle(
    category: '5. Recrutamento',
    id: 'recrutamento-ajustes',
    title: 'Ajustes: etapas, catálogo e retenção LGPD',
    icon: Icons.tune_outlined,
    keywords:
        'ajustes etapa pipeline renomear reordenar catalogo area cargo lgpd retencao anonimizacao periodo 2 anos privacidade',
    markdown: '''
## Ajustes do recrutamento

A aba **Ajustes** concentra três configurações estruturais.

### Etapas do pipeline

![Etapas do pipeline](${_shot}recrut-etapas.webp)

Renomeie, reordene (setas) e crie etapas do funil. As etapas de **entrada** (Novo) e **terminais** (Contratado, Descartado) aparecem com cadeado: podem ser renomeadas, mas não removidas — o sistema depende delas para calcular conversão.

### Catálogo de áreas e cargos

![Catálogo de áreas e cargos](${_shot}recrut-catalogo.webp)

O catálogo alimenta vagas, filtros e o **cadastro de funcionários**. Cada área e cargo pode ser ativado, desativado ou renomeado.

> **🧹 Catálogo limpo evita retrabalho**
>
> "TI" e "Tecnologia da Informação" como áreas separadas quebram relatório e filtro. Padronize a nomenclatura aqui e o resto do sistema herda.

### Retenção de candidatos (LGPD)

O **período de retenção** define depois de quanto tempo candidatos não contratados são **anonimizados automaticamente**. É o controle que mantém o banco de talentos em conformidade sem depender de limpeza manual.
''',
  ),

  // ══════════════════ 6. Financeiro ══════════════════
  ManualArticle(
    category: '6. Financeiro',
    id: 'financeiro',
    title: 'Financeiro: pagar, receber e fluxo de caixa',
    icon: Icons.account_balance_wallet_outlined,
    keywords:
        'financeiro visao geral saldo contas a pagar receber despesa boleto cobranca inadimplencia fluxo de caixa extrato conciliacao movimentacao',
    markdown: '''
## Financeiro

O módulo tem quatro telas:

| Tela | O que responde |
| --- | --- |
| Visão Geral | Saldo, contas a pagar e a receber do período |
| Contas a Pagar | Despesas, boletos e pagamentos agendados |
| Contas a Receber | Faturamentos, cobranças e inadimplência |
| Fluxo de Caixa | Extrato de movimentações e conciliação |

### Ligação com a operação

![Canal de categoria financeira](${_shot}canal-builder.webp)

Solicitações financeiras que nascem no chat não devem virar mensagem solta: crie um canal de categoria **Financeiro** com o workflow **Liberação Contas a Pagar**. A demanda chega ao financeiro já com responsável, prazo e anexos organizados, e o histórico fica auditável.

> **🔁 Um processo, dois lugares**
>
> O canal Kanban trata da **aprovação** da despesa; o módulo Financeiro trata do **registro contábil e do caixa**. Um alimenta o outro — não substitui.
''',
  ),

  // ══════════════════ 7. Segurança e Governança ══════════════════
  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'rbac',
    title: 'Perfis e permissões (RBAC)',
    icon: Icons.lock_outline,
    keywords:
        'rbac permissao perfil acesso visualizar gerenciar super admin rh gestor colaborador sistema modulo chave salvar menu',
    markdown: '''
## Perfis e permissões (RBAC)

![Gerenciamento de acessos](${_shot}admin-rbac.webp)

O controle de acesso do $_app é baseado em **perfis** (RBAC). A tela **Painel Admin > Acessos** tem dois lados: à esquerda os **Perfis de Acesso**, à direita as permissões do perfil selecionado.

### As duas chaves de cada módulo

| Chave | O que libera |
| --- | --- |
| **Visualizar** | Abrir a tela do módulo e consultar os dados |
| **Gerenciar** | Alterar configurações, permissões e registros do módulo |

O contador ao lado do módulo (ex.: `1/2`) mostra quantas chaves estão ligadas.

### Perfis padrão

| Perfil | Alcance típico |
| --- | --- |
| Super Admin | Acesso total ao sistema, incluindo auditoria e backup |
| RH | Gestão completa de Recursos Humanos e recrutamento |
| Gestor | Gestão de equipe com visão de RH limitada |
| Colaborador | Acesso padrão de funcionário |

Perfis marcados como **SISTEMA** não podem ser excluídos, mas suas permissões podem ser ajustadas. Use o **"+"** para criar perfis sob medida (ex.: Coordenador de Faturamento).

> **🔑 Princípio do menor privilégio**
>
> Comece pelo mínimo necessário e libere sob demanda. É muito mais simples conceder uma permissão depois do que auditar excesso de acesso já distribuído.

Após ajustar as chaves, toque em **Salvar**. O menu lateral do usuário afetado é remontado no próximo carregamento a partir dessas permissões.
''',
  ),
  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'usuarios',
    title: 'Gestão de usuários e cadastros pendentes',
    icon: Icons.manage_accounts_outlined,
    keywords:
        'usuario conta cadastro pendente aprovar liberar bloquear desativar perfil papel funcao novo cadastro filial departamento',
    markdown: '''
## Gestão de usuários

![Gestão de usuários](${_shot}admin-usuarios.webp)

A aba **Gestão de Usuários** lista todas as contas com o perfil atribuído e a função declarada. O filtro alterna entre **Todos** e **Pendentes**.

### Cadastros pendentes

Quem se cadastra sozinho fica **pendente** até a liberação do TI. Enquanto isso, o login é bloqueado com aviso explícito na tela de entrada.

### Cadastro pelo painel

![Formulário de novo cadastro](${_img}admin-novo-cadastro.webp)

A aba **Novo Cadastro** cria a conta diretamente: dados do colaborador, filial, departamento e perfil de acesso. É o caminho usado quando o TI provisiona o acesso antes do primeiro dia de trabalho.

### Alterar ou desativar

Expanda a linha do usuário para trocar o perfil de acesso ou desativar a conta. Toda alteração vai para a auditoria com autor e horário.

> **👤 Desativar em vez de excluir**
>
> Desativar preserva o histórico de mensagens, cards e aprovações daquela pessoa. Excluir quebra a rastreabilidade de tudo que ela tocou.
''',
  ),
  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'auditoria',
    title: 'Auditoria, moderação e relatórios',
    icon: Icons.fact_check_outlined,
    keywords:
        'auditoria log registro imutavel historico moderacao advertir excluir mensagem canal relatorio uso usuarios ativos online metricas',
    markdown: '''
## Auditoria

![Logs de auditoria](${_img}admin-auditoria.webp)

A auditoria registra automaticamente as ações críticas — criação e movimentação de cards, alteração de permissões, exclusão de mensagens, logins e mudanças de cadastro — com autor, alvo e horário. Os registros são gerados no banco e não podem ser editados pela interface.

## Moderação de conteúdo

![Moderação de conteúdo](${_shot}admin-moderacao.webp)

A aba **Moderação** separa **Mensagens** e **Canais**. Em cada item, duas ações:

- **Advertir** — notifica o autor sobre a violação de política.
- **Excluir** — remove o conteúdo.

Ambas ficam registradas na auditoria. Advertências acumuladas podem gerar restrição temporária de envio de mensagens e mídia, pelo prazo definido pela administração.

## Relatórios de uso

![Relatórios de uso](${_shot}admin-relatorios.webp)

| Indicador | Leitura |
| --- | --- |
| Usuários Ativos | Contas em uso no período |
| Online Agora | Quem está conectado neste momento |
| Mensagens (Mês) | Volume de mensagens trocadas |
| Chamadas (Mês) | Volume de chamadas realizadas |
| Total de Chats / Canais | Tamanho da base de conversas |
| Mensagens por dia (7 dias) | Tendência recente de uso |

Serve para dimensionar adoção: um módulo liberado para todos e com uso próximo de zero costuma indicar falta de treinamento, não falta de necessidade.
''',
  ),
  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'backup',
    title: 'Backup e chave de IA',
    icon: Icons.backup_outlined,
    keywords:
        'backup exportar dump base dados cache midia sincronizar chave ia credencial assistente questoes',
    markdown: '''
## Backup

![Painel de backups](${_img}admin-backup.webp)

A aba **Backup** do Painel Admin permite exportar a base e sincronizar o cache de mídia.

> **💾 Rode antes de mudar estrutura**
>
> Antes de alterações estruturais — reorganizar workspaces, migrar perfis, limpar canais —, gere o backup. É a diferença entre um susto e uma perda.

## Chave de IA

A aba **Chave de IA** guarda a credencial usada por dois recursos:

- O **Assistente de IA** disponível nas conversas.
- A **geração de questões** do módulo de recrutamento.

Sem a chave configurada, ambos ficam indisponíveis — o assistente responde com mensagem de contingência em vez de falhar silenciosamente.
''',
  ),
  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'gps',
    title: 'Rastreamento de campo (GPS)',
    icon: Icons.location_on_outlined,
    keywords:
        'gps localizacao rastreamento campo mapa rota trajeto bateria permissao sempre permitir background acelerometro supervisor',
    markdown: '''
## Rastreamento de campo

![Configuração de GPS no aparelho](${_img}rastreamento-config.webp)

O rastreamento existe para logística e segurança de equipes externas: roteirização de atendimentos e localização de quem está em campo.

### Ativação no aparelho

1. Conceda a permissão de localização do Android como **"Sempre permitir"**.
2. Ative a chave de rastreamento em **Configurações > Rastreamento**.

> **📍 Por que "Sempre permitir"**
>
> Sem a permissão contínua, o Android interrompe a coleta assim que o app sai da tela — e o trajeto fica cheio de buracos.

### Consumo de bateria

O serviço é adaptativo: parado por mais de 5 minutos, suspende o envio de coordenadas e só retoma quando detecta movimento. Na prática, o consumo é uma fração do que um rastreador contínuo gastaria.

### Painel do supervisor

![Mapa de localização](${_img}admin-localizacao-lista.webp)

A aba **Localização** do Painel Admin mostra a posição da equipe no mapa, o trajeto das últimas horas, o nível de bateria e a velocidade de cada aparelho.
''',
  ),

  ManualArticle(
    category: '7. Segurança e Governança',
    id: 'privacidade',
    title: 'Privacidade e seus dados (LGPD)',
    icon: Icons.privacy_tip_outlined,
    keywords:
        'privacidade lgpd dados pessoais exportar meus dados titular pedido correcao eliminacao compartilhamento termos politica aceite documentos legais',
    markdown: '''
## Privacidade e seus dados (LGPD)

Tudo que envolve seus dados pessoais fica em **Configurações → Privacidade e Dados**, a Central de Privacidade e Dados.

### O que você encontra lá

| Seção | Para quê |
| --- | --- |
| **Documentos** | Termos de Uso, Política de Privacidade e demais políticas. Cada um mostra a versão e se é de **aceite obrigatório** ou **informativo** |
| **Histórico de aceites** | Quais versões você aceitou e quando |
| **Exportar meus dados agora** | Gera um arquivo JSON com os seus dados no $_app |
| **Novo Pedido do Titular (LGPD)** | Pedido formal à empresa, com prazo legal de resposta de **até 15 dias** |
| **Backup e Restauração** | Cópia cifrada das suas conversas |

### Tipos de pedido do titular

| Pedido | Quando usar |
| --- | --- |
| **Correção de Dados** (Art. 18, III) | Algum dado seu está incompleto, errado ou desatualizado |
| **Eliminação de Dados** (Art. 18, VI) | Você quer que dados tratados com base no seu consentimento sejam apagados |
| **Informação / Compartilhamento** (Art. 18, VIII) | Saber com quem seus dados foram compartilhados |

Descreva o pedido com clareza. Ele fica listado na própria Central com a data de abertura e o status.

### Quando a política muda

Se uma política de aceite obrigatório ganha versão nova com mudança relevante, o $_app mostra a tela de aceite de novo no próximo acesso.

> **ℹ️ Importante**
>
> Alguns dados precisam ser mantidos por obrigação legal (registros trabalhistas, por exemplo) mesmo após um pedido de eliminação. A resposta ao seu pedido explica o que foi apagado e o que precisa ser guardado.
''',
  ),
  // ══════════════════ 8. Automações ══════════════════
  ManualArticle(
    category: '8. Automações',
    id: 'automacoes',
    title: 'SMTP, templates e regras de automação',
    icon: Icons.mark_email_read_outlined,
    keywords:
        'smtp host porta usuario senha app password remetente from criptografada template email regra automacao gatilho etapa disparo',
    markdown: '''
## Comunicação e automações

O módulo tem três abas: **Servidor SMTP**, **Templates de E-mail** e **Regras de Automação**. Elas se completam nessa ordem.

### 1. Servidor SMTP

![Configuração SMTP](${_shot}auto-smtp.webp)

| Campo | Observação |
| --- | --- |
| Host | Endereço do servidor (ex.: smtp do seu provedor) |
| Porta | Normalmente 465 (SSL) ou 587 (TLS) |
| Usuário | E-mail de autenticação |
| Senha | Senha ou **App Password** — armazenada criptografada |
| Nome do Remetente | Nome exibido ao destinatário |
| E-mail do Remetente | Endereço que aparece no "De:" |

Enviar pelo domínio da empresa aumenta a entregabilidade e a confiança de quem recebe.

> **⚠️ Configure o SMTP primeiro**
>
> Sem servidor configurado, as regras de automação não têm por onde enviar e o disparo falha silenciosamente para o candidato.

### 2. Templates de e-mail

Crie as mensagens padrão do processo: confirmação de inscrição, convite para entrevista, feedback de reprovação, proposta. Um template bem escrito é reaproveitado por várias regras.

### 3. Regras de automação

![Nova automação](${_shot}auto-regras.webp)

Uma regra liga **uma etapa do funil** a **um template**:

> Quando o candidato for movido para a etapa **[Descartado]**, enviar o e-mail **[Feedback de reprovação]**.

Depois de salvar, a regra vale para todos os candidatos que passarem por aquela etapa.

> **🧪 Teste antes de anunciar**
>
> Mova um candidato de teste pela etapa configurada e confira a caixa de entrada. Assim você valida remetente, assunto e formatação antes que a regra alcance gente de verdade.
''',
  ),

  // ══════════════════ 9. Perguntas Frequentes ══════════════════
  ManualArticle(
    category: '9. Perguntas Frequentes',
    id: 'faq',
    title: 'Perguntas frequentes (FAQ)',
    icon: Icons.help_outline,
    keywords:
        'faq perguntas frequentes senha gps bateria canais anexo punicao holerite documento vinculo permissao modulo sumiu',
    markdown: '''
## Perguntas frequentes

### Como redefino a minha senha?

Na tela de login, toque em **Esqueci minha senha**, informe o e-mail cadastrado e siga o link recebido. O link é de uso único e expira.

### Um módulo sumiu do meu menu. É bug?

Quase nunca. O menu é montado a partir das suas permissões: se o item saiu, o seu perfil perdeu a chave "Visualizar" daquele módulo. Abra um chamado para o TI conferir em *Painel Admin > Acessos*.

### O GPS consome muita bateria?

Não. O serviço suspende o envio de coordenadas após 5 minutos parado e só retoma ao detectar movimento. O gasto é muito inferior ao de um rastreamento contínuo.

### Quem pode criar canais oficiais?

Perfis com permissão de **gerenciar** o módulo de canais — tipicamente TI e gestores autorizados. A restrição existe para evitar proliferação de canais duplicados.

### Meu holerite (ou documento) não apareceu. Por quê?

Provavelmente a ficha de RH ainda não foi vinculada à sua conta de acesso. Sem esse vínculo, o RH publica o arquivo mas ele não chega ao seu "Meu espaço". Peça ao RH ou ao TI para verificar.

### Abri um card por engano. Posso finalizar?

Não. Quem solicita acompanha, mas não move status nem finaliza — isso é do operador, por desenho. Peça o cancelamento no próprio card.

### Como sei que meu anexo foi salvo no card?

O campo **Anexos** lista os arquivos, e o histórico de movimentação registra o envio com link direto de download.

### Como funcionam as punições por conteúdo?

Advertências aplicadas na moderação podem acumular e gerar restrição temporária de envio de mensagens e mídia, pelo prazo definido pela administração.

### A IA vê o gabarito da prova junto com o candidato?

Não. A geração acontece do lado da empresa e a resposta correta nunca é enviada ao candidato — ele vê apenas enunciado e alternativas.

### Ainda não achei minha resposta.

Use a busca desta Central, consulte a aba **Guias** para o roteiro do módulo e, se ainda assim persistir, abra um chamado em **Suporte T.I.**
''',
  ),
];
