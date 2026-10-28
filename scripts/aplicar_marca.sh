#!/usr/bin/env bash
# ============================================================
# aplicar_marca.sh — prepara uma distribuição do AlinhaJá com marca própria
#
# O nome e a cor do produto dentro do app vêm da build (--dart-define). Mas
# alguns textos ficam em arquivos que o Flutter não gera: título da aba e
# manifesto do app Web, nome do app no Android. Este script troca esses
# arquivos e imprime o restante da lista (ícones, identificador do pacote,
# Firebase, Secrets) que depende de arquivos ou contas do distribuidor.
#
# Uso, numa CÓPIA ou branch de distribuição (não comite em main):
#   bash scripts/aplicar_marca.sh --nome "MarcaX" --cor "#1565C0" \
#        [--descricao "Plataforma de comunicação corporativa"]
#
# Guia completo: docs/GUIA-MARCA-DISTRIBUIDOR.md
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

NOME=""; COR=""; DESCRICAO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --nome)      NOME="${2:-}"; shift 2 ;;
    --cor)       COR="${2:-}"; shift 2 ;;
    --descricao) DESCRICAO="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $1 (use --help)" >&2; exit 2 ;;
  esac
done

if [ -z "$NOME" ] || [ -z "$COR" ]; then
  echo "Informe --nome e --cor. Ex.: --nome \"MarcaX\" --cor \"#1565C0\"" >&2
  exit 2
fi
if ! printf '%s' "$COR" | grep -Eq '^#[0-9A-Fa-f]{6}$'; then
  echo "Cor inválida: use #RRGGBB (ex.: #1565C0)." >&2
  exit 2
fi
# Aspas, <, > e & quebrariam o HTML, o JSON ou o XML editados abaixo.
if printf '%s%s' "$NOME" "$DESCRICAO" | grep -q '[<>&"\\]'; then
  echo "Nome e descrição não podem conter < > & \" ou \\." >&2
  exit 2
fi

COR=$(printf '%s' "$COR" | tr 'a-f' 'A-F')
HEX=${COR#\#}
DESCRICAO=${DESCRICAO:-"$NOME - Plataforma de Comunicação Corporativa"}

# sed -i portátil (GNU e BSD/macOS)
sedi() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
# Escapa & / e \ para o lado da substituição do sed.
esc() { printf '%s' "$1" | sed -e 's/[&/\]/\\&/g'; }
N=$(esc "$NOME"); D=$(esc "$DESCRICAO")

# ── Web ──────────────────────────────────────────────────────
sedi -e "s/<title>[^<]*<\/title>/<title>$N<\/title>/" \
     -e "s/\(name=\"apple-mobile-web-app-title\" content=\"\)[^\"]*\"/\1$N\"/" \
     -e "s/\(name=\"description\" content=\"\)[^\"]*\"/\1$D\"/" \
     web/index.html

sedi -e "s/\(\"name\": \"\)[^\"]*\"/\1$N\"/" \
     -e "s/\(\"short_name\": \"\)[^\"]*\"/\1$N\"/" \
     -e "s/\(\"theme_color\": \"\)[^\"]*\"/\1$COR\"/" \
     -e "s/\(\"description\": \"\)[^\"]*\"/\1$D\"/" \
     web/manifest.json

# ── Android ──────────────────────────────────────────────────
sedi -e "s/android:label=\"[^\"]*\"/android:label=\"$N\"/" \
     android/app/src/main/AndroidManifest.xml

echo "Arquivos atualizados:"
echo "  web/index.html, web/manifest.json, android/app/src/main/AndroidManifest.xml"
echo
echo "Gere as builds com a marca:"
echo "  --dart-define=BRAND_NAME=\"$NOME\" --dart-define=BRAND_PRIMARY_COLOR=0xFF$HEX"
echo
echo "Ainda à mão (ver docs/GUIA-MARCA-DISTRIBUIDOR.md):"
echo "  1. Substituir assets/images/logo.png e logo_header.png e rodar"
echo "     dart run flutter_launcher_icons (ícones do app)."
echo "  2. Trocar ícones e favicon de web/ (icons/, favicon.png)."
echo "  3. Definir o identificador do pacote Android (applicationId)."
echo "  4. Projeto Firebase próprio (google-services.json e config Web)."
echo "  5. Secrets das Edge Functions: APP_NAME, SENDER_NAME, LANDING_URL,"
echo "     APP_BASE_URL e o servidor de e-mail (SMTP_*)."
