const { createClient } = require('@supabase/supabase-js');

// Credenciais vem SO do ambiente. O ref do projeto tambem: estes scripts ja
// apontaram fixo para o projeto do outro fork e rodaram no banco errado.
//
//   $env:SUPABASE_URL = "https://ffsspqscpdxlmxuaiytj.supabase.co"   # DEV
//   # PROD: "https://gpeemngsxvqjflasdody.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error(
    'Faltam variaveis de ambiente.\n' +
      '  SUPABASE_URL=<url do projeto>\n' +
      '  SUPABASE_SERVICE_ROLE_KEY=<chave service_role>\n' +
      'Nunca coloque a chave em arquivo versionado.',
  );
  process.exit(1);
}
const sb = createClient(supabaseUrl, supabaseKey, {
  auth: { persistSession: false }
});

async function main() {
  console.log('Checking messages table...');
  const { data: messages, error: mError } = await sb.from('messages').select('id, chat_id, sender_id, content, created_at').limit(10);
  if (mError) {
    console.error('Error fetching messages:', mError);
  } else {
    console.log(`Found ${messages.length} messages:`);
    console.log(messages);
  }

  console.log('\nChecking chats table...');
  const { data: chats, error: cError } = await sb.from('chats').select('id, name, type').limit(10);
  if (cError) {
    console.error('Error fetching chats:', cError);
  } else {
    console.log(`Found ${chats.length} chats:`);
    console.log(chats);
  }

  console.log('\nChecking channel_members...');
  const { data: members, error: memError } = await sb.from('channel_members').select('chat_id, user_id, role, unread_count').limit(10);
  if (memError) {
    console.error('Error fetching channel_members:', memError);
  } else {
    console.log(`Found ${members.length} channel_members:`);
    console.log(members);
  }
}

main().catch(console.error);
