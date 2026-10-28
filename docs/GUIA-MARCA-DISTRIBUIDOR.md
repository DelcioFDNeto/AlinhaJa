# GUIA DE MARCA PARA DISTRIBUIDORES — ALINHAJÁ

**Como distribuir a plataforma com marca própria e como cada empresa cliente aplica a própria identidade**

---

## Os dois níveis de identidade

O AlinhaJá é white-label em dois níveis independentes:

| Nível | O que muda | Quem faz | Exige nova build? |
| ----- | ---------- | -------- | ----------------- |
| **Marca do produto** | Nome do app, cor-base, ícones, nome nas lojas, domínios, remetente dos e-mails | A empresa que distribui ou adquire a plataforma | Sim, uma vez por distribuição |
| **Identidade da empresa cliente** | Logo e cores de cada empresa atendida | O administrador de cada empresa, pelo painel | Não; vale na hora |

Uma mesma distribuição atende várias empresas, cada uma com o próprio logo e as próprias cores, sobre a marca do produto.

---

## Parte 1 — Marca do produto (distribuidor)

Faça estas etapas numa cópia ou branch de distribuição. O repositório principal permanece com a marca AlinhaJá.

### 1. Arquivos de build

```bash
bash scripts/aplicar_marca.sh --nome "MarcaX" --cor "#1565C0" \
     --descricao "MarcaX - Comunicação corporativa"
```

O script altera o título e o manifesto do app Web (`web/index.html`, `web/manifest.json`) e o nome do app no Android (`AndroidManifest.xml`). Nome e descrição não podem conter `<`, `>`, `&`, aspas ou barra invertida.

### 2. Nome e cor dentro do app

O nome e a cor-base são definidos na build, sem editar código:

```bash
flutter build web --dart-define=BRAND_NAME="MarcaX" \
                  --dart-define=BRAND_PRIMARY_COLOR=0xFF1565C0 \
                  --dart-define-from-file=dart_defines.json
```

- **Formato da cor:** `0xFF` seguido do código `RRGGBB`. Um valor em outro formato (por exemplo `#1565C0`) é ignorado sem aviso e a build sai com o vermelho padrão — confira a tela de login antes de publicar.
- Os mesmos parâmetros valem para `flutter build apk` e `flutter run`.
- O nome passa a aparecer em todo o app: título, menu, central de ajuda, notificações e autenticador de dois fatores.
- Os documentos legais (`docs/legal/`) foram escritos com o nome AlinhaJá e aprovados assim. O app troca o nome pelo da marca na hora de exibir, sem editar o texto aprovado.

### 3. Logos e ícones

| Arquivo | Uso |
| ------- | --- |
| `assets/images/logo.png` | Ícone do app (gerado por `dart run flutter_launcher_icons`) |
| `assets/images/logo_header.png` | Logo no cabeçalho, quando a empresa não cadastrou o próprio |
| `web/icons/*.png`, `web/favicon.png` | Ícones do app Web instalado e da aba do navegador |
| `assets/images/help/shots/*.webp` | Capturas de tela da central de ajuda (mostram a marca original) |

### 4. Identificador do pacote Android

O identificador `com.alinha_ja.app` precisa ser único por distribuição na loja. Altere `applicationId` e `namespace` em `android/app/build.gradle.kts` e mova `MainActivity.kt` para o pacote correspondente. O nome interno do projeto Dart (`alinha_ja`) não aparece para o usuário e não precisa mudar.

### 5. Firebase e backend

- **Firebase próprio:** `android/app/google-services.json`, a configuração Web em `web/index.html` e `web/firebase-messaging-sw.js`, e as chaves `FIREBASE_WEB_*` do `dart_defines.json`.
- **Supabase:** endereço e chave pública no `dart_defines.json` ou, na Web, no `config.json` publicado ao lado do `index.html` (ver `docs/PLANO-EVOLUCAO-ARQUITETURA.md`).
- **Secrets das Edge Functions:**

| Secret | Uso |
| ------ | --- |
| `APP_NAME` | Nome do produto nos e-mails e no Assistente IA |
| `SENDER_NAME` | Nome do remetente dos e-mails |
| `LANDING_URL` | Site da marca; o logo dos e-mails é lido de `LANDING_URL/logo_header.webp` |
| `APP_BASE_URL` | Endereço do app Web nos links enviados por e-mail |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL` | Servidor de e-mail da distribuição |

### 6. Site de apresentação

`landing-page/src/brand.ts` concentra nome, slogan, endereço do app e logos do site. O site publica os mesmos documentos de `docs/legal/`, mas sem a troca automática do nome: na distribuição, gere a cópia do site com o nome da marca.

### O que mantém o nome original, de propósito

- O prefixo das salas de videoconferência (`AlinhaJá_<sala>`): é identificador técnico; trocá-lo faria versões diferentes do app entrarem em salas diferentes da mesma reunião.
- Nomes internos de pacote, migrations e comentários de código — não aparecem para o usuário.

---

## Parte 2 — Identidade da empresa cliente (administrador)

No app, **Painel Administrativo → Identidade Visual**:

1. **Logo:** PNG, JPG ou WebP, de preferência horizontal e com fundo transparente. O app converte para WebP e limita a 2 MB.
2. **Cor principal:** barras, botões, ícones e destaques. Escolha da paleta ou informe o código `#RRGGBB`.
3. **Cor secundária:** opcional, para detalhes de apoio.
4. Confira a **prévia** — ela usa o mesmo tema que o app aplica — e salve.

- A aba aparece para o perfil Super Admin; outros perfis podem recebê-la pela gestão de acessos, mas só administradores conseguem salvar.
- O app avisa quando a cor escolhida compromete a leitura (texto sobre a cor ou a cor sobre fundo branco). O aviso não impede a gravação.
- Cada alteração fica registrada na auditoria (`org.identity_changed`).
- Quem escolheu outro esquema de cores em **Configurações** mantém a própria escolha.
- O dono da plataforma, atuando por uma empresa, edita a identidade dela pela mesma aba.

---

## Conferência antes de publicar uma distribuição

- [ ] Login e menu exibem o nome e a cor da marca
- [ ] Aba do navegador e app Web instalado mostram o nome e o ícone da marca
- [ ] Nome do app no Android correto e identificador do pacote próprio
- [ ] E-mail de verificação (2FA) chega com o nome, o remetente e o logo da marca
- [ ] Assistente IA se apresenta com o nome da marca e o nome da empresa do usuário
- [ ] Uma empresa de teste com logo e cor próprios aparece corretamente após salvar

*AlinhaJá — Guia de Marca para Distribuidores.*
