import {
  BarChart3,
  Bell,
  Boxes,
  Briefcase,
  CalendarDays,
  CheckCircle,
  ClipboardList,
  Cpu,
  FileCheck2,
  Fingerprint,
  Gauge,
  GraduationCap,
  Headset,
  Kanban,
  Layers,
  Lock,
  Mail,
  MapPin,
  Megaphone,
  MessagesSquare,
  Route,
  ScrollText,
  Settings,
  Shield,
  ShieldCheck,
  Sparkles,
  Ticket,
  Timer,
  UserPlus,
  Users,
  Video,
  Wallet,
  Workflow,
  Zap,
} from 'lucide-react';

export type Shot = {
  src: string;
  title: string;
  desc: string;
};

export type Area = {
  id: string;
  label: string;
  color: string;
  icon: React.ReactNode;
  headline: string;
  summary: string;
  bullets: string[];
  shots: Shot[];
};

/** As 5 áreas do produto, cada uma com capturas reais do sistema. */
export const areas: Area[] = [
  {
    id: 'comunicacao',
    label: 'Comunicação',
    color: '#3b82f6',
    icon: <MessagesSquare size={16} />,
    headline: 'Comunicado oficial que você sabe quem leu',
    summary:
      'Canais por departamento, conversas diretas, chamadas de vídeo e avisos da diretoria com confirmação obrigatória de leitura.',
    bullets: [
      'Botão "Estou Ciente" com taxa de leitura',
      'Canais separados por área e categoria',
      'Chamadas e reuniões dentro do próprio chat',
    ],
    shots: [
      {
        src: '/shots/comunicados.webp',
        title: 'Comunicados com "Estou Ciente"',
        desc: 'Anúncios oficiais que exigem confirmação de leitura de cada colaborador.',
      },
      {
        src: '/shots/workspaces.webp',
        title: 'Espaços de trabalho',
        desc: 'Fluxos operacionais, OS e avisos organizados por departamento.',
      },
      {
        src: '/shots/conversas.webp',
        title: 'Conversas diretas',
        desc: 'Mensageria 1:1 e em grupo, com criptografia ponta a ponta.',
      },
      {
        src: '/shots/chamadas.webp',
        title: 'Chamadas e reuniões',
        desc: 'Histórico de chamadas, perdidas e reuniões agendadas por canal.',
      },
    ],
  },
  {
    id: 'operacao',
    label: 'Operação',
    color: '#f59e0b',
    icon: <Kanban size={16} />,
    headline: 'Cada demanda vira um card com dono e prazo',
    summary:
      'Monte o funil da sua operação sem código, acompanhe SLA por prioridade e centralize chamados internos de TI e manutenção.',
    bullets: [
      'Kanban Builder: crie as etapas do seu fluxo',
      'Helpdesk com conversa dedicada por chamado',
      'Categorias: financeiro, faturamento, operacional e RH',
    ],
    shots: [
      {
        src: '/shots/canal-builder.webp',
        title: 'Kanban Builder',
        desc: 'Crie o canal, escolha a categoria e monte as etapas do funil arrastando.',
      },
      {
        src: '/shots/helpdesk.webp',
        title: 'Gestão de helpdesk (TI)',
        desc: 'Chamados agrupados por status, com prioridade, categoria e responsável.',
      },
      {
        src: '/shots/helpdesk-ticket.webp',
        title: 'Chamado com conversa',
        desc: 'Cada ticket tem sua própria thread até a resolução.',
      },
      {
        src: '/shots/ajuda-central.webp',
        title: 'Central de ajuda',
        desc: 'Busca por termos operacionais, permissões e chamados abertos.',
      },
    ],
  },
  {
    id: 'rh',
    label: 'Pessoas & RH',
    color: '#10b981',
    icon: <Users size={16} />,
    headline: 'O RH inteiro dentro da mesma plataforma',
    summary:
      'Diretório de funcionários, documentos com vencimento, férias, ponto, holerites, benefícios, onboarding e ciclos de desempenho.',
    bullets: [
      'Alertas automáticos de ASO, CNH e experiência',
      'Calendário de férias e saldo por período aquisitivo',
      'Avaliação 360°: autoavaliação, gestor, pares',
    ],
    shots: [
      {
        src: '/shots/rh-funcionarios.webp',
        title: 'Diretório de funcionários',
        desc: 'Filial, departamento, cargo, matrícula, vínculo e status de cada pessoa.',
      },
      {
        src: '/shots/rh-documentos.webp',
        title: 'Documentos digitais',
        desc: 'ASO, CNH e certificados com controle de validade e ciência do funcionário.',
      },
      {
        src: '/shots/rh-ausencias.webp',
        title: 'Ausências e férias',
        desc: 'Calendário da equipe com férias, atestados, folgas e pendências de aprovação.',
      },
      {
        src: '/shots/rh-ponto.webp',
        title: 'Controle de ponto',
        desc: 'Registros por período e funcionário, com lançamento manual auditável.',
      },
      {
        src: '/shots/rh-holerites.webp',
        title: 'Holerites',
        desc: 'Emissão e distribuição digital com confirmação de visualização.',
      },
      {
        src: '/shots/rh-beneficios.webp',
        title: 'Benefícios',
        desc: 'Catálogo de benefícios e adesões por colaborador, com desconto em folha.',
      },
      {
        src: '/shots/rh-desempenho.webp',
        title: 'Ciclos de desempenho',
        desc: 'Ciclos 360° com autoavaliação, gestor, pares e subordinados.',
      },
      {
        src: '/shots/rh-avaliacoes.webp',
        title: 'Avaliações 1:1',
        desc: 'Notas e feedback registrados por gestor, com histórico por pessoa.',
      },
      {
        src: '/shots/rh-onboarding.webp',
        title: 'Templates de onboarding',
        desc: 'Checklists de integração padrão ou específicos por time.',
      },
    ],
  },
  {
    id: 'recrutamento',
    label: 'Recrutamento',
    color: '#a855f7',
    icon: <UserPlus size={16} />,
    headline: 'Da vaga publicada ao candidato contratado',
    summary:
      'Central de recrutamento com funil configurável, página de carreiras pública, banco de questões gerado por IA e retenção LGPD.',
    bullets: [
      'Página de carreiras com link e QR code',
      'Prova objetiva com questões geradas por IA',
      'Anonimização automática por período de retenção',
    ],
    shots: [
      {
        src: '/shots/recrut-visao-geral.webp',
        title: 'Visão geral do recrutamento',
        desc: 'Funil, conversão, candidatos por fonte e por nível em um só painel.',
      },
      {
        src: '/shots/recrut-pipeline.webp',
        title: 'Pipeline de candidatos',
        desc: 'Candidatos por etapa, com aderência, pretensão e origem.',
      },
      {
        src: '/shots/recrut-carreiras.webp',
        title: 'Página de carreiras',
        desc: 'Link público e QR code para divulgar vagas em qualquer canal.',
      },
      {
        src: '/shots/recrut-ia-questoes.webp',
        title: 'Questões com IA',
        desc: 'A IA gera a prova por cargo e nível — o gabarito nunca vai ao candidato.',
      },
      {
        src: '/shots/recrut-etapas.webp',
        title: 'Etapas do funil',
        desc: 'Renomeie, reordene e crie etapas do processo seletivo.',
      },
      {
        src: '/shots/recrut-catalogo.webp',
        title: 'Áreas e cargos',
        desc: 'Catálogo que alimenta vagas, filtros e o cadastro de funcionários.',
      },
    ],
  },
  {
    id: 'admin',
    label: 'Administração',
    color: '#06b6d4',
    icon: <ShieldCheck size={16} />,
    headline: 'Governança, permissões e rastreabilidade',
    summary:
      'Perfis de acesso granulares, auditoria de ações, moderação de conteúdo, relatórios de uso e automações de e-mail.',
    bullets: [
      'RBAC por módulo e por ação (ver / gerenciar)',
      'Auditoria, moderação e relatórios de uso',
      'SMTP próprio e regras de automação por etapa',
    ],
    shots: [
      {
        src: '/shots/admin-rbac.webp',
        title: 'Perfis e permissões (RBAC)',
        desc: 'Defina exatamente o que cada perfil pode ver e gerenciar em cada módulo.',
      },
      {
        src: '/shots/admin-usuarios.webp',
        title: 'Gestão de usuários',
        desc: 'Usuários, papéis e cargos hierárquicos em um painel único.',
      },
      {
        src: '/shots/admin-relatorios.webp',
        title: 'Relatórios de uso',
        desc: 'Usuários ativos, mensagens, chamadas e canais por período.',
      },
      {
        src: '/shots/admin-moderacao.webp',
        title: 'Moderação de conteúdo',
        desc: 'Advertir ou remover mensagens e canais fora da política.',
      },
      {
        src: '/shots/auto-smtp.webp',
        title: 'SMTP próprio',
        desc: 'Envie e-mails pelo domínio da empresa, com senha criptografada.',
      },
      {
        src: '/shots/auto-regras.webp',
        title: 'Regras de automação',
        desc: 'Mudou de etapa no funil? Dispara o template de e-mail configurado.',
      },
      {
        src: '/shots/configuracoes.webp',
        title: 'Configurações',
        desc: 'Tema, notificações, 2FA, gestão de equipe e rastreamento.',
      },
      {
        src: '/shots/meu-perfil.webp',
        title: 'Meu perfil',
        desc: 'Dados organizacionais e atalhos para documentos, ponto e holerites.',
      },
      {
        src: '/shots/ajuda-academia.webp',
        title: 'Academia interna',
        desc: 'Guias passo a passo e manuais de cada módulo do sistema.',
      },
      {
        src: '/shots/nav-modulos.webp',
        title: 'Todos os módulos',
        desc: 'Comunicação e Recursos Humanos acessíveis na mesma navegação.',
      },
    ],
  },
];

/** Números do topo — resumo honesto do que a plataforma entrega. */
export const heroStats = [
  { value: '5', label: 'áreas integradas' },
  { value: '20+', label: 'módulos' },
  { value: '1', label: 'login para tudo' },
];

/** Pilares — a promessa central da plataforma. */
export const pillars = [
  {
    icon: <Layers size={20} />,
    title: 'Conversa vira processo',
    desc: 'A mensagem não morre no chat: vira card com responsável, status e prazo.',
    color: '#3b82f6',
  },
  {
    icon: <Users size={20} />,
    title: 'RH de ponta a ponta',
    desc: 'Da vaga ao holerite, sem planilha paralela nem sistema separado.',
    color: '#10b981',
  },
  {
    icon: <Shield size={20} />,
    title: 'Governança real',
    desc: 'Permissão por módulo, auditoria de ações e retenção conforme a LGPD.',
    color: '#a855f7',
  },
  {
    icon: <Zap size={20} />,
    title: 'Configurável sem código',
    desc: 'Você monta os funis, as etapas, os cargos e as automações.',
    color: '#f59e0b',
  },
];

/** Grade de recursos — visão rápida do que existe dentro do app. */
export const features = [
  { icon: <Megaphone size={18} />, title: 'Comunicados', desc: 'Avisos oficiais com "Estou Ciente"', color: '#3b82f6' },
  { icon: <MessagesSquare size={18} />, title: 'Mensageria', desc: 'Canais, conversas e anexos', color: '#60a5fa' },
  { icon: <Video size={18} />, title: 'Videochamadas', desc: 'Chamadas 1:1 e reuniões', color: '#14b8a6' },
  { icon: <Workflow size={18} />, title: 'Kanban Builder', desc: 'Monte as etapas do seu fluxo', color: '#f59e0b' },
  { icon: <Gauge size={18} />, title: 'SLA', desc: 'Prazo e prioridade visíveis', color: '#fb923c' },
  { icon: <Ticket size={18} />, title: 'Helpdesk', desc: 'Chamados de TI e manutenção', color: '#eab308' },
  { icon: <Briefcase size={18} />, title: 'Funcionários', desc: 'Diretório com filial e cargo', color: '#10b981' },
  { icon: <FileCheck2 size={18} />, title: 'Documentos', desc: 'ASO, CNH e certificados', color: '#34d399' },
  { icon: <CalendarDays size={18} />, title: 'Férias', desc: 'Calendário e saldo aquisitivo', color: '#22c55e' },
  { icon: <Fingerprint size={18} />, title: 'Ponto', desc: 'Registros por período', color: '#4ade80' },
  { icon: <Wallet size={18} />, title: 'Holerites', desc: 'Entrega digital com ciência', color: '#84cc16' },
  { icon: <Boxes size={18} />, title: 'Benefícios', desc: 'Catálogo e adesões', color: '#a3e635' },
  { icon: <BarChart3 size={18} />, title: 'Desempenho', desc: 'Ciclos 360° e 1:1', color: '#06b6d4' },
  { icon: <ClipboardList size={18} />, title: 'Onboarding', desc: 'Checklists de integração', color: '#22d3ee' },
  { icon: <UserPlus size={18} />, title: 'Recrutamento', desc: 'Funil, vagas e candidatos', color: '#a855f7' },
  { icon: <Sparkles size={18} />, title: 'Provas com IA', desc: 'Questões geradas por cargo', color: '#c084fc' },
  { icon: <Bell size={18} />, title: 'Alertas RH', desc: 'Vencimentos e pendências', color: '#f472b6' },
  { icon: <Mail size={18} />, title: 'Automações', desc: 'E-mail por etapa do funil', color: '#ec4899' },
  { icon: <Lock size={18} />, title: 'RBAC', desc: 'Permissão por módulo e ação', color: '#6366f1' },
  { icon: <ScrollText size={18} />, title: 'Auditoria', desc: 'Histórico de ações', color: '#818cf8' },
  { icon: <MapPin size={18} />, title: 'Rastreamento', desc: 'GPS da equipe de campo', color: '#f97316' },
  { icon: <GraduationCap size={18} />, title: 'Academia', desc: 'Guias e manual interativo', color: '#0ea5e9' },
  { icon: <Cpu size={18} />, title: 'Assistente IA', desc: 'Suporte dentro do chat', color: '#8b5cf6' },
  { icon: <Settings size={18} />, title: 'Configurável', desc: 'Cargos, áreas e etapas', color: '#94a3b8' },
];

/** Passos do fluxo operacional. */
export const flowSteps = [
  {
    icon: <Megaphone size={16} />,
    title: 'Solicita',
    desc: 'Colaborador abre a demanda no canal certo',
    color: '#3b82f6',
  },
  {
    icon: <Route size={16} />,
    title: 'Anda no funil',
    desc: 'Card muda de etapa com responsável definido',
    color: '#f59e0b',
  },
  {
    icon: <Timer size={16} />,
    title: 'Cumpre o SLA',
    desc: 'Prioridade e prazo ficam visíveis para todos',
    color: '#a855f7',
  },
  {
    icon: <CheckCircle size={16} />,
    title: 'Fecha auditável',
    desc: 'Anexo final, histórico e registro permanente',
    color: '#10b981',
  },
];

/** Linhas do comparativo com um grupo de WhatsApp. */
export const comparisonRows: Array<[string, boolean]> = [
  ['Responsável definido por demanda', true],
  ['Status e SLA visíveis', true],
  ['Confirmação de leitura de comunicado', true],
  ['Documentos com controle de validade', true],
  ['Permissão por módulo e por ação', true],
  ['Histórico auditável de ações', true],
];

export const supportIcons = { Headset };
