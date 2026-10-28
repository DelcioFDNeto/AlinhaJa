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
  console.log('Calling reset_operational_data(true)...');
  const { data, error } = await sb.rpc('reset_operational_data', { p_reseed_channels: true });
  if (error) {
    console.error('ERROR:', error.message);
    process.exit(1);
  }
  console.log('Success:', data);
  process.exit(0);
}

main();