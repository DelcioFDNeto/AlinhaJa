# Separação de dados organizacionais — Shineray (Fluxy) × DuBairro (AlinhaJá)

**Contexto:** o AlinhaJá é fork do Fluxy e herdou as migrations que semeiam a
estrutura organizacional da Shineray (concessionária). Resultado: o banco do
DuBairro (supermercado) contém filiais, departamentos, cargos e canais de
workflow da concessionária misturados aos dados `dub_*` corretos. Estes
scripts separam os dois mundos.

## Status da execução

- ✅ **06/07/2026 — Banco DuBairro limpo** (executado via MCP): removidas 25
  filiais Shineray (o TI Administrador `ti@alinhaja.com.br` estava vinculado a
  "Belém/PA" e foi reatribuído para "Corporativo" antes), 16 cargos e 4
  departamentos de concessionária, todos sem vínculos.
- ⏳ **Pendente — decisão futura:** canal "Recursos Humanos" (1 card, 1
  mensagem) mantido no workspace legado `alinha_operations`; decidir se migra
  o `metadata->>'workspace'` para um workspace próprio do DuBairro.
- ⏳ **Pendente — verificação Shineray:** o token MCP do executor não tem
  acesso ao projeto `hzvmqsgpopgfkvdxyain` (o que é bom — escopo limitado
  elimina o risco de tocar o banco errado). Um administrador com acesso deve
  rodar manualmente `Chat-BySabel-Flutter/supabase/scripts/verificar_dados_dubairro_shineray.sql`
  (somente leitura; esperado 0 linhas em todas as consultas).

## Identificação dos projetos Supabase (NÃO CONFUNDIR)

| Empresa | App | Projeto Supabase (ref) |
|---|---|---|
| DuBairro (supermercado) | AlinhaJá | `gpeemngsxvqjflasdody` |
| Shineray (concessionária) | Fluxy | `hzvmqsgpopgfkvdxyain` |

> ⚠️ **ARMADILHA CONHECIDA:** o CLI do Supabase no repositório AlinhaJá está
> linkado ao projeto da **Shineray** (`supabase/.temp/project-ref` =
> `hzvmqsgpopgfkvdxyain`). **Não use `supabase db push`/`db query` pelo CLI
> deste repo até relinkar**: `npx supabase link --project-ref gpeemngsxvqjflasdody`.

## Execução via MCP (Supabase MCP server)

A execução será feita por um agente via MCP. Regras específicas:

1. **Confirme o projeto ANTES de qualquer query**: chame `list_projects` /
   `get_project` e confira que o ref do projeto conectado bate com a tabela
   acima para o script em questão. Se o MCP estiver configurado com
   `--project-ref` fixo, verifique qual é. **Nunca assuma** — o CLI deste repo
   já apontou para o projeto errado uma vez.
2. Use `execute_sql` para os scripts. O conteúdo de cada arquivo pode ser
   enviado inteiro em uma chamada.
3. **`RAISE NOTICE` não aparece no retorno do MCP.** Os relatórios de itens
   mantidos/removidos do script 02 são invisíveis via MCP — por isso o
   fluxo obrigatório é: rodar script 01 (antes) → script 02 → script 01
   (depois) e **comparar os dois resultados** para saber o que foi removido.
4. Se a tool `execute_sql` recusar `BEGIN;`/`COMMIT;` (algumas implementações
   já envolvem tudo em transação própria), remova apenas essas duas linhas do
   script 02 — cada bloco `DO $$ ... $$` continua atômico por si só.
5. Não use `apply_migration` para estes scripts — são operações de dados
   pontuais, não schema, e não devem entrar no histórico de migrations.

## Passo a passo

### Banco DuBairro (projeto `gpeemngsxvqjflasdody`)

1. **Backup**: confirme que existe backup recente do projeto (Dashboard →
   Database → Backups) antes de executar o script 02.
2. **Verificar (somente leitura)**: execute
   [`01_verificar_dados_shineray_dubairro.sql`](01_verificar_dados_shineray_dubairro.sql)
   via `execute_sql`. **Guarde o resultado completo — é o "antes".**
3. **Limpar**: execute
   [`02_limpar_legado_shineray_dubairro.sql`](02_limpar_legado_shineray_dubairro.sql).
   - Transacional e idempotente (pode rodar 2x sem efeito colateral).
   - **Regra:** só apaga itens SEM vínculos (0 usuários / 0 cards / 0
     mensagens). Itens em uso NÃO são tocados.
4. **Conferir**: execute o script 01 de novo e compare com o "antes".
   - Itens que sumiram = removidos com sucesso.
   - Itens que permaneceram = têm vínculo real e exigem decisão humana
     (ex.: canal "Liberação Contas a Pagar" com cards — arquivar? migrar?
     manter?). **Reportar essas sobras ao final, sem agir sobre elas.**

### Banco Shineray (projeto `hzvmqsgpopgfkvdxyain`)

1. Rode (somente leitura) o script do repositório Fluxy:
   `Chat-BySabel-Flutter/supabase/scripts/verificar_dados_dubairro_shineray.sql`.
2. **Esperado: todas as consultas retornam 0 linhas.** Se retornarem algo, o
   seed do DuBairro foi executado lá por engano — **não apagar nada**;
   reportar o resultado para decisão.

## O que os scripts NÃO fazem (de propósito)

- Não mexem em usuários, mensagens, cards nem em departamentos genéricos
  compartilhados (`ti`, `financeiro`, `rh`, `administrativo`, `diretoria`) —
  o seed do DuBairro reutiliza esses registros por nome.
- Não removem canais com conteúdo (cards/mensagens); apenas reportam.
- Não alteram as migrations históricas (já aplicadas nos dois bancos).

## Prevenção de recontaminação (futuro)

- As migrations `002`, `013`, `20260427152600` e `20260512*` semeiam dados da
  Shineray. Elas **já foram aplicadas** e não rodam de novo no banco atual —
  o risco só existe ao recriar o banco do zero (`db reset`). Se isso
  acontecer, rode o script 02 logo após o reset e o seed do DuBairro
  (`seed_dubairro_employees.sql`).
- No app AlinhaJá, o fallback hardcoded de filiais da Shineray em
  `lib/features/admin/ui/tabs/user_create_tab.dart` foi substituído pelas
  unidades do DuBairro (commit correspondente a estas instruções).
