/**
 * Script de Seed: Criacao de Canais de Teste para o AlinhaJa
 * Cria um canal de cada tipo de workflow com as etapas configuradas corretamente.
 * "Cancelado" e tratado como status independente (NAO e final).
 *
 * Credenciais vem SO do ambiente. O ref do projeto tambem: este script ja
 * apontou fixo para o projeto do outro fork e semeou no banco errado.
 *
 *   $env:SUPABASE_URL = "https://ffsspqscpdxlmxuaiytj.supabase.co"   # DEV
 *   # PROD: "https://gpeemngsxvqjflasdody.supabase.co"
 *   $env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
 */

const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!process.env.SUPABASE_URL || !SERVICE_KEY) {
  console.error(
    'Faltam variaveis de ambiente.\n' +
      '  SUPABASE_URL=<url do projeto>\n' +
      '  SUPABASE_SERVICE_ROLE_KEY=<chave service_role>\n' +
      'Nunca coloque a chave em arquivo versionado.',
  );
  process.exit(1);
}

// A base do REST e derivada da URL do projeto — nao repetir o /rest/v1 na env.
const SUPABASE_URL = `${process.env.SUPABASE_URL.replace(/\/+$/, '')}/rest/v1`;
const HEADERS = {
  'apikey': SERVICE_KEY,
  'Authorization': `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation',
};

// Délcio (super_admin) como criador
const CREATOR_ID = '00000000-0000-0000-0000-111111111111';

// Todos os users para adicionar como membros
const ALL_USERS = [
  '00000000-0000-0000-0000-111111111111', // Délcio
  '00000000-0000-0000-0000-222222222222', // Diretor
  '0ad5fc38-f7e3-4e23-9fe8-b01ddf87726e', // BC Direção
  '84067375-b94f-488d-87e9-f46a450f61ae', // BC Gestão
  '00000000-0000-0000-0000-333333333333', // Julio
];

const CHANNELS = [
  {
    name: 'Liberação Contas a Pagar',
    description: 'Canal para controle e aprovação de contas a pagar do departamento financeiro.',
    category: 'financeiro',
    card_type: 'conta_pagar',
    color: '#2E7D32',
    icon: 'payments_outlined',
    statuses: [
      { status: 'Novo',                  order: 1, color: '#3B82F6', icon: 'add_circle', is_final: false },
      { status: 'Em análise',            order: 2, color: '#F59E0B', icon: 'search',     is_final: false },
      { status: 'Aguardando aprovação',  order: 3, color: '#8B5CF6', icon: 'hourglass_empty', is_final: false },
      { status: 'Aprovado',              order: 4, color: '#10B981', icon: 'check_circle', is_final: false },
      { status: 'Rejeitado',             order: 5, color: '#EF4444', icon: 'error_outline', is_final: false },
      { status: 'Pago',                  order: 6, color: '#22C55E', icon: 'task_alt',   is_final: true },
      { status: 'Cancelado',             order: 7, color: '#EF4444', icon: 'cancel',     is_final: false },
    ],
  },
  {
    name: 'Liberação Fat. Moto',
    description: 'Canal para aprovação de faturamento de motocicletas.',
    category: 'operacional',
    card_type: 'fat_moto',
    color: '#7B1FA2',
    icon: 'two_wheeler',
    statuses: [
      { status: 'Solicitação criada',      order: 1, color: '#3B82F6', icon: 'add_circle',      is_final: false },
      { status: 'Em conferência',          order: 2, color: '#F59E0B', icon: 'search',           is_final: false },
      { status: 'Aguardando liberação',    order: 3, color: '#8B5CF6', icon: 'hourglass_empty',  is_final: false },
      { status: 'Liberado',                order: 4, color: '#10B981', icon: 'check_circle',     is_final: false },
      { status: 'Pendente de ajuste',      order: 5, color: '#F59E0B', icon: 'warning',          is_final: false },
      { status: 'Finalizado',              order: 6, color: '#22C55E', icon: 'task_alt',         is_final: true },
      { status: 'Cancelado',               order: 7, color: '#EF4444', icon: 'cancel',           is_final: false },
    ],
  },
  {
    name: 'Emplacamento',
    description: 'Canal para acompanhamento do processo de emplacamento de veículos.',
    category: 'operacional',
    card_type: 'emplacamento',
    color: '#1565C0',
    icon: 'directions_car_outlined',
    statuses: [
      { status: 'Solicitação aberta',         order: 1, color: '#3B82F6', icon: 'add_circle',      is_final: false },
      { status: 'Documentação em análise',    order: 2, color: '#F59E0B', icon: 'search',           is_final: false },
      { status: 'Aguardando pagamento/taxa',  order: 3, color: '#8B5CF6', icon: 'hourglass_empty',  is_final: false },
      { status: 'Em processamento',           order: 4, color: '#F97316', icon: 'sync',             is_final: false },
      { status: 'Emplacado',                  order: 5, color: '#22C55E', icon: 'task_alt',         is_final: true },
      { status: 'Pendência documental',       order: 6, color: '#F59E0B', icon: 'warning',          is_final: false },
      { status: 'Cancelado',                  order: 7, color: '#EF4444', icon: 'cancel',           is_final: false },
    ],
  },
  {
    name: 'Faturamento OS/Peças',
    description: 'Canal para controle de faturamento de ordens de serviço e peças.',
    category: 'faturamento',
    card_type: 'faturamento_os',
    color: '#E65100',
    icon: 'receipt_outlined',
    statuses: [
      { status: 'Aberto',                order: 1, color: '#3B82F6', icon: 'add_circle',      is_final: false },
      { status: 'Em análise',            order: 2, color: '#F59E0B', icon: 'search',           is_final: false },
      { status: 'Em faturamento',        order: 3, color: '#F97316', icon: 'sync',             is_final: false },
      { status: 'Aguardando correção',   order: 4, color: '#EF4444', icon: 'warning',          is_final: false },
      { status: 'Faturado',              order: 5, color: '#22C55E', icon: 'task_alt',         is_final: true },
      { status: 'Cancelado',             order: 6, color: '#EF4444', icon: 'cancel',           is_final: false },
    ],
  },
  {
    name: 'Avisos Gerais',
    description: 'Canal para comunicação de avisos e informativos gerais da empresa.',
    category: 'informativo',
    card_type: 'aviso',
    color: '#C62828',
    icon: 'campaign_outlined',
    statuses: [
      { status: 'Ativo',      order: 1, color: '#10B981', icon: 'circle',   is_final: false },
      { status: 'Arquivado',  order: 2, color: '#6B7280', icon: 'archive',  is_final: true },
    ],
  },
  {
    name: 'Canal Genérico de Teste',
    description: 'Canal genérico para testes gerais de workflow.',
    category: 'operacional',
    card_type: 'generic',
    color: '#616161',
    icon: 'workspaces_rounded',
    statuses: [
      { status: 'Novo',           order: 1, color: '#3B82F6', icon: 'add_circle',   is_final: false },
      { status: 'Em andamento',   order: 2, color: '#F59E0B', icon: 'sync',         is_final: false },
      { status: 'Concluído',      order: 3, color: '#22C55E', icon: 'task_alt',     is_final: true },
      { status: 'Cancelado',      order: 4, color: '#EF4444', icon: 'cancel',       is_final: false },
    ],
  },
];

async function apiPost(path, body) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    method: 'POST',
    headers: HEADERS,
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`POST ${path} failed (${res.status}): ${txt}`);
  }
  return res.json();
}

async function main() {
  console.log('🚀 Iniciando seed de canais de teste...\n');

  for (const ch of CHANNELS) {
    try {
      // 1. Criar o canal
      const [channel] = await apiPost('/chats', {
        type: 'channel',
        name: ch.name,
        description: ch.description,
        created_by: CREATOR_ID,
        metadata: {
          workspace: 'alinha_operations',
          workflow_enabled: true,
          card_type: ch.card_type,
          category: ch.category,
          color: ch.color,
          icon: ch.icon,
        },
      });
      const channelId = channel.id;
      console.log(`✅ Canal "${ch.name}" criado (${channelId})`);

      // 2. Adicionar membros
      const members = ALL_USERS.map(uid => ({
        chat_id: channelId,
        user_id: uid,
        role: uid === CREATOR_ID ? 'owner' : 'member',
      }));
      await apiPost('/chat_members', members);
      console.log(`   👥 ${members.length} membros adicionados`);

      // 3. Configurar workflow status
      const statusRows = ch.statuses.map(s => ({
        channel_id: channelId,
        status: s.status,
        status_order: s.order,
        color: s.color,
        icon: s.icon,
        is_final: s.is_final,
      }));
      await apiPost('/workflow_status_config', statusRows);
      console.log(`   🔧 ${statusRows.length} etapas configuradas`);
      console.log('');
    } catch (e) {
      console.error(`❌ Erro ao criar "${ch.name}": ${e.message}\n`);
    }
  }

  console.log('🎉 Seed completo!');
}

main().catch(console.error);
