// deno-lint-ignore-file no-explicit-any
// ============================================================
// rh-candidatura — backend do Portal do Candidato (RH-2)
// Toda interação anônima do portal passa por aqui (service role);
// nenhuma policy `anon` existe nas tabelas (S042–S054).
//
// Ações (POST JSON { action, ... }):
//   org     { slug }                          → dados públicos da empresa
//   apply   { slug, dados..., cv_base64 }     → candidatura + e-mail
//   status  { token }                         → status + mensagens
//   message { token, texto }                  → candidato envia mensagem
//   upload  { token, base64, nome }           → documento adicional
//
// Secrets: servidor de e-mail (ver _shared/mailer.ts), opcional SENDER_NAME,
//   APP_BASE_URL (link da área do candidato),
//   DEV_EMAIL_OVERRIDE (S021 — em DEV, todo e-mail vai para este endereço).
// ============================================================
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { APP_BASE_URL, APP_NAME, APP_TAGLINE, EMAIL_LOGO_URL } from '../_shared/brand.ts';
import { escapeHtml } from '../_shared/html.ts';
import { platformSmtp, resolveSmtp, sendMail, SMTP_NOT_CONFIGURED } from '../_shared/mailer.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MAX_CV_BYTES = 5 * 1024 * 1024; // S047
const MAX_DOC_BYTES = 10 * 1024 * 1024; // S014
const RATE_LIMIT_PER_HOUR = 10; // S052

// Módulo licenciável que habilita o Portal de Carreiras. Empresas que não o
// contrataram (organizations.settings.modules) não têm página pública: tanto
// `org` quanto `apply` respondem 404, coerente com o gate multi-tenant.
const MODULE_BANCO_TALENTOS = 'rh_banco_talentos';

/// Empresa contratou o módulo? Lê organizations.settings.modules (array de ids).
function orgHasModule(org: any, moduleId: string): boolean {
  const mods = org?.settings?.modules;
  return Array.isArray(mods) && mods.includes(moduleId);
}

/// Extrai o IP real do cliente a partir de proxies confiáveis de borda (Achado 03 - LGPD Art. 8º).
/// Evita confiar no primeiro elemento de x-forwarded-for enviado pelo próprio cliente.
function getClientIp(req: Request): string {
  const cfIp = req.headers.get('cf-connecting-ip')?.trim();
  if (cfIp) return cfIp;

  const realIp = req.headers.get('x-real-ip')?.trim();
  if (realIp) return realIp;

  const xff = req.headers.get('x-forwarded-for');
  if (xff) {
    const parts = xff.split(',').map((p) => p.trim()).filter(Boolean);
    if (parts.length > 0) {
      return parts[parts.length - 1];
    }
  }

  return 'unknown';
}

/// Checa e registra rate limit contra rh_portal_rate_limit por IP e ação (Achado 02).
async function checkRateLimit(
  supabase: any,
  ip: string,
  acao: string,
  maxAttempts: number,
  windowMs: number
): Promise<{ allowed: boolean; retryAfterMin: number }> {
  if (ip === 'unknown') {
    return { allowed: true, retryAfterMin: 0 };
  }

  const windowStart = new Date(Date.now() - windowMs).toISOString();
  const { count } = await supabase
    .from('rh_portal_rate_limit')
    .select('id', { count: 'exact', head: true })
    .eq('ip', ip)
    .eq('acao', acao)
    .gte('created_at', windowStart);

  if ((count ?? 0) >= maxAttempts) {
    return { allowed: false, retryAfterMin: Math.ceil(windowMs / 60000) };
  }

  await supabase.from('rh_portal_rate_limit').insert({ ip, acao });
  supabase.rpc('fn_rh_rate_limit_cleanup').then(() => {}, () => {});
  return { allowed: true, retryAfterMin: 0 };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const body = await req.json();
    const action = body?.action as string;
    const ip = getClientIp(req);
    const userAgent = req.headers.get('user-agent') ?? '';

    switch (action) {
      case 'org':
        return await handleOrg(supabase, body);
      case 'apply':
        return await handleApply(supabase, body, ip, userAgent, req);
      case 'status':
        return await handleStatus(supabase, body);
      case 'message':
        return await handleMessage(supabase, body);
      case 'upload':
        return await handleUpload(supabase, body);
      case 'avaliacao_iniciar':
        return await handleAvaliacaoIniciar(supabase, body);
      case 'avaliacao_enviar':
        return await handleAvaliacaoEnviar(supabase, body);
      case 'auth_signup':
        return await handleAuthSignup(supabase, body, ip);
      case 'auth_verify':
        return await handleAuthVerify(supabase, body);
      case 'auth_login':
        return await handleAuthLogin(supabase, body, ip);
      case 'api_me':
        return await handleApiMe(supabase, req);
      default:
        return json({ error: 'Ação inválida' }, 400);
    }
  } catch (error: any) {
    console.error('[rh-candidatura] Unexpected error:', error);
    return json({ error: 'Erro interno. Tente novamente.' }, 500);
  }
});

// ── org: dados públicos da empresa (S043/S044) ────────────────
async function handleOrg(supabase: any, body: any) {
  const slug = String(body?.slug ?? '').toLowerCase();
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    return json({ error: 'Página não encontrada' }, 404);
  }
  const { data: org } = await supabase
    .from('organizations')
    .select('id, name, logo_url, settings, carreiras_ativo, carreiras_headline, carreiras_sobre')
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle();
  // Empresa inexistente/inativa OU sem o módulo de carreiras → 404 (não revela
  // que a empresa existe mas não contratou o módulo).
  if (!org || !orgHasModule(org, MODULE_BANCO_TALENTOS)) {
    return json({ error: 'Página não encontrada' }, 404);
  }

  // Vagas abertas e não expiradas (RH-10/Fase 2) — apenas campos públicos.
  const today = new Date().toISOString().split('T')[0];
  const { data: vagas } = await supabase
    .from('vaga')
    .select(
      'id, titulo, nivel, tipo_contrato, localidade, remoto, faixa_salarial, descricao, requisitos, publicada_em',
    )
    .eq('organization_id', org.id)
    .eq('status', 'aberta')
    .is('deleted_at', null)
    .or(`expira_em.is.null,expira_em.gte.${today}`)
    .order('publicada_em', { ascending: false });

  // Catálogo de áreas/cargos da empresa (RH-9) — vira sugestão nos campos
  // do formulário. Só o nome sai daqui: id interno não interessa à página
  // pública e o vínculo é resolvido server-side no apply.
  const [{ data: areas }, { data: cargos }] = await Promise.all([
    supabase.from('rh_area').select('nome')
      .eq('organization_id', org.id).eq('ativo', true).order('nome'),
    supabase.from('rh_cargo').select('nome')
      .eq('organization_id', org.id).eq('ativo', true).order('nome'),
  ]);

  // Só dados pensados para a página pública — nada interno (S044/S053).
  // carreiras_* (F1.1) deixam o RH pausar a página e editar a mini-landing.
  return json({
    name: org.name,
    logo_url: org.logo_url,
    carreiras_ativo: org.carreiras_ativo !== false,
    carreiras_headline: org.carreiras_headline ?? null,
    carreiras_sobre: org.carreiras_sobre ?? null,
    vagas: vagas ?? [],
    areas: (areas ?? []).map((a: any) => a.nome),
    cargos: (cargos ?? []).map((c: any) => c.nome),
  });
}

// ── apply: candidatura pública (S045–S054) ────────────────────
async function handleApply(supabase: any, body: any, ip: string, userAgent: string, req?: Request) {
  const slug = String(body?.slug ?? '').toLowerCase();
  const { data: org } = await supabase
    .from('organizations')
    .select('id, name, settings, carreiras_ativo')
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle();
  // Mesmo gate do `org`: sem o módulo contratado, o intake é recusado como 404
  // (defesa server-side mesmo se alguém postar direto na Edge Function).
  if (!org || !orgHasModule(org, MODULE_BANCO_TALENTOS)) {
    return json({ error: 'Página não encontrada' }, 404);
  }
  // Página pausada pelo RH (F1.1): recusa novas candidaturas com
  // mensagem amigável — defesa server-side além do aviso na UI.
  if (org.carreiras_ativo === false) {
    return json({
      error: 'As inscrições estão temporariamente pausadas. Volte em breve!',
    }, 403);
  }

  // Rate limiting: máx. 10 tentativas por IP por hora (S052)
  const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await supabase
    .from('rh_portal_rate_limit')
    .select('id', { count: 'exact', head: true })
    .eq('ip', ip)
    .gte('created_at', oneHourAgo);
  if ((count ?? 0) >= RATE_LIMIT_PER_HOUR) {
    return json({ error: 'Muitas tentativas. Tente novamente em 1 hora.' }, 429);
  }
  await supabase.from('rh_portal_rate_limit').insert({ ip, acao: 'apply' });
  supabase.rpc('fn_rh_rate_limit_cleanup').then(() => {}, () => {});

  // Validações (S045)
  const nome = String(body?.nome ?? '').trim();
  const email = String(body?.email ?? '').trim().toLowerCase();
  if (nome.length < 3) return json({ error: 'Informe seu nome completo.' }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ error: 'E-mail inválido.' }, 400);
  }
  if (body?.consentimento_lgpd !== true) {
    return json({ error: 'É necessário aceitar a política de privacidade (LGPD).' }, 400);
  }

  // Candidato logado (RH-16): vincula a candidatura à conta e habilita o
  // reaproveitamento do currículo já enviado antes.
  const authUserId = await candidatoUsuarioIdFromRequest(supabase, req);

  // Currículo: ou vem anexado agora, ou é reaproveitado da última
  // candidatura da conta (Fase 7 — reuso de currículo).
  const querReusar = body?.reusar_cv === true;
  let cvBytes: Uint8Array | null = null;
  let tipo: string | null = null;
  let cvOrigem:
    { arquivo_url: string; tipo_arquivo: string; tamanho_bytes: number } | null =
      null;

  if (querReusar) {
    if (!authUserId) {
      return json({
        error: 'Entre na sua conta para reaproveitar o currículo.',
      }, 401);
    }
    cvOrigem = await ultimoCurriculoDoUsuario(supabase, authUserId);
    if (!cvOrigem) {
      return json({
        error: 'Não encontramos um currículo anterior. Anexe o arquivo.',
      }, 400);
    }
    tipo = cvOrigem.tipo_arquivo;
  } else {
    // Currículo obrigatório no portal: valida tamanho e MIME real (S046/S047)
    const cvB64 = String(body?.cv_base64 ?? '');
    if (!cvB64) return json({ error: 'Anexe seu currículo (PDF ou DOCX).' }, 400);
    cvBytes = base64ToBytes(cvB64);
    if (cvBytes.length > MAX_CV_BYTES) {
      return json({ error: 'O currículo deve ter no máximo 5MB.' }, 400);
    }
    tipo = sniffFileType(cvBytes);
    if (tipo !== 'pdf' && tipo !== 'docx') {
      return json({ error: 'Formato inválido — envie PDF ou DOCX.' }, 400);
    }
  }

  // Candidatura vinculada a vaga (RH-10): valida que a vaga é da org,
  // está aberta e não expirou. Espontânea segue com vaga_id null.
  let vagaId: string | null = null;
  if (body?.vaga_id) {
    const vagaIdRaw = String(body.vaga_id);
    if (!/^[0-9a-f-]{36}$/.test(vagaIdRaw)) {
      return json({ error: 'Vaga inválida.' }, 400);
    }
    const { data: vaga } = await supabase
      .from('vaga')
      .select('id, status, expira_em')
      .eq('id', vagaIdRaw)
      .eq('organization_id', org.id)
      .is('deleted_at', null)
      .maybeSingle();
    const expirada = vaga?.expira_em &&
      new Date(vaga.expira_em) < new Date(new Date().toISOString().split('T')[0]);
    if (!vaga || vaga.status !== 'aberta' || expirada) {
      return json({
        error: 'Esta vaga não está mais disponível. ' +
          'Você ainda pode se cadastrar no banco de talentos.',
      }, 410);
    }
    vagaId = vaga.id;
  }

  // Duplicidade por organização (S035)
  const { data: existing } = await supabase
    .from('candidato')
    .select('id')
    .eq('organization_id', org.id)
    .ilike('email', email)
    .is('deleted_at', null)
    .maybeSingle();
  if (existing) {
    return json({
      error: 'Já recebemos uma candidatura com este e-mail nesta empresa.',
    }, 409);
  }

  // Área/cargo: o texto digitado é preservado como veio, e em paralelo
  // tentamos casá-lo com o catálogo da empresa (RH-9) para preencher as
  // FKs. Elas alimentam filtros, dashboard e o sorteio de questões da
  // avaliação técnica — sem isso, quem se candidata pelo portal fica
  // invisível para tudo que consulta area_id/cargo_id.
  const areaTexto = strOrNull(body?.area_interesse);
  const cargoTexto = strOrNull(body?.cargo_pretendido);
  const [areaId, cargoId] = await Promise.all([
    resolveCatalogo(supabase, 'rh_area', org.id, areaTexto),
    resolveCatalogo(supabase, 'rh_cargo', org.id, cargoTexto),
  ]);

  // Insere candidato (token do portal é gerado pelo banco, expira em 90 dias — S048)
  const { data: candidato, error: insertError } = await supabase
    .from('candidato')
    .insert({
      organization_id: org.id,
      nome,
      email,
      telefone: strOrNull(body?.telefone),
      cidade: strOrNull(body?.cidade),
      estado: strOrNull(body?.estado)?.toUpperCase()?.slice(0, 2),
      area_interesse: areaTexto,
      cargo_pretendido: cargoTexto,
      area_id: areaId,
      cargo_id: cargoId,
      nivel: strOrNull(body?.nivel),
      disponibilidade: strOrNull(body?.disponibilidade),
      pretensao_salarial: body?.pretensao_salarial ?? null,
      vaga_id: vagaId,
      fonte: 'portal',
      consentimento_lgpd: true,
      consentimento_versao: 'v1',
      consentimento_ip: ip,          // S054
      consentimento_user_agent: userAgent,
      candidato_usuario_id: authUserId,
    })
    .select('id, portal_token')
    .single();
  if (insertError) {
    console.error('[apply] insert error:', insertError);
    return json({ error: 'Não foi possível registrar a candidatura.' }, 500);
  }

  // Currículo: cada candidatura fica com a própria cópia do arquivo, mesmo
  // quando reaproveitado — a retenção da LGPD apaga por candidato, então
  // compartilhar o objeto derrubaria o currículo das outras candidaturas.
  const path = `${candidato.id}/${Date.now()}.${tipo}`;
  const contentType = tipo === 'pdf'
    ? 'application/pdf'
    : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  let cvFalhou = false;
  // candidato_curriculo.tamanho_bytes é NOT NULL: no reuso, herda o tamanho
  // do registro de origem.
  let cvTamanho = 0;

  if (cvOrigem) {
    const { error: copyError } = await supabase.storage
      .from('rh-curriculos')
      .copy(cvOrigem.arquivo_url, path);
    if (copyError) {
      console.error('[apply] copy error:', copyError);
      cvFalhou = true;
    } else {
      cvTamanho = cvOrigem.tamanho_bytes;
    }
  } else {
    const { error: uploadError } = await supabase.storage
      .from('rh-curriculos')
      .upload(path, cvBytes!, { contentType });
    if (uploadError) {
      console.error('[apply] upload error:', uploadError);
      cvFalhou = true;
    } else {
      cvTamanho = cvBytes!.length;
    }
  }

  if (!cvFalhou) {
    await supabase.from('candidato_curriculo').insert({
      candidato_id: candidato.id,
      arquivo_url: path,
      tipo_arquivo: tipo,
      tamanho_bytes: cvTamanho,
    });
  }

  await supabase.from('candidato_historico').insert({
    candidato_id: candidato.id,
    acao: 'cadastro',
    detalhes: {
      fonte: 'portal',
      ip,
      ...(vagaId ? { vaga_id: vagaId } : {}),
      ...(cvOrigem ? { curriculo_reaproveitado: true } : {}),
    },
  });

  // E-mail de confirmação com link da área do candidato (RH-2.6/S049)
  let emailEnviado = false;
  try {
    await sendConfirmationEmail(email, nome, org.name, candidato.portal_token, org.id);
    emailEnviado = true;
  } catch (e) {
    // Falha de e-mail não invalida a candidatura — mas o cliente precisa
    // saber, senão o candidato fica esperando um e-mail que não vem.
    console.error('[apply] email error:', e);
  }

  // O token vai na resposta para que a tela de confirmação leve o
  // candidato direto à área dele. Sem isso, o e-mail é o ÚNICO caminho
  // de entrada — e em DEV o e-mail vai para DEV_EMAIL_OVERRIDE (S021),
  // ou seja, o candidato nunca chega ao próprio acompanhamento.
  return json({
    success: true,
    token: candidato.portal_token,
    email_enviado: emailEnviado,
  });
}

// ── status: área do candidato (RH-2.7) ────────────────────────
async function handleStatus(supabase: any, body: any) {
  const found = await candidateByToken(supabase, body?.token);
  if ('response' in found) return found.response;
  const c = found.candidato;

  const { data: mensagens } = await supabase
    .from('candidato_mensagem')
    .select('autor, texto, anexo_url, anexo_nome, created_at')
    .eq('candidato_id', c.id)
    .order('created_at');

  // URLs assinadas de 15 min para anexos (S102)
  const withUrls = [];
  for (const m of mensagens ?? []) {
    let anexo_link = null;
    if (m.anexo_url) {
      const { data } = await supabase.storage
        .from('rh-documentos')
        .createSignedUrl(m.anexo_url, 900);
      anexo_link = data?.signedUrl ?? null;
    }
    withUrls.push({ ...m, anexo_url: undefined, anexo_link });
  }

  // Etapas do funil da org (RH-14) — permite ao portal exibir a linha
  // do tempo com as etapas customizadas. Vazio = app usa o funil padrão.
  const { data: etapas } = await supabase
    .from('pipeline_etapa')
    .select('slug, nome, ordem, tipo')
    .eq('organization_id', c.organization_id)
    .order('ordem');

  // Contexto da candidatura: para qual empresa e, se houver, para qual vaga.
  // Sem isso o candidato que se inscreveu em várias empresas abre o link e
  // não sabe de qual processo está vendo o andamento.
  const [{ data: org }, vaga] = await Promise.all([
    supabase.from('organizations').select('name, logo_url')
      .eq('id', c.organization_id).maybeSingle(),
    c.vaga_id
      ? supabase.from('vaga').select('titulo').eq('id', c.vaga_id).maybeSingle()
        .then((r: any) => r.data)
      : Promise.resolve(null),
  ]);

  return json({
    nome: c.nome,
    status: c.status,
    criado_em: c.created_at,
    mensagens: withUrls,
    pipeline: etapas ?? [],
    empresa: org?.name ?? null,
    empresa_logo: org?.logo_url ?? null,
    vaga_titulo: vaga?.titulo ?? null,
    // Estado da prova resolvido AQUI, não no clique. Oferecer "Iniciar
    // avaliação" e só então descobrir que a empresa não tem banco de
    // questões é um beco sem saída — o candidato clica e leva um "não".
    avaliacao: await avaliacaoResumo(supabase, c),
  });
}

/// Situação da avaliação técnica do candidato, sem criar nada.
///
/// Espelha as decisões de handleAvaliacaoIniciar (prova encerrada, prova em
/// andamento, pool vazio) para que a tela já abra no estado certo. É só
/// leitura: quem cria a linha `avaliacao` continua sendo o iniciar.
async function avaliacaoResumo(supabase: any, c: any) {
  const { data: cand } = await supabase
    .from('candidato')
    .select('id, organization_id, cargo_id, nivel')
    .eq('id', c.id)
    .single();

  // Encerrada (enviada ou expirada): mostra o resultado, sem botão.
  const { data: feita } = await supabase
    .from('avaliacao')
    .select('nota, status, finalizada_em')
    .eq('candidato_id', cand.id)
    .in('status', ['finalizada', 'expirada'])
    .order('finalizada_em', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (feita) {
    return {
      estado: feita.status === 'expirada' ? 'expirada' : 'concluida',
      nota: feita.nota,
      finalizada_em: feita.finalizada_em,
    };
  }

  // Em andamento: o prazo pode ter estourado desde o último acesso. Aqui
  // só relatamos — encerrar de fato é responsabilidade do iniciar/enviar,
  // que gravam o resultado.
  const { data: emAndamento } = await supabase
    .from('avaliacao')
    .select('expira_em, limite_minutos')
    .eq('candidato_id', cand.id)
    .eq('status', 'iniciada')
    .order('iniciada_em', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (emAndamento) {
    const vencida = emAndamento.expira_em != null &&
      new Date(emAndamento.expira_em).getTime() <= Date.now();
    return {
      estado: vencida ? 'expirada' : 'em_andamento',
      expira_em: emAndamento.expira_em,
      limite_minutos: emAndamento.limite_minutos,
    };
  }

  // Nunca iniciada: só oferece a prova se existir questão para sortear.
  const pool = await fetchQuestoes(
    supabase, cand.organization_id, cand.cargo_id, cand.nivel);
  if (pool.length === 0) return { estado: 'indisponivel' };

  const { data: org } = await supabase
    .from('organizations').select('settings')
    .eq('id', cand.organization_id).maybeSingle();
  const minutosRaw = Number(org?.settings?.avaliacao_minutos ?? 0);
  return {
    estado: 'disponivel',
    total_questoes: Math.min(
      pool.length,
      Math.min(15, Math.max(1,
        Number(org?.settings?.avaliacao_qtd ?? AVALIACAO_QTD_DEFAULT) ||
          AVALIACAO_QTD_DEFAULT)),
    ),
    limite_minutos: Number.isFinite(minutosRaw) && minutosRaw > 0
      ? Math.min(AVALIACAO_MINUTOS_MAX, Math.floor(minutosRaw))
      : null,
  };
}

// ── message: candidato → RH (RH-2.8) ──────────────────────────
async function handleMessage(supabase: any, body: any) {
  const found = await candidateByToken(supabase, body?.token);
  if ('response' in found) return found.response;
  const texto = String(body?.texto ?? '').trim().slice(0, 2000);
  if (!texto) return json({ error: 'Mensagem vazia.' }, 400);

  await supabase.from('candidato_mensagem').insert({
    candidato_id: found.candidato.id,
    autor: 'candidato',
    texto,
  });
  return json({ success: true });
}

// ── upload: documento adicional do candidato (RH-2.9) ─────────
async function handleUpload(supabase: any, body: any) {
  const found = await candidateByToken(supabase, body?.token);
  if ('response' in found) return found.response;
  const c = found.candidato;

  const bytes = base64ToBytes(String(body?.base64 ?? ''));
  if (bytes.length === 0) return json({ error: 'Arquivo vazio.' }, 400);
  if (bytes.length > MAX_DOC_BYTES) {
    return json({ error: 'O arquivo deve ter no máximo 10MB.' }, 400);
  }
  const tipo = sniffFileType(bytes);
  if (!tipo) return json({ error: 'Formato inválido — envie PDF, DOCX, JPG ou PNG.' }, 400);

  const nomeOriginal = String(body?.nome ?? 'documento').slice(0, 120);
  const path = `candidatos/${c.id}/${Date.now()}.${tipo}`;
  const { error: uploadError } = await supabase.storage
    .from('rh-documentos')
    .upload(path, bytes, { contentType: contentTypeOf(tipo) });
  if (uploadError) {
    console.error('[upload] error:', uploadError);
    return json({ error: 'Falha no envio do arquivo.' }, 500);
  }

  await supabase.from('candidato_mensagem').insert({
    candidato_id: c.id,
    autor: 'candidato',
    texto: `Documento enviado: ${nomeOriginal}`,
    anexo_url: path,
    anexo_nome: nomeOriginal,
  });
  return json({ success: true });
}

// ── avaliacao_iniciar: candidato começa a prova (RH-12) ───────
// Sorteia N questões ativas (preferindo o cargo, depois o nível) e
// devolve SEM correta_idx. Cria a linha `avaliacao`. Impede refazer.
// RH-23: carimba o prazo (expira_em) e guarda o conjunto sorteado, o
// que permite retomar uma prova em andamento sem sortear de novo.
const AVALIACAO_QTD_DEFAULT = 5;
const AVALIACAO_MINUTOS_MAX = 180;

async function handleAvaliacaoIniciar(supabase: any, body: any) {
  const found = await candidateByToken(supabase, body?.token);
  if ('response' in found) return found.response;

  const { data: cand } = await supabase
    .from('candidato')
    .select('id, organization_id, cargo_id, nivel, vaga_id')
    .eq('id', found.candidato.id)
    .single();

  // Já encerrada (enviada ou expirada)? Não permite refazer.
  const { data: feita } = await supabase
    .from('avaliacao')
    .select('id, nota, status')
    .eq('candidato_id', cand.id)
    .in('status', ['finalizada', 'expirada'])
    .order('finalizada_em', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (feita) {
    return json({
      ja_feita: true,
      nota: feita.nota,
      expirada: feita.status === 'expirada',
    });
  }

  // Config por org: quantidade e minutos (0/ausente = sem limite).
  const { data: org } = await supabase
    .from('organizations')
    .select('settings')
    .eq('id', cand.organization_id)
    .maybeSingle();
  const qtd = Math.min(
    15,
    Math.max(1, Number(org?.settings?.avaliacao_qtd ?? AVALIACAO_QTD_DEFAULT) || AVALIACAO_QTD_DEFAULT),
  );
  const minutosRaw = Number(org?.settings?.avaliacao_minutos ?? 0);
  const minutos = Number.isFinite(minutosRaw) && minutosRaw > 0
    ? Math.min(AVALIACAO_MINUTOS_MAX, Math.floor(minutosRaw))
    : null;

  // Prova em andamento: retoma no lugar de sortear outra. Isso fecha a
  // brecha de reiniciar até cair um conjunto de questões mais fácil.
  const { data: emAndamento } = await supabase
    .from('avaliacao')
    .select('id, expira_em, limite_minutos, questao_ids')
    .eq('candidato_id', cand.id)
    .eq('status', 'iniciada')
    .order('iniciada_em', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (emAndamento) {
    const vencida = emAndamento.expira_em != null &&
      new Date(emAndamento.expira_em).getTime() <= Date.now();
    if (vencida) {
      await supabase.from('avaliacao').update({
        status: 'expirada',
        finalizada_em: emAndamento.expira_em,
        acertos: 0,
        nota: 0,
      }).eq('id', emAndamento.id);
      return json({ ja_feita: true, nota: 0, expirada: true });
    }
    const retomadas = await fetchQuestoesPorIds(supabase, emAndamento.questao_ids ?? []);
    if (retomadas.length > 0) {
      return json({
        avaliacao_id: emAndamento.id,
        limite_minutos: emAndamento.limite_minutos,
        expira_em: emAndamento.expira_em,
        retomada: true,
        questoes: retomadas.map((q: any) => ({
          id: q.id,
          enunciado: q.enunciado,
          opcoes: q.opcoes,
        })),
      });
    }
    // Sem questao_ids (prova criada antes do RH-23): abandona a linha
    // órfã e sorteia uma nova abaixo.
    await supabase.from('avaliacao')
      .update({ status: 'expirada', finalizada_em: new Date().toISOString() })
      .eq('id', emAndamento.id);
  }

  // Seleciona questões ativas da org, priorizando o cargo do candidato.
  let pool = await fetchQuestoes(supabase, cand.organization_id, cand.cargo_id, cand.nivel);
  if (pool.length === 0) {
    return json({ disponivel: false });
  }
  // Embaralha e corta.
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  const escolhidas = pool.slice(0, qtd);
  const expiraEm = minutos != null
    ? new Date(Date.now() + minutos * 60_000).toISOString()
    : null;

  const { data: aval, error: avalErr } = await supabase
    .from('avaliacao')
    .insert({
      organization_id: cand.organization_id,
      candidato_id: cand.id,
      vaga_id: cand.vaga_id ?? null,
      nivel: cand.nivel ?? null,
      total_questoes: escolhidas.length,
      status: 'iniciada',
      limite_minutos: minutos,
      expira_em: expiraEm,
      questao_ids: escolhidas.map((q: any) => q.id),
    })
    .select('id')
    .single();
  if (avalErr) {
    console.error('[avaliacao_iniciar] insert error:', avalErr);
    return json({ error: 'Não foi possível iniciar a avaliação.' }, 500);
  }

  return json({
    avaliacao_id: aval.id,
    limite_minutos: minutos,
    expira_em: expiraEm,
    questoes: escolhidas.map((q: any) => ({
      id: q.id,
      enunciado: q.enunciado,
      opcoes: q.opcoes,
    })),
  });
}

// Recarrega, na ordem salva, as questões de uma prova retomada.
async function fetchQuestoesPorIds(supabase: any, ids: string[]) {
  if (!Array.isArray(ids) || ids.length === 0) return [];
  const { data } = await supabase
    .from('questao')
    .select('id, enunciado, opcoes')
    .in('id', ids);
  const porId = new Map((data ?? []).map((q: any) => [q.id, q]));
  return ids.map((id) => porId.get(id)).filter(Boolean);
}

// Busca questões ativas priorizando cargo → nível → org inteira.
async function fetchQuestoes(
  supabase: any, orgId: string, cargoId: string | null, nivel: string | null,
) {
  const base = () => supabase
    .from('questao')
    .select('id, enunciado, opcoes')
    .eq('organization_id', orgId)
    .eq('ativa', true)
    .is('deleted_at', null)
    .limit(50);

  if (cargoId) {
    const { data } = await base().eq('cargo_id', cargoId);
    if (data && data.length > 0) return data;
  }
  if (nivel) {
    const { data } = await base().eq('nivel', nivel);
    if (data && data.length > 0) return data;
  }
  const { data } = await base();
  return data ?? [];
}

// ── avaliacao_enviar: correção 100% server-side (RH-12) ───────
// RH-23: o prazo também é decidido aqui. O relógio do cliente não vale
// nada — o que conta é expira_em, gravado no início da prova.
// Tolerância para cobrir latência do auto-envio disparado no timeout.
const AVALIACAO_TOLERANCIA_MS = 30_000;

async function handleAvaliacaoEnviar(supabase: any, body: any) {
  const found = await candidateByToken(supabase, body?.token);
  if ('response' in found) return found.response;

  const avaliacaoId = String(body?.avaliacao_id ?? '');
  if (!/^[0-9a-f-]{36}$/.test(avaliacaoId)) {
    return json({ error: 'Avaliação inválida.' }, 400);
  }
  const respostas = Array.isArray(body?.respostas) ? body.respostas : [];

  // Avaliação precisa ser do candidato e ainda estar em andamento.
  const { data: aval } = await supabase
    .from('avaliacao')
    .select('id, candidato_id, organization_id, total_questoes, status, expira_em, questao_ids')
    .eq('id', avaliacaoId)
    .maybeSingle();
  if (!aval || aval.candidato_id !== found.candidato.id) {
    return json({ error: 'Avaliação não encontrada.' }, 404);
  }
  if (aval.status !== 'iniciada') {
    return json({ error: 'Esta avaliação já foi finalizada.' }, 409);
  }

  // Prazo estourado além da tolerância: nada é corrigido, a prova é
  // encerrada com nota 0. Dentro da tolerância, o envio vale.
  if (aval.expira_em != null &&
      Date.now() > new Date(aval.expira_em).getTime() + AVALIACAO_TOLERANCIA_MS) {
    await supabase.from('avaliacao').update({
      status: 'expirada',
      finalizada_em: aval.expira_em,
      acertos: 0,
      nota: 0,
    }).eq('id', aval.id);
    await supabase.from('candidato_historico').insert({
      candidato_id: aval.candidato_id,
      acao: 'avaliacao',
      detalhes: { expirada: true, nota: 0 },
    });
    return json({ error: 'O tempo da avaliação terminou.', expirada: true }, 409);
  }

  // Só contam as questões que caíram para este candidato. Provas
  // anteriores ao RH-23 não têm questao_ids — nelas segue o critério
  // antigo (o que veio no corpo).
  const permitidas: Set<string> | null = Array.isArray(aval.questao_ids) &&
      aval.questao_ids.length > 0
    ? new Set(aval.questao_ids as string[])
    : null;

  // Gabarito lido no servidor — correta_idx nunca sai daqui.
  const questaoIds = respostas
    .map((r: any) => String(r?.questao_id ?? ''))
    .filter((id: string) => /^[0-9a-f-]{36}$/.test(id))
    .filter((id: string) => permitidas == null || permitidas.has(id));
  const { data: gabarito } = await supabase
    .from('questao')
    .select('id, correta_idx')
    .in('id', questaoIds.length > 0 ? questaoIds : ['00000000-0000-0000-0000-000000000000']);
  const correta: Record<string, number> = {};
  for (const q of gabarito ?? []) correta[q.id] = q.correta_idx;

  let acertos = 0;
  const linhas: any[] = [];
  const vistas = new Set<string>();
  for (const r of respostas) {
    const qid = String(r?.questao_id ?? '');
    if (!(qid in correta) || vistas.has(qid)) continue;
    vistas.add(qid);
    const idx = Number(r?.resposta_idx);
    const acertou = Number.isInteger(idx) && idx === correta[qid];
    if (acertou) acertos++;
    linhas.push({
      organization_id: aval.organization_id,
      avaliacao_id: aval.id,
      questao_id: qid,
      resposta_idx: Number.isInteger(idx) ? idx : null,
      correta: acertou,
    });
  }

  if (linhas.length > 0) {
    await supabase.from('avaliacao_resposta').insert(linhas);
  }

  const total = aval.total_questoes > 0 ? aval.total_questoes : linhas.length;
  const nota = total > 0 ? Math.round((acertos * 100) / total) : 0;

  await supabase.from('avaliacao').update({
    acertos,
    nota,
    status: 'finalizada',
    finalizada_em: new Date().toISOString(),
  }).eq('id', aval.id);

  await supabase.from('candidato_historico').insert({
    candidato_id: aval.candidato_id,
    acao: 'avaliacao',
    detalhes: { nota, acertos, total },
  });

  return json({ nota, acertos, total });
}

// ── Auth & Portal do Candidato (RH-16) ────────────────────────
async function handleAuthSignup(supabase: any, body: any, ip: string) {
  const nome = String(body?.nome ?? '').trim();
  const email = String(body?.email ?? '').trim().toLowerCase();
  const password = String(body?.password ?? '');

  // Rate limiting (Achado 02): máx. 5 cadastros por hora por IP
  const rateLimit = await checkRateLimit(supabase, ip, 'auth_signup', 5, 3600_000);
  if (!rateLimit.allowed) {
    return json({ error: 'Muitas tentativas de cadastro. Tente novamente em 1 hora.' }, 429);
  }

  if (nome.length < 3) return json({ error: 'Informe seu nome completo.' }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'E-mail inválido.' }, 400);

  // Política de senha forte (Achado 05 - alinhado ao BackupCrypto: min 12 caracteres com letra, número e símbolo)
  if (
    password.length < 12 ||
    !/[A-Za-z]/.test(password) ||
    !/[0-9]/.test(password) ||
    !/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(password)
  ) {
    return json(
      {
        error:
          'A senha deve ter no mínimo 12 caracteres e conter letras, números e ao menos um símbolo.',
      },
      400
    );
  }

  const { data: token, error } = await supabase.rpc('rh_candidato_signup', {
    p_nome: nome,
    p_email: email,
    p_password: password,
  });

  if (error) {
    if (error.message.includes('unique constraint') || error.message.includes('violates unique constraint')) {
      return json({ error: 'Este e-mail já está cadastrado.' }, 409);
    }
    console.error('[auth_signup] error:', error);
    return json({ error: 'Erro ao criar conta.' }, 500);
  }

  try {
    await sendVerificationEmail(email, nome, token);
  } catch (e) {
    console.error('[auth_signup] email error:', e);
  }

  return json({ success: true });
}

async function handleAuthLogin(supabase: any, body: any, ip: string) {
  const email = String(body?.email ?? '').trim().toLowerCase();
  const password = String(body?.password ?? '');

  // Rate limiting (Achado 02): máx. 5 tentativas a cada 15 min por IP
  const rateLimit = await checkRateLimit(supabase, ip, 'auth_login', 5, 15 * 60_000);
  if (!rateLimit.allowed) {
    return json(
      { error: `Muitas tentativas de login. Tente novamente em ${rateLimit.retryAfterMin} minutos.` },
      429
    );
  }

  const { data: token, error } = await supabase.rpc('rh_candidato_login', {
    p_email: email,
    p_password: password,
  });

  if (error) {
    console.warn(`[auth_login] Falha de login para ${email}: ${error.message}`);
    // Resposta unificada que não distingue se o e-mail existe no portal (Achado 06)
    return json({ error: 'E-mail ou senha incorretos, ou e-mail pendente de verificação.' }, 401);
  }

  return json({ token });
}

async function handleAuthVerify(supabase: any, body: any) {
  const token = String(body?.token ?? '');
  
  const { data: success, error } = await supabase.rpc('rh_candidato_verify', {
    p_token: token,
  });

  if (error || !success) {
    return json({ error: 'Código de verificação inválido.' }, 400);
  }

  return json({ success: true });
}

async function handleApiMe(supabase: any, req: Request) {
  const authHeader = req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ error: 'Não autorizado' }, 401);
  }
  const token = authHeader.replace('Bearer ', '').trim();

  const { data: user, error } = await supabase.rpc('rh_candidato_get_user', {
    p_session_token: token,
  });

  if (error || !user) {
    return json({ error: 'Sessão inválida ou expirada' }, 401);
  }

  const { data: candidaturas } = await supabase
    .from('candidato')
    .select('id, organization_id, organizations(name, logo_url), status, created_at, portal_token')
    .eq('candidato_usuario_id', user.id)
    .is('deleted_at', null)
    .order('created_at', { ascending: false });

  // Fase 7: a página de carreiras usa isto para oferecer "usar o currículo
  // que já enviei" em vez de exigir upload a cada vaga.
  const cv = await ultimoCurriculoDoUsuario(supabase, user.id);

  return json({
    user,
    candidaturas: candidaturas ?? [],
    curriculo_reaproveitavel: cv != null,
    curriculo_tipo: cv?.tipo_arquivo ?? null,
  });
}

// ── Helpers ───────────────────────────────────────────────────

/// Resolve a conta do candidato (RH-16) a partir do Bearer da requisição.
/// Ausente ou inválido → null (a candidatura segue como anônima).
async function candidatoUsuarioIdFromRequest(
  supabase: any, req?: Request,
): Promise<string | null> {
  const authHeader = req?.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;
  const token = authHeader.replace('Bearer ', '').trim();
  const { data: user } = await supabase.rpc('rh_candidato_get_user', {
    p_session_token: token,
  });
  return user?.id ?? null;
}

/// Currículo mais recente entre as candidaturas da conta (Fase 7).
/// Confere que o objeto ainda existe no storage — candidaturas antigas
/// podem ter sido purgadas pela retenção da LGPD.
async function ultimoCurriculoDoUsuario(
  supabase: any, userId: string,
): Promise<
  { arquivo_url: string; tipo_arquivo: string; tamanho_bytes: number } | null
> {
  const { data: candidaturas } = await supabase
    .from('candidato')
    .select('id')
    .eq('candidato_usuario_id', userId)
    .is('deleted_at', null);
  const ids = (candidaturas ?? []).map((c: any) => c.id);
  if (ids.length === 0) return null;

  const { data: curriculos } = await supabase
    .from('candidato_curriculo')
    .select('arquivo_url, tipo_arquivo, tamanho_bytes')
    .in('candidato_id', ids)
    .order('created_at', { ascending: false })
    .limit(5);

  for (const cv of curriculos ?? []) {
    if (cv.tipo_arquivo !== 'pdf' && cv.tipo_arquivo !== 'docx') continue;
    const barra = cv.arquivo_url.lastIndexOf('/');
    if (barra <= 0) continue;
    const { data: existe } = await supabase.storage
      .from('rh-curriculos')
      .list(cv.arquivo_url.slice(0, barra), {
        search: cv.arquivo_url.slice(barra + 1),
      });
    if ((existe ?? []).length > 0) return cv;
  }
  return null;
}

// Retorno anotado: inferido, cada ramo ganha a chave do outro como opcional
// e `found.response` vira `Response | undefined` mesmo após `'response' in`.
async function candidateByToken(
  supabase: any, tokenRaw: any,
): Promise<{ response: Response } | { candidato: any }> {
  const token = String(tokenRaw ?? '');
  if (!/^[0-9a-f-]{36}$/.test(token)) {
    return { response: json({ error: 'Link inválido.' }, 404) };
  }
  const { data: candidato } = await supabase
    .from('candidato')
    .select(
      'id, organization_id, nome, status, created_at, portal_token_expira, vaga_id')
    .eq('portal_token', token)
    .is('deleted_at', null)
    .maybeSingle();
  if (!candidato) return { response: json({ error: 'Link inválido.' }, 404) };
  if (new Date(candidato.portal_token_expira) < new Date()) {
    return { response: json({ error: 'Este link expirou. Entre em contato com o RH.' }, 410) };
  }
  return { candidato };
}

/// Casa o texto digitado com uma entrada do catálogo da org (RH-9).
///
/// Deliberadamente NÃO cria linha nova: o catálogo é curadoria do RH, e
/// deixar a página pública inserir nele encheria os filtros de variações
/// digitadas por candidatos. Sem correspondência, o texto livre fica salvo
/// no candidato e a FK segue null.
async function resolveCatalogo(
  supabase: any, tabela: 'rh_area' | 'rh_cargo', orgId: string,
  texto: string | null,
): Promise<string | null> {
  const t = texto?.trim();
  if (!t) return null;
  // ilike com o termo escapado: `%`/`_` digitados são literais, não curinga.
  const alvo = t.replace(/[\\%_]/g, (c) => `\\${c}`);
  const { data } = await supabase
    .from(tabela)
    .select('id')
    .eq('organization_id', orgId)
    .eq('ativo', true)
    .ilike('nome', alvo)
    .limit(1)
    .maybeSingle();
  return data?.id ?? null;
}

function strOrNull(v: any): string | null {
  const s = String(v ?? '').trim();
  return s.length > 0 ? s.slice(0, 200) : null;
}

function base64ToBytes(b64: string): Uint8Array {
  try {
    const clean = b64.includes(',') ? b64.split(',')[1] : b64;
    const bin = atob(clean);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  } catch {
    return new Uint8Array(0);
  }
}

/// Detecta o tipo real pelos magic bytes (S046 — não confiar na extensão).
function sniffFileType(bytes: Uint8Array): string | null {
  if (bytes.length < 4) return null;
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return 'pdf'; // %PDF
  if (bytes[0] === 0x50 && bytes[1] === 0x4b) return 'docx'; // PK (zip/docx)
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return 'jpg';
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return 'png';
  return null;
}

function contentTypeOf(tipo: string): string {
  switch (tipo) {
    case 'pdf': return 'application/pdf';
    case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'jpg': return 'image/jpeg';
    case 'png': return 'image/png';
    default: return 'application/octet-stream';
  }
}

// ── E-mail de confirmação (SMTP próprio da org ou servidor da plataforma) ─
async function sendConfirmationEmail(
  to: string, nome: string, empresa: string, token: string, orgId?: string,
) {
  // S021 — em DEV nenhum candidato real recebe e-mail
  const devOverride = Deno.env.get('DEV_EMAIL_OVERRIDE');
  const recipient = devOverride || to;
  const link = `${APP_BASE_URL}/candidato/${token}`;

  let orgRow: any = null;
  if (orgId) {
    try {
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );
      const { data: smtpData } = await supabaseAdmin.rpc('rh_get_smtp_server', { p_org_id: orgId });
      orgRow = smtpData?.[0] ?? null;
    } catch (err) {
      console.warn('[rh-candidatura] Falha ao buscar SMTP da org, usando fallback:', err);
    }
  }

  const senderName = Deno.env.get('SENDER_NAME') || APP_NAME;
  const smtp = resolveSmtp(orgRow, `${empresa} via ${senderName}`);
  if (!smtp) throw new Error(SMTP_NOT_CONFIGURED);
  // Sem nome cadastrado no SMTP da empresa, o remetente é a própria empresa.
  if (orgRow?.host && !orgRow?.from_name) smtp.fromName = empresa;

  await sendMail(smtp, {
    to: recipient,
    replyTo: smtp.fromEmail,
    subject: `Recebemos sua candidatura - ${empresa}`,
    text: confirmationText(nome, empresa, link),
    html: confirmationHtml(nome, empresa, link),
    headers: {
      'Auto-Submitted': 'auto-generated',
      'X-Auto-Response-Suppress': 'All',
    },
  });
}

function confirmationText(nome: string, empresa: string, link: string): string {
  return `Olá, ${nome}!

Sua candidatura para ${empresa} foi registrada com sucesso.
Nossa equipe de RH vai analisar seu currículo e você pode acompanhar o andamento pelo link abaixo:

${link}

Este link é pessoal e expira em 90 dias.
Se você não se candidatou, ignore este e-mail.

--
${APP_TAGLINE}`;
}

function confirmationHtml(rawNome: string, rawEmpresa: string, rawLink: string): string {
  // `nome` vem do portal público: sem escape, vira HTML no e-mail da empresa.
  const nome = escapeHtml(rawNome);
  const empresa = escapeHtml(rawEmpresa);
  const link = escapeHtml(rawLink);
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0a0a0f;font-family:'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0f;padding:40px 20px;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background-color:#12121a;border-radius:20px;overflow:hidden;border:1px solid rgba(255,255,255,0.06);">
        <tr><td style="background:linear-gradient(135deg,#D32F2F 0%,#8B0000 100%);padding:36px 40px;text-align:center;">
          <img src="${EMAIL_LOGO_URL}" alt="${APP_NAME}" width="160" style="display:block;margin:0 auto 16px;object-fit:contain;background:rgba(255,255,255,0.1);padding:10px;border-radius:12px;">
          <h1 style="margin:8px 0 0;color:#ffffff;font-size:22px;font-weight:700;">Candidatura recebida!</h1>
        </td></tr>
        <tr><td style="padding:36px 40px 40px;">
          <p style="margin:0 0 8px;color:#e0e0e0;font-size:16px;line-height:1.6;">Olá, <strong style="color:#ffffff;">${nome}</strong>!</p>
          <p style="margin:0 0 24px;color:#8888a0;font-size:14px;line-height:1.7;">
            Sua candidatura para <strong style="color:#e0e0e0;">${empresa}</strong> foi registrada com sucesso.
            Nossa equipe de RH vai analisar seu currículo e você pode acompanhar o andamento pelo link abaixo:
          </p>
          <table cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr><td style="background:#D32F2F;border-radius:10px;">
            <a href="${link}" style="display:inline-block;padding:14px 28px;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;">Acompanhar minha candidatura</a>
          </td></tr></table>
          <p style="margin:24px 0 0;color:#8888a0;font-size:12px;line-height:1.6;text-align:center;">
            Este link é pessoal e expira em 90 dias.<br>
            Se você não se candidatou, ignore este e-mail.
          </p>
        </td></tr>
        <tr><td style="padding:18px 40px;background:rgba(0,0,0,0.3);text-align:center;border-top:1px solid rgba(255,255,255,0.04);">
          <p style="margin:0;color:#444460;font-size:11px;">© ${new Date().getFullYear()} ${APP_TAGLINE}</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function verifyHtml(rawNome: string, rawLink: string): string {
  const nome = escapeHtml(rawNome);
  const link = escapeHtml(rawLink);
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0a0a0f;font-family:'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0f;padding:40px 20px;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background-color:#12121a;border-radius:20px;overflow:hidden;border:1px solid rgba(255,255,255,0.06);">
        <tr><td style="background:linear-gradient(135deg,#D32F2F 0%,#8B0000 100%);padding:36px 40px;text-align:center;">
          <h1 style="margin:8px 0 0;color:#ffffff;font-size:22px;font-weight:700;">Verifique seu E-mail</h1>
        </td></tr>
        <tr><td style="padding:36px 40px 40px;">
          <p style="margin:0 0 8px;color:#e0e0e0;font-size:16px;line-height:1.6;">Olá, <strong style="color:#ffffff;">${nome}</strong>!</p>
          <p style="margin:0 0 24px;color:#8888a0;font-size:14px;line-height:1.7;">
            Para acessar o Portal de Candidatos, verifique seu e-mail clicando no link abaixo:
          </p>
          <table cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr><td style="background:#D32F2F;border-radius:10px;">
            <a href="${link}" style="display:inline-block;padding:14px 28px;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;">Verificar E-mail</a>
          </td></tr></table>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

async function sendVerificationEmail(
  to: string, nome: string, token: string,
) {
  const devOverride = Deno.env.get('DEV_EMAIL_OVERRIDE');
  const recipient = devOverride || to;
  const smtp = platformSmtp();
  if (!smtp) throw new Error(SMTP_NOT_CONFIGURED);

  const link = `${APP_BASE_URL}/candidato/verify?token=${token}`;
  await sendMail(smtp, {
    to: recipient,
    replyTo: smtp.fromEmail,
    subject: `Verifique seu e-mail - ${APP_NAME}`,
    text: verifyText(nome, link),
    html: verifyHtml(nome, link),
    headers: {
      'Auto-Submitted': 'auto-generated',
      'X-Auto-Response-Suppress': 'All',
    },
  });
}

function verifyText(nome: string, link: string): string {
  return `Olá, ${nome}!

Para acessar o Portal de Candidatos, verifique seu e-mail acessando o link abaixo:

${link}

--
${APP_TAGLINE}`;
}

function json(data: Record<string, any>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
