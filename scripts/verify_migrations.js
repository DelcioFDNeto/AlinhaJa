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

async function verifyTableExists(tableName) {
  // Query Postgrest for information_schema.tables
  // By default, information_schema is not fully exposed to Postgrest, 
  // but let's see if we can query pg_catalog or information_schema directly or query a simple select limit 1 from the table.
  try {
    const { data, error } = await sb
      .from(tableName)
      .select('*')
      .limit(1);

    if (error) {
      if (error.code === 'PGRST116' || error.message.includes('JSON object') || error.message.includes('0 rows')) {
        // Table exists but is empty or single row expectations
        return { exists: true, message: 'Table exists (accessed successfully)' };
      }
      return { exists: false, error: error.message, code: error.code };
    }
    return { exists: true, message: `Table exists (accessed successfully, returned ${data.length} rows)` };
  } catch (e) {
    return { exists: false, error: e.message };
  }
}

async function verifyColumnExists(tableName, columnName) {
  try {
    // Attempting to select only this column to see if it succeeds
    const { data, error } = await sb
      .from(tableName)
      .select(columnName)
      .limit(1);

    if (error) {
      return { exists: false, error: error.message, code: error.code };
    }
    return { exists: true, message: `Column '${columnName}' exists on table '${tableName}'` };
  } catch (e) {
    return { exists: false, error: e.message };
  }
}

async function verifyRpcExists(rpcName, params = {}) {
  try {
    // Calling RPC with dummy arguments that will fail on logic (e.g. wrong caller role or invalid UUID)
    // but if it exists, it will execute and return either access denied error or a database error,
    // whereas if it does NOT exist, it will return a PGRST202 / "Could not find the function" error.
    const { data, error } = await sb.rpc(rpcName, params);

    if (error) {
      if (error.message.includes('Could not find') || error.code === 'PGRST202') {
        return { exists: false, error: error.message, code: error.code };
      }
      // If it returns access denied or invalid UUID, it exists!
      return { exists: true, message: `RPC exists (returned execution response: [${error.code}] ${error.message})` };
    }
    return { exists: true, message: `RPC exists (executed successfully, returned ${JSON.stringify(data)})` };
  } catch (e) {
    return { exists: false, error: e.message };
  }
}

async function main() {
  console.log('🔍 INICIANDO AUDITORIA DE MIGRAÇÕES NO BANCO REMOTO...\n');
  console.log(`URL do Supabase: ${supabaseUrl}`);
  console.log('==================================================\n');

  // 1. Verificar Tabela starred_messages
  console.log('1. Verificando Tabela public.starred_messages...');
  const tableCheck = await verifyTableExists('starred_messages');
  if (tableCheck.exists) {
    console.log(`   ✅ SUCESSO: ${tableCheck.message}`);
  } else {
    console.log(`   ❌ FALHA: ${tableCheck.error} (código: ${tableCheck.code})`);
  }
  console.log('');

  // 2. Verificar Coluna unread_count em channel_members
  console.log('2. Verificando Coluna unread_count em public.channel_members...');
  const columnCheck = await verifyColumnExists('channel_members', 'unread_count');
  if (columnCheck.exists) {
    console.log(`   ✅ SUCESSO: ${columnCheck.message}`);
  } else {
    console.log(`   ❌ FALHA: ${columnCheck.error} (código: ${columnCheck.code})`);
  }
  console.log('');

  // 3. Verificar RPC archive_user
  console.log('3. Verificando RPC archive_user...');
  const archiveRpcCheck = await verifyRpcExists('archive_user', { p_user_id: '00000000-0000-0000-0000-000000000000' });
  if (archiveRpcCheck.exists) {
    console.log(`   ✅ SUCESSO: ${archiveRpcCheck.message}`);
  } else {
    console.log(`   ❌ FALHA: ${archiveRpcCheck.error} (código: ${archiveRpcCheck.code})`);
  }
  console.log('');

  // 4. Verificar RPC reactivate_user
  console.log('4. Verificando RPC reactivate_user...');
  const reactivateRpcCheck = await verifyRpcExists('reactivate_user', { p_user_id: '00000000-0000-0000-0000-000000000000' });
  if (reactivateRpcCheck.exists) {
    console.log(`   ✅ SUCESSO: ${reactivateRpcCheck.message}`);
  } else {
    console.log(`   ❌ FALHA: ${reactivateRpcCheck.error} (código: ${reactivateRpcCheck.code})`);
  }
  console.log('');

  // 5. Verificar RPC delete_user_account
  console.log('5. Verificando RPC delete_user_account...');
  const deleteRpcCheck = await verifyRpcExists('delete_user_account', { p_user_id: '00000000-0000-0000-0000-000000000000' });
  if (deleteRpcCheck.exists) {
    console.log(`   ✅ SUCESSO: ${deleteRpcCheck.message}`);
  } else {
    console.log(`   ❌ FALHA: ${deleteRpcCheck.error} (código: ${deleteRpcCheck.code})`);
  }
  console.log('\n==================================================');
  
  const allSuccessful = tableCheck.exists && columnCheck.exists && archiveRpcCheck.exists && reactivateRpcCheck.exists && deleteRpcCheck.exists;
  if (allSuccessful) {
    console.log('🎉 TODAS AS NOVAS MIGRATIONS FORAM VERIFICADAS E EXECUTADAS COM SUCESSO NO BANCO!');
  } else {
    console.log('⚠️ ALGUNS ELEMENTOS NÃO FORAM ENCONTRADOS OU APRESENTARAM FALHAS DE CONEXÃO.');
  }
}

main().catch(console.error);
