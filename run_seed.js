const fs = require('fs');
const { Client } = require('pg');

// A conexão vem SÓ do ambiente: a senha do banco já esteve escrita aqui.
//   DATABASE_URL="postgresql://postgres:<senha>@db.<ref>.supabase.co:5432/postgres" node run_seed.js
async function runSeed() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('Defina DATABASE_URL. Nunca coloque a senha em arquivo versionado.');
    process.exit(1);
  }
  const sql = fs.readFileSync('supabase/seed.sql', 'utf8');
  const client = new Client({ connectionString });

  try {
    await client.connect();
    console.log('Connected to DEV database.');
    await client.query(sql);
    console.log('Seed executed successfully.');
  } catch (error) {
    console.error('Error executing seed:', error);
    process.exit(1);
  } finally {
    await client.end();
  }
}

runSeed();
