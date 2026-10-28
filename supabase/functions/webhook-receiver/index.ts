import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Definido na migração 021_threads_and_bots.sql
const BOT_USER_ID = '00000000-0000-0000-0000-000000000001';

serve(async (req) => {
  try {
    const { method } = req;
    
    // Tratamento basico para OPTIONS (CORS) caso a chamada venha do browser
    if (method === 'OPTIONS') {
      return new Response('ok', {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      });
    }

    if (method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed. Use POST.' }), { status: 405 });
    }

    // 1. Validar SECRET (obrigatório — esta função insere mensagens como bot com service role)
    const authHeader = req.headers.get('Authorization') || req.headers.get('webhook-secret');
    const secret = Deno.env.get('WEBHOOK_SECRET');

    if (!secret) {
      console.error('[AUTH] WEBHOOK_SECRET não configurado — recusando requisição. Configure: npx supabase secrets set WEBHOOK_SECRET=<valor forte>');
      return new Response(JSON.stringify({ error: 'Webhook not configured (missing WEBHOOK_SECRET).' }), { status: 503 });
    }
    if (authHeader !== `Bearer ${secret}` && authHeader !== secret) {
      return new Response(JSON.stringify({ error: 'Unauthorized webhook call. Missing or invalid secret.' }), { status: 401 });
    }

    const body = await req.json();
    const { channel_name, message, content_type = 'text', thread_id = null } = body;

    if (!channel_name || !message) {
      return new Response(JSON.stringify({ error: 'Missing "channel_name" or "message" in JSON body' }), { status: 400 });
    }

    // 2. Conectar ao Supabase (Service Role para ignorar RLS e inserir como bot_id interno)
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase environment variables missing (SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY)');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // 3. Localizar Canal pelo Nome exato (case-sensitive por enquanto, mas pode ser ilike)
    const { data: channel, error: channelError } = await supabase
      .from('chats')
      .select('id')
      .eq('type', 'channel')
      .eq('name', channel_name)
      .maybeSingle();

    if (channelError) throw channelError;
    if (!channel) {
      return new Response(JSON.stringify({ error: `Channel '${channel_name}' not found` }), { status: 404 });
    }

    // 4. Inserir a mensagem na tabela messages
    const payload: any = {
      chat_id: channel.id,
      sender_id: BOT_USER_ID,
      content: message,
      content_type: content_type,
      is_bot: true,
    };

    if (thread_id) {
      payload.thread_id = thread_id;
    }

    const { data: insertData, error: insertError } = await supabase
      .from('messages')
      .insert(payload)
      .select()
      .single();

    if (insertError) throw insertError;

    // 5. Retornar Sucesso
    return new Response(JSON.stringify({ success: true, data: insertData }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    console.error('Webhook error:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});
