# Supabase - Scripts SQL

## Fluxo Atual

As migrations ficam em `supabase/migrations/` e devem ser aplicadas em ordem pelo Supabase CLI:

```powershell
npx supabase migration list
npx supabase db push
```

Para ambiente local, `supabase/seed.sql` cria usuarios de teste e chama `public.seed_base_workflow_channels(TRUE, TRUE)` para popular os canais operacionais atuais.

## Funcoes Unificadas

A migration `20260512180000_unified_workflow_channel_seed.sql` concentra a logica de seed/reset:

| Funcao | Uso |
|--------|-----|
| `public.seed_base_workflow_channels(reset_statuses, preserve_operator_config)` | Cria/atualiza os 5 canais base, membros e status de workflow atuais |
| `public.reset_operational_data(reseed_channels)` | Limpa dados transacionais e, opcionalmente, chama o seed dos canais |

Essas funcoes ficam restritas para uso administrativo/service role. Nao sao RPCs de produto para usuario final.

## Scripts Manuais

| Arquivo | Descricao |
|---------|-----------|
| `scripts/create_base_channels.sql` | Reaplica o seed dos canais base preservando operadores configurados |
| `scripts/reset_and_seed_operational_data.sql` | Reset operacional destrutivo + reseed dos canais base |
| `scripts/promover_super_admin.sql` | Define o administrador principal de uma instalacao (ver runbook, etapa 14) |

## Canais Base

O seed atual cria estes workspaces:

- `Liberação Contas a Pagar`
- `Liberação Fat Moto`
- `Emplacamento`
- `Faturamento OS/Peças`
- `Avisos Gerais`

Todos usam metadata com `workflow_enabled`, `posting_permission`, `card_type`, `category`, `color`, `icon`, `assignment_mode`, `operator_ids`, `default_operator_id`, `operator_count` e `archived`.

Por padrao, os canais nascem em `operator_pool`, sem operadores definidos. Depois, o `super_admin` ou criador do canal decide na tela de informacoes se o canal tera operador unico ou equipe de operadores.

## Reset Operacional

O reset operacional remove dados transacionais como mensagens, canais, cards, reunioes, chamadas, notificacoes, tickets e historicos operacionais.

Ele preserva usuarios (`auth.users`, `public.users`) e estrutura organizacional. Antes de executar em banco real, confirme backup e ambiente.
