import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { RtcTokenBuilder, RtcRole } from "npm:agora-token@2.0.3";

import { corsHeadersFor } from '../_shared/cors.ts';

console.log("Edge Function 'get-agora-token' — Agora RTC Token Server booting...");

serve(async (req: Request) => {
  // CORS restrito à allowlist: esta function emite token de sala com o
  // JWT do usuário, então não pode responder a qualquer origem.
  const corsHeaders = corsHeadersFor(req);

  // CORS Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 1. Validar cabeçalho de Autorização (JWT)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Inicializar Supabase Client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseAnonKey);

    // 3. Autenticar usuário Supabase decodificando o JWT
    const tokenJwt = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(tokenJwt);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized: Invalid token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 4. Ler parâmetros da requisição
    const { channelName, uid } = await req.json();
    if (!channelName) {
      return new Response(JSON.stringify({ error: 'channelName is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 4b. SEGURANÇA: só emite token para sala a que o usuário tem acesso.
    //     (audit 2026-09-03 — impede espionagem de chamadas; ampliado em
    //     2026-09-16.)
    //
    //     O app só usa dois formatos: `call_<chat ou canal>` e
    //     `room_<reunião>`. Qualquer outro nome passava sem checagem nenhuma e
    //     rendia token de PUBLISHER para uma sala arbitrária — agora é recusado.
    //
    //     `room_` é id de `meetings`, não de conversa. Antes ele era procurado
    //     em chat_members/channel_members e nunca era encontrado, então quem
    //     tinha acesso à reunião recebia 403.
    const forbidden = () => new Response(
      JSON.stringify({ error: 'Forbidden: you are not a member of this conversation' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

    const roomMatch = typeof channelName === 'string'
      ? channelName.match(/^(call|room)_([A-Za-z0-9-]{1,64})$/)
      : null;
    if (!roomMatch) {
      console.warn(`[GET-AGORA-TOKEN] BLOQUEADO: nome de canal fora do padrão "${channelName}" (user="${user.id}").`);
      return forbidden();
    }

    const [, roomKind, contextId] = roomMatch;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const isMemberOf = async (chatId: string | null, channelId: string | null) => {
      if (chatId) {
        const { data } = await adminClient
          .from('chat_members').select('user_id')
          .eq('chat_id', chatId).eq('user_id', user.id).maybeSingle();
        if (data) return true;
      }
      if (channelId) {
        const { data } = await adminClient
          .from('channel_members').select('user_id')
          .eq('channel_id', channelId).eq('user_id', user.id).maybeSingle();
        if (data) return true;
      }
      return false;
    };

    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(contextId);
    let allowed = false;

    if (roomKind === 'call') {
      // O mesmo id pode ser de chat (DM/grupo) ou de canal.
      allowed = isUuid && await isMemberOf(contextId, contextId);
    } else {
      // Mesmo critério da policy de SELECT de meetings: anfitrião, quem
      // chamou, ou membro do chat/canal a que a reunião pertence.
      const { data: meeting } = isUuid
        ? await adminClient
          .from('meetings')
          .select('host_id, caller_id, chat_id, channel_id')
          .eq('id', contextId)
          .maybeSingle()
        : { data: null };
      if (meeting) {
        allowed = meeting.host_id === user.id ||
          meeting.caller_id === user.id ||
          await isMemberOf(meeting.chat_id, meeting.channel_id);
      }
    }

    if (!allowed) {
      console.warn(
        `[GET-AGORA-TOKEN] BLOQUEADO: user="${user.id}" tentou acessar canal "${channelName}" sem ser membro.`
      );
      return forbidden();
    }

    // 5. Ler credenciais da Agora dos segredos do ambiente
    const appId = Deno.env.get('AGORA_APP_ID');
    const appCertificate = Deno.env.get('AGORA_APP_CERTIFICATE');

    if (!appId || !appCertificate) {
      console.error('AGORA_APP_ID or AGORA_APP_CERTIFICATE not set in environment.');
      return new Response(
        JSON.stringify({ error: 'Agora credentials are not configured on the server' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 6. Configurar parâmetros de expiração do Token (1 Hora)
    // Na biblioteca npm:agora-token@2.0.3, tokenExpire e privilegeExpire recebem
    // a validade relativa em SEGUNDOS (e não timestamp epoch absoluto).
    const numericUid = uid !== undefined ? Number(uid) : 0;
    const role = RtcRole.PUBLISHER; // Broadcaster/Publisher
    const expirationTimeInSeconds = 3600; // Validade: 1 hora (3600s)

    console.log(`[GET-AGORA-TOKEN] Gerando token para canal="${channelName}", uid=${numericUid}, user="${user.id}"`);

    // 7. Gerar Token Oficial usando RtcTokenBuilder
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      numericUid,
      role,
      expirationTimeInSeconds,
      expirationTimeInSeconds
    );

    return new Response(JSON.stringify({ token }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[ERRO CRÍTICO] Falha ao gerar token:', error);
    const err = error as Error;
    return new Response(JSON.stringify({ error: err.message || 'Internal Server Error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
