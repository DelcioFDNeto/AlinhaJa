# PLANO DE EVOLUÇÃO DA ARQUITETURA — ALINHAJÁ

**Diagnóstico de rigidez e caminho para uma plataforma configurável por cliente**

---

## Resumo

O AlinhaJá é funcionalmente completo, e a escolha de stack (Flutter + Supabase) não é o que o torna rígido. A rigidez vem de **onde as coisas que variam por cliente foram colocadas**: endereço do servidor, marca, cores, nome da empresa e fornecedores estão no código ou na compilação, e não em configuração. Por isso cada cliente novo, cada instalação no servidor do cliente e cada marca exigem build, fork ou edição de código.

Um segundo fator agrava o primeiro: até esta entrega, **não havia nenhuma verificação automática**. Sem rede de proteção, toda mudança estrutural parecia arriscada, e a resposta natural da equipe foi evitar mexer. Um exemplo encontrado nesta análise: a geração de questões técnicas por IA do RH está quebrada desde 30/07/2026 porque uma função referencia uma variável inexistente. Uma checagem de tipos teria acusado o erro no mesmo dia.

A recomendação é **manter a stack** e mudar a organização, em fases curtas e independentes, sob um princípio único:

> **Um código, uma build por plataforma, quantas implantações forem necessárias. Tudo o que varia por cliente é dado, não código.**

A Fase 0 (base de segurança e configuração) já foi executada nesta entrega e está descrita na seção 3.

### Posicionamento dos dois produtos

Todas as recomendações deste plano partem desta distinção:

| Produto | Natureza | Consequência para a arquitetura |
| ------- | -------- | ------------------------------- |
| **Fluxy** | Exclusivo da Shineray by Sabel: uma única empresa, com marca, implantação e banco próprios | Nunca compartilha banco, nuvem, dados ou marca com o AlinhaJá. Recursos desenvolvidos para a Shineray só chegam a outros clientes por decisão expressa |
| **AlinhaJá** | White-label multiempresa, disponível para distribuição ou aquisição por outras empresas | Tudo o que identifica quem usa precisa ser configurável — inclusive o nome do próprio produto, para quem o adquirir ou distribuir sob marca própria |

---

## 1. Diagnóstico

| # | Ponto de rigidez | Evidência no código | Efeito no negócio |
| - | ---------------- | ------------------- | ----------------- |
| 1 | **Duas linhas de código divergentes** (Fluxy e AlinhaJá) sincronizadas à mão | Branches `Fluxy`/`Fluxy-dev` e `Alinhaja`/`Alinhaja-dev` no mesmo repositório, com 113 e 50 commits exclusivos em cada linha de desenvolvimento; `scripts/check_brand.sh` existe só para impedir vazamento de marca entre elas; `CONTEXT.md` traz 52 menções a porte/paridade, inclusive uma diretiva proibindo portar uma migration específica (seção 31) | Cada recurso comum é feito duas vezes; defeitos viajam junto com os portes (o da geração de questões veio do commit `e02a399`, "port … from Fluxy", e está nas quatro branches); no modelo atual, cada empresa que distribuir o AlinhaJá com marca própria seria mais uma linha a sincronizar. **Resolvido em 28/10/2026:** repositórios separados (Fase 1) |
| 2 | **Servidor definido na compilação** | `AppEnv` lia apenas `--dart-define` e `.env` (`lib/core/config/app_env.dart`) | Instalação no servidor do cliente exigia uma build exclusiva; no celular, continua exigindo um APK por servidor |
| 3 | **Marca e identidade em constantes** | `AppConstants.appName`, `companyName = 'DuBairro'` e `primary` em `lib/core/constants.dart`; 52 usos de `AppConstants.primary` e 935 de `Colors.*` na interface; apenas dois esquemas visuais fixos (`theme_provider.dart`) | Para um produto white-label, é o ponto comercial mais sensível: quem adquire ou distribui o AlinhaJá espera trocar nome, logo e cores sem desenvolvimento, e hoje cada marca exige alteração de código e nova build. A personalização por empresa prometida na documentação comercial também não é viável sem código. O Assistente IA dizia a funcionários de **qualquer** empresa que trabalhavam no DuBairro (corrigido nesta entrega) |
| 4 | **Telas falando direto com o banco** | 93 arquivos chamam o Supabase diretamente, 43 deles telas (`ui/`); 519 chamadas a 94 tabelas e 120 funções; 30 arquivos com mais de 800 linhas (`workflow_main_view.dart` tem 2.535) | Alterar uma tabela obriga a caçar telas; testar uma tela exige um Supabase real; arquivos grandes concentram conflito de edição |
| 5 | **Regra de negócio dividida entre app, SQL e functions** | 197 migrations (+44 legadas), 432 funções SQL, 91 triggers, 369 políticas; 16 migrations disparam Edge Functions por HTTP a partir do banco | Uma instalação nova reexecuta 197 scripts em ordem; o comportamento de um fluxo só se entende lendo três camadas |
| 6 | **Fornecedores presos no código** | `smtp.gmail.com` fixo em 4 functions (corrigido); dois caminhos de IA (Groq global no assistente, chave própria da empresa no RH); dois stacks de vídeo (Agora e MiroTalk); reuniões em grupo no **servidor público** `sfu.mirotalk.com`; mapas no servidor público do OpenStreetMap | Trocar de provedor exige alterar código em vários pontos; reuniões corporativas trafegam por um servidor de demonstração de terceiros, sem contrato — ponto de atenção para a LGPD |
| 7 | **Sem rede de proteção** | Nenhum pipeline de CI; versão do Flutter não registrada (o `pubspec.lock` só bate com a 3.41.x); 10 dos 43 arquivos de teste verificam texto do código-fonte, e não comportamento | Defeitos chegam à produção sem aviso; o medo de regressão trava refatorações |
| 8 | **Configuração por empresa sem contrato** | `organizations.settings` é um JSON livre com chaves lidas separadamente em SQL e em Dart (`modules`, `legal`, `ai_provider`, `msg_retencao_dias`, `backup_*`…) | Não há validação nem lugar único para saber o que uma empresa pode configurar; o Console de Plataforma só alterna módulos |

### O que não é problema

- **Flutter e Supabase** são escolhas adequadas. O Supabase ser de código aberto e auto-hospedável é exatamente o que permitiu a instalação na VM do DuBairro; trocar de stack custaria meses e não resolveria nenhum dos oito pontos acima.
- **A segurança no banco (RLS)** é um ponto forte e deve continuar lá. O objetivo da Fase 4 é organizar a camada SQL, não esvaziá-la.
- **O registro de módulos** (`lib/core/modules/module_registry.dart`) já segue o princípio certo: navegação, rotas, permissões e notificações derivam de uma lista única. É o modelo para o restante.

---

## 2. Onde cada variação deve morar

| Camada | O que varia | Onde passa a morar |
| ------ | ----------- | ------------------ |
| **Implantação** (onde roda) | endereço do Supabase, chaves públicas, domínio do app, servidor de e-mail | `config.json` publicado junto do app Web; Secrets das Edge Functions |
| **Empresa** (tenant) | nome, logo, cores, módulos, retenções, provedor de IA, SMTP próprio | tabela `organizations`, com campos tipados e editáveis no Console de Plataforma |
| **Produto** (marca) | Fluxy (exclusivo da Shineray), AlinhaJá e a marca de cada empresa que distribuir o AlinhaJá: nome do app, ícone, identificador do pacote, domínios, recursos habilitados | Fluxy em repositório próprio; no AlinhaJá, perfil de marca escolhido na build (flavor) e na implantação, sobre **o mesmo código** |

---

## 3. Fase 0 — Executada nesta entrega

As alterações foram feitas no AlinhaJá. Em 28/10/2026, as que valem para o Fluxy — geração de questões, módulo de e-mail, erros de tipo, senha da conta de sistema e CI — foram aplicadas também na `Fluxy-dev`.

| Item | O que mudou | Onde |
| ---- | ----------- | ---- |
| **Assistente IA por empresa** | O prompt usa o nome da organização da conversa (`organizations.name`), não mais o nome fixo do deployment. Antes, o colaborador de qualquer cliente ouvia que trabalhava no DuBairro | `supabase/functions/ai-chatbot/index.ts` |
| **Configuração em tempo de execução** | O app Web lê `config.json` ao lado do `index.html` antes de iniciar. O mesmo build atende a nuvem e o servidor do cliente; arquivo ausente ou inválido mantém os valores do build | `lib/core/config/runtime_config*.dart`, `app_env.dart`, `main.dart`, `main_admin.dart` |
| **Endereços fixos removidos** | Link de redefinição de senha e página de carreiras usam `AppEnv.appBaseUrl` (configurável; na Web, a própria origem). Antes, a redefinição de senha da Web sempre levava ao domínio de produção da nuvem | `login_screen.dart`, `careers_link_panel.dart` |
| **E-mail independente de provedor** | Um módulo único substitui quatro cópias do cliente SMTP presas ao Gmail. Aceita Office 365, SES ou o SMTP interno do cliente por `SMTP_HOST/PORT/USER/PASSWORD`; `GMAIL_*` continua valendo | `supabase/functions/_shared/mailer.ts` e as 4 functions de e-mail |
| **Endereço do app nas functions** | `APP_BASE_URL` centralizado; o valor padrão do portal do candidato apontava para um domínio inexistente (`alinha-ja.web.app`) | `_shared/brand.ts`, `rh-candidatura` |
| **Geração de questões por IA** | Corrigido o `ReferenceError` que derrubava toda resposta da function desde 30/07 | `rh-gerar-questoes/index.ts` |
| **Pipeline de CI** | A cada push: análise e testes do app (Flutter fixado em 3.41.9, compatível com o `pubspec.lock`), checagem de tipos e testes das 12 Edge Functions, guarda de marca | `.github/workflows/ci.yml` |

**Validação executada:** `flutter analyze` sem apontamentos no projeto inteiro; 401 testes do app aprovados (inclusive os novos de configuração); checagem de tipos das 12 Edge Functions sem erros (5 erros de tipo preexistentes corrigidos); 6 testes novos do módulo de e-mail aprovados; guarda de marca aprovada. O build Web de produção foi aberto no navegador em três cenários: com `config.json`, o app se conectou ao servidor indicado no arquivo; sem o arquivo (404) e com a resposta HTML que o Firebase Hosting devolve para rotas inexistentes, manteve o servidor do build. No GitHub, o CI passou nos três jobs (app, Edge Functions e guarda de marca).

### Limpeza de segurança (28/10/2026)

| Item | O que mudou |
| ---- | ----------- |
| **Conta mestre** | `handle_new_user()` promovia a super_admin ativo quem se cadastrasse com um e-mail fixo, em toda instalação e com cadastro aberto. A regra saiu (`20261028120000`); contas existentes não mudam. O primeiro administrador passa a ser definido na instalação por `supabase/scripts/promover_super_admin.sql`, com registro na auditoria |
| **Conta de sistema** | Era semeada com senha escrita no código. O seed usa senha aleatória e `20261028120100` troca a original apenas se a conta ainda estiver bloqueada |
| **Dados de outros clientes** | Saíram os seeds com nome, e-mail, cargo e senha padrão de funcionários da Shineray. Os scripts com dados pessoais de funcionários do DuBairro não vieram para este repositório |
| **Script obsoleto** | `recover_user_data.sql` usava papéis inexistentes: se executado, derrubava todo cadastro |
| **Credencial** | `run_seed.js` tinha a senha do banco DEV no código; agora lê `DATABASE_URL` |
| **Estrutura herdada** | Migrations antigas semeiam filiais, cargos e canais da concessionária. O runbook remove esses registros logo após as migrations, antes de qualquer dado do cliente; a consolidação definitiva é a migration de base (Fase 4) |
| **Repositório** | Este repositório começou com histórico limpo. `test/sem_contas_fixas_test.dart` impede a volta de contas fixas, senhas em código e dados da Shineray |

### Como usar a configuração em tempo de execução

Publicar, ao lado do `index.html` da implantação, um arquivo `config.json`:

```json
{
  "SUPABASE_URL": "https://supabase.cliente.com.br",
  "SUPABASE_ANON_KEY": "chave pública (anon) do Supabase do cliente",
  "APP_BASE_URL": "https://app.cliente.com.br"
}
```

- Prioridade: `config.json` → `--dart-define` → `.env`.
- No Firebase Hosting, copiar o arquivo para `build/web/` antes do `firebase deploy`. O cabeçalho sem cache já está configurado em `firebase.json`.
- O arquivo é público por natureza (como o próprio app): **apenas** chaves públicas. Nunca a `service_role`.
- No celular o arquivo não se aplica; ver Fase 4.

---

## 4. Roteiro das próximas fases

Tamanhos: **P** até 1 semana · **M** 2 a 4 semanas · **G** mais de um mês (uma pessoa). Cada fase entrega valor sozinha e pode ser interrompida sem deixar o sistema pela metade.

### Fase 1 — Dois repositórios independentes · executada em 28/10/2026

Como o AlinhaJá pode ser distribuído ou vendido, o Fluxy não deve depender de código que possa mudar de dono. Os produtos ficam em repositórios separados:

| Produto | Repositório | Linhas |
| ------- | ----------- | ------ |
| **AlinhaJá** (white-label) | `DelcioFDNeto/AlinhaJa` | `main` |
| **Fluxy** (exclusivo da Shineray) | `DelcioFDNeto/Fluxy` | `Fluxy` e `Fluxy-dev` |

1. **Sem paridade automática:** um recurso só passa de um produto para o outro por decisão explícita, o que preserva a exclusividade da Shineray.
2. **Componentes neutros por cópia**, nunca por dependência: envio de e-mail, helpers de HTML, push, CI e guarda de marca. `scripts/comparar_componentes_comuns.sh` aponta qualquer divergência entre as cópias.
3. **Branches antigas:** `Alinhaja` e `Alinhaja-dev` foram arquivadas no repositório do Fluxy como `backup/alinhaja-20261028` e `backup/alinhaja-dev-20261028` (mesmos commits). Falta apagar as originais.
4. **Pendência da separação:** apontar implantação, CI e segredos do AlinhaJá para o repositório novo.

### Fase 2 — White-label de verdade no AlinhaJá · M

O AlinhaJá precisa trocar de identidade em dois níveis, ambos sem desenvolvimento:

- **Marca de distribuição** — para quem adquirir ou distribuir o produto: nome do app, ícone, domínios, nome nas lojas e nos e-mails. Resolvido com um **perfil de marca** (`BrandProfile`: nome do app, cores-base, ícones, domínios, identificador do pacote) escolhido na build por `--dart-define=BRAND=...` e por *flavors* do Android, e com `APP_NAME`, `APP_BASE_URL` e `LANDING_URL` por implantação, que as Edge Functions já leem dos Secrets.
- **Identidade da empresa cliente** — dentro de uma distribuição, cada empresa com seu logo e suas cores:

1. Campos de identidade em `organizations` (a coluna `logo_url` já existe; acrescentar cor primária e secundária).
2. Tema montado em tempo de execução a partir da empresa do usuário, no lugar de `AppConstants.primary`.
3. Substituir `Colors.*` por *tokens* do tema de forma gradual — o projeto já tem `AlinhaStatusTokens` como modelo —, priorizando as telas mais visíveis.
4. Transformar `organizations.settings` em um contrato tipado (modelo Dart + validação no banco), editável no Console de Plataforma.

### Fase 3 — Camada de dados entre telas e banco · G, contínua

1. Para cada módulo, um repositório (`features/<modulo>/data/`) que concentra as consultas; telas e providers dependem dele via Riverpod.
2. Regra para código novo: telas não chamam o Supabase diretamente, verificada por teste no CI.
3. Começar pelos módulos que mais mudam (Workflow, Conversas, Canais). Arquivos com mais de 800 linhas são divididos quando forem tocados, não em uma reescrita única.
4. Com repositórios, os testes passam a usar implementações falsas e verificar comportamento, em vez de procurar texto no código-fonte.

### Fase 4 — Instalação e banco · M

1. **Migration de base:** consolidar as 197 migrations em um esquema único para instalações novas (o histórico permanece para as existentes), conferido pelo `scripts/verify_migrations.js`.
2. **Descoberta de servidor no celular:** no primeiro acesso, o aplicativo identifica a empresa (código ou domínio do e-mail) e obtém o endereço do servidor dela em um diretório central. Um único APK passa a atender a nuvem e os clientes com servidor próprio. Até lá, o perfil de marca da Fase 2 permite gerar o APK de um cliente a partir do mesmo código.
3. Roteiro de instalação automatizado a partir do runbook do DuBairro.

### Fase 5 — Fornecedores como adaptadores · M

1. **IA:** um módulo compartilhado de provedores (o `rh-extract-cv` já tem a base) usado pelo assistente e pelo RH, com o mesmo modelo de chave por empresa.
2. **Vídeo:** decidir entre Agora e MiroTalk. Mantido o MiroTalk, hospedar um servidor próprio (inclusive na VM do cliente) em vez do público.
3. **Mapas:** endereço do servidor de mapas configurável; o servidor público do OpenStreetMap não admite uso comercial intenso.
4. **Notificações:** manter o FCM, isolado no módulo compartilhado que já existe (`_shared/fcm.ts`).

---

## 5. Regras para novas contribuições

1. Nada que varie por cliente, empresa ou marca entra como constante no código.
2. Código novo de tela não acessa o Supabase diretamente.
3. Edge Functions novas usam os módulos compartilhados (`mailer`, `cors`, `brand`, `fcm`).
4. Alteração só é integrada com o CI verde.
5. Migrations tratam de esquema; dados de um cliente específico vão para scripts de implantação.

---

## 6. Decisões pendentes

| Decisão | Opções | Recomendação |
| ------- | ------ | ------------ |
| Dados pessoais fora do git | Armazenamento seguro para as planilhas de funcionários usadas nas importações | Definir antes da carga dos 187 usuários do DuBairro |
| Vídeo em grupo | Servidor MiroTalk próprio ou padronizar no Agora | Avaliar custo do Agora para reuniões; sem isso, servidor próprio |
| Ordem das próximas fases | 2 → 4 → 3 → 5 (sugerida) | Fase 2 primeiro: é o que torna o AlinhaJá vendável como white-label sem desenvolvimento por cliente |

*AlinhaJá — Plano de Evolução da Arquitetura. Documento interno da equipe técnica.*
