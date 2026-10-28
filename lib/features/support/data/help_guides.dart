import 'package:flutter/material.dart';

/// Guias passo a passo da **Academia** (aba "Guias" da Central de Ajuda).
///
/// Cada [HelpGuide] cobre um módulo do sistema e traz um roteiro de
/// [HelpGuideStep] numerados, com a captura da tela real correspondente. As
/// imagens vivem em `assets/images/help/` (capturas antigas) e
/// `assets/images/help/shots/` (capturas novas, as mesmas da página
/// institucional). Nas duas pastas o nome do arquivo é o slug da tela que
/// ele mostra (`admin-auditoria.webp`, `novo-canal-etapas.webp`) — ao
/// acrescentar uma captura, siga a mesma convenção.
///
/// Esta lista é a fonte de verdade única do treinamento in-app: se um módulo
/// existe no `kModuleRegistry`, ele precisa ter um guia aqui.
class HelpGuide {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  /// Para quem o roteiro foi escrito (exibido como etiqueta no cartão).
  final String audience;

  /// Rota do módulo, quando existe uma tela correspondente. Alimenta o botão
  /// "Abrir módulo"; `null` esconde o botão.
  final String? route;

  /// Id do módulo no `kModuleRegistry`, usado para checar permissão RBAC
  /// antes de oferecer o atalho de [route].
  final String? moduleId;

  /// Termos extras de busca (além de título e descrição).
  final String keywords;

  final List<HelpGuideStep> steps;

  const HelpGuide({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.audience,
    required this.keywords,
    required this.steps,
    this.route,
    this.moduleId,
  });
}

class HelpGuideStep {
  final String title;
  final String description;

  /// Caminho completo do asset da captura, ou `null` quando o passo não tem
  /// tela associada (regra de negócio, pré-requisito, etc.).
  final String? image;

  /// Observação curta destacada abaixo do passo ("dica", "atenção").
  final String? tip;

  const HelpGuideStep({
    required this.title,
    required this.description,
    this.image,
    this.tip,
  });
}

/// Capturas novas (mesmas da página institucional).
const String _shot = 'assets/images/help/shots/';

/// Capturas herdadas da primeira versão da Academia.
const String _img = 'assets/images/help/';

// Públicos-alvo — evita divergência de texto entre guias.
const _todos = 'Todos os colaboradores';
const _gestores = 'Gestores e operadores';
const _rh = 'Recursos Humanos';
const _admin = 'TI e administradores';

/// Roteiros de treinamento por módulo.
const List<HelpGuide> kHelpGuides = [
  // ───────────────────────────── Começando ─────────────────────────────
  HelpGuide(
    id: 'primeiros-passos',
    title: 'Primeiros passos',
    description: 'Entrar, se localizar na navegação e deixar o perfil pronto.',
    icon: Icons.rocket_launch_rounded,
    color: Color(0xFF3b82f6),
    audience: _todos,
    keywords: 'login entrar acesso senha navegacao menu inicio comecar tour',
    steps: [
      HelpGuideStep(
        title: 'Entrar com o seu e-mail corporativo',
        description:
            'Abra o app (Android) ou o endereço web da empresa, informe o e-mail cadastrado e a senha entregue pelo TI e toque em "Entrar". Se a sua conta acabou de ser criada, ela pode estar aguardando aprovação do TI — nesse caso o login avisa e basta tentar de novo após a liberação.',
        image: '${_img}login.webp',
        tip:
            'Esqueceu a senha? Use "Esqueci minha senha" na própria tela de login: o link de redefinição chega no seu e-mail.',
      ),
      HelpGuideStep(
        title: 'Reconhecer a navegação e os módulos',
        description:
            'O menu lateral agrupa os módulos por área: Comunicação (Canais, Conversas, Chamadas), Recursos Humanos, Financeiro, Helpdesk e Administração. Você só enxerga os módulos liberados para o seu perfil de acesso — se um item não aparece, é permissão, não erro.',
        image: '${_shot}nav-modulos.webp',
      ),
      HelpGuideStep(
        title: 'Completar o seu perfil',
        description:
            'Em Configurações > Meu Perfil, confira filial de lotação, departamento, cargo e nível de acesso. Ajuste foto e nome de exibição e toque em "Salvar Perfil". Esses dados definem em quais canais e filas de atendimento você aparece.',
        image: '${_shot}meu-perfil.webp',
      ),
      HelpGuideStep(
        title: 'Ajustar tema, notificações e segurança',
        description:
            'Ainda em Configurações você escolhe o tema (Claro, Escuro ou Automático), personaliza quais notificações quer receber por módulo, ativa a verificação em duas etapas (2FA) e revisa seus dispositivos confiáveis.',
        image: '${_shot}configuracoes.webp',
        tip:
            'Ative o 2FA logo no primeiro acesso: ele protege a sua conta mesmo que a senha vaze.',
      ),
      HelpGuideStep(
        title: 'Saber onde pedir ajuda',
        description:
            'Esta Central de Ajuda tem quatro abas: Central de Ajuda (perguntas frequentes com busca), Guias (estes roteiros), Manual (documentação de referência) e Meus Chamados. Os atalhos no topo abrem o tour guiado ou um chamado para o TI.',
        image: '${_shot}ajuda-central.webp',
      ),
    ],
  ),

  // ─────────────────────────── Comunicação ───────────────────────────
  HelpGuide(
    id: 'canais',
    title: 'Canais e comunicados oficiais',
    description:
        'Espaços de trabalho por departamento e avisos com confirmação de leitura.',
    icon: Icons.campaign_rounded,
    color: Color(0xFF3b82f6),
    audience: _todos,
    route: '/chats?tab=canais',
    moduleId: 'comunicacao_canais',
    keywords:
        'canais espacos de trabalho workspaces comunicados avisos estou ciente leitura transmissao thread notificacao silenciar mencao arroba canal aqui editar apagar mensagem novas mensagens',
    steps: [
      HelpGuideStep(
        title: 'Encontrar os canais do seu departamento',
        description:
            'A aba Canais mostra os Espaços de Trabalho da empresa. Use a busca para localizar um canal pelo nome e os filtros de categoria (Todos, Operações, Financeiro, Faturamento, RH) para reduzir a lista. Cada cartão exibe a descrição e a data da última atividade.',
        image: '${_shot}workspaces.webp',
      ),
      HelpGuideStep(
        title: 'Definir quanto o canal te notifica',
        description:
            'O ícone de sino, na barra do canal, escolhe entre Todas as mensagens, Somente menções e Silenciado. É uma preferência sua: não muda nada para os outros membros. A mesma opção está em Informações do canal → Minhas notificações.',
        tip:
            'Prefira silenciar o canal específico a desligar a notificação do app inteiro — assim o que é urgente continua chegando.',
      ),
      HelpGuideStep(
        title: 'Chamar uma pessoa ou o canal inteiro',
        description:
            'Digite @ e escolha a pessoa na lista. No topo das sugestões ficam @canal e @aqui, que alcançam inclusive quem colocou o canal em "somente menções" — a notificação de quem foi citado chega destacada.',
        tip:
            'Use @canal só para o que precisa de atenção agora: ele fura o silêncio que as pessoas escolheram, e abusar dele faz o time silenciar o canal por completo.',
      ),
      HelpGuideStep(
        title: 'Corrigir ou remover o que você enviou',
        description:
            'Toque e segure a mensagem para abrir as ações. "Editar" corrige o texto e a bolha passa a mostrar "editado"; "Apagar" remove para todos. Anúncios e enquetes não são editáveis, porque já carregam confirmações de leitura e votos.',
        tip:
            'Quem administra o workspace também pode apagar mensagem de terceiro — a ação fica registrada na auditoria.',
      ),
      HelpGuideStep(
        title: 'Descobrir e seguir canais públicos',
        description:
            'O ícone de bússola no topo abre a descoberta de canais: ali ficam os canais públicos que você ainda não segue. Entre no canal e ele passa a aparecer na sua lista, com contador de mensagens não lidas.',
        image: '${_shot}workspaces.webp',
      ),
      HelpGuideStep(
        title: 'Ler um comunicado e confirmar com "Estou Ciente"',
        description:
            'Comunicados oficiais chegam destacados como ANÚNCIO OFICIAL. Quando o autor exige confirmação, o aviso traz o botão "Estou Ciente" no rodapé da mensagem: leia o texto até o fim e toque no botão. A confirmação registra o seu nome, a data e a hora na auditoria.',
        image: '${_shot}comunicados.webp',
        tip:
            'Enquanto houver comunicado pendente, ele continua em destaque no topo do canal.',
      ),
      HelpGuideStep(
        title: 'Acompanhar a taxa de leitura (gestores)',
        description:
            'O cabeçalho do canal de avisos mostra o percentual de ciência já coletado. Abra o detalhe do comunicado para ver a lista de quem confirmou e de quem ainda está pendente — é o que você usa para cobrar internamente.',
        image: '${_shot}comunicados.webp',
      ),
      HelpGuideStep(
        title: 'Responder em thread',
        description:
            'Para discutir um ponto específico sem poluir o canal, use "Responder em thread" na mensagem. A conversa abre numa linha própria e quem não participa dela continua vendo o canal limpo.',
        tip:
            'Dentro de um tópico as menções coletivas não aparecem: uma resposta em thread não deve virar aviso geral.',
      ),
      HelpGuideStep(
        title: 'Retomar de onde parou',
        description:
            'Ao reabrir um canal com mensagens novas, uma régua "Novas mensagens" marca o ponto em que a sua leitura parou.',
      ),
    ],
  ),
  HelpGuide(
    id: 'conversas',
    title: 'Conversas e mensagens diretas',
    description: 'Bate-papo 1:1, grupos, anexos e o assistente de IA.',
    icon: Icons.chat_bubble_rounded,
    color: Color(0xFF60a5fa),
    audience: _todos,
    route: '/chats?tab=conversas',
    moduleId: 'comunicacao_conversas',
    keywords:
        'conversas chat dm mensagem direta grupo anexo foto arquivo favoritos assistente ia criptografia',
    steps: [
      HelpGuideStep(
        title: 'Abrir uma conversa',
        description:
            'Na aba Conversas você vê seus bate-papos recentes com a prévia da última mensagem e o indicador de leitura. Toque no botão flutuante de balão para iniciar uma conversa nova com qualquer colega da empresa.',
        image: '${_shot}conversas.webp',
        tip: 'As conversas diretas são criptografadas de ponta a ponta.',
      ),
      HelpGuideStep(
        title: 'Encontrar a pessoa certa',
        description:
            'A lista de contatos vem agrupada por filial e departamento (Faturamento, Comercial/Vendas, Diretoria, RH, TI…). Use a busca por nome ou role até o setor para achar quem procura sem depender de lista de telefone.',
        image: '${_img}novo-chat-por-departamento.webp',
      ),
      HelpGuideStep(
        title: 'Criar um grupo',
        description:
            'Grupos funcionam como no WhatsApp e são independentes do seu cargo global: quem cria administra, podendo promover ou remover administradores do próprio grupo, definir nome e foto e adicionar ou remover participantes.',
      ),
      HelpGuideStep(
        title: 'Enviar anexos e salvar o que importa',
        description:
            'Envie fotos, documentos e áudios direto do chat. Mensagens importantes podem ser marcadas com estrela e reencontradas depois em "Favoritos", sem precisar rolar o histórico.',
      ),
      HelpGuideStep(
        title: 'Usar o Assistente de IA',
        description:
            'A conversa com o Assistente de IA funciona como qualquer outra: pergunte sobre procedimentos internos, peça resumos ou tire dúvidas de uso do sistema. O histórico dessa conversa é seu e pode ser apagado a qualquer momento.',
        image: '${_shot}conversas.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'chamadas',
    title: 'Chamadas e reuniões',
    description: 'Voz e vídeo 1:1, salas de grupo e histórico de chamadas.',
    icon: Icons.videocam_rounded,
    color: Color(0xFF14b8a6),
    audience: _todos,
    route: '/chats?tab=chamadas',
    moduleId: 'comunicacao_chamadas',
    keywords:
        'chamada ligacao video voz reuniao sala compartilhar tela perdidas historico',
    steps: [
      HelpGuideStep(
        title: 'Fazer uma chamada 1:1',
        description:
            'Abra a conversa direta com o colega e toque no ícone de câmera (vídeo) ou telefone (voz) no topo. O aparelho da outra pessoa toca e vibra, mesmo com o app em segundo plano.',
      ),
      HelpGuideStep(
        title: 'Abrir uma sala de reunião em grupo',
        description:
            'Em um canal ou grupo, toque no ícone de câmera do cabeçalho: o sistema cria uma sala de videoconferência e publica o convite no próprio chat. Quem quiser participar entra com um toque no cartão da reunião.',
      ),
      HelpGuideStep(
        title: 'Usar os recursos durante a chamada',
        description:
            'Na barra inferior da sala você alterna câmera, silencia o microfone, compartilha a tela, abre o chat da reunião e ajusta a qualidade do vídeo conforme a sua conexão.',
      ),
      HelpGuideStep(
        title: 'Consultar o histórico',
        description:
            'A aba Chamadas guarda tudo em três filtros: Todas, Perdidas e Reuniões. Cada linha mostra o interlocutor ou o canal, o tipo da chamada e quando aconteceu — e permite retornar a ligação com um toque.',
        image: '${_shot}chamadas.webp',
      ),
      HelpGuideStep(
        title: 'Entender a proteção de tela bloqueada',
        description:
            'Se você atende uma chamada com o celular bloqueado, minimizar a chamada ou voltar para o app exige biometria ou senha do aparelho. É o que impede que suas conversas fiquem expostas em um celular perdido.',
      ),
    ],
  ),

  // ───────────────────────────── Operação ─────────────────────────────
  HelpGuide(
    id: 'notificacoes',
    title: 'Notificações e alertas',
    description:
        'Receba, responda e ajuste as notificações no celular e no navegador.',
    icon: Icons.notifications_active_rounded,
    color: Color(0xFFf97316),
    audience: _todos,
    route: '/settings/notifications',
    keywords:
        'notificacao push alerta responder marcar como lida silenciar mencao horario silencioso navegador iphone nao recebo',
    steps: [
      HelpGuideStep(
        title: 'Permitir notificações',
        description:
            'No Android, aceite o pedido de permissão na primeira abertura. No navegador, vá em Configurações > Notificações e toque em Ativar notificações. No iPhone, instale o app pela Tela de Início antes — sem isso o sistema não entrega nada.',
        tip: 'Se você recusou por engano, libere nas configurações do celular ou do site no navegador.',
      ),
      HelpGuideStep(
        title: 'Ler a notificação da conversa',
        description:
            'Cada conversa ganha uma notificação só, com a foto de quem enviou e as últimas mensagens empilhadas. Em grupos e canais, o nome do grupo fica no topo e cada linha mostra o autor.',
      ),
      HelpGuideStep(
        title: 'Responder sem abrir o app',
        description:
            'Toque em Responder, escreva e envie. Sua resposta aparece na notificação como "Você: …" e a conversa já fica marcada como lida. Se a linha mostrar "Não enviada", abra a conversa e tente de novo.',
      ),
      HelpGuideStep(
        title: 'Marcar como lida',
        description:
            'Marcar como lida zera a conversa e tira a notificação da bandeja, sem precisar abrir o app. Abrir a conversa faz o mesmo.',
      ),
      HelpGuideStep(
        title: 'Ajustar quanto cada lugar te avisa',
        description:
            'Em Configurações > Notificações ligue ou desligue por tipo e defina o horário silencioso. Dentro de um canal, escolha Todas as mensagens, Somente menções ou Silenciado. Numa conversa, use Silenciar notificações no menu.',
        tip: 'Chamadas continuam tocando no horário silencioso.',
      ),
      HelpGuideStep(
        title: 'Resolver "não estou recebendo"',
        description:
            'Confira a permissão do app no aparelho, o liga/desliga geral, o horário silencioso e se a conversa está silenciada. No Android, desative a otimização de bateria para o app: alguns fabricantes fecham apps em segundo plano.',
      ),
    ],
  ),
  HelpGuide(
    id: 'quadro-branco',
    title: 'Quadro branco',
    description:
        'Desenhe em equipe, em tempo real, por cima de fotos e documentos.',
    icon: Icons.draw_rounded,
    color: Color(0xFF00A79D),
    audience: _todos,
    keywords:
        'quadro branco lousa desenhar caneta marca texto borracha anexo foto pdf colaborativo',
    steps: [
      HelpGuideStep(
        title: 'Criar o quadro na conversa',
        description:
            'No + ao lado do campo de mensagem, escolha Quadro e dê um nome. O quadro vira um cartão na conversa ou no canal, e só os membros dali conseguem abrir.',
      ),
      HelpGuideStep(
        title: 'Desenhar junto',
        description:
            'Toque em Abrir quadro. Escolha Caneta ou Marca-texto e a espessura. Todo mundo que estiver com o quadro aberto vê os traços aparecerem na hora.',
      ),
      HelpGuideStep(
        title: 'Anexar uma foto ou arquivo',
        description:
            'Adicione uma imagem da galeria, tire uma foto ou anexe um PDF ou planilha, e desenhe por cima para marcar o ponto que importa.',
        tip: 'Use Mover anexos para arrastar e redimensionar o que foi anexado.',
      ),
      HelpGuideStep(
        title: 'Corrigir',
        description:
            'Desfazer meu último traço desfaz só o que você desenhou. Borracha apaga um trecho, e Limpar traços remove os desenhos do quadro depois de confirmar.',
      ),
    ],
  ),
  HelpGuide(
    id: 'workflow',
    title: 'Espaços de trabalho e Workflow Kanban',
    description:
        'Monte o funil da operação e transforme solicitações em cards com dono e prazo.',
    icon: Icons.view_kanban_rounded,
    color: Color(0xFFf59e0b),
    audience: _gestores,
    keywords:
        'kanban workflow card demanda funil etapas sla prioridade builder canal assumir atendimento anexo',
    steps: [
      HelpGuideStep(
        title: 'Escolher um preset de partida',
        description:
            'Em Canais > Novo Fluxo, a primeira faixa mostra os modelos disponíveis: os de fábrica (Liberação Contas a Pagar, Liberação de Pedido, Documentação/Cadastro, Faturamento OS/Produtos, Avisos Gerais, Canal Genérico e Somente Comunicação) e os que a sua empresa criou. Escolha o mais parecido com o seu processo — ele preenche identidade, formulário do card e etapas de uma vez.',
        image: '${_shot}canal-builder.webp',
        tip:
            'O preset é ponto de partida, não camisa de força: tudo continua editável antes de confirmar.',
      ),
      HelpGuideStep(
        title: 'Ajustar identidade e categoria',
        description:
            'Dê nome e descrição, escolha o ícone e a cor do workspace e defina a categoria: Financeiro, Faturamento, Operacional, Informativo, RH, Comercial ou TI. O cartão no topo mostra em tempo real como o canal vai aparecer na lista.',
        image: '${_shot}canal-builder.webp',
      ),
      HelpGuideStep(
        title: 'Montar as etapas do funil',
        description:
            'Em "Etapas do Kanban": arraste pelo ícone ☰ para reordenar, toque no ícone da etapa para trocar o desenho, na paleta para a cor, e escreva no nome para renomear. O menu ⋮ de cada etapa marca qual é a inicial, qual conclui e qual cancela.',
        image: '${_shot}canal-builder.webp',
        tip:
            'Se a sua etapa de cancelamento não se chama "Cancelado" — por exemplo "Recusado" ou "Reprovado" —, marque-a pelo menu ⋮. Sem isso ela vira uma coluna comum do quadro e entra na conta do SLA.',
      ),
      HelpGuideStep(
        title: 'Salvar a montagem como preset (opcional)',
        description:
            'O ícone de marcador, no topo da tela de criação, transforma a configuração atual em um preset reutilizável. Você escolhe se ele fica compartilhado com a empresa ou privado. A biblioteca completa fica no ícone de modelos, na aba Canais, onde dá para editar, duplicar e excluir os seus presets.',
        tip:
            'Os modelos de fábrica são somente leitura — use "Duplicar" para criar a sua versão a partir deles.',
      ),
      HelpGuideStep(
        title: 'Abrir uma demanda',
        description:
            'Dentro do canal, use a aba Workflow e o botão "+" para criar o card. Preencha título, descrição, prioridade (Baixa, Média, Alta, Urgente), valores quando houver e anexe os documentos de apoio.',
        image: '${_img}workflow-kanban.webp',
      ),
      HelpGuideStep(
        title: 'Assumir o atendimento',
        description:
            'Se o canal tem operador fixo, o card já nasce atribuído. Se opera em fila, ele fica disponível para todos os operadores autorizados até alguém tocar em "Assumir Atendimento" — a partir daí o responsável é público.',
      ),
      HelpGuideStep(
        title: 'Mover o card pelas etapas',
        description:
            'Arraste o card para a próxima coluna à medida que o processo anda. Cada transição grava quem moveu, quando moveu e quanto tempo o card ficou na etapa anterior. Use "Aguardando Solicitante" quando a tratativa depender de algo que o solicitante precisa enviar.',
        image: '${_img}workflow-kanban.webp',
        tip:
            'Quem abriu o card acompanha tudo, mas não move status nem finaliza — isso é do operador, por desenho.',
      ),
      HelpGuideStep(
        title: 'Encerrar com comprovante',
        description:
            'Na etapa final, anexe o comprovante e finalize. O card é arquivado com todo o histórico de conversa, prazos e movimentações preservado para consulta e auditoria.',
      ),
      HelpGuideStep(
        title: 'Escolher a visualização que te serve',
        description:
            'O Workflow tem três modos: Quadro (colunas Kanban, bom para acompanhamento visual), Lista (volume alto, ordenação por prazo) e Compacta (telas pequenas ou muitos chamados simultâneos).',
      ),
      HelpGuideStep(
        title: 'Ajustar o workspace depois de pronto',
        description:
            'O lápis ao lado do nome, em Informações do canal, abre a edição completa: identidade, categoria, permissão de publicação e as etapas do Kanban. O funil não fica mais congelado no formato escolhido na criação.',
        tip:
            'Ao remover uma etapa que ainda tem cards, o sistema pergunta para onde movê-los e registra a mudança no histórico de cada card — nada se perde.',
      ),
    ],
  ),
  HelpGuide(
    id: 'minha-operacao',
    title: 'Minha Operação',
    description:
        'Os cards atribuídos a você em todos os workspaces, por urgência.',
    icon: Icons.assignment_ind_rounded,
    color: Color(0xFF0ea5e9),
    audience: _gestores,
    route: '/minha-operacao',
    keywords:
        'minha operacao meus cards atribuidos atrasados hoje proximos prazo todos os workspaces',
    steps: [
      HelpGuideStep(
        title: 'Abrir a tela',
        description:
            'No menu ⋮ da tela inicial, toque em Minha Operação. A lista junta os cards que estão com você em todos os espaços de trabalho.',
      ),
      HelpGuideStep(
        title: 'Priorizar pelo grupo',
        description:
            'Os cards vêm separados em Em atraso, Para hoje, Próximos, Sem prazo e Concluídos. Comece pelo topo: o que está atrasado primeiro.',
      ),
      HelpGuideStep(
        title: 'Ir até o workspace',
        description:
            'Cada card mostra de qual workspace veio. Toque para abrir o workspace e mover, comentar ou concluir o card por lá.',
        tip: 'Cards que você abriu como solicitante não entram aqui — eles estão com outra pessoa.',
      ),
    ],
  ),
  HelpGuide(
    id: 'helpdesk',
    title: 'Suporte e Helpdesk (TI)',
    description: 'Abrir chamados, conversar com o técnico e acompanhar o SLA.',
    icon: Icons.confirmation_number_rounded,
    color: Color(0xFFeab308),
    audience: _todos,
    route: '/support/help',
    moduleId: 'helpdesk_central',
    keywords:
        'helpdesk chamado ticket suporte ti hardware software rede acesso credencial sla prioridade',
    steps: [
      HelpGuideStep(
        title: 'Abrir um chamado',
        description:
            'Use "Abrir chamado" nos atalhos da Central de Ajuda. Escolha a categoria — Sistema/Software, Equipamentos/Hardware, Internet/Rede, Acessos/Credenciais, Dúvida Geral ou Outro —, defina a prioridade (Baixa, Normal, Alta, Urgente) e descreva o problema com o máximo de detalhe.',
        image: '${_shot}ajuda-central.webp',
        tip:
            'Anexe print ou foto do erro: chamados com evidência costumam ser resolvidos numa fração do tempo.',
      ),
      HelpGuideStep(
        title: 'Conversar dentro do chamado',
        description:
            'Cada ticket abre uma conversa própria com o técnico responsável. Todo o histórico — mensagens, fotos e arquivos — fica preso àquele chamado, sem se misturar com os seus outros chats.',
        image: '${_shot}helpdesk-ticket.webp',
      ),
      HelpGuideStep(
        title: 'Acompanhar em Meus Chamados',
        description:
            'A aba "Meus Chamados" desta Central lista os seus tickets com status atual: Novo, Em Andamento, Pendente Fornecedor, Resolvido ou Cancelado. Toque em qualquer um para retomar a conversa.',
      ),
      HelpGuideStep(
        title: 'Atender a fila (equipe de TI)',
        description:
            'Quem tem permissão de atendimento vê o painel Helpdesk TI, com os chamados agrupados em Novos, Em Atendimento, Pendentes e Concluídos, cada um com categoria, prioridade, autor e responsável. Assuma o chamado, responda no chat e encerre quando resolver.',
        image: '${_shot}helpdesk.webp',
      ),
    ],
  ),

  // ─────────────────────────── Pessoas & RH ───────────────────────────
  HelpGuide(
    id: 'rh-funcionarios',
    title: 'Funcionários',
    description: 'Diretório da organização e ficha completa de cada pessoa.',
    icon: Icons.contact_page_rounded,
    color: Color(0xFF10b981),
    audience: _rh,
    route: '/rh/funcionarios',
    moduleId: 'rh_funcionarios',
    keywords:
        'funcionarios colaborador diretorio ficha matricula clt pj aprendiz vinculo admissao desligamento filial cargo',
    steps: [
      HelpGuideStep(
        title: 'Ler o diretório',
        description:
            'O topo resume o quadro: Total, Ativo, Férias, Afastado e Desligado. Cada linha mostra filial, departamento, cargo, matrícula e tempo de casa, com etiquetas de vínculo (CLT, PJ, Aprendiz) e de situação.',
        image: '${_shot}rh-funcionarios.webp',
      ),
      HelpGuideStep(
        title: 'Filtrar e localizar uma pessoa',
        description:
            'Busque por nome ou matrícula e combine com os filtros de situação (Todos, Ativo, Férias, Afastado, Desligado) para chegar rápido em quem você precisa.',
        image: '${_shot}rh-funcionarios.webp',
      ),
      HelpGuideStep(
        title: 'Cadastrar um novo funcionário',
        description:
            'Use "Novo funcionário" e preencha dados pessoais, vínculo, filial, departamento, cargo, matrícula e data de admissão. As áreas e cargos disponíveis vêm do Catálogo mantido no módulo de Recrutamento.',
      ),
      HelpGuideStep(
        title: 'Vincular o funcionário à conta de acesso',
        description:
            'Na ficha, use a opção de vínculo para conectar o cadastro de RH ao usuário do aplicativo. É esse vínculo que faz holerites, documentos, ponto e onboarding aparecerem no "Meu espaço" da pessoa.',
        tip:
            'Sem vínculo, o funcionário existe no RH mas não recebe nada no app.',
      ),
      HelpGuideStep(
        title: 'Manter o histórico',
        description:
            'A ficha guarda dependentes, histórico de cargo e salário e a situação cadastral. Atualize aqui promoções e mudanças de vínculo em vez de abrir um cadastro novo — o histórico é o que sustenta a auditoria.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-documentos',
    title: 'Documentos digitais',
    description: 'ASO, CNH e certificados com validade e ciência do funcionário.',
    icon: Icons.folder_shared_rounded,
    color: Color(0xFF34d399),
    audience: _rh,
    route: '/rh/documentos',
    moduleId: 'rh_documentos',
    keywords:
        'documentos aso cnh certificado validade vencimento ciencia upload assinatura meus documentos',
    steps: [
      HelpGuideStep(
        title: 'Entender os estados de validade',
        description:
            'Cada documento mostra categoria, dono e uma etiqueta de situação: Válido (verde), Próximo do Vencimento (amarelo) ou Vencido (vermelho), calculada a partir da data de vencimento informada.',
        image: '${_shot}rh-documentos.webp',
      ),
      HelpGuideStep(
        title: 'Enviar um documento',
        description:
            'Cadastre o documento escolhendo o funcionário, a categoria (ASO, Identidade, Certificação…) e a data de vencimento, e anexe o arquivo. Use "Ver / Baixar" a qualquer momento para consultar o original.',
        image: '${_shot}rh-documentos.webp',
      ),
      HelpGuideStep(
        title: 'Exigir ciência do funcionário',
        description:
            'Ligue a chave "Exigir ciência do funcionário" para que a pessoa precise confirmar a leitura em "Meus Documentos". A confirmação fica registrada com data e hora.',
        image: '${_shot}rh-documentos.webp',
      ),
      HelpGuideStep(
        title: 'Acompanhar vencimentos sem planilha',
        description:
            'O módulo Alertas RH recolhe automaticamente os documentos vencidos e a vencer, junto com contratos de experiência e outras pendências, para você agir antes do prazo estourar.',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Meus Documentos, a pessoa vê os próprios arquivos, baixa cópias e dá a ciência quando solicitada — sem precisar passar pelo RH por e-mail.',
        image: '${_shot}meu-perfil.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-ausencias',
    title: 'Ausências e férias',
    description: 'Solicitações, calendário da equipe e saldo de férias.',
    icon: Icons.event_busy_rounded,
    color: Color(0xFF22c55e),
    audience: _rh,
    route: '/rh/ausencias',
    moduleId: 'rh_ausencias',
    keywords:
        'ausencia falta atestado folga ferias saldo periodo aquisitivo aprovacao calendario afastamento',
    steps: [
      HelpGuideStep(
        title: 'Receber a solicitação',
        description:
            'A aba Solicitações concentra os pedidos enviados pelos colaboradores — férias, atestado ou folga — com o período pedido e o comprovante anexado.',
        image: '${_shot}rh-ausencias.webp',
      ),
      HelpGuideStep(
        title: 'Ler o calendário da equipe',
        description:
            'A aba Calendário mostra o mês inteiro com as ausências por pessoa. A legenda separa Férias, Atestado, Folga e Aguardando aprovação — é assim que você evita aprovar duas saídas simultâneas no mesmo setor.',
        image: '${_shot}rh-ausencias.webp',
      ),
      HelpGuideStep(
        title: 'Aprovar ou recusar',
        description:
            'Abra a solicitação, confira o comprovante e decida. Ao aprovar, a ausência entra no calendário e no histórico oficial do funcionário; ao recusar, o colaborador é notificado.',
      ),
      HelpGuideStep(
        title: 'Controlar o saldo de férias',
        description:
            'A aba "Saldos de férias" acompanha o período aquisitivo e os dias disponíveis de cada pessoa, para programar as férias sem estourar prazo legal.',
        image: '${_shot}rh-ausencias.webp',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Minhas Ausências e Férias, a pessoa abre o pedido, anexa o atestado pelo celular e acompanha a aprovação.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-ponto',
    title: 'Controle de ponto',
    description: 'Registros por período, ajustes auditáveis e espelho do mês.',
    icon: Icons.access_time_filled_rounded,
    color: Color(0xFF4ade80),
    audience: _rh,
    route: '/rh/ponto',
    moduleId: 'rh_ponto',
    keywords:
        'ponto batida espelho horas extras banco de horas entrada saida lancamento ajuste',
    steps: [
      HelpGuideStep(
        title: 'Filtrar o que você quer ver',
        description:
            'Escolha o intervalo de datas e o funcionário (ou "Todos") no topo da tela. Os registros vêm agrupados por dia, com horário, tipo de batida (Entrada/Saída) e o nome de quem registrou.',
        image: '${_shot}rh-ponto.webp',
      ),
      HelpGuideStep(
        title: 'Lançar um registro manualmente',
        description:
            'Quando houver falha de marcação, use "Lançar registro" para incluir a batida faltante informando funcionário, data, hora e tipo. O lançamento manual fica identificado como tal.',
        image: '${_shot}rh-ponto.webp',
        tip:
            'Todo ajuste manual é auditável: fica gravado quem lançou e quando.',
      ),
      HelpGuideStep(
        title: 'Corrigir ou remover uma batida',
        description:
            'O menu de três pontos ao lado de cada registro permite editar o horário ou excluir a marcação incorreta, mantendo o espelho consistente.',
        image: '${_shot}rh-ponto.webp',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Meu Ponto, a pessoa consulta o próprio espelho do período e identifica divergências antes do fechamento da folha.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-holerites',
    title: 'Holerites',
    description: 'Distribuição digital do contracheque com confirmação de leitura.',
    icon: Icons.request_quote_rounded,
    color: Color(0xFF84cc16),
    audience: _rh,
    route: '/rh/holerites',
    moduleId: 'rh_holerites',
    keywords:
        'holerite contracheque recibo pagamento folha pdf visualizado emitir competencia',
    steps: [
      HelpGuideStep(
        title: 'Emitir o holerite',
        description:
            'Use "Emitir holerite", selecione o funcionário e a competência (mês/ano) e anexe o PDF. O colaborador recebe uma notificação assim que o arquivo é publicado.',
        image: '${_shot}rh-holerites.webp',
      ),
      HelpGuideStep(
        title: 'Conferir quem já visualizou',
        description:
            'Cada linha mostra competência, funcionário e a etiqueta "Visualizado" com data e hora da abertura. É a sua prova de entrega do contracheque.',
        image: '${_shot}rh-holerites.webp',
      ),
      HelpGuideStep(
        title: 'Filtrar por pessoa e por ano',
        description:
            'Os seletores de Funcionário e Ano no topo reduzem a lista quando você precisa auditar uma competência específica ou reenviar um documento.',
        image: '${_shot}rh-holerites.webp',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Meus Holerites, a pessoa acessa o histórico completo e baixa o PDF direto do celular, sem pedir segunda via.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-beneficios',
    title: 'Benefícios',
    description: 'Catálogo de planos e adesões por colaborador.',
    icon: Icons.card_giftcard_rounded,
    color: Color(0xFFa3e635),
    audience: _rh,
    route: '/rh/beneficios',
    moduleId: 'rh_beneficios',
    keywords:
        'beneficios vale refeicao alimentacao plano de saude odontologico adesao desconto folha operadora',
    steps: [
      HelpGuideStep(
        title: 'Montar o catálogo',
        description:
            'A aba Catálogo lista os benefícios oferecidos pela empresa com tipo (refeição, alimentação, saúde…) e operadora. Use "Novo benefício" para cadastrar e o lápis para editar ou desativar um plano.',
        image: '${_shot}rh-beneficios.webp',
      ),
      HelpGuideStep(
        title: 'Registrar a adesão de um colaborador',
        description:
            'Na aba Adesões, toque em "Nova adesão", escolha o funcionário e o benefício, informe a data de adesão e, se houver, o desconto em folha. O valor é armazenado criptografado por organização.',
        image: '${_shot}rh-desempenho.webp',
      ),
      HelpGuideStep(
        title: 'Acompanhar e encerrar adesões',
        description:
            'A lista de adesões mostra benefício, pessoa, data e situação. Use o botão de encerrar para cancelar a adesão quando o colaborador sai do plano — o histórico permanece.',
        image: '${_shot}rh-desempenho.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-desempenho',
    title: 'Desempenho e avaliações',
    description: 'Ciclos de avaliação e registros de 1:1 por colaborador.',
    icon: Icons.insights_rounded,
    color: Color(0xFF06b6d4),
    audience: _rh,
    route: '/rh/desempenho',
    moduleId: 'rh_desempenho',
    keywords:
        'desempenho avaliacao ciclo 360 autoavaliacao gestor pares feedback nota meta 1:1',
    steps: [
      HelpGuideStep(
        title: 'Abrir um ciclo de avaliação',
        description:
            'Na aba Ciclos, crie o ciclo com nome e período e defina quem participa. É o ciclo que organiza autoavaliação, avaliação do gestor, dos pares e dos subordinados dentro da mesma janela.',
      ),
      HelpGuideStep(
        title: 'Registrar uma avaliação 1:1',
        description:
            'Na aba Avaliações 1:1, use "Nova avaliação", escolha o colaborador, a nota e escreva o feedback. Cada registro fica com o autor, o papel (gestor, par, autoavaliação) e a data.',
        image: '${_shot}rh-avaliacoes.webp',
      ),
      HelpGuideStep(
        title: 'Consultar o histórico de uma pessoa',
        description:
            'O seletor de Funcionário filtra a lista e mostra a evolução das notas e dos comentários ao longo do tempo — a base da conversa de carreira.',
        image: '${_shot}rh-avaliacoes.webp',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Meu Desempenho, a pessoa acompanha as próprias notas e devolutivas e responde a autoavaliação quando o ciclo está aberto.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-onboarding',
    title: 'Onboarding',
    description: 'Checklists de integração padrão ou específicos por time.',
    icon: Icons.assignment_turned_in_rounded,
    color: Color(0xFF22d3ee),
    audience: _rh,
    route: '/rh/onboarding-templates',
    moduleId: 'rh_onboarding',
    keywords:
        'onboarding integracao checklist template primeiro dia admissao novo colaborador',
    steps: [
      HelpGuideStep(
        title: 'Usar o template padrão',
        description:
            'O template marcado como "Padrão" é aplicado a todo novo colaborador. Ele reúne os itens que valem para a empresa inteira: e-mail corporativo, crachá, entrega de equipamento, treinamentos obrigatórios.',
        image: '${_shot}rh-onboarding.webp',
      ),
      HelpGuideStep(
        title: 'Criar um checklist por time',
        description:
            'Use "Novo Template" para montar roteiros específicos (por exemplo, Integração Comercial). Adicione os itens na ordem em que devem acontecer e descreva o que é considerado concluído.',
        image: '${_shot}rh-onboarding.webp',
      ),
      HelpGuideStep(
        title: 'Acompanhar a execução',
        description:
            'Ao vincular o template a um novo funcionário, cada item vira uma tarefa acompanhada. Você enxerga o que já foi feito e o que está pendente antes do fim do período de experiência.',
      ),
      HelpGuideStep(
        title: 'O lado do colaborador',
        description:
            'Em Meu Perfil > Meu Onboarding, o recém-chegado vê a própria lista de integração e marca o que já concluiu.',
      ),
    ],
  ),
  HelpGuide(
    id: 'rh-alertas',
    title: 'Alertas de RH',
    description: 'Vencimentos, aniversários e pendências reunidos em um painel.',
    icon: Icons.warning_rounded,
    color: Color(0xFFf472b6),
    audience: _rh,
    route: '/rh/alertas',
    moduleId: 'rh_alertas',
    keywords:
        'alertas vencimento contrato experiencia aniversario pendencia prazo aviso rh',
    steps: [
      HelpGuideStep(
        title: 'Ler o painel de alertas',
        description:
            'O módulo reúne automaticamente o que tem prazo: documentos vencidos e a vencer, fim de contrato de experiência, aniversariantes do mês e pendências de aprovação.',
      ),
      HelpGuideStep(
        title: 'Agir a partir do alerta',
        description:
            'Cada alerta leva direto ao registro de origem — o documento, a ficha do funcionário ou a solicitação — para você resolver sem procurar em outro módulo.',
      ),
      HelpGuideStep(
        title: 'Receber no celular',
        description:
            'Ative as notificações do módulo Alertas RH em Configurações > Notificações para ser avisado sem depender de abrir o painel.',
        image: '${_shot}configuracoes.webp',
      ),
    ],
  ),

  // ─────────────────────────── Recrutamento ───────────────────────────
  HelpGuide(
    id: 'recrutamento',
    title: 'Recrutamento e seleção',
    description:
        'Da vaga publicada ao candidato contratado, com prova gerada por IA.',
    icon: Icons.person_add_alt_1_rounded,
    color: Color(0xFFa855f7),
    audience: _rh,
    route: '/rh',
    moduleId: 'rh_banco_talentos',
    keywords:
        'recrutamento vaga candidato pipeline funil carreiras qr code prova ia questoes lgpd retencao etapas catalogo areas cargos',
    steps: [
      HelpGuideStep(
        title: 'Ler a visão geral',
        description:
            'A aba Visão Geral resume o processo: candidatos, em processo, contratados, taxa de conversão e contratações nos últimos 30 dias, mais o funil por etapa e a distribuição por fonte e por nível. "Exportar CSV" leva os dados para fora quando você precisa de relatório.',
        image: '${_shot}recrut-visao-geral.webp',
      ),
      HelpGuideStep(
        title: 'Publicar a vaga',
        description:
            'Na aba Vagas, cadastre título, área, cargo, nível, local e faixa salarial. A vaga publicada passa a aparecer na página pública de carreiras.',
      ),
      HelpGuideStep(
        title: 'Divulgar a página de carreiras',
        description:
            'Na aba Divulgação, ative "Página de carreiras ativa" e use o link de inscrição — com botões de copiar, WhatsApp e e-mail — ou o QR code para cartaz e material impresso. O texto de chamada e a apresentação da empresa são editáveis ali mesmo.',
        image: '${_shot}recrut-carreiras.webp',
      ),
      HelpGuideStep(
        title: 'Trabalhar o pipeline',
        description:
            'A aba Pipeline lista os candidatos por etapa (Novo, Em análise, Entrevista, Aprovado, Contratado, Descartado), com aderência, pretensão salarial e origem. Busque por nome, e-mail ou cargo e use "Meus candidatos" para ver só os seus.',
        image: '${_shot}recrut-pipeline.webp',
      ),
      HelpGuideStep(
        title: 'Gerar a prova com IA',
        description:
            'Na aba Avaliações, use "Gerar com IA": escolha o cargo, o nível e a quantidade de questões. A IA monta a prova de múltipla escolha; revise antes de aplicar. O gabarito nunca é enviado ao candidato.',
        image: '${_shot}recrut-ia-questoes.webp',
        tip:
            'Você também pode criar questões manualmente em "Nova questão" e misturar com as geradas.',
      ),
      HelpGuideStep(
        title: 'Ajustar as etapas do funil',
        description:
            'Em Ajustes > Etapas do pipeline você renomeia, reordena e cria etapas. As etapas de entrada (Novo) e terminais (Contratado, Descartado) são fixas por natureza — as do meio você molda ao seu processo.',
        image: '${_shot}recrut-etapas.webp',
      ),
      HelpGuideStep(
        title: 'Manter o catálogo de áreas e cargos',
        description:
            'Ainda em Ajustes, o Catálogo de Áreas e Cargos alimenta vagas, filtros e o cadastro de funcionários. Ative, desative ou renomeie itens para manter a nomenclatura padronizada em toda a empresa.',
        image: '${_shot}recrut-catalogo.webp',
      ),
      HelpGuideStep(
        title: 'Definir a retenção LGPD',
        description:
            'Em Ajustes, o período de retenção define depois de quanto tempo candidatos não contratados são anonimizados automaticamente. É o controle que mantém o banco de talentos dentro da LGPD.',
        image: '${_shot}recrut-etapas.webp',
      ),
      HelpGuideStep(
        title: 'Converter o aprovado em funcionário',
        description:
            'Ao mover o candidato para Contratado, use a conversão para criar a ficha de funcionário aproveitando os dados já preenchidos na candidatura.',
      ),
    ],
  ),

  // ─────────────────────── Automações e e-mail ───────────────────────
  HelpGuide(
    id: 'automacoes',
    title: 'Comunicação e automações',
    description: 'SMTP próprio, templates de e-mail e disparo por etapa do funil.',
    icon: Icons.mark_email_read_rounded,
    color: Color(0xFFec4899),
    audience: _admin,
    route: '/rh/automacoes',
    moduleId: 'rh_automacoes',
    keywords:
        'smtp email remetente template automacao regra gatilho disparo dominio senha app password',
    steps: [
      HelpGuideStep(
        title: 'Configurar o servidor SMTP da empresa',
        description:
            'Na aba Servidor SMTP, informe host, porta, usuário e senha (ou App Password) e defina o remetente — nome e e-mail que o candidato verá. A senha é armazenada de forma criptografada. Salve a configuração ao final.',
        image: '${_shot}auto-smtp.webp',
        tip:
            'Sem SMTP configurado, as automações não têm por onde enviar: configure esta aba primeiro.',
      ),
      HelpGuideStep(
        title: 'Escrever os templates de e-mail',
        description:
            'Na aba Templates de E-mail, crie as mensagens padrão do processo: confirmação de inscrição, convite para entrevista, feedback de reprovação, proposta. Um template bem escrito é reaproveitado por todas as regras.',
      ),
      HelpGuideStep(
        title: 'Criar a regra de automação',
        description:
            'Na aba Regras de Automação, use "Nova Regra": escolha a etapa do funil que dispara o envio ("Quando o candidato for movido para a etapa") e o template correspondente ("Enviar o e-mail"). Salve e a regra passa a valer para todos os candidatos.',
        image: '${_shot}auto-regras.webp',
      ),
      HelpGuideStep(
        title: 'Testar antes de valer para todo mundo',
        description:
            'Mova um candidato de teste pela etapa configurada e confira a caixa de entrada antes de anunciar a automação ao time. Assim você valida remetente, assunto e formatação.',
      ),
    ],
  ),

  // ───────────────────────── Administração ─────────────────────────
  HelpGuide(
    id: 'admin-acessos',
    title: 'Perfis e permissões (RBAC)',
    description: 'Defina o que cada perfil pode ver e gerenciar em cada módulo.',
    icon: Icons.lock_rounded,
    color: Color(0xFF6366f1),
    audience: _admin,
    route: '/admin',
    moduleId: 'admin_panel',
    keywords:
        'rbac permissao perfil acesso visualizar gerenciar super admin gestor colaborador papel cargo modulo',
    steps: [
      HelpGuideStep(
        title: 'Abrir o Gerenciamento de Acessos',
        description:
            'No Painel Admin, entre na aba Acessos. A tela tem dois lados: à esquerda os Perfis de Acesso (Super Admin, RH, Gestor, Colaborador e os que você criar), à direita as permissões do perfil selecionado.',
        image: '${_shot}admin-rbac.webp',
      ),
      HelpGuideStep(
        title: 'Entender "Visualizar" e "Gerenciar"',
        description:
            'Cada módulo tem até duas chaves: Visualizar (pode abrir a tela) e Gerenciar (pode alterar configurações, permissões e dados). O contador ao lado do módulo (ex.: 1/2) mostra quantas chaves estão ligadas.',
        image: '${_shot}admin-rbac.webp',
        tip:
            'Comece pelo mínimo necessário e libere sob demanda — é mais fácil conceder depois do que auditar excesso.',
      ),
      HelpGuideStep(
        title: 'Criar um perfil novo',
        description:
            'Use o "+" ao lado de "Perfis de Acesso" para criar um perfil sob medida (ex.: Coordenador de Faturamento). Perfis marcados como SISTEMA não podem ser excluídos, mas podem ter permissões ajustadas.',
        image: '${_shot}admin-rbac.webp',
      ),
      HelpGuideStep(
        title: 'Salvar e conferir o efeito',
        description:
            'Toque em "Salvar" após ajustar as chaves. O usuário afetado passa a ver (ou deixar de ver) os itens no menu no próximo carregamento — o menu lateral é montado a partir dessas permissões.',
        image: '${_shot}admin-rbac.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'admin-usuarios',
    title: 'Gestão de usuários',
    description: 'Aprovar cadastros, atribuir perfis e controlar contas.',
    icon: Icons.manage_accounts_rounded,
    color: Color(0xFF818cf8),
    audience: _admin,
    route: '/admin',
    moduleId: 'admin_panel',
    keywords:
        'usuarios cadastro aprovar pendentes perfil papel funcao bloquear desativar conta novo usuario',
    steps: [
      HelpGuideStep(
        title: 'Ver quem tem acesso',
        description:
            'A aba Gestão de Usuários lista todas as contas com o perfil atribuído (Super Admin, Administrador, Colaborador…) e a função declarada. Use a busca por nome para localizar rapidamente.',
        image: '${_shot}admin-usuarios.webp',
      ),
      HelpGuideStep(
        title: 'Liberar cadastros pendentes',
        description:
            'O filtro "Pendentes" mostra quem se cadastrou e ainda aguarda aprovação do TI. Enquanto não for aprovado, o login é bloqueado com aviso na tela de entrada.',
        image: '${_shot}admin-usuarios.webp',
      ),
      HelpGuideStep(
        title: 'Cadastrar um usuário direto',
        description:
            'A aba Novo Cadastro cria a conta pelo painel: dados do colaborador, filial, departamento e perfil de acesso. É o caminho usado quando o TI provisiona a conta antes do primeiro dia.',
        image: '${_img}admin-novo-cadastro.webp',
      ),
      HelpGuideStep(
        title: 'Trocar o perfil de alguém',
        description:
            'Expanda a linha do usuário para alterar o perfil de acesso ou desativar a conta. A mudança é registrada na auditoria com autor e horário.',
        image: '${_shot}admin-usuarios.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'admin-governanca',
    title: 'Auditoria, moderação e relatórios',
    description: 'Rastrear ações, moderar conteúdo e medir o uso da plataforma.',
    icon: Icons.shield_rounded,
    color: Color(0xFF06b6d4),
    audience: _admin,
    route: '/admin',
    moduleId: 'admin_panel',
    keywords:
        'auditoria log moderacao advertir excluir mensagem canal relatorio uso metricas backup exportar localizacao chave ia',
    steps: [
      HelpGuideStep(
        title: 'Consultar a auditoria',
        description:
            'A aba Auditoria registra as ações críticas: criação e movimentação de cards, alteração de permissões, exclusão de mensagens, logins e mudanças de cadastro — com autor, alvo e horário.',
        image: '${_img}admin-auditoria.webp',
      ),
      HelpGuideStep(
        title: 'Moderar conteúdo',
        description:
            'A aba Moderação separa Mensagens e Canais. Em cada item você pode "Advertir" o autor ou "Excluir" o conteúdo fora da política. A ação fica registrada na auditoria.',
        image: '${_shot}admin-moderacao.webp',
      ),
      HelpGuideStep(
        title: 'Ler os relatórios de uso',
        description:
            'A aba Relatórios mostra usuários ativos, quem está online agora, mensagens e chamadas no mês, total de chats e canais, além do gráfico de mensagens por dia dos últimos 7 dias.',
        image: '${_shot}admin-relatorios.webp',
      ),
      HelpGuideStep(
        title: 'Gerar backup',
        description:
            'A aba Backup permite exportar a base e sincronizar o cache de mídia. Rode antes de mudanças estruturais — é a sua rede de segurança.',
        image: '${_img}admin-backup.webp',
      ),
      HelpGuideStep(
        title: 'Configurar a chave de IA',
        description:
            'A aba Chave de IA guarda a credencial usada pelo assistente e pela geração de questões do recrutamento. Sem ela, esses recursos ficam indisponíveis.',
        image: '${_shot}admin-rbac.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'rastreamento',
    title: 'Rastreamento de campo (GPS)',
    description: 'Localização da equipe externa com consumo controlado de bateria.',
    icon: Icons.location_on_rounded,
    color: Color(0xFFf97316),
    audience: _gestores,
    keywords:
        'gps localizacao rastreamento campo mapa rota bateria permissao background equipe externa',
    steps: [
      HelpGuideStep(
        title: 'Ativar no aparelho do colaborador',
        description:
            'No Android, conceda a permissão de localização como "Sempre permitir" e ative a chave de rastreamento em Configurações > Rastreamento. Sem a permissão contínua, o trajeto não é gravado em segundo plano.',
        image: '${_img}rastreamento-config.webp',
      ),
      HelpGuideStep(
        title: 'Entender o modo econômico',
        description:
            'Se o aparelho fica parado por mais de 5 minutos, o envio de coordenadas é suspenso e só volta quando há movimento detectado. É isso que evita drenar a bateria durante o expediente.',
        image: '${_img}rastreamento-config.webp',
      ),
      HelpGuideStep(
        title: 'Acompanhar no painel',
        description:
            'A aba Localização do Painel Admin mostra no mapa a posição da equipe, o trajeto das últimas horas, o nível de bateria e a velocidade de cada aparelho.',
        image: '${_img}admin-localizacao-lista.webp',
      ),
    ],
  ),

  // ───────────────────────────── Financeiro ─────────────────────────────
  HelpGuide(
    id: 'financeiro',
    title: 'Financeiro',
    description: 'Contas a pagar, a receber e fluxo de caixa em um só lugar.',
    icon: Icons.account_balance_wallet_rounded,
    color: Color(0xFF0ea5e9),
    audience: _gestores,
    route: '/finance/dashboard',
    moduleId: 'fin_dashboard',
    keywords:
        'financeiro contas a pagar receber fluxo de caixa saldo extrato conciliacao despesa cobranca inadimplencia',
    steps: [
      HelpGuideStep(
        title: 'Começar pela visão geral',
        description:
            'A Visão Geral Financeira reúne saldo, contas a pagar e a receber do período. É o painel que responde "como estamos hoje" antes de você entrar em cada fila.',
      ),
      HelpGuideStep(
        title: 'Lançar contas a pagar',
        description:
            'Em Contas a Pagar você registra despesas, boletos e pagamentos agendados, acompanhando o que vence nos próximos dias.',
      ),
      HelpGuideStep(
        title: 'Acompanhar contas a receber',
        description:
            'Em Contas a Receber ficam faturamentos e cobranças, com destaque para o que está em atraso.',
      ),
      HelpGuideStep(
        title: 'Conferir o fluxo de caixa',
        description:
            'O Fluxo de Caixa mostra o extrato de movimentações para conciliação com o banco, fechando o ciclo entre o que foi previsto e o que efetivamente entrou ou saiu.',
      ),
      HelpGuideStep(
        title: 'Conectar com a operação',
        description:
            'Solicitações financeiras que nascem no chat viram cards no canal de categoria Financeiro (ex.: Liberação Contas a Pagar), com responsável e prazo — e chegam ao financeiro já organizadas.',
        image: '${_shot}canal-builder.webp',
      ),
    ],
  ),

  // ──────────────────────── Meu espaço (self-service) ────────────────────────
  HelpGuide(
    id: 'meu-espaco',
    title: 'Meu espaço (autoatendimento)',
    description:
        'Seus documentos, ausências, ponto, holerites, onboarding e desempenho.',
    icon: Icons.badge_rounded,
    color: Color(0xFF94a3b8),
    audience: _todos,
    route: '/profile',
    keywords:
        'meu perfil meus documentos minhas ausencias meu ponto meus holerites meu onboarding meu desempenho autoatendimento',
    steps: [
      HelpGuideStep(
        title: 'Abrir Meu Perfil',
        description:
            'Em Configurações > Meu Perfil você confere filial de lotação, departamento, cargo e nível de acesso, e ajusta seus dados de exibição.',
        image: '${_shot}meu-perfil.webp',
      ),
      HelpGuideStep(
        title: 'Usar os atalhos de RH',
        description:
            'O bloco Recursos Humanos do perfil dá acesso direto a Meus Documentos, Meu Onboarding, Minhas Ausências e Férias, Meu Ponto, Meus Holerites e Meu Desempenho — tudo o que é seu, sem passar pelo RH.',
        image: '${_shot}meu-perfil.webp',
      ),
      HelpGuideStep(
        title: 'Pedir suporte',
        description:
            'O bloco Suporte T.I. no topo do perfil leva à Central de Ajuda e, para quem atende, ao Painel Helpdesk.',
        image: '${_shot}meu-perfil.webp',
      ),
      HelpGuideStep(
        title: 'Ver seu histórico de atividades',
        description:
            'Configurações > Meu Histórico lista suas ações recentes no aplicativo — útil para relembrar o que você fez e quando.',
        image: '${_shot}configuracoes.webp',
      ),
    ],
  ),
  HelpGuide(
    id: 'privacidade',
    title: 'Privacidade e seus dados',
    description:
        'Consulte as políticas, exporte seus dados e faça pedidos da LGPD.',
    icon: Icons.privacy_tip_rounded,
    color: Color(0xFF14b8a6),
    audience: _todos,
    route: '/privacidade',
    keywords:
        'privacidade lgpd exportar dados titular correcao eliminacao politica termos aceite',
    steps: [
      HelpGuideStep(
        title: 'Abrir a Central de Privacidade',
        description:
            'Em Configurações > Privacidade e Dados ficam os documentos legais, o histórico dos seus aceites, a exportação de dados e os pedidos do titular.',
      ),
      HelpGuideStep(
        title: 'Exportar seus dados',
        description:
            'Toque em Exportar meus dados agora. O app gera um arquivo JSON com os seus dados na plataforma para você guardar ou conferir.',
      ),
      HelpGuideStep(
        title: 'Fazer um pedido do titular',
        description:
            'Em Novo Pedido do Titular (LGPD), escolha Correção, Eliminação ou Informação sobre compartilhamento, descreva o pedido e envie. A empresa tem até 15 dias para responder.',
        tip: 'O pedido fica listado na Central com a data de abertura e o status.',
      ),
    ],
  ),
];
