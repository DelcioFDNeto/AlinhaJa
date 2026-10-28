import 'package:alinha_ja/core/constants.dart';

/// Perguntas frequentes da aba **Central de Ajuda**.
///
/// É a camada mais rasa do módulo de ajuda: resposta curta e direta, pensada
/// para quem chega com uma dúvida pontual. Roteiros passo a passo vivem em
/// `help_guides.dart`; as regras completas, em `help_manual.dart`.
class HelpTopic {
  final String category;
  final String title;
  final String content;
  final List<String> tags;

  const HelpTopic({
    required this.category,
    required this.title,
    required this.content,
    required this.tags,
  });
}

/// Nome da marca desta build — nunca escreva o literal na UI.
const String _app = AppConstants.appName;

/// Tópicos exibidos e pesquisáveis na Central de Ajuda, agrupados por
/// categoria. O prefixo numérico define a ordem das seções na tela.
const List<HelpTopic> kHelpTopics = [
  // ───────────────────────── Começando ─────────────────────────
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Como faço meu primeiro acesso?',
    content:
        'Abra o app Android ou o endereço web da empresa, informe o e-mail corporativo e a senha entregue pelo TI e toque em **Entrar**.\n\n'
        'Se aparecer "conta aguardando aprovação", o cadastro existe mas ainda não foi liberado pelo TI — tente novamente após a liberação.\n\n'
        'No primeiro acesso, vale gastar dois minutos em **Configurações**: confira seu perfil, escolha o tema e ative a verificação em duas etapas.',
    tags: ['login', 'entrar', 'primeiro acesso', 'senha', 'aprovação'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Esqueci minha senha. Como redefinir?',
    content:
        'Na tela de login, toque em **Esqueci minha senha** e informe o e-mail cadastrado. Você receberá um link de redefinição.\n\n'
        'O link é de uso único e expira — se demorar para usá-lo, solicite outro.',
    tags: ['senha', 'redefinir', 'esqueci', 'recuperar', 'link'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Um módulo sumiu do meu menu. É erro?',
    content:
        'Quase nunca. O menu lateral é montado a partir das suas permissões: se o item deixou de aparecer, o seu perfil de acesso não tem mais a chave **Visualizar** daquele módulo.\n\n'
        'Abra um chamado para o TI conferir em **Painel Admin > Acessos**.',
    tags: ['menu', 'módulo', 'sumiu', 'permissão', 'acesso', 'rbac'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Como ativo a verificação em duas etapas (2FA)?',
    content:
        'Vá em **Configurações > Segurança e 2FA** e siga o passo a passo para vincular um aplicativo autenticador.\n\n'
        'Na mesma tela você gerencia os **dispositivos confiáveis** — aparelhos em que já validou o segundo fator e não precisa repetir a cada acesso. Revise essa lista de tempos em tempos e remova o que não usa mais.',
    tags: ['2fa', 'mfa', 'segurança', 'autenticador', 'dispositivos'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Como mudo o tema e as notificações?',
    content:
        'Em **Configurações > Aparência** você escolhe o tema Claro, Escuro ou Automático (acompanha o sistema do aparelho).\n\n'
        'Em **Configurações > Notificações** você liga e desliga os avisos por módulo — documentos, onboarding, alertas de RH e helpdesk, entre outros.',
    tags: ['tema', 'escuro', 'claro', 'notificação', 'aparência', 'som'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Como instalo o $_app no iPhone ou uso pelo navegador?',
    content:
        'No computador, basta abrir o endereço da empresa no navegador.\n\n'
        'No iPhone, abra o endereço no **Safari**, toque em **Compartilhar → Adicionar à Tela de Início** e passe a abrir pelo ícone criado. É assim que o iPhone entrega notificações.\n\n'
        'No Android, instale o APK distribuído pelo TI.',
    tags: ['instalar', 'iphone', 'pwa', 'navegador', 'apk', 'tela de início'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Apareceu "Nova versão disponível". O que faço?',
    content:
        'Recarregue a página quando terminar o que está fazendo — nada se perde. As novidades de cada versão ficam em **Configurações → Novidades**.',
    tags: ['atualizar', 'versão', 'nova versão', 'recarregar', 'novidades'],
  ),
  HelpTopic(
    category: '1 · 🚀 Começando',
    title: 'Consigo usar o app sem internet?',
    content:
        'Em parte. As conversas já carregadas continuam abrindo, e mensagens de texto enviadas sem conexão entram numa fila e saem sozinhas quando a internet volta.\n\n'
        'Fotos e arquivos precisam de conexão: sem ela, a mensagem fica marcada com erro para você reenviar.',
    tags: ['offline', 'sem internet', 'fila', 'conexão'],
  ),

  // ───────────────────────── Comunicação ─────────────────────────
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Qual a diferença entre Canais e Conversas?',
    content:
        'São duas coisas diferentes de propósito:\n\n'
        '1. **Conversas (diretas e grupos)** — bate-papo do dia a dia. As mensagens diretas são criptografadas de ponta a ponta, e a administração de um grupo é independente do seu cargo global: quem cria administra.\n'
        '2. **Canais corporativos** — espaços oficiais por departamento ou processo, com categoria, funil de trabalho e moderação. É onde ficam os comunicados e as demandas operacionais.',
    tags: ['canal', 'conversa', 'chat', 'grupo', 'dm', 'workspace'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'O que é o botão "Estou Ciente"?',
    content:
        'É a confirmação formal de leitura de um comunicado oficial. Quando o autor exige ciência, a mensagem traz o botão no rodapé.\n\n'
        '• **Para você**: leia o comunicado até o fim e toque no botão. Ficam registrados seu nome, a data e a hora.\n'
        '• **Para gestores**: o cabeçalho do canal mostra o percentual já confirmado, e o detalhe do comunicado lista quem confirmou e quem está pendente.',
    tags: ['estou ciente', 'comunicado', 'aviso', 'leitura', 'confirmação'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Como encontro canais que ainda não sigo?',
    content:
        'Use o ícone de **bússola** no topo da lista de canais: ele abre a descoberta de canais públicos.\n\n'
        'Entre no canal e ele passa a aparecer na sua lista, com contador de mensagens não lidas. Canais privados só aparecem por convite.',
    tags: ['descobrir', 'canal', 'público', 'seguir', 'bússola', 'entrar'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Como funcionam as chamadas e reuniões?',
    content:
        '• **Chamada 1:1** — no cabeçalho de uma conversa direta, toque no ícone de câmera ou telefone. O aparelho do colega toca e vibra, mesmo com o app em segundo plano.\n'
        '• **Reunião de grupo** — no cabeçalho de um canal ou grupo, o ícone de câmera cria uma sala e publica o convite no chat; quem quiser entra com um toque.\n\n'
        'O histórico fica na aba **Chamadas**, com filtros Todas, Perdidas e Reuniões.',
    tags: ['chamada', 'vídeo', 'voz', 'reunião', 'sala', 'ligação'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'O que é o Assistente de IA?',
    content:
        'É uma conversa como qualquer outra, usada para tirar dúvidas de processo e de uso do sistema.\n\n'
        'O histórico é individual e pode ser apagado por você a qualquer momento. Se o assistente responder que está indisponível, a credencial de IA precisa ser configurada pelo TI no Painel Admin.',
    tags: ['ia', 'assistente', 'inteligência artificial', 'bot', 'dúvida'],
  ),

  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Um canal está notificando demais. Como reduzir?',
    content:
        'Toque no ícone de **sino** na barra do canal (ou abra **Informações do canal → Minhas notificações**) e escolha:\n\n'
        '• **Todas as mensagens** — o padrão.\n'
        '• **Somente menções** — notifica só quando você é citado ou alguém usa **@canal**.\n'
        '• **Silenciado** — nenhuma notificação; o canal continua na sua lista.\n\n'
        'É uma preferência individual: não muda nada para os outros membros, e quem administra o canal não a controla.\n\n'
        'Ajustar canal a canal é melhor do que desligar a notificação do sistema inteiro — assim o que é urgente continua chegando.',
    tags: [
      'notificação',
      'silenciar',
      'mudo',
      'sino',
      'canal',
      'menções',
      'incomodando'
    ],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Como aviso todo mundo do canal?',
    content:
        'Digite **@** e escolha **@canal** ou **@aqui** no topo da lista de sugestões.\n\n'
        'Essas menções alcançam **inclusive quem colocou o canal em "somente menções"**, e a notificação chega destacada para quem foi citado.\n\n'
        'Use com parcimônia: `@canal` fura o silêncio que as pessoas escolheram. Abusar dele faz o time silenciar o canal por completo.\n\n'
        'Dentro de um tópico as menções coletivas não aparecem — uma resposta em thread não deve virar aviso geral.',
    tags: ['@canal', '@aqui', 'menção', 'avisar todos', 'arroba', 'broadcast'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Posso editar ou apagar uma mensagem que enviei no canal?',
    content:
        'Sim. Toque e segure a mensagem para abrir as ações.\n\n'
        '• **Editar** — corrige o texto (ou a legenda de uma mídia). A bolha passa a exibir **"editado"**.\n'
        '• **Apagar** — remove para todos.\n\n'
        'Anúncios e enquetes **não** são editáveis: eles carregam confirmações de leitura e votos, que ficariam fora de sincronia com um texto novo.\n\n'
        'Quem administra o workspace também pode apagar mensagem de terceiro, para moderação — e a ação fica registrada na auditoria.',
    tags: ['editar', 'apagar', 'excluir', 'corrigir', 'mensagem', 'canal'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Não estou recebendo notificações. O que verifico?',
    content:
        'Confira nesta ordem:\n\n'
        '1. A permissão de notificação do $_app nas configurações do celular ou do navegador.\n'
        '2. O liga/desliga geral e o horário silencioso em **Configurações → Notificações**.\n'
        '3. Se a conversa ou o canal está silenciado.\n'
        '4. No Android, se a **otimização de bateria** está restringindo o app.\n'
        '5. No navegador, se aparece o botão **Ativar notificações** em Configurações → Notificações. No iPhone, o app precisa estar instalado pela Tela de Início.',
    tags: ['notificação', 'não recebo', 'push', 'bateria', 'permissão'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Dá para responder direto pela notificação?',
    content:
        'Sim, no Android. Toque em **Responder**, escreva e envie — a resposta aparece na notificação e a conversa fica marcada como lida.\n\n'
        'Também há **Marcar como lida**, que zera a conversa sem abrir o app. Se a resposta mostrar "Não enviada", abra a conversa e tente de novo.',
    tags: ['responder', 'notificação', 'marcar como lida', 'resposta rápida'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Como sei quem leu minha mensagem?',
    content:
        'Toque e segure a mensagem e escolha **Informações**. Em grupos e canais aparecem quantas pessoas **leram**, **receberam** e ainda estão **pendentes**, com o nome de cada uma. Em conversas diretas, aparece quando foi recebida e quando foi lida.',
    tags: ['lida', 'leitura', 'recibo', 'quem leu', 'informações'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Como encaminho ou guardo uma mensagem importante?',
    content:
        'Toque e segure a mensagem. Na barra de seleção, **Encaminhar** envia para outra conversa ou canal e **Favoritar** guarda a mensagem.\n\n'
        'As favoritas ficam em **Mensagens Favoritas**, no menu ⋮ da tela inicial.',
    tags: ['encaminhar', 'favoritar', 'favoritas', 'salvar mensagem'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Para que serve o Quadro branco?',
    content:
        'É uma lousa compartilhada dentro da conversa: todos desenham juntos, em tempo real, por cima de fotos e documentos anexados.\n\n'
        'Crie pelo **+** ao lado do campo de mensagem, em **Quadro**. **Desfazer meu último traço** só desfaz o que você desenhou.',
    tags: ['quadro branco', 'lousa', 'desenhar', 'colaborativo'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Sou o único administrador de um canal. Posso sair?',
    content:
        'Pode, mas antes o $_app pede que você escolha quem vai administrar o canal. Ao tocar em **Sair do Canal**, aparece a lista de membros (editores primeiro): escolha a pessoa e toque em **Transferir e sair**.\n\n'
        'Quem recebe a administração é avisado por notificação. Se você for o último membro do canal, a saída é direta.',
    tags: ['sair do canal', 'administrador', 'sucessor', 'transferir'],
  ),
  HelpTopic(
    category: '2 · 💬 Comunicação',
    title: 'Pedi para entrar em um canal e não fui aprovado. Como fico sabendo?',
    content:
        'Quando quem administra o canal recusa o pedido, você recebe a notificação **Solicitação não aprovada**. Tocar nela abre a descoberta de canais.\n\n'
        'O pedido recusado é apagado, então você pode pedir de novo — mas vale falar antes com quem administra o canal.',
    tags: ['pedido', 'recusado', 'entrar no canal', 'solicitação'],
  ),

  // ───────────────────────── Operação ─────────────────────────
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Como transformo uma solicitação em card?',
    content:
        'Dentro do canal, abra a aba **Workflow** e use o botão "+". Preencha título, descrição, prioridade (Baixa, Média, Alta, Urgente), valores quando houver e anexe os documentos de apoio.\n\n'
        'A partir daí a demanda tem responsável, etapa e prazo — e para de depender de alguém lembrar dela no meio do chat.',
    tags: ['card', 'demanda', 'solicitação', 'kanban', 'workflow', 'abrir'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Quem pode mover e finalizar um card?',
    content:
        'As regras são estritas de propósito:\n\n'
        '• **Quem solicitou** acompanha o progresso, mas **não** move status, assume, arquiva ou finaliza o próprio card.\n'
        '• **Operador ou gestor** é quem move as etapas e anexa o comprovante conclusivo.\n\n'
        'Se você abriu um card por engano, peça o cancelamento no próprio card em vez de tentar fechá-lo.',
    tags: ['mover', 'finalizar', 'operador', 'solicitante', 'regra', 'status'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'O que significa "Assumir Atendimento"?',
    content:
        'Depende de como o canal foi configurado:\n\n'
        '• **Operador fixo** — o card já nasce atribuído a quem responde por aquele fluxo.\n'
        '• **Fila** — o card fica disponível para todos os operadores autorizados até alguém tocar em **Assumir Atendimento**. A partir daí o responsável é público e o relógio corre para ele.',
    tags: ['assumir', 'atendimento', 'fila', 'atribuição', 'responsável'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'O que é o status "Aguardando Solicitante"?',
    content:
        'É um status de pausa. O operador o utiliza quando a tratativa depende de um documento ou informação que só quem abriu o chamado pode fornecer.\n\n'
        'Deixa explícito, para os dois lados, que a bola está com o solicitante — e o tempo nessa etapa fica registrado.',
    tags: ['aguardando', 'solicitante', 'pausa', 'status', 'pendente'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Posso montar meu próprio funil de etapas?',
    content:
        'Sim. Ao criar um canal (**Canais > Novo Fluxo**), escolha um **preset** de partida e ajuste tudo em seguida.\n\n'
        'Na seção **Etapas do Kanban**: arraste pelo ícone ☰ para reordenar, toque no ícone da etapa para trocar o desenho, na paleta para a cor, e escreva no nome para renomear. O menu ⋮ de cada etapa marca qual é a **inicial**, qual **conclui** e qual **cancela**.\n\n'
        'Se a sua etapa de cancelamento não se chama "Cancelado" — por exemplo "Recusado" —, marque-a pelo menu ⋮. Sem isso ela vira uma coluna comum do quadro e entra na conta do SLA.',
    tags: [
      'builder',
      'etapa',
      'funil',
      'coluna',
      'criar canal',
      'workflow',
      'preset'
    ],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Como crio, edito ou apago um preset de workspace?',
    content:
        'O ícone de **modelos**, no topo da aba Canais, abre a biblioteca de presets.\n\n'
        '• **Criar** — botão "Novo Preset".\n'
        '• **Editar** — toque em um preset da empresa.\n'
        '• **Duplicar** — menu do preset; abre uma cópia editável já preenchida.\n'
        '• **Excluir** — menu do preset (os canais já criados não são afetados).\n\n'
        'Os **modelos de fábrica são somente leitura**: use "Duplicar" para criar a sua versão a partir deles.\n\n'
        'Você também pode salvar o que montou na tela de criação (ou de edição) do workspace pelo ícone de marcador, e escolher se o preset fica compartilhado com a empresa ou privado.',
    tags: [
      'preset',
      'modelo',
      'template',
      'workspace',
      'duplicar',
      'biblioteca'
    ],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Dá para mudar as etapas de um canal que já existe?',
    content:
        'Sim. O **lápis ao lado do nome**, em Informações do canal, abre a edição completa: nome, descrição, ícone, cor, categoria, permissão de publicação e as etapas do Kanban. O funil não fica mais congelado no formato escolhido na criação.\n\n'
        'Ao **remover uma etapa que ainda tem cards**, o sistema pergunta para onde movê-los e registra a mudança no histórico de cada card. Nenhum card fica órfão.\n\n'
        '**Renomear** é seguro: os cards acompanham o novo nome automaticamente.\n\n'
        'Membros e operadores continuam sendo geridos na tela de Informações do canal — definir quem opera o workflow exige permissão mais alta do que editar o espaço.',
    tags: [
      'editar',
      'etapa',
      'alterar',
      'workspace',
      'canal',
      'mover cards',
      'renomear'
    ],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Existe outra forma de ver a fila além do quadro?',
    content:
        'Sim, três modos de visualização:\n\n'
        '• **Quadro (Kanban)** — colunas verticais, melhor para acompanhamento visual.\n'
        '• **Lista** — volume alto, com ordenação por prazo e filtro por responsável.\n'
        '• **Compacta** — telas pequenas ou dezenas de chamados simultâneos; mostra só o essencial.',
    tags: ['visualização', 'board', 'lista', 'compacta', 'quadro'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Onde vejo todos os cards que estão comigo?',
    content:
        'Em **Minha Operação**, no menu ⋮ da tela inicial. A tela junta os cards atribuídos a você em todos os workspaces, separados em **Em atraso**, **Para hoje**, **Próximos**, **Sem prazo** e **Concluídos**.',
    tags: ['minha operação', 'meus cards', 'atrasados', 'prazo'],
  ),
  HelpTopic(
    category: '3 · 📋 Operação e Workflow',
    title: 'Abri um card. Por que não consigo comentar nele?',
    content:
        'Quem abre o card (o solicitante) não opera nem comenta o próprio pedido enquanto ele está em andamento — isso garante que a tratativa fique com a equipe responsável.\n\n'
        'Depois que o card chega à etapa final, o comentário fica liberado. Enquanto isso, fale com a equipe pela conversa do canal.',
    tags: ['comentar', 'solicitante', 'card', 'bloqueado'],
  ),

  // ───────────────────────── Helpdesk ─────────────────────────
  HelpTopic(
    category: '4 · 🎫 Helpdesk (Suporte T.I.)',
    title: 'Como abro um chamado para a T.I.?',
    content:
        'Use o atalho **Abrir chamado** aqui na Central de Ajuda (ou o bloco Suporte T.I. do seu perfil).\n\n'
        '1. Escolha a categoria: Sistema/Software, Equipamentos/Hardware, Internet/Rede, Acessos/Credenciais, Dúvida Geral ou Outro.\n'
        '2. Defina a prioridade: Baixa, Normal, Alta ou Urgente.\n'
        '3. Descreva o problema com o máximo de detalhe e anexe evidência.\n\n'
        'Um chat exclusivo é aberto com o técnico responsável. Acompanhe pela aba **Meus Chamados**.',
    tags: ['chamado', 'ticket', 'suporte', 'ti', 'abrir', 'helpdesk'],
  ),
  HelpTopic(
    category: '4 · 🎫 Helpdesk (Suporte T.I.)',
    title: 'O que significa cada status do chamado?',
    content:
        '• **Novo** — aberto, ainda sem atendente designado.\n'
        '• **Em Andamento** — técnico trabalhando no caso.\n'
        '• **Pendente Fornecedor** — depende de terceiro (garantia, operadora, fabricante).\n'
        '• **Resolvido** — encerrado com solução aplicada.\n'
        '• **Cancelado** — encerrado sem tratativa.',
    tags: ['status', 'novo', 'andamento', 'resolvido', 'cancelado', 'pendente'],
  ),
  HelpTopic(
    category: '4 · 🎫 Helpdesk (Suporte T.I.)',
    title: 'Meu chamado demora. O que acelera?',
    content:
        'Descrição vaga é a principal causa de idas e vindas. Ajuda muito:\n\n'
        '• Print da tela ou foto do equipamento com o problema visível.\n'
        '• O texto exato da mensagem de erro.\n'
        '• O que você estava fazendo quando aconteceu e se acontece sempre.\n'
        '• Prioridade honesta — marcar tudo como Urgente faz o filtro perder o sentido.',
    tags: ['demora', 'sla', 'prazo', 'prioridade', 'evidência', 'anexo'],
  ),

  // ───────────────────────── RH ─────────────────────────
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Onde vejo meus holerites, documentos e ponto?',
    content:
        'Tudo que é seu fica em **Meu Perfil**, no bloco Recursos Humanos: Meus Documentos, Meu Onboarding, Minhas Ausências e Férias, Meu Ponto, Meus Holerites e Meu Desempenho.\n\n'
        'Se algum deles estiver vazio, provavelmente sua ficha de RH ainda não foi vinculada à sua conta de acesso — peça ao RH ou ao TI para verificar o vínculo.',
    tags: [
      'meu perfil',
      'holerite',
      'documento',
      'ponto',
      'autoatendimento',
      'vínculo'
    ],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Como solicito férias ou envio um atestado?',
    content:
        'Em **Meu Perfil > Minhas Ausências e Férias**, abra o pedido informando o tipo (férias, atestado ou folga) e o período, e anexe o comprovante pelo próprio celular.\n\n'
        'O RH recebe na fila de solicitações, confere o comprovante e aprova ou recusa. Aprovado, o período entra no calendário da equipe e no seu histórico oficial.',
    tags: ['férias', 'atestado', 'folga', 'ausência', 'solicitar', 'anexar'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Funcionários: o que a ficha guarda?',
    content:
        'Dados pessoais, dados funcionais (filial, departamento, cargo, matrícula, admissão), vínculo (CLT, PJ, Aprendiz), dependentes e o histórico de cargo e salário.\n\n'
        'Atualize promoções e mudanças de vínculo na ficha existente em vez de abrir um cadastro novo: é o histórico que sustenta a auditoria.',
    tags: ['funcionário', 'ficha', 'matrícula', 'vínculo', 'clt', 'pj'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Documentos: como funciona o controle de validade?',
    content:
        'Cada documento (ASO, CNH, certificações) é cadastrado com categoria, arquivo e **data de vencimento**. A partir dela, o sistema mostra a etiqueta **Válido**, **Próximo do Vencimento** ou **Vencido**.\n\n'
        'A chave **Exigir ciência do funcionário** faz a pessoa confirmar a leitura em Meus Documentos, com data e hora registradas. Os vencimentos aparecem automaticamente em **Alertas RH**.',
    tags: ['documento', 'aso', 'cnh', 'validade', 'vencimento', 'ciência'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Ponto: posso corrigir uma batida errada?',
    content:
        'Sim. No módulo **Controle de Ponto**, filtre por período e funcionário; o menu de três pontos de cada registro permite editar o horário ou excluir a marcação. Use **Lançar registro** para incluir uma batida que faltou.\n\n'
        'Todo ajuste manual fica auditável, com autor e horário — é isso que permite defender o espelho de ponto depois.',
    tags: ['ponto', 'batida', 'corrigir', 'ajuste', 'espelho', 'lançar'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Holerites: como sei que o colaborador recebeu?',
    content:
        'Cada holerite emitido exibe a etiqueta **Visualizado** com data e hora da abertura pelo colaborador. Essa marca substitui a assinatura de recebimento em papel.\n\n'
        'Os filtros de Funcionário e Ano ajudam a auditar uma competência específica.',
    tags: ['holerite', 'visualizado', 'comprovação', 'entrega', 'competência'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Benefícios: catálogo e adesão são a mesma coisa?',
    content:
        'Não. O **Catálogo** é o que a empresa oferece (Vale Refeição, Vale Alimentação, plano de saúde, odontológico), com tipo e operadora.\n\n'
        'A **Adesão** liga um funcionário a um benefício, com data de adesão e, opcionalmente, o desconto em folha — que fica armazenado criptografado. Encerrar uma adesão não apaga o histórico.',
    tags: ['benefício', 'catálogo', 'adesão', 'vr', 'va', 'desconto'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Desempenho: qual a diferença entre ciclo e avaliação 1:1?',
    content:
        '• **Ciclo** — a janela em que a avaliação acontece, organizando autoavaliação, gestor, pares e subordinados no mesmo período.\n'
        '• **Avaliação 1:1** — o registro individual: colaborador, nota, papel de quem avaliou, data e feedback.\n\n'
        'O colaborador acompanha as próprias notas em Meu Perfil > Meu Desempenho.',
    tags: ['desempenho', 'ciclo', 'avaliação', '1:1', 'feedback', '360'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Onboarding: como padronizo a integração?',
    content:
        'Crie **templates** de checklist em Onboarding. O template marcado como **Padrão** vale para todo novo colaborador; os demais são específicos por time.\n\n'
        'Vinculado o template ao novo funcionário, cada item vira tarefa acompanhada. A pessoa marca o que concluiu em Meu Perfil > Meu Onboarding.',
    tags: ['onboarding', 'integração', 'checklist', 'template', 'novo'],
  ),
  HelpTopic(
    category: '5 · 👥 Recursos Humanos',
    title: 'Para que serve o painel de Alertas RH?',
    content:
        'Ele recolhe automaticamente tudo que tem prazo: documentos vencidos e a vencer, fim de contrato de experiência, aniversariantes do mês e pendências de aprovação.\n\n'
        'Cada alerta leva direto ao registro de origem. Ative o canal **Alertas RH** em Configurações > Notificações para ser avisado sem precisar abrir o painel.',
    tags: ['alerta', 'vencimento', 'experiência', 'aniversário', 'prazo'],
  ),

  // ───────────────────────── Recrutamento ─────────────────────────
  HelpTopic(
    category: '6 · 🎯 Recrutamento',
    title: 'Como divulgo uma vaga para fora da empresa?',
    content:
        'Publique a vaga na aba **Vagas** e vá até **Divulgação**. Ative "Página de carreiras ativa" e use o **link de inscrição** (com botões de copiar, WhatsApp e e-mail) ou o **QR code** para cartaz e material impresso.\n\n'
        'O texto de chamada e a apresentação da empresa são editáveis na mesma tela. Desativar a página fecha novas inscrições, mas não apaga candidaturas já recebidas.',
    tags: ['vaga', 'carreiras', 'link', 'qr code', 'divulgar', 'portal'],
  ),
  HelpTopic(
    category: '6 · 🎯 Recrutamento',
    title: 'Como funciona a prova gerada por IA?',
    content:
        'Na aba **Avaliações**, use **Gerar com IA**: escolha o cargo, o nível e a quantidade de questões. A IA monta uma prova de múltipla escolha para você revisar antes de aplicar.\n\n'
        'O **gabarito nunca é enviado ao candidato** — ele vê apenas enunciado e alternativas. Você também pode escrever questões manualmente e misturá-las com as geradas.',
    tags: ['prova', 'ia', 'questão', 'teste', 'gabarito', 'candidato'],
  ),
  HelpTopic(
    category: '6 · 🎯 Recrutamento',
    title: 'Posso mudar as etapas do processo seletivo?',
    content:
        'Sim, em **Ajustes > Etapas do pipeline**: renomeie, reordene e crie etapas.\n\n'
        'As etapas de entrada (Novo) e terminais (Contratado, Descartado) aparecem com cadeado — podem ser renomeadas, mas não removidas, porque o cálculo de conversão depende delas.',
    tags: ['etapa', 'pipeline', 'funil', 'reordenar', 'renomear', 'ajustes'],
  ),
  HelpTopic(
    category: '6 · 🎯 Recrutamento',
    title: 'O que acontece com os dados de quem não foi contratado?',
    content:
        'Em **Ajustes**, o **período de retenção (LGPD)** define depois de quanto tempo candidatos não contratados são anonimizados automaticamente.\n\n'
        'É o controle que mantém o banco de talentos em conformidade sem depender de limpeza manual.',
    tags: ['lgpd', 'retenção', 'anonimizar', 'privacidade', 'dados'],
  ),
  HelpTopic(
    category: '6 · 🎯 Recrutamento',
    title: 'Como transformo um aprovado em funcionário?',
    content:
        'Ao mover o candidato para a etapa **Contratado**, use a conversão para criar a ficha de funcionário reaproveitando os dados já preenchidos na candidatura — sem redigitar nada.\n\n'
        'Depois, lembre de vincular a ficha à conta de acesso para que ele receba documentos, holerites e onboarding no app.',
    tags: ['contratar', 'converter', 'candidato', 'funcionário', 'admissão'],
  ),

  // ───────────────────────── Automações ─────────────────────────
  HelpTopic(
    category: '7 · ✉️ Automações e E-mail',
    title: 'Como envio e-mails pelo domínio da empresa?',
    content:
        'Em **Comunicação e Automações > Servidor SMTP**, informe host, porta, usuário e senha (ou App Password) e defina o remetente — nome e e-mail que o destinatário verá.\n\n'
        'A senha é armazenada criptografada. Enviar pelo domínio próprio aumenta a entregabilidade e a confiança de quem recebe.',
    tags: ['smtp', 'e-mail', 'remetente', 'domínio', 'senha', 'porta'],
  ),
  HelpTopic(
    category: '7 · ✉️ Automações e E-mail',
    title: 'Como disparo um e-mail automático por etapa do funil?',
    content:
        'Na aba **Regras de Automação**, use "Nova Regra": escolha a etapa que dispara o envio ("Quando o candidato for movido para a etapa") e o template correspondente ("Enviar o e-mail"). Salve e a regra passa a valer para todos.\n\n'
        'Configure o **SMTP primeiro** — sem servidor, o disparo não acontece. E teste com um candidato fictício antes de anunciar a automação ao time.',
    tags: ['automação', 'regra', 'gatilho', 'template', 'disparo', 'etapa'],
  ),

  // ───────────────────────── Segurança e Admin ─────────────────────────
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Como funcionam os perfis de acesso (RBAC)?',
    content:
        'Cada perfil tem, por módulo, até duas chaves: **Visualizar** (abrir a tela) e **Gerenciar** (alterar configurações e dados). O contador ao lado do módulo (ex.: 1/2) mostra quantas estão ligadas.\n\n'
        'Perfis padrão: **Super Admin** (acesso total, incluindo auditoria e backup), **RH** (gestão completa de Recursos Humanos), **Gestor** (equipe com visão de RH limitada) e **Colaborador** (acesso padrão). Perfis marcados como SISTEMA não podem ser excluídos, mas suas permissões podem ser ajustadas.',
    tags: ['rbac', 'perfil', 'permissão', 'visualizar', 'gerenciar', 'cargo'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Um colega novo não consegue entrar. O que faço?',
    content:
        'Contas criadas por autocadastro ficam **pendentes** até a liberação do TI, e o login é bloqueado com aviso na tela.\n\n'
        'No Painel Admin > Gestão de Usuários, use o filtro **Pendentes** para liberar. Alternativamente, provisione a conta antes pelo **Novo Cadastro**.',
    tags: ['pendente', 'aprovar', 'liberar', 'novo usuário', 'bloqueado'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'O que é registrado na auditoria?',
    content:
        'Ações críticas: criação e movimentação de cards, alteração de permissões, exclusão de mensagens, logins e mudanças de cadastro — com autor, alvo e horário.\n\n'
        'Os registros são gerados no banco e não podem ser editados pela interface.',
    tags: ['auditoria', 'log', 'histórico', 'registro', 'rastreabilidade'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Como funciona a moderação de conteúdo?',
    content:
        'A aba **Moderação** do Painel Admin separa Mensagens e Canais, com duas ações: **Advertir** (notifica o autor) e **Excluir** (remove o conteúdo). Ambas ficam registradas na auditoria.\n\n'
        'Advertências acumuladas podem gerar restrição temporária de envio de mensagens e mídia, pelo prazo definido pela administração.',
    tags: ['moderação', 'advertir', 'excluir', 'punição', 'política'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Devo excluir ou desativar um usuário que saiu?',
    content:
        '**Desative.** Desativar preserva o histórico de mensagens, cards e aprovações daquela pessoa; excluir quebra a rastreabilidade de tudo que ela tocou.\n\n'
        'A troca de perfil e a desativação ficam registradas na auditoria com autor e horário.',
    tags: ['desativar', 'excluir', 'desligamento', 'conta', 'histórico'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Por que o app pede GPS em segundo plano?',
    content:
        'O rastreamento existe para logística e segurança de equipes externas. Ele exige a permissão de localização do Android como **"Sempre permitir"**, senão o trajeto fica cheio de buracos.\n\n'
        'O consumo é controlado: parado por mais de 5 minutos, o envio de coordenadas é suspenso e só retoma ao detectar movimento.',
    tags: ['gps', 'localização', 'background', 'bateria', 'rastreamento'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Por que a chamada pede biometria ao voltar para o app?',
    content:
        'É a proteção de tela bloqueada. Se você atende com o celular bloqueado, minimizar a chamada ou apertar "voltar" exige biometria ou senha do aparelho.\n\n'
        'É o que impede que suas conversas fiquem expostas em um celular perdido ou emprestado.',
    tags: ['biometria', 'bloqueio', 'segurança', 'chamada', 'privacidade'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Quando devo gerar backup?',
    content:
        'Antes de qualquer alteração estrutural: reorganizar workspaces, migrar perfis de acesso, limpar canais em massa.\n\n'
        'A aba **Backup** do Painel Admin exporta a base e sincroniza o cache de mídia.',
    tags: ['backup', 'exportar', 'restaurar', 'base', 'segurança'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'Como exporto meus dados ou faço um pedido da LGPD?',
    content:
        'Em **Configurações → Privacidade e Dados**:\n\n'
        '- **Exportar meus dados agora** gera um arquivo com os seus dados na plataforma.\n'
        '- **Novo Pedido do Titular (LGPD)** abre um pedido de correção, eliminação ou informação sobre compartilhamento. A empresa tem até **15 dias** para responder.',
    tags: ['lgpd', 'privacidade', 'exportar', 'titular', 'meus dados'],
  ),
  HelpTopic(
    category: '8 · 🛡️ Segurança e Administração',
    title: 'O que acontece quando recuso um cadastro pendente?',
    content:
        'O cadastro é removido e a pessoa recebe um **e-mail** avisando que não foi aprovada, com a orientação de procurar o TI ou o gestor. O aviso vai por e-mail porque um cadastro pendente nunca chegou a entrar no app.',
    tags: ['cadastro pendente', 'recusar', 'rejeitar', 'e-mail'],
  ),

  // ───────────────────────── Ajuda sobre a ajuda ─────────────────────────
  HelpTopic(
    category: '9 · 📚 Guias e Manuais',
    title: 'Qual a diferença entre as abas Guias e Manual?',
    content:
        '• **Guias** (lâmpada) — roteiros passo a passo, numerados e com a captura da tela real. Use quando quiser **aprender a fazer** um fluxo do início ao fim.\n'
        '• **Manual** (documento) — a referência: regras de negócio, tabelas de permissões, status, campos e comportamento de cada módulo. Use quando quiser **entender por que** o sistema se comporta de determinada forma.\n\n'
        'Ambas têm busca própria — o mesmo termo costuma trazer resultados complementares nas duas.',
    tags: ['guia', 'manual', 'tutorial', 'documentação', 'referência'],
  ),
  HelpTopic(
    category: '9 · 📚 Guias e Manuais',
    title: 'Como reviso o tour de apresentação do $_app?',
    content:
        'Use o atalho **Rever tutorial** no topo desta Central de Ajuda. Ele reinicia a introdução guiada, destacando os principais pontos da navegação.\n\n'
        'É útil depois de uma atualização grande ou ao ajudar um colega recém-chegado.',
    tags: ['tour', 'tutorial', 'onboarding', 'introdução', 'rever'],
  ),
  HelpTopic(
    category: '9 · 📚 Guias e Manuais',
    title: 'Não achei minha resposta em lugar nenhum.',
    content:
        'Tente a busca com termos mais genéricos ("card", "ponto", "permissão") — ela varre título, conteúdo e etiquetas.\n\n'
        'Se ainda assim não resolver, abra um chamado em **Suporte T.I.** pelo botão no rodapé desta tela. Descreva o que você tentou: isso encurta o atendimento.',
    tags: ['dúvida', 'não achei', 'suporte', 'contato', 'ajuda'],
  ),
];
