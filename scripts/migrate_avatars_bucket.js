#!/usr/bin/env node
/**
 * Migração one-off: chat-media/avatars/* → bucket avatars/*
 *
 * POR QUÊ
 * Trocar um objeto de bucket não é operação SQL — o path físico inclui o
 * bucket, então é preciso reenviar o conteúdo. Este script faz a cópia e
 * atualiza users.avatar_url para a nova URL pública.
 *
 * QUANDO RODAR
 *   1. Depois de aplicar 20260803150000_avatars_bucket.sql
 *   2. ANTES de aplicar 20260803140000 (etapa B — chat-media privado)
 *
 * Se rodar depois da etapa B, os avatares antigos já estarão inacessíveis
 * por URL pública e o download aqui falha.
 *
 * USO (PowerShell):
 *   $env:SUPABASE_URL = "https://ffsspqscpdxlmxuaiytj.supabase.co"   # DEV
 *   # PROD: "https://gpeemngsxvqjflasdody.supabase.co"
 *   $env:SUPABASE_SERVICE_ROLE_KEY = "<service role>"
 *   node scripts/migrate_avatars_bucket.js            # simula (dry-run)
 *   node scripts/migrate_avatars_bucket.js --apply    # executa
 *
 * A chave NUNCA é lida de arquivo versionado — só do ambiente. Depois de
 * rodar, feche o terminal para não deixar a variável na sessão.
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const APPLY = process.argv.includes('--apply');

const SOURCE_BUCKET = 'chat-media';
const SOURCE_PREFIX = 'avatars';
const TARGET_BUCKET = 'avatars';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error(
    'Faltam variáveis de ambiente.\n' +
      '  SUPABASE_URL=<url do projeto>\n' +
      '  SUPABASE_SERVICE_ROLE_KEY=<chave service_role>\n' +
      'Nunca coloque a chave em arquivo versionado.',
  );
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false },
});

async function main() {
  console.log(
    `\n${APPLY ? '>> APLICANDO' : '>> DRY-RUN (use --apply para executar)'}\n`,
  );

  // 1. Lista os avatares no bucket de origem
  const { data: objects, error: listError } = await supabase.storage
    .from(SOURCE_BUCKET)
    .list(SOURCE_PREFIX, { limit: 1000 });

  if (listError) {
    console.error('Erro ao listar avatares:', listError.message);
    process.exit(1);
  }

  const files = (objects ?? []).filter((o) => o.id !== null);
  console.log(`Encontrados ${files.length} avatares em ${SOURCE_BUCKET}/${SOURCE_PREFIX}/`);

  if (files.length === 0) {
    console.log('Nada a migrar.');
    return;
  }

  let copied = 0;
  let skipped = 0;
  const failures = [];

  for (const file of files) {
    const sourcePath = `${SOURCE_PREFIX}/${file.name}`;

    if (!APPLY) {
      console.log(`  [dry] ${SOURCE_BUCKET}/${sourcePath} → ${TARGET_BUCKET}/${file.name}`);
      copied++;
      continue;
    }

    try {
      // 2. Baixa do bucket de origem
      const { data: blob, error: dlError } = await supabase.storage
        .from(SOURCE_BUCKET)
        .download(sourcePath);
      if (dlError) throw new Error(`download: ${dlError.message}`);

      const buffer = Buffer.from(await blob.arrayBuffer());

      // 3. Sobe no bucket de destino (upsert para ser reexecutável)
      const { error: upError } = await supabase.storage
        .from(TARGET_BUCKET)
        .upload(file.name, buffer, {
          contentType: file.metadata?.mimetype ?? 'image/webp',
          upsert: true,
        });
      if (upError) throw new Error(`upload: ${upError.message}`);

      copied++;
      process.stdout.write(`\r  copiados: ${copied}/${files.length}`);
    } catch (e) {
      failures.push({ file: file.name, error: e.message });
    }
  }

  if (APPLY) process.stdout.write('\n');

  // 4. Reaponta users.avatar_url para a nova URL
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, avatar_url')
    .like('avatar_url', `%/${SOURCE_BUCKET}/${SOURCE_PREFIX}/%`);

  if (usersError) {
    console.error('Erro ao ler users:', usersError.message);
    process.exit(1);
  }

  console.log(`\n${users.length} usuários com avatar_url apontando para ${SOURCE_BUCKET}`);

  let updated = 0;
  for (const user of users) {
    const fileName = user.avatar_url.split('/').pop().split('?')[0];
    const { data: pub } = supabase.storage
      .from(TARGET_BUCKET)
      .getPublicUrl(fileName);
    const newUrl = pub.publicUrl;

    if (!APPLY) {
      console.log(`  [dry] ${user.id}: → ${newUrl}`);
      updated++;
      continue;
    }

    const { error } = await supabase
      .from('users')
      .update({ avatar_url: newUrl })
      .eq('id', user.id);

    if (error) {
      failures.push({ file: `users/${user.id}`, error: error.message });
    } else {
      updated++;
    }
  }

  // 5. Relatório
  console.log('\n─────────────────────────────');
  console.log(`  arquivos copiados : ${copied}`);
  console.log(`  avatar_url ajustados: ${updated}`);
  console.log(`  ignorados         : ${skipped}`);
  console.log(`  falhas            : ${failures.length}`);
  if (failures.length) {
    console.log('\nFalhas:');
    for (const f of failures) console.log(`  - ${f.file}: ${f.error}`);
  }
  if (!APPLY) {
    console.log('\nDry-run. Reexecute com --apply para efetivar.');
  } else {
    console.log(
      '\nOs objetos antigos em chat-media/avatars/ foram mantidos.\n' +
        'Confirme que as fotos aparecem no app e só então apague-os.',
    );
  }
}

main().catch((e) => {
  console.error('Erro inesperado:', e);
  process.exit(1);
});
