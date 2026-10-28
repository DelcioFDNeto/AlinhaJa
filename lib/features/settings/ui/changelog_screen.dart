import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/constants.dart';

/// Tela de Novidades / Changelog.
///
/// Reúne as notas de patch, progresso de desenvolvimento e melhorias do
/// AlinhaJá em uma linha do tempo. As entradas são mantidas em [_releases]
/// (mais recente no topo) e alimentadas a partir do histórico do `CONTEXT.md`.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Novidades',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: ResponsiveWidthContainer(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Header(theme: theme),
            const SizedBox(height: 20),
            for (var i = 0; i < _releases.length; i++)
              _ReleaseCard(
                release: _releases[i],
                isLatest: i == 0,
                isLast: i == _releases.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Cabeçalho ──────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ThemeData theme;
  const _Header({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.14),
            theme.colorScheme.primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'O que há de novo',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Notas de patch, melhorias e progresso do desenvolvimento. '
                  'Versão atual: v${AppConstants.appVersion}.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cartão de Release ──────────────────────────────────────────

class _ReleaseCard extends StatelessWidget {
  final _Release release;
  final bool isLatest;
  final bool isLast;

  const _ReleaseCard({
    required this.release,
    required this.isLatest,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Trilho da timeline ──
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: isLatest
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // ── Conteúdo do release ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        release.version,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (isLatest)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ATUAL',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      Text(
                        release.date,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  if (release.summary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      release.summary!,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...release.changes.map((c) => _ChangeRow(change: c)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final _Change change;
  const _ChangeRow({required this.change});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = change.type.style(theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  change.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Modelo de dados ────────────────────────────────────────────

enum _ChangeType {
  feature,
  improvement,
  fix,
  security;

  /// Retorna (ícone, cor, rótulo) de acordo com o tema atual.
  (IconData, Color, String) style(ThemeData theme) {
    switch (this) {
      case _ChangeType.feature:
        return (Icons.rocket_launch, theme.colorScheme.primary, 'NOVO');
      case _ChangeType.improvement:
        return (Icons.trending_up, Colors.blue, 'MELHORIA');
      case _ChangeType.fix:
        return (Icons.build_circle, Colors.orange, 'CORREÇÃO');
      case _ChangeType.security:
        return (Icons.shield, Colors.teal, 'SEGURANÇA');
    }
  }
}

class _Change {
  final _ChangeType type;
  final String text;
  const _Change(this.type, this.text);
}

class _Release {
  final String version;
  final String date;
  final String? summary;
  final List<_Change> changes;

  const _Release({
    required this.version,
    required this.date,
    this.summary,
    required this.changes,
  });
}

// ─── Conteúdo (extraído do CONTEXT.md — mais recente no topo) ────

const List<_Release> _releases = [
  _Release(
    version: 'v1.3.10',
    date: '22/09/2026',
    summary:
        'Controle de acesso unificado por módulo no RH, mensagens de erro '
        'humanizadas, mídias de visualização única aprimoradas e otimizações '
        'de desempenho no banco e na web.',
    changes: [
      _Change(_ChangeType.security,
          'Controle de acesso por módulo no RH: Banco de Talentos, Funcionários, Onboarding, Documentos, Ponto e Holerites agora têm permissões independentes de visualização e gestão.'),
      _Change(_ChangeType.security,
          'Proteção hierárquica e integridade: administradores comuns não podem alterar ou desativar super administradores, e registros de ponto utilizam o relógio do servidor.'),
      _Change(_ChangeType.feature,
          'Mensagens de erro humanizadas: falhas de permissão, conexão ou validação de dados são apresentadas de forma clara e orientativa.'),
      _Change(_ChangeType.feature,
          'Mídias de visualização única (View-Once): novo componente visual e destruição segura com tolerância a falhas temporárias de rede.'),
      _Change(_ChangeType.fix,
          'Melhorias de desempenho e estabilidade: consultas de permissão otimizadas no banco de dados e resiliência na inicialização do Console Administrativo.'),
    ],
  ),
  _Release(
    version: 'v1.3.9',
    date: '16/09/2026',
    summary:
        'Notificações no estilo WhatsApp com resposta direta, auditoria geral '
        'de segurança e LGPD, revisão completa de canais e workspaces e uma '
        'Central de Ajuda bem mais completa.',
    changes: [
      _Change(_ChangeType.feature,
          'Notificações de conversa redesenhadas: foto de quem enviou, mensagens empilhadas por conversa, resumo "5 mensagens de 2 conversas" e destaque quando você é mencionado.'),
      _Change(_ChangeType.feature,
          'Responder e Marcar como lida direto na notificação, sem abrir o app — funciona com o app aberto, em segundo plano ou fechado. Se a resposta não puder ser enviada, a notificação avisa.'),
      _Change(_ChangeType.feature,
          'Botão "Ativar notificações" em Configurações → Notificações para o navegador e o iPhone. No iPhone o pedido de permissão só é aceito a partir de um toque, e o pedido automático era recusado em silêncio.'),
      _Change(_ChangeType.fix,
          'Tocar numa notificação com o app fechado agora abre a conversa, e abrir a conversa tira a notificação dela da bandeja.'),
      _Change(_ChangeType.fix,
          'Chamada em canal tocava mas não podia ser atendida. E uma chamada que chegava atrasada no celular deixa de tocar depois de 1 minuto.'),
      _Change(_ChangeType.fix,
          'No navegador, cada mensagem podia gerar duas notificações. Agora é uma por conversa, com a foto do remetente — e ela aparece também quando o app está aberto atrás de outra janela.'),
      _Change(_ChangeType.fix,
          'Card de workflow atribuído a você passou a tocar com som e a abrir o canal do card ao ser tocado.'),
      _Change(_ChangeType.security,
          'Auditoria geral de segurança: funções do banco que aceitavam a identidade informada pelo aplicativo passaram a validar o usuário da sessão, e ações de administrador ficam restritas à própria empresa.'),
      _Change(_ChangeType.security,
          'E-mails do portal de carreiras protegidos contra injeção de links, código da verificação em duas etapas gerado com sorteio criptográfico e chamadas protegidas contra toque falso em nome de outra pessoa.'),
      _Change(_ChangeType.security,
          'Workspaces: pedido de entrada só pode ser aprovado por quem administra aquele canal — antes, quem administrava qualquer canal conseguia aprovar a própria entrada em outro. Os ajustes do canal também deixaram de alterar operadores e arquivamento.'),
      _Change(_ChangeType.feature,
          'Sucessão no canal: o último administrador só sai depois de escolher quem assume a administração, e a pessoa escolhida é avisada. Antes o canal podia ficar sem ninguém para aprovar entradas ou gerir membros.'),
      _Change(_ChangeType.feature,
          'Recusas avisadas: quem tem o pedido de entrada num canal recusado recebe uma notificação, e o cadastro pendente recusado recebe um e-mail explicando o que fazer.'),
      _Change(_ChangeType.fix,
          'E-mails automáticos do recrutamento por mudança de etapa não eram disparados: o banco chamava um endereço inexistente da função de automações.'),
      _Change(_ChangeType.fix,
          'Sair da conta sem internet voltou a funcionar, e o logout agora apaga todas as mensagens guardadas no aparelho, inclusive a fila de envio offline.'),
      _Change(_ChangeType.fix,
          'Canais grandes: as mensagens mais recentes podiam faltar na tela, a contagem de mensagens por membro parava em 1000 e a galeria mostrava arquivos já apagados.'),
      _Change(_ChangeType.fix,
          'Ajustar uma opção do canal antes de a tela terminar de carregar apagava ícone, cor e categoria do workspace. Aprovar solicitação sem permissão mostrava sucesso falso, e excluir um canal podia apagar os anexos mesmo quando a exclusão falhava.'),
      _Change(_ChangeType.fix,
          'Quem abriu o card perdia o comentário ao tentar comentar depois da conclusão: o texto sumia sem aviso.'),
      _Change(_ChangeType.improvement,
          'Minha Operação ganhou atalho no menu ⋮ da tela inicial — a tela existia, mas nenhum menu levava até ela. A descoberta de canais também ficou mais rápida.'),
      _Change(_ChangeType.improvement,
          'Central de Ajuda mais completa: novos artigos e guias sobre notificações, recursos das mensagens, quadro branco, Minha Operação, privacidade e instalação do app, além de novas perguntas frequentes.'),
    ],
  ),
  _Release(
    version: 'v1.3.8',
    date: '03/09/2026',
    summary:
        'Auditoria geral de segurança, conformidade estrita com a LGPD, '
        'reforço na infraestrutura de envio de e-mails corporativos e '
        'otimização extrema de performance da landing page.',
    changes: [
      _Change(_ChangeType.security,
          'Proteção de dados pessoais e privacidade (LGPD): revogação de privilégios de leitura irrestrita da coluna de telefone. Telefone e CPF agora só são acessíveis pelo próprio usuário ou por administradores em consulta auditada.'),
      _Change(_ChangeType.security,
          'Barreira de segurança no primeiro login: contas provisionadas com credenciais temporárias agora são forçadas a cadastrar uma nova senha pessoal antes de acessar o aplicativo.'),
      _Change(_ChangeType.security,
          'Hardening do banco e isolamento multi-tenant: fechamento de políticas de acesso entre filiais, fortalecimento contra ataques de sequestro de path (search_path) e limpeza de fotos no armazenamento ao arquivar ou excluir usuários.'),
      _Change(_ChangeType.security,
          'Portal de Carreiras blindado: proteção contra ataques de força bruta com limitação de taxa de requisições (rate limiting), validação de senhas com alta entropia e expiração controlada de tokens de verificação.'),
      _Change(_ChangeType.feature,
          'Suporte avançado a servidores SMTP: integração flexível compatível com Gmail, SendGrid, Amazon SES e Office 365 com negociação dinâmica TLS e STARTTLS (portas 465 e 587), além de ferramenta de teste de conexão em tempo real.'),
      _Change(_ChangeType.fix,
          'Proteção contra perda de dados no perfil: adicionada guarda inteligente que impede que falhas transitórias de conexão sobrescrevam dados confidenciais com valores em branco ao salvar o perfil.'),
      _Change(_ChangeType.improvement,
          'Landing page ultrarrápida: substituição de filtros pesados de blur por gradientes radiais nativos acelerados por GPU, congelamento de animações em segundo plano no mobile e redução drástica no tempo de carregamento inicial.'),
    ],
  ),
  _Release(
    version: 'v1.3.7',
    date: '21/08/2026',
    summary:
        'Fechamento do perímetro dos workspaces, trilha de auditoria da '
        'operação, busca que enxerga canais e cards, e a tela "Minha operação" '
        'com tudo que está com você num lugar só.',
    changes: [
      _Change(_ChangeType.security,
          'Entrada em canal deixou de ser livre. Qualquer pessoa da empresa conseguia, por chamada direta à API, se inserir como membro de um canal e ler todo o histórico — mensagens, cards, comentários e anexos. A solicitação de entrada existia na tela, mas o servidor não a exigia. Agora a membresia só entra por convite de um administrador ou por solicitação aprovada.'),
      _Change(_ChangeType.feature,
          'Workspace privado: um canal marcado como privado deixa de aparecer para quem não é membro — nome, descrição e lista de participantes incluídos. A entrada passa a ser só por convite. Até aqui todo canal era visível para a empresa inteira, o que inviabilizava workspace de RH, jurídico ou diretoria.'),
      _Change(_ChangeType.security,
          'Canal somente-leitura passou a valer no servidor. Em canais de aviso, a trava de "somente admins publicam" existia apenas na interface: o compositor ficava escondido, mas uma chamada direta à API publicava normalmente.'),
      _Change(_ChangeType.security,
          'Histórico de card à prova de atalho: trocar o responsável ou arquivar um card não deixava registro nenhum, nem no uso normal do app. Agora toda alteração é gravada pelo próprio banco, por qualquer caminho. Entrada e saída de membro de canal também passaram a ser auditadas.'),
      _Change(_ChangeType.security,
          'Mudança de etapa com regra única: era possível mover um card direto pela API, pulando as validações de etapa configurada, de papel e da regra que impede o solicitante de operar o próprio pedido. Esse caminho foi fechado.'),
      _Change(_ChangeType.feature,
          'Minha operação: nova tela com os cards atribuídos a você em todos os workspaces, agrupados por atraso, hoje e próximos. Antes era preciso abrir cada quadro para saber o que estava na sua mão.'),
      _Change(_ChangeType.feature,
          'A busca passou a encontrar conteúdo de workspace. Mensagens de canal e cards de workflow ficavam de fora — só conversas e grupos eram pesquisados, sem qualquer aviso de que o resto não estava sendo procurado.'),
      _Change(_ChangeType.improvement,
          'Busca mais rápida: mensagens e cards ganharam índice próprio. Antes cada pesquisa varria as tabelas inteiras.'),
      _Change(_ChangeType.fix,
          'Card concluído com atraso parava de ficar vermelho. O aviso de prazo olhava só a data e ignorava a etapa, então um pedido entregue fora do prazo seguia marcado como atrasado para sempre no histórico.'),
      _Change(_ChangeType.improvement,
          'Conversa mais fluida com imagens: cada mensagem nova, reação ou indicador de digitação refazia consultas ao banco e ao disco para toda imagem na tela, que voltava a piscar o carregamento. As imagens agora ficam paradas e a conversa para de travar em canais movimentados.'),
      _Change(_ChangeType.improvement,
          'Fotos de perfil passaram a ser guardadas no aparelho e carregadas no tamanho em que aparecem. Antes eram rebaixadas a cada abertura do app e abertas em resolução cheia, consumindo memória à toa nas listas.'),
    ],
  ),
  _Release(
    version: 'v1.3.6',
    date: '20/08/2026',
    summary:
        'Anexos e manipulação no Quadro Branco, recibos nominais de entrega/leitura '
        'de mensagens e experiência guiada com estados vazios no RH.',
    changes: [
      _Change(_ChangeType.feature,
          'Anexos no Quadro Branco: adicione imagens da galeria, câmera ou arquivos direto na lousa. Use a nova ferramenta Mover para reposicionar e redimensionar elementos com replicação em tempo real.'),
      _Change(_ChangeType.feature,
          'Informações da Mensagem: pressione e segure qualquer mensagem para ver quem já leu, quem recebeu no aparelho e quem ainda está pendente de entrega.'),
      _Change(_ChangeType.improvement,
          'Guia visual no RH: 28 telas agora contam com estados vazios educativos com passo a passo prático para guiar o primeiro cadastro ou sugerir a limpeza de filtros.'),
      _Change(_ChangeType.security,
          'Privacidade de Mídia e Segurança Admin: bucket de arquivos do chat 100% privado com assinatura de URLs e trava estrita de permissões nas funções administrativas.'),
    ],
  ),
  _Release(
    version: 'v1.3.5',
    date: '13/08/2026',
    summary:
        'Espaços de trabalho maleáveis: presets que você mesmo cria e edita, '
        'funil ajustável depois de pronto, e o básico de comunicação que '
        'faltava — silenciar canal, @canal, editar e apagar mensagem.',
    changes: [
      _Change(_ChangeType.feature,
          'Presets de Workspace: os modelos de canal deixaram de ser fixos. Em Canais, o ícone de modelos abre a biblioteca onde você cria, edita, duplica e exclui seus próprios presets — com identidade, formulário do card, modo de atribuição e etapas prontos para reaproveitar.'),
      _Change(_ChangeType.feature,
          'Editar o Workspace depois de criado: antes só era possível trocar nome e descrição. Agora categoria, ícone, cor, permissão de publicação e, principalmente, as etapas do Kanban podem ser alteradas a qualquer momento pelo lápis na tela de informações do canal.'),
      _Change(_ChangeType.feature,
          'Remoção de etapa sem perder card: ao excluir uma etapa que ainda tem cards, o sistema pergunta para onde movê-los e registra a mudança no histórico de cada card. Nenhum card fica órfão.'),
      _Change(_ChangeType.improvement,
          'Etapas com significado próprio: marque qual etapa é a inicial, qual conclui e qual cancela. Antes o cancelamento era reconhecido pelo nome "Cancelado" — um funil com "Recusado" ou "Encerrado" saía do lugar no quadro e no SLA.'),
      _Change(_ChangeType.improvement,
          'Construtor de etapas mais completo: escolha ícone e cor de cada coluna, veja quantos cards existem em cada etapa e reordene arrastando.'),
      _Change(_ChangeType.feature,
          'Notificações por canal: escolha entre Todas as mensagens, Somente menções ou Silenciado. Fica no ícone de sino da barra do canal e em Informações → Minhas notificações. Até aqui só era possível silenciar conversas e grupos.'),
      _Change(_ChangeType.feature,
          'Menção ao canal: @canal e @aqui alcançam quem colocou o canal em "somente menções". A notificação de quem foi citado chega destacada.'),
      _Change(_ChangeType.feature,
          'Editar mensagem em canal: corrija o texto de uma mensagem sua — a bolha passa a exibir "editado". Anúncios e enquetes não são editáveis, porque carregam confirmações de leitura e votos.'),
      _Change(_ChangeType.fix,
          'Apagar mensagem em canal voltou a funcionar. A mensagem sumia da tela e reaparecia ao recarregar: a exclusão nunca chegava ao servidor. Quem administra o workspace também pode apagar mensagem de terceiro, para moderação.'),
      _Change(_ChangeType.feature,
          'Marcador de "Novas mensagens": uma régua indica onde a leitura parou ao reabrir um canal.'),
      _Change(_ChangeType.security,
          'Correção de escalonamento de privilégio: era possível, por manipulação direta da API, um membro comum promover a si próprio a administrador do workspace e passar a excluir o canal, arquivar e gerir membros. O privilégio de escrita foi restringido às colunas que o app realmente usa.'),
      _Change(_ChangeType.fix,
          'Encerrar reunião passou a valer para todos os cards. O encerramento gravava só parte da informação, e o card do convite podia continuar indicando reunião em andamento. Agora tudo é feito numa única operação e o app avisa se o encerramento falhar.'),
      _Change(_ChangeType.improvement,
          'Filtros de canal automáticos: a barra de categorias passa a mostrar apenas as categorias que têm workspace, incluindo as novas (RH, Comercial, TI).'),
    ],
  ),
  _Release(
    version: 'v1.3.4',
    date: '12/08/2026',
    summary:
        'Backup em nuvem cifrado de ponta a ponta, por conta e por dispositivo, '
        'com retenção automática, auditoria e correção de um vazamento na '
        'exportação antiga.',
    changes: [
      _Change(_ChangeType.feature,
          'Backup em Nuvem: nova tela em Privacidade e Dados → Backup e Restauração, com cópias por conta (tudo que é seu no servidor) ou por dispositivo (o histórico deste aparelho).'),
      _Change(_ChangeType.security,
          'Criptografia Ponta a Ponta: o backup é cifrado no seu aparelho com AES-256 e uma senha que só você conhece. O servidor guarda apenas o arquivo ilegível — nem a empresa, nem a TI, nem o suporte conseguem abri-lo. Sem a senha, o backup é irrecuperável.'),
      _Change(_ChangeType.security,
          'Correção de Vazamento na Exportação: a exportação anterior gerava um ZIP sem criptografia com TODO o histórico guardado no aparelho, inclusive conversas de outras contas que já haviam usado o mesmo dispositivo. O arquivo agora é cifrado e contém apenas os dados do titular logado.'),
      _Change(_ChangeType.feature,
          'Gestão de Dispositivos: veja de quais aparelhos vieram seus backups e revogue um deles — o que apaga, no mesmo ato, todas as cópias originadas dele. Indicado em caso de perda ou furto.'),
      _Change(_ChangeType.feature,
          'Backup Automático (opcional): uma vez por dia, apenas em Wi-Fi, com a senha guardada no cofre seguro do aparelho (Keychain no iOS, Keystore no Android). Desligado por padrão — nada é enviado sem sua ativação.'),
      _Change(_ChangeType.feature,
          'Restauração: recupere suas mensagens a partir de um backup na nuvem ou de um arquivo .fxb salvo por você, com verificação de integridade antes de abrir.'),
      _Change(_ChangeType.security,
          'Retenção e Descarte Automáticos: os backups expiram no prazo definido pela organização (90 dias por padrão) e são apagados por rotina diária, com o volume removido registrado como evidência de cumprimento (LGPD, arts. 15 e 16).'),
      _Change(_ChangeType.security,
          'Auditoria: criação, restauração, exclusão de backup e revogação de dispositivo passam a ser registradas no log imutável de auditoria (LGPD, art. 37).'),
      _Change(_ChangeType.security,
          'Limpeza ao Sair da Conta: o histórico local e o cache de mídia são apagados no logout, e o que restar de outra conta é descartado ao entrar no mesmo aparelho.'),
      _Change(_ChangeType.improvement,
          'Painel Administrativo: a aba Backup passa a mostrar cobertura da organização e política de retenção. Por desenho, ela não dá acesso ao conteúdo dos backups — o acesso corporativo a conversas continua sendo feito pela Moderação, com justificativa e registro.'),
    ],
  ),
  _Release(
    version: 'v1.3.3',
    date: '10/08/2026',
    summary:
        'Documentos LGPD preenchidos automaticamente com os dados de cada empresa, '
        'com captura no proprio cadastro do tenant, Quadro Branco Colaborativo '
        'em tempo real e correcoes de infraestrutura no banco.',
    changes: [
      _Change(_ChangeType.feature,
          'Dados Legais no Cadastro da Empresa: o Console de Plataforma passa a exigir razao social, CNPJ, endereco, Encarregado (DPO), e-mail do DPO e data de vigencia ao criar uma empresa.'),
      _Change(_ChangeType.feature,
          'Dados Legais da Empresa: nova aba no Painel Administrativo para consultar e ajustar esses dados depois, incluindo comarca e regiao de hospedagem.'),
      _Change(_ChangeType.feature,
          'Preenchimento Automatico dos Documentos: os Termos de Uso e a Politica de Privacidade passam a exibir os dados da empresa em atuacao no lugar dos campos entre colchetes, incluindo os prazos de retencao realmente configurados.'),
      _Change(_ChangeType.improvement,
          'Aviso de Documento Nao Personalizado: enquanto faltar dado cadastral, o leitor sinaliza quais campos faltam em vez de exibir um documento aparentemente completo.'),
      _Change(_ChangeType.feature,
          'Quadro Branco Colaborativo: desenho compartilhado em tempo real com caneta, borracha, paleta de cores e desfazer.'),
      _Change(_ChangeType.feature,
          'Permissoes de Anuncios Oficiais: controle granular de quem pode publicar anuncios em conversas e canais.'),
      _Change(_ChangeType.fix,
          'Estatisticas de Anuncio: corrigida a contagem de confirmacoes de ciencia em canais, que exibia zero e listava participantes como pendentes.'),
      _Change(_ChangeType.fix,
          'Cadastro de Usuarios sem Telefone: corrigida a falha ao criar o segundo usuario sem telefone informado.'),
      _Change(_ChangeType.fix,
          'Auditoria de Dados Pessoais: restaurado o registro de acesso a dados sensiveis no Painel Administrativo.'),
      _Change(_ChangeType.fix,
          'Troca de Empresa no Celular: os documentos legais passam a acompanhar a empresa em atuacao; antes mantinham em cache os dados da empresa anterior.'),
    ],
  ),
  _Release(
    version: 'v1.3.2',
    date: '07/08/2026',
    summary:
        'Ajustes de Infraestrutura e Interatividade: suporte a enquetes em canais, '
        'botão de mensagem direta (DM) nos cartões de contato e otimização dos recursos do chat.',
    changes: [
      _Change(_ChangeType.feature,
          'Mensagem Direta via Cartão de Contato: adição do botão "Mensagem" nos cartões de contato compartilhados para iniciar conversa 1:1 instantaneamente.'),
      _Change(_ChangeType.fix,
          'Enquetes em Canais: correção da integridade de chave estrangeira na tabela message_actions para suporte nativo a votação e resultados em canais.'),
      _Change(_ChangeType.improvement,
          'Limpeza e Simplificação do Chat: remoção do suporte a mensagens temporárias/efêmeras para simplificar o fluxo de comunicação corporativa.'),
      _Change(_ChangeType.improvement,
          'Assistente IA de Conversa: validação e auditoria das configurações do assistente (Groq/Llama 3.3 70B, RAG de contexto corporativo e comandos /limpar, /ping, /resumo e /ajuda).'),
    ],
  ),
  _Release(
    version: 'v1.3.1',
    date: '04/08/2026',
    summary:
        'Conformidade LGPD & Pacote Legal Completo: Central de Privacidade e Dados, '
        'exportação de dados em JSON, chamados de direitos do titular (Art. 18), '
        '13 documentos legais unificados e portão de aceite obrigatório.',
    changes: [
      _Change(_ChangeType.feature,
          'Central de Privacidade e Dados: novo portal acessível em Configurações → Privacidade e Dados para gestão completa da sua privacidade no app.'),
      _Change(_ChangeType.feature,
          'Portabilidade e Acesso (LGPD Art. 18): exportação direta em um clique de todos os seus dados pessoais, mensagens enviadas, localização e histórico em arquivo JSON.'),
      _Change(_ChangeType.feature,
          'Exercício de Direitos do Titular (Art. 18, VI): canal direto no app para abertura e acompanhamento de solicitações formais de eliminação, correção ou informação com prazo legal de resposta.'),
      _Change(_ChangeType.security,
          'Pacote Legal de 13 Documentos: Termos de Uso, Política de Privacidade, Monitoramento, Consentimento GPS, Aviso de Candidatos, Cookies, IA, Retenção, Incidentes, ROPA, Suboperadores e Termo de Aceite.'),
      _Change(_ChangeType.security,
          'Portão de Aceite Compulsório: registro eletrônico auditável via banco de dados Supabase com versão e timestamp em conformidade com a LGPD.'),
      _Change(_ChangeType.improvement,
          'Leitor Unificado de Documentos: navegação cruzada entre documentos em Markdown na Central de Privacidade e na Landing Page pública.'),
    ],
  ),
  _Release(
    version: 'v1.3.0',
    date: '30/07/2026',
    summary:
        'Atualização de Segurança e LGPD: gestão de consentimento GPS, mídias '
        'com bucket privado e assinaturas temporárias, recibos de leitura '
        'e entrega em tempo real. Chega também a Central de Ajuda completa, '
        'a introdução guiada para novos usuários e o console da plataforma.',
    changes: [
      _Change(_ChangeType.security,
          'Consentimento de GPS & LGPD: controle explícito pelo colaborador com aceite, revogação e eliminação do histórico (Art. 18). Painel admin no Dashboard de Rastreamento com aba e alertas de consentimento.'),
      _Change(_ChangeType.security,
          'Privacidade de Mídias (Bucket Privado): todas as fotos, vídeos, áudios e documentos trocados em chats e workflows agora usam URLs assinadas temporárias sob controle de permissão por membro do grupo.'),
      _Change(_ChangeType.feature,
          'Recibos de Entrega e Leitura (Checks): atualização em tempo real de confirmação de envio (✓), entrega (✓✓ cinza) e leitura (✓✓ azul) na lista de conversas e nas mensagens.'),
      _Change(_ChangeType.feature,
          'Visualização Única Aperfeiçoada: fotos e vídeos de visualização única agora têm purga física automática do servidor de arquivos imediatamente após a abertura.'),
      _Change(_ChangeType.security,
          'Sessão & Redação de PII: logout automático por inatividade (30 min), remoção de dados pessoais (CPF, e-mail, cartão) antes de enviar mensagens ao modelo de IA e moderação com registro de justificativa auditado.'),
      _Change(_ChangeType.feature,
          'Central de Ajuda: nova área com perguntas frequentes, guias passo a passo, manual completo do sistema e abertura de chamados para o suporte.'),
      _Change(_ChangeType.feature,
          'Introdução guiada: carrossel de boas-vindas e tour interativo pelas telas principais no primeiro acesso, com opção de rever o tutorial a qualquer momento pela Central de Ajuda.'),
      _Change(_ChangeType.feature,
          'Console da Plataforma: administração multi-empresa com troca de organização ativa para o proprietário da plataforma.'),
      _Change(_ChangeType.feature,
          'Mensagens e mídia: seleção múltipla de mensagens, encaminhamento, envio de mídia em lote com pré-visualização e tira de fotos recentes na barra de anexos.'),
      _Change(_ChangeType.improvement,
          'Interface & Navegação: reposicionamento do botão do Modo Foco e eliminação de tela preta ao fechar conversas em layouts adaptativos/desktop.'),
      _Change(_ChangeType.fix,
          'Respostas em canais: correção do vínculo entre responder a uma mensagem e o tópico (thread) em que ela está.'),
    ],
  ),
  _Release(
    version: 'v1.2.0',
    date: '15/07/2026',
    summary:
        'Central de Recrutamento completa, portal do candidato com login e '
        'nova suíte de Gestão de Pessoas: ausências, ponto, holerites, '
        'benefícios, desempenho e automações de e-mail.',
    changes: [
      _Change(_ChangeType.feature,
          'Central de Recrutamento: divulgação com link/QR da página de carreiras, vagas publicáveis, avaliação técnica com questões geradas por IA, dashboard de RH e pipeline com etapas customizáveis por empresa.'),
      _Change(_ChangeType.feature,
          'Portal do Candidato: crie uma conta com e-mail e senha e acompanhe todas as suas candidaturas em um só lugar, com verificação por e-mail.'),
      _Change(_ChangeType.feature,
          'Ausências e Férias: colaborador solicita pelo perfil; RH aprova ou rejeita em um painel dedicado.'),
      _Change(_ChangeType.feature,
          'Controle de Ponto: batidas pelo app (Meu Ponto), espelho por período para o RH, lançamentos manuais e aprovação de ajustes.'),
      _Change(_ChangeType.feature,
          'Holerites digitais: RH emite o PDF por competência; o colaborador abre pelo app e o RH acompanha o recibo de leitura.'),
      _Change(_ChangeType.feature,
          'Benefícios: catálogo da empresa (saúde, VA/VR, VT...) e adesões por funcionário com desconto em folha criptografado.'),
      _Change(_ChangeType.feature,
          'Avaliações de desempenho: ciclos 1:1, experiência, anual e 360 com pontuação e feedback.'),
      _Change(_ChangeType.feature,
          'Automações de e-mail no recrutamento: templates da empresa + regras "ao mover para etapa X, enviar e-mail Y", com servidor SMTP próprio opcional.'),
      _Change(_ChangeType.feature,
          'Ficha do funcionário: histórico de cargos e salários (criptografado e auditado) e cadastro de dependentes.'),
      _Change(_ChangeType.security,
          'Blindagem multi-tenant e de credenciais: senha SMTP criptografada com chave por empresa no Vault e nunca exibida; isolamento por organização reforçado em todos os módulos novos.'),
    ],
  ),
  _Release(
    version: 'v1.1.0',
    date: '10/07/2026',
    summary:
        'Grande atualização com Inteligência Artificial no RH e no chat, '
        'módulos completos de Recursos Humanos e base white-label.',
    changes: [
      _Change(_ChangeType.feature,
          'Assistente IA: novo contato inteligente na lista de conversas. Fale com ele em DMs ou adicione a grupos (mencionando @assistente) para tirar dúvidas de RH, TI e processos.'),
      _Change(_ChangeType.feature,
          'IA multi-provedor no RH (BYOK): cada empresa usa a própria chave — Anthropic (Claude), OpenAI (GPT), Google (Gemini) ou Groq (Llama) — para extração automática de currículos e documentos.'),
      _Change(_ChangeType.feature,
          'Módulos de RH: banco de talentos, portal de carreiras, área do candidato, gestão de funcionários, onboarding, alertas e documentos com aprovação/rejeição.'),
      _Change(_ChangeType.feature,
          'Gerenciamento de Acessos (RBAC): perfis customizados por empresa (Super Admin, RH, Gestor, Colaborador) com permissões por módulo, editáveis no Painel Admin.'),
      _Change(_ChangeType.improvement,
          'Assistente IA mais preciso: contexto de negócios do app, identificação do usuário pelo nome e 5 regras anti-alucinação (sem inventar leis, datas ou links).'),
      _Change(_ChangeType.improvement,
          'Design System de status (base white-label): cores de status agora vêm do tema, permitindo personalização visual por empresa sem alterar telas.'),
      _Change(_ChangeType.improvement,
          'Desempenho do RH: contagem de funcionários por status resolvida em uma única consulta.'),
      _Change(_ChangeType.security,
          'LGPD no RH: retenção configurável por empresa, anonimização e direito ao esquecimento com job diário automático de expiração.'),
    ],
  ),
  _Release(
    version: 'v1.0.11',
    date: '09/07/2026',
    summary:
        'Refinamentos de comunicação no chat e polimento de interface.',
    changes: [
      _Change(_ChangeType.feature,
          'Busca de mensagens dentro das conversas por termo.'),
      _Change(_ChangeType.feature,
          'Silenciar e sair de conversas de ponta a ponta.'),
      _Change(_ChangeType.improvement,
          'Scrollbars responsivas, novos empty-states e diversos ajustes de UX no chat.'),
      _Change(_ChangeType.fix,
          'Ícones do Material que sumiam na versão Web (codepoint alto) foram corrigidos.'),
    ],
  ),
  _Release(
    version: 'v1.0.9',
    date: '09/06/2026',
    summary:
        'Estabilidade de chamadas, controle de canais e atualização forçada de versão.',
    changes: [
      _Change(_ChangeType.feature,
          'Central de Ajuda e Suporte T.I. (Helpdesk) com abertura de tickets em tempo real.'),
      _Change(_ChangeType.feature,
          'Controle de entrada em canais com aprovação de solicitações e notificação instantânea.'),
      _Change(_ChangeType.feature,
          'Atualização de versão forçada: clientes desatualizados são avisados e atualizados automaticamente.'),
      _Change(_ChangeType.improvement,
          'Ringtone e notificações nativas de chamada na Web mesmo com o navegador em segundo plano.'),
      _Change(_ChangeType.fix,
          'Correção de travamento no encerramento de chamadas WebRTC e da tela preta ao excluir canais.'),
      _Change(_ChangeType.security,
          'Bloqueio de acesso a conteúdo com a tela do Android bloqueada.'),
    ],
  ),
  _Release(
    version: 'v1.0.4',
    date: '22/05/2026',
    summary: 'Base do produto: rebranding e fundação da plataforma.',
    changes: [
      _Change(_ChangeType.feature,
          'Chat corporativo (DMs, grupos e canais), workflow/Service Desk estilo Kanban e videochamadas 1:1 e em grupo.'),
      _Change(_ChangeType.feature,
          'Rastreamento de localização por GPS e "Estou Ciente" em comunicados de canais.'),
      _Change(_ChangeType.improvement,
          'Rebranding completo e nova infraestrutura de hospedagem.'),
    ],
  ),
];
