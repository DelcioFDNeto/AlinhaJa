# Runbook de Instalação — AlinhaJá na VM do DuBairro

> Instalação do núcleo Supabase em servidor próprio, com o aplicativo servido pela nuvem.
> Executar por SSH, com a VPN conectada, **um comando por vez**.

## Parâmetros fixos deste ambiente

| Parâmetro | Valor |
| --- | --- |
| Host interno | `192.168.3.165` |
| Usuário SSH | `alinhaja` |
| Endereço público (definitivo) | `https://alinhaja-dubairro.freeddns.org` |
| IP público | `206.84.60.178` |
| Sistema | Ubuntu Server 24.04 LTS · 4 vCPU · 8 GB RAM · 250 GB |
| Aplicativo | Firebase Hosting (site dedicado do DuBairro) |
| Fuso de referência | `America/Belem` (UTC−3) |

## Convenções

- Comandos com `sudo`: rode `sudo -v` antes de colar blocos, para o prompt de senha não engolir as linhas seguintes.
- Segredos **nunca** são impressos no terminal nem passados como argumento de comando — vão direto para arquivo com permissão `600`.
- Scripts operacionais ficam em `/opt/alinhaja-ops`, separados do conteúdo baixado em `/opt/alinhaja`.

## Pré-condições antes de começar

- [ ] **Console do hipervisor acessível** — o firewall será ativado por SSH; sem console de emergência, um erro deixa a máquina inalcançável.
- [ ] Decidido qual site do Firebase Hosting servirá o DuBairro (necessário na Etapa 5).
- [ ] Credenciais de SMTP disponíveis, ou decisão consciente sobre o primeiro acesso dos 187 usuários (Etapa 14).

---

# ETAPA 0 — Reconhecimento da versão instalada

**Esta etapa não existia na primeira versão deste runbook, e a ausência dela foi um erro.** O pacote de self-hosting do Supabase mudou: há instalador próprio, variantes de proxy e um `.env` muito maior. Configurar sem conferir leva a editar arquivos que a versão instalada não usa.

```bash
cd /opt/alinhaja
echo "=== Arquivos de orquestração ==="; ls -1 docker-compose*.yml
echo "=== Instalador próprio? ===";      ls -1 setup.sh run.sh update.sh 2>/dev/null
echo "=== Versões fixadas ===";          head -40 versions.md 2>/dev/null
echo "=== Seções do CONFIG ===";         grep -n '^##\? ' CONFIG.md | head -30
echo "=== Chaves do .env ===";           grep -vE '^\s*#|^\s*$' .env | cut -d= -f1 | tr '\n' ' '
echo; echo "=== Analytics tem profile? ==="; grep -n -A4 'analytics:' docker-compose.yml | head -20
echo "=== Serviço de proxy embutido? ==="; grep -nE '^\s{2}(kong|nginx|caddy|envoy):' docker-compose.yml
```

Decisões que dependem desta saída:

| Pergunta | Consequência |
| --- | --- |
| Existe `setup.sh` funcional? | Se gerar segredos e `.env`, substitui parte das Etapas 4–5 |
| `analytics` está atrás de um `profile`? | Se sim, basta não ativar o profile — sem editar o compose (Etapa 6) |
| Há proxy embutido (nginx/caddy)? | Se sim, **não** instalar nginx no host: conflito na porta 80 (Etapa 15) |
| Postgres 15 ou 17? | As migrations foram validadas em 15; o 17 exige teste prévio |

> **Não avance sem essa saída.** As etapas seguintes assumem o layout clássico e precisam ser ajustadas se a versão instalada divergir.

---

# ETAPA 1 — Preparação do sistema

```bash
df -h /                       # confirmar ~244G após o lvextend
sudo timedatectl set-timezone America/Belem
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates jq postgresql-client-16 unattended-upgrades
```

### Docker pelo repositório oficial (com verificação de chave)

Substitui o `curl | sudo sh`, que executa script remoto como root sem validação:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
 | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker alinhaja
```

### Rotação de log do Docker

Sem isto, os logs crescem sem limite e enchem o disco — queda silenciosa e previsível:

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
JSON
sudo systemctl restart docker
```

**Encerre e reabra o SSH** para o grupo `docker` valer. Confirme com `docker ps` sem `sudo`.

---

# ETAPA 2 — Segurança do servidor

> **Ordem importa:** configure a chave SSH e teste o login por chave **antes** de ativar o firewall. Tenha o console do hipervisor à mão.

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "COLE_SUA_CHAVE_PUBLICA_AQUI" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Em **outra janela**, teste `ssh alinhaja@192.168.3.165` e confirme que entra sem senha. Só então:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status numbered
```

Troque a senha (a atual circulou em canal aberto) e guarde no cofre:

```bash
passwd
```

O banco (5432) não é liberado: fica acessível apenas dentro da rede do Docker.

---

# ETAPA 3 — Obter o pacote do Supabase

```bash
sudo mkdir -p /opt/alinhaja /opt/alinhaja-ops
sudo chown alinhaja:alinhaja /opt/alinhaja /opt/alinhaja-ops
cd /opt/alinhaja

git clone --depth 1 https://github.com/supabase/supabase
cp -r supabase/docker/* .
cp supabase/docker/.env.example .env      # explícito: o glob * NÃO copia dotfiles
rm -rf supabase
```

Conferência obrigatória — não siga sem os três OK:

```bash
test -f docker-compose.yml && echo "compose OK" || echo "compose FALTANDO"
test -f .env             && echo "env OK"     || echo "env FALTANDO"
test -d volumes          && echo "volumes OK" || echo "volumes FALTANDO"
```

---

# ETAPA 4 — Gerar os segredos sem vazamento

Segredos não são impressos no terminal (scrollback, log de sessão) nem passados como argumento (`ps`, `~/.bash_history`). Vão direto para arquivo restrito:

```bash
umask 077
SEC=/opt/alinhaja-ops/secrets.env
{
  echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
  echo "JWT_SECRET=$(openssl rand -hex 32)"
  echo "SECRET_KEY_BASE=$(openssl rand -hex 32)"
  echo "VAULT_ENC_KEY=$(openssl rand -hex 16)"
  echo "DASHBOARD_PASSWORD=$(openssl rand -hex 12)"
  echo "WEBHOOK_SECRET=$(openssl rand -hex 24)"
} > "$SEC"
chmod 600 "$SEC"
wc -l "$SEC"        # deve imprimir 6
```

### Chaves da API (anon e service_role)

O script **lê o segredo do arquivo**; nada sensível passa pela linha de comando:

```bash
cat > /opt/alinhaja-ops/genkeys.py <<'PY'
import hmac, hashlib, base64, json, time, os, sys

path = "/opt/alinhaja-ops/secrets.env"
env = dict(l.strip().split("=", 1) for l in open(path) if "=" in l)
secret = env["JWT_SECRET"]

def b64(x): return base64.urlsafe_b64encode(x).rstrip(b"=").decode()

now = int(time.time())
out = []
for role in ("anon", "service_role"):
    hdr = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    pay = b64(json.dumps({"role": role, "iss": "supabase", "iat": now,
                          "exp": now + 60*60*24*365*10}, separators=(",", ":")).encode())
    sig = b64(hmac.new(secret.encode(), f"{hdr}.{pay}".encode(), hashlib.sha256).digest())
    out.append(f"{role.upper()}_KEY={hdr}.{pay}.{sig}")

with open(path, "a") as f:
    f.write("\n".join(out) + "\n")
print("chaves anon e service_role gravadas em", path)
PY

python3 -I /opt/alinhaja-ops/genkeys.py
grep -c '=' /opt/alinhaja-ops/secrets.env      # deve imprimir 8
```

### Registre no cofre da empresa, hoje

| Segredo | Se for perdido |
| --- | --- |
| `JWT_SECRET` | Regerar invalida a `ANON_KEY` embutida no app → **todos os 187 APKs param de funcionar** até serem reinstalados |
| `VAULT_ENC_KEY` | Dados sensíveis de RH (CPF, salário, dependentes) tornam-se irrecuperáveis |
| `POSTGRES_PASSWORD` | Perde-se o acesso administrativo ao banco |

---

# ETAPA 5 — Configurar o `.env`

Aplicação idempotente, sem edição manual e sem exibir valores:

```bash
cat > /opt/alinhaja-ops/apply_env.py <<'PY'
import re, sys

sec = dict(l.strip().split("=", 1) for l in open("/opt/alinhaja-ops/secrets.env") if "=" in l)

SITE = sys.argv[1]            # URL do app no Firebase
API  = "https://alinhaja-dubairro.freeddns.org"

vals = {
    "POSTGRES_PASSWORD": sec["POSTGRES_PASSWORD"],
    "JWT_SECRET":        sec["JWT_SECRET"],
    "ANON_KEY":          sec["ANON_KEY"],
    "SERVICE_ROLE_KEY":  sec["SERVICE_ROLE_KEY"],
    "SECRET_KEY_BASE":   sec["SECRET_KEY_BASE"],
    "VAULT_ENC_KEY":     sec["VAULT_ENC_KEY"],
    "DASHBOARD_USERNAME": "admin",
    "DASHBOARD_PASSWORD": sec["DASHBOARD_PASSWORD"],
    "API_EXTERNAL_URL":   API,
    "SUPABASE_PUBLIC_URL": API,
    "SITE_URL":            SITE,
    "ADDITIONAL_REDIRECT_URLS": SITE + "/**",
}

path = "/opt/alinhaja/.env"
txt = open(path).read()
if txt and not txt.endswith("\n"):
    txt += "\n"

for k, v in vals.items():
    if re.search(rf"^{k}=", txt, re.M):
        # lambda evita que barras invertidas no valor virem referências de grupo
        txt = re.sub(rf"^{k}=.*$", lambda m, v=v, k=k: f"{k}={v}", txt, flags=re.M)
    else:
        txt += f"{k}={v}\n"

open(path, "w").write(txt)
print("aplicadas", len(vals), "chaves em", path)
PY

python3 -I /opt/alinhaja-ops/apply_env.py "https://SITE-DO-DUBAIRRO.web.app"
chmod 600 /opt/alinhaja/.env
```

> **`SITE_URL` não é o DDNS.** É o endereço do aplicativo no Firebase — dele saem os links de recuperação de senha e de verificação de e-mail dos candidatos. Se ainda não estiver definido, **pare aqui**: configurar depois exige reiniciar a stack e reemitir convites.

SMTP é tratado na Etapa 14, como bloqueador de go-live — não como pendência menor.

---

# ETAPA 6 — Ajustar a stack para 8 GB

Conforme a saída da Etapa 0:

**Se `analytics` estiver atrás de um profile:** não ative o profile. Nada a editar.

**Se não estiver:** edite com cópia de segurança e registre a divergência:

```bash
cd /opt/alinhaja
cp docker-compose.yml docker-compose.yml.original
# remover os serviços analytics e vector, e todo depends_on que os cite
nano docker-compose.yml
docker compose config > /dev/null && echo "compose válido"
```

Consequência aceita: a aba de logs do Studio deixa de funcionar. Diagnóstico passa a ser por `docker compose logs`.

### Tuning do PostgreSQL — inclui o fuso do agendador

```bash
mkdir -p /opt/alinhaja/volumes/db/conf
cat > /opt/alinhaja/volumes/db/conf/99-alinhaja.conf <<'CONF'
shared_buffers = 2GB
effective_cache_size = 4GB
maintenance_work_mem = 512MB
work_mem = 8MB
max_connections = 100
random_page_cost = 1.1
effective_io_concurrency = 200

# Agendador: sem isto os jobs rodam em UTC
shared_preload_libraries = 'pg_cron,pg_net'
cron.database_name = 'postgres'
cron.timezone = 'America/Belem'
CONF
```

**Por que o fuso importa aqui:** o sistema agenda seis rotinas (`0 3`, `20 3`, `40 3`, `0 8`, `0 9`, `5 * * * *`) para expurgo de GPS, retenção LGPD, vencimento de documentos e alertas de RH. Elas seguem o fuso do **Postgres**, não o do sistema operacional. Sem esta linha, o alerta de RH das 9h dispara às 6h de Belém.

Confirme no `docker-compose.yml` que o serviço `db` monta `./volumes/db/conf`. Se não montar, acrescente o volume.

---

# ETAPA 7 — Subir a stack

```bash
cd /opt/alinhaja
docker compose pull
docker compose up -d
sleep 60
docker compose ps
```

Todos em `running` / `healthy`. Para qualquer serviço reiniciando em laço:

```bash
docker compose logs --tail=80 <servico>
```

Teste interno (a `ANON_KEY` vem do arquivo, não é digitada):

```bash
. /opt/alinhaja-ops/secrets.env
curl -s -o /dev/null -w "REST: %{http_code}\n" \
  http://localhost:8000/rest/v1/ -H "apikey: $ANON_KEY"
```

Esperado: `200`.

---

# ETAPA 8 — Extensões obrigatórias

Sem elas o sistema sobe e não funciona:

```bash
cd /opt/alinhaja
docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT extname FROM pg_extension
 WHERE extname IN ('pgcrypto','uuid-ossp','pg_net','pg_cron','supabase_vault');
SHOW cron.timezone;
SQL
```

As cinco extensões precisam aparecer e `cron.timezone` deve mostrar `America/Belem`. Se `pg_cron` falhar, o `shared_preload_libraries` da Etapa 6 não foi aplicado: confira a montagem do volume e reinicie o `db`.

---

# ETAPA 9 — Backup antes das migrations

**Não pule.** São cerca de 200 arquivos; uma falha no meio deixa o banco em estado intermediário, e sem este ponto de retorno a única saída é recomeçar do zero.

```bash
sudo mkdir -p /backup/alinhaja && sudo chown alinhaja:alinhaja /backup/alinhaja
cd /opt/alinhaja
docker compose exec -T db pg_dump -U postgres -d postgres \
  | gzip > /backup/alinhaja/pre-migrations-$(date +%Y%m%d-%H%M).sql.gz
ls -lh /backup/alinhaja/
```

Para restaurar, se necessário:

```bash
zcat /backup/alinhaja/pre-migrations-<carimbo>.sql.gz \
  | docker compose exec -T db psql -U postgres -d postgres
```

---

# ETAPA 10 — Aplicar as migrations

Copie `supabase/migrations` e `supabase/scripts` do repositório para `/opt/alinhaja-ops/migrations` e `/opt/alinhaja-ops/scripts` (WinSCP ou `scp`). As migrations são aplicadas em ordem, com registro do que foi aplicado:

```bash
cd /opt/alinhaja
LOG=/opt/alinhaja-ops/migrations-aplicadas.log
touch "$LOG"

for f in $(ls /opt/alinhaja-ops/migrations/*.sql | sort); do
  nome=$(basename "$f")
  grep -qx "$nome" "$LOG" && { echo "já aplicada: $nome"; continue; }
  echo ">>> $nome"
  if docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < "$f"; then
    echo "$nome" >> "$LOG"
  else
    echo "FALHOU EM: $nome — corrigir antes de continuar"
    break
  fi
done

echo "aplicadas: $(wc -l < "$LOG") de $(ls /opt/alinhaja-ops/migrations/*.sql | wc -l)"
```

O log permite **retomar de onde parou** sem reaplicar o que já passou. Conferência:

```bash
docker compose exec -T db psql -U postgres -d postgres -c "
SELECT count(*) AS tabelas  FROM information_schema.tables WHERE table_schema='public';
SELECT count(*) AS policies FROM pg_policies WHERE schemaname='public';
SELECT jobname, schedule FROM cron.job ORDER BY jobname;"
```

Devem aparecer os seis jobs agendados.

### Remover a estrutura herdada da Shineray

Migrations antigas, herdadas do Fluxy, semeiam filiais, departamentos, cargos e canais de concessionária da Shineray. Numa instalação nova eles precisam sair **agora**, antes de qualquer dado do DuBairro: a limpeza remove registros por nome (inclusive nomes genéricos, como "Matriz"), e só é segura enquanto o banco não tem dados do cliente.

```bash
cd /opt/alinhaja
S=/opt/alinhaja-ops/scripts
docker compose exec -T db psql -U postgres -d postgres -f - < $S/01_verificar_dados_shineray_dubairro.sql
docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < $S/02_limpar_legado_shineray_dubairro.sql
docker compose exec -T db psql -U postgres -d postgres -f - < $S/01_verificar_dados_shineray_dubairro.sql
```

A verificação final deve voltar sem linhas. Os scripts só apagam registros sem usuários, cards ou mensagens vinculados.

---

# ETAPA 11 — Segredos do Vault

As funções `get_edge_base_url()` e `get_webhook_secret()` leem do **Vault do Postgres**, não de variável de ambiente. Sem estes registros, notificações push, assistente de IA e automações de RH falham **sem erro visível**.

```bash
cd /opt/alinhaja
. /opt/alinhaja-ops/secrets.env
docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -v wh="$WEBHOOK_SECRET" <<'SQL'
SELECT vault.create_secret('http://kong:8000/functions/v1', 'edge_base_url');
SELECT vault.create_secret(:'wh', 'webhook_secret');
SELECT name FROM vault.secrets ORDER BY name;
SQL
```

O endereço é **interno** (`kong:8000`), então os gatilhos funcionam mesmo antes da publicação externa.

---

# ETAPA 12 — Publicar as Edge Functions

Copie as pastas de `supabase/functions` para `/opt/alinhaja/volumes/functions/` — **12 funções mais a biblioteca `_shared`**, que é obrigatória: as funções importam `../_shared/cors.ts` e `../_shared/brand.ts`, e sem ela nenhuma inicia.

```
ai-chatbot · get-agora-token · rh-automations · rh-candidatura
rh-extract-cv · rh-gerar-questoes · send-2fa-code · send-call-notification
send-chat-notification · send-module-notification · send-workflow-notification
webhook-receiver · _shared
```

> **Dependência de internet no primeiro uso:** `get-agora-token` importa `npm:agora-token@2.0.3` e as funções de notificação importam `npm:google-auth-library@9.6.3`. O runtime baixa esses pacotes na primeira execução. Se a saída da VM estiver bloqueada, as funções falham só quando forem chamadas — não na subida.

```bash
cd /opt/alinhaja
docker compose restart functions
docker compose logs --tail=40 functions
```

Teste de vida da função:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/functions/v1/webhook-receiver
```

**Esperado: `401`** — a função exige o cabeçalho de secret e rejeita a chamada. O 401 prova que o runtime carregou e executou o código. Um `404` indicaria função não encontrada; `500`, erro de carregamento.

---

# ETAPA 13 — Áreas de armazenamento

```bash
cd /opt/alinhaja
docker compose exec -T db psql -U postgres -d postgres -c \
 "SELECT id, public, file_size_limit FROM storage.buckets ORDER BY id;"
```

Devem existir quatro: `avatars`, `chat-media`, `rh-curriculos`, `rh-documentos`.

Para os que faltarem (ajuste o limite conforme o bucket):

```bash
docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('rh-curriculos','rh-curriculos', false,  5242880)
ON CONFLICT (id) DO NOTHING;
SQL
```

As políticas de acesso vêm das migrations. Confirme que existem antes de prosseguir:

```bash
docker compose exec -T db psql -U postgres -d postgres -c \
 "SELECT count(*) AS policies_storage FROM pg_policies WHERE schemaname='storage';"
```

Se retornar `0`, alguma migration de storage não foi aplicada — volte à Etapa 10.

---

# ETAPA 14 — Organização, administrador e primeiro acesso

### Criar o tenant

Use `supabase/scripts/seed_demo_tenant.sql` como modelo, trocando:

| No script | Para |
| --- | --- |
| Nome da organização | `DuBairro Supermercados` |
| Slug | `dubairro` |
| E-mail do admin | E-mail real do administrador indicado pelo cliente |
| Senha inicial | Gerada e entregue por canal seguro |
| Módulos habilitados | Conforme contrato |

### Definir o administrador principal

Nenhuma conta nasce administradora: o cadastro cria contas bloqueadas, à espera de aprovação. O administrador principal é definido aqui, de forma explícita e registrada na auditoria. A conta precisa existir antes (criada pelo script acima, pelo painel do Supabase ou por convite):

```bash
cd /opt/alinhaja
docker compose exec -T db psql -U postgres -d postgres \
  -v email=<e-mail do administrador> \
  -f - < /opt/alinhaja-ops/scripts/promover_super_admin.sql
```

A mensagem esperada é `Usuário … promovido a super_admin`. Repita para um segundo administrador, para que a empresa nunca dependa de uma única pessoa.

Depois, preencher os **dados legais** pelo painel administrativo. Quatro campos continuam pendentes com o cliente: endereço da sede, Encarregado (DPO), e-mail do Encarregado e data de vigência.

### Primeiro acesso dos 187 usuários — bloqueador de go-live

O caminho normal é o provisionamento pelo administrador (o cadastro pelo aplicativo existe, mas cria contas bloqueadas até aprovação), e o usuário precisa receber a senha ou um link de definição. **Sem SMTP configurado não há envio de convite nem recuperação de senha.**

Três caminhos possíveis, a decidir **antes** da carga de usuários:

| Caminho | Implicação |
| --- | --- |
| SMTP do cliente configurado no `.env` | Fluxo normal: convite e recuperação por e-mail |
| Senha inicial padronizada, troca no primeiro acesso | Dispensa SMTP no go-live, mas exige distribuição controlada e força a troca |
| Go-live adiado até o SMTP existir | Mais seguro, menos prático |

Enquanto não houver decisão, **não execute a carga dos 187 usuários** — contas criadas sem caminho de acesso geram chamado em massa no primeiro dia.

---

# ETAPA 15 — Proxy reverso e TLS

> **Depende da Etapa 0.** Se o pacote trouxer proxy embutido (nginx/caddy/envoy) em uso, **não** instale nginx no host — haverá conflito na porta 80 e o certificado não será emitido. Nesse caso, configure o proxy do próprio pacote.

Para o cenário sem proxy embutido:

```bash
sudo apt install -y nginx certbot python3-certbot-nginx

sudo tee /etc/nginx/sites-available/alinhaja >/dev/null <<'NGINX'
server {
    listen 80;
    server_name alinhaja-dubairro.freeddns.org;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/alinhaja /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

As diretivas `Upgrade`/`Connection` sustentam o **WebSocket do chat em tempo real**. Sem elas as mensagens só aparecem ao recarregar a tela — sintoma que demora a ser diagnosticado.

**Quando a porta 80 for liberada no firewall do cliente:**

```bash
sudo certbot --nginx -d alinhaja-dubairro.freeddns.org
sudo systemctl status certbot.timer
sudo certbot renew --dry-run          # valida a renovação automática
```

O `--dry-run` é o que garante que o certificado não vai expirar em 90 dias sem aviso.

---

# ETAPA 16 — Backup confiável

Backup que não é verificado não é backup. Este script **valida o dump antes de aceitá-lo** e só rotaciona os antigos se o novo for íntegro:

```bash
cat > /opt/alinhaja-ops/backup.sh <<'SH'
#!/bin/bash
set -euo pipefail

DEST=/backup/alinhaja
STAMP=$(date +%Y%m%d-%H%M)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd /opt/alinhaja

# 1. Dump
docker compose exec -T db pg_dump -U postgres -d postgres | gzip > "$TMP/db-$STAMP.sql.gz"

# 2. Validação: precisa descomprimir e conter o marcador final do pg_dump
gzip -t "$TMP/db-$STAMP.sql.gz"
zcat "$TMP/db-$STAMP.sql.gz" | tail -5 | grep -q "PostgreSQL database dump complete" \
  || { echo "ERRO: dump incompleto, backup abortado"; exit 1; }

# 3. Só move para o destino depois de validado
mv "$TMP/db-$STAMP.sql.gz" "$DEST/"
tar czf "$DEST/storage-$STAMP.tar.gz" volumes/storage

# 4. Rotação ocorre apenas após um backup válido
find "$DEST" -name "*.gz" -mtime +14 -delete

date -Iseconds > "$DEST/.last-success"
echo "backup concluído: $STAMP"
SH

chmod +x /opt/alinhaja-ops/backup.sh
/opt/alinhaja-ops/backup.sh          # primeira execução manual
```

Agendamento diário às 02:00:

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/alinhaja-ops/backup.sh >> /var/log/alinhaja-backup.log 2>&1") | crontab -
```

### Monitoramento do backup

O arquivo `.last-success` permite detectar falha silenciosa. Verificação semanal:

```bash
find /backup/alinhaja/.last-success -mtime +1 && echo "ALERTA: backup sem sucesso há mais de 24h"
```

> **Pendência com o cliente:** o diretório `/backup` está no mesmo disco dos dados. Isso protege contra erro lógico, **não** contra falha de hardware. Solicitar ao Edmilson um destino externo — segundo disco, compartilhamento de rede ou cópia para o storage corporativo.

### Teste de restauração

Antes do go-live, restaurar um dump em banco separado e conferir contagem de tabelas e de políticas. Backup não testado é suposição.

---

# ETAPA 17 — Resiliência a reinício

Supermercado tem queda de energia. O sistema precisa voltar sozinho.

```bash
cd /opt/alinhaja
grep -c "restart:" docker-compose.yml          # todos os serviços devem ter política
docker compose ps --format "table {{.Service}}\t{{.Status}}"
```

Se algum serviço não tiver `restart: unless-stopped`, acrescente. Depois, **teste de verdade**:

```bash
sudo reboot
```

Reconecte após dois minutos e confirme:

```bash
cd /opt/alinhaja && docker compose ps
. /opt/alinhaja-ops/secrets.env
curl -s -o /dev/null -w "REST após reboot: %{http_code}\n" \
  http://localhost:8000/rest/v1/ -H "apikey: $ANON_KEY"
```

Esperado: todos `running` e `200`. Este teste deve ser feito **antes** do go-live, não depois do primeiro apagão.

---

# ETAPA 18 — Pendências do firewall do cliente

Quando o Edmilson liberar:

- [ ] `443/tcp` → `192.168.3.165:443`
- [ ] `80/tcp` → `192.168.3.165:80`
- [ ] Emitir o certificado (Etapa 15) e validar com `certbot renew --dry-run`
- [ ] Testar **de fora, com a VPN desconectada**:
      `curl -I https://alinhaja-dubairro.freeddns.org/rest/v1/`
- [ ] Compilar a build do aplicativo apontando para o DDNS
- [ ] Testar login de um celular em **rede móvel**, fora da rede do DuBairro
- [ ] Testar envio e recebimento de mídia (exercita o Storage pelo link do cliente)

---

# Riscos aceitos e decisões registradas

| Item | Decisão | Consequência assumida |
| --- | --- | --- |
| 8 GB de RAM | Aceito pelo cliente | Analytics desligado; ampliação para 16 GB em 24h se o monitoramento pedir |
| DDNS gratuito | Escolhido pelo cliente | Disponibilidade do sistema depende de serviço gratuito de terceiro |
| Backup no mesmo disco | Temporário | Não protege contra falha de hardware — destino externo pendente |
| Analytics removido | Necessário com 8 GB | Aba de logs do Studio indisponível |
| Hospedagem na rede do cliente | Escolha do cliente | Link e energia do DuBairro são ponto único de falha para os 187 usuários |

---

# Pendências de segurança a encerrar

- [ ] Trocar a senha da VM (Etapa 2)
- [ ] Trocar a senha da VPN
- [ ] Reemitir o certificado da VPN (a chave privada circulou em grupo de WhatsApp)
- [ ] Mover `secrets.env` para cofre corporativo e remover da VM após a instalação
- [ ] Registrar os segredos com acesso a mais de uma pessoa

---

# Validação antes do go-live

- [ ] Etapa 0 executada e divergências de versão tratadas
- [ ] Todas as migrations aplicadas (`wc -l` do log igual à quantidade de arquivos)
- [ ] Estrutura herdada da Shineray removida (Etapa 10, verificação final sem linhas)
- [ ] Administrador principal definido pelo script (Etapa 14)
- [ ] Seis jobs do `pg_cron` agendados, com `cron.timezone = America/Belem`
- [ ] Dois segredos no Vault (`edge_base_url`, `webhook_secret`)
- [ ] Doze funções respondendo (teste de vida = 401 na `webhook-receiver`)
- [ ] Quatro buckets com políticas aplicadas
- [ ] Backup executado, validado e **restaurado em teste**
- [ ] Reboot testado, stack sobe sozinha
- [ ] Certificado emitido e `renew --dry-run` aprovado
- [ ] Acesso testado de rede móvel, fora da rede do cliente
- [ ] Caminho de primeiro acesso dos 187 usuários definido (Etapa 14)
