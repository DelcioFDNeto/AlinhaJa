// rh-automations — Fase 9 (Comunicação & Automações)
// Disparada pelo trigger trg_rh_automacao_notify (AFTER INSERT em
// candidato_historico, acao='mudanca_status'). Envia e-mails de
// automação usando o SMTP da org (rh_get_smtp_server) ou o remetente
// global da plataforma como fallback, e registra em rh_comunicacao_log.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { APP_NAME } from '../_shared/brand.ts';
import { escapeHtml, stripHeaderBreaks } from '../_shared/html.ts';
import { isImplicitTls, resolveSmtp, sendMail } from '../_shared/mailer.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

/// `escape` trata o valor de cada variável conforme o destino: o template é
/// HTML escrito pelo RH, mas `nome` vem do portal público de candidatos e
/// não pode entrar no corpo como marcação nem quebrar a linha do assunto.
/// Substituição por função: um `$&` no nome não é interpretado como padrão.
function render(
  tpl: string,
  vars: Record<string, string>,
  escape: (v: string) => string,
): string {
  return tpl
    .replace(/{{\s*nome\s*}}/g, () => escape(vars.nome))
    .replace(/{{\s*candidato_nome\s*}}/g, () => escape(vars.nome))
    .replace(/{{\s*empresa\s*}}/g, () => escape(vars.empresa))
    .replace(/{{\s*etapa\s*}}/g, () => escape(vars.etapa));
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // Só o banco (trigger com x-webhook-secret) pode invocar — sem isso,
    // qualquer pessoa com a anon key dispararia e-mails arbitrários.
    //
    // Fail-closed: sem WEBHOOK_SECRET a função recusa (503). O modo antigo
    // "aceitando sem validação" deixava o envio de e-mail em nome da empresa
    // aberto a qualquer chamador.
    //
    // WEBHOOK_SECRET_PREVIOUS é opcional e existe apenas para a janela de
    // rotação: mantenha nele o valor antigo até o Vault e as secrets das
    // functions estarem sincronizados, depois remova.
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET') ?? '';
    const previousSecret = Deno.env.get('WEBHOOK_SECRET_PREVIOUS') ?? '';

    let isAuthorized = false;
    let authOrgId: string | null = null;
    let authViaJwt = false;
    let authUserEmail: string | null = null;

    const receivedSecret = req.headers.get('x-webhook-secret') ?? '';
    if (
      (webhookSecret && receivedSecret === webhookSecret) ||
      (previousSecret && receivedSecret === previousSecret)
    ) {
      isAuthorized = true;
    } else {
      // Verifica JWT do usuário autenticado (para teste manual de SMTP pelo painel de RH)
      const authHeader = req.headers.get('Authorization');
      if (authHeader) {
        const token = authHeader.replace(/^Bearer\s+/i, '');
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
        const userClient = createClient(supabaseUrl, supabaseAnonKey, {
          global: { headers: { Authorization: `Bearer ${token}` } },
        });
        const { data: { user }, error: userErr } = await userClient.auth.getUser();
        if (user && !userErr) {
          const adminClient = createClient(
            supabaseUrl,
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
          );
          const { data: userData } = await adminClient
            .from('users')
            .select('organization_id')
            .eq('id', user.id)
            .single();

          // RBAC do módulo de automações (a mesma regra do banco). Antes era
          // role_level — incluindo 'gestor', valor que nem existe no enum.
          const { data: podeGerir } = await userClient.rpc('fn_rh_pode', {
            p_module: 'rh_automacoes',
            p_action: 'manage',
          });

          if (userData && podeGerir === true) {
            isAuthorized = true;
            authViaJwt = true;
            authOrgId = userData.organization_id;
            authUserEmail = user.email ?? null;
          }
        }
      }
    }

    if (!isAuthorized) {
      console.warn('[AUTH] Requisição rejeitada: nem x-webhook-secret nem JWT de RH/Admin válido.');
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: corsHeaders });
    }

    const payload = await req.json();

    // ── Modo Teste de Conexão SMTP ──────────────────────────────
    if (payload.action === 'test_smtp') {
      // SEGURANÇA (Achado 04): No caminho autenticado por JWT, a organização vem
      // estritamente do token do usuário autenticado (authOrgId). O organization_id
      // do payload é ignorado para impedir que um gestor teste o SMTP de outro tenant.
      const orgId = authViaJwt ? authOrgId : payload.organization_id;
      if (!orgId) {
        return new Response(JSON.stringify({ error: 'organization_id is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );

      const { data: smtpData, error: errSmtp } = await supabase
        .rpc('rh_get_smtp_server', { p_org_id: orgId });

      const smtpConfig = resolveSmtp(smtpData?.[0], `${APP_NAME} RH`);
      if (!smtpConfig) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Nenhuma credencial SMTP configurada para a organização nem fallback global.',
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // SEGURANÇA: No caminho autenticado por JWT, o e-mail de teste vai estritamente
      // para o próprio usuário logado (authUserEmail) para evitar relay arbitrário.
      const targetEmail = authUserEmail || payload.target_email || smtpConfig.fromEmail;
      const implicitTls = isImplicitTls(smtpConfig);

      try {
        await sendMail(smtpConfig, {
          to: targetEmail,
          subject: `[${APP_NAME}] Teste de Conexão SMTP`,
          html: `
            <div style="font-family: Arial, sans-serif; padding: 24px; color: #333; max-width: 600px; border: 1px solid #e0e0e0; border-radius: 8px;">
              <h2 style="color: #2e7d32; margin-top: 0;">✓ Conexão SMTP Estabelecida com Sucesso!</h2>
              <p>Este é um e-mail de teste disparado pelo painel de <strong>Comunicação & Automações de RH</strong> do <strong>${APP_NAME}</strong>.</p>
              <div style="background-color: #f9f9f9; padding: 16px; border-radius: 6px; margin: 20px 0;">
                <p style="margin: 0 0 8px 0;"><strong>Servidor (Host):</strong> ${smtpConfig.host}</p>
                <p style="margin: 0 0 8px 0;"><strong>Porta:</strong> ${smtpConfig.port} (${implicitTls ? 'SSL/TLS direto' : 'STARTTLS'})</p>
                <p style="margin: 0 0 8px 0;"><strong>Usuário:</strong> ${smtpConfig.username}</p>
                <p style="margin: 0;"><strong>Remetente configurado:</strong> ${smtpConfig.fromName} &lt;${smtpConfig.fromEmail}&gt;</p>
              </div>
              <p style="font-size: 13px; color: #666;">Se você recebeu esta mensagem, suas automações de recrutamento já podem enviar e-mails aos candidatos.</p>
            </div>
          `,
        });

        return new Response(
          JSON.stringify({
            success: true,
            message: `E-mail de teste enviado com sucesso para ${targetEmail}!`,
            details: {
              host: smtpConfig.host,
              port: smtpConfig.port,
              from: smtpConfig.fromEmail,
            },
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      } catch (sendErr) {
        console.error('[rh-automations] Erro no teste de SMTP:', sendErr);
        const errMsg = sendErr instanceof Error ? sendErr.message : String(sendErr);
        return new Response(
          JSON.stringify({
            success: false,
            error: `Falha ao conectar ou enviar via SMTP: ${errMsg}`,
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // SEGURANÇA (auditoria 2026-09-16): o JWT de gestor só libera o teste de
    // SMTP acima. O disparo de automações confia em `payload.organization_id`,
    // que só o trigger do banco (autenticado pelo secret) pode informar — pelo
    // JWT, um gestor dispararia e-mails para candidatos de outra organização.
    if (authViaJwt) {
      return new Response(JSON.stringify({ error: 'Forbidden' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (payload.table !== 'candidato_historico' || payload.type !== 'INSERT') {
      return new Response('Not a target event', { status: 200, headers: corsHeaders });
    }

    const record = payload.record ?? {};
    const organizationId = payload.organization_id; // resolvido pelo trigger
    const candidatoId = record.candidato_id;
    // candidato_historico: acao='mudanca_status', detalhes={de, para}
    const detalhes = typeof record.detalhes === 'string'
      ? JSON.parse(record.detalhes)
      : (record.detalhes ?? {});
    const etapaDestino = detalhes?.para;

    if (record.acao !== 'mudanca_status' || !etapaDestino || !candidatoId || !organizationId) {
      return new Response('Not a status change', { status: 200, headers: corsHeaders });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: automations, error: errAuto } = await supabase
      .from('rh_automacao')
      .select('*, rh_email_template(nome, assunto, body_html)')
      .eq('organization_id', organizationId)
      .eq('evento', 'mudanca_etapa')
      .eq('ativo', true);
    if (errAuto) throw errAuto;

    // deno-lint-ignore no-explicit-any
    const matching = (automations ?? []).filter((a: any) => {
      const cond = typeof a.condicao === 'string' ? JSON.parse(a.condicao) : a.condicao;
      return cond && cond.etapa_destino === etapaDestino &&
        a.acao === 'enviar_email' && a.rh_email_template;
    });
    if (matching.length === 0) {
      return new Response('No matching automations', { status: 200, headers: corsHeaders });
    }

    const { data: cand, error: errCand } = await supabase
      .from('candidato')
      .select('nome, email, organization_id, organizations(name)')
      .eq('id', candidatoId)
      .single();
    if (errCand || !cand?.email || cand.organization_id !== organizationId) {
      console.warn(`[rh-automations] Candidato ${candidatoId} sem e-mail válido ou org divergente.`);
      return new Response('Candidato sem email', { status: 200, headers: corsHeaders });
    }

    // Nome da etapa para os templates ({{etapa}})
    const { data: etapaRow } = await supabase
      .from('pipeline_etapa')
      .select('nome')
      .eq('organization_id', organizationId)
      .eq('slug', etapaDestino)
      .maybeSingle();
    const etapaNome = etapaRow?.nome ?? etapaDestino;

    // SMTP da org (BYO-SMTP) com fallback global da plataforma
    const { data: smtpData, error: errSmtp } = await supabase
      .rpc('rh_get_smtp_server', { p_org_id: organizationId });
    if (errSmtp) console.error('[rh-automations] Erro ao buscar SMTP da org:', errSmtp);

    const smtpConfig = resolveSmtp(smtpData?.[0], `${APP_NAME} RH`);
    if (!smtpConfig) {
      console.error('[rh-automations] Credenciais SMTP ausentes. Org:', organizationId);
      return new Response('SMTP credentials missing', { status: 500, headers: corsHeaders });
    }

    const devOverride = Deno.env.get('DEV_EMAIL_OVERRIDE');
    const targetEmail = devOverride || cand.email;
    const vars = {
      nome: cand.nome ?? 'Candidato(a)',
      empresa: cand.organizations?.name ?? '',
      etapa: etapaNome,
    };

    let sent = 0;
    for (const rule of matching) {
      const tpl = rule.rh_email_template;
      const subject = stripHeaderBreaks(render(tpl.assunto, vars, (v) => v));
      const body = render(tpl.body_html, vars, escapeHtml);

      let sendStatus = 'enviado';
      let errorDetail: string | null = null;
      try {
        await sendMail(smtpConfig, { to: targetEmail, subject, html: body });
        sent++;
        console.log(`[rh-automations] E-mail enviado para ${targetEmail} (Regra: ${rule.id})`);
      } catch (e) {
        console.error('[rh-automations] Email send error:', e);
        sendStatus = 'erro';
        errorDetail = e instanceof Error ? e.message : String(e);
      }

      await supabase.from('rh_comunicacao_log').insert({
        organization_id: organizationId,
        candidato_id: candidatoId,
        tipo: 'email',
        assunto: subject,
        status: sendStatus,
        erro_detalhe: errorDetail,
      });
    }

    return new Response(JSON.stringify({ success: true, count: matching.length, sent }), {
      headers: corsHeaders,
      status: 200,
    });
  } catch (err) {
    console.error('[rh-automations] Critical Error:', err);
    return new Response(String(err), { status: 500, headers: corsHeaders });
  }
});
