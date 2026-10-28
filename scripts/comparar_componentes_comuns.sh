#!/usr/bin/env bash
# ============================================================
# comparar_componentes_comuns.sh — confere os componentes neutros
#
# Os dois produtos vivem em repositórios separados e não compartilham
# código por dependência. Os poucos componentes neutros (sem marca, sem
# regra de cliente) são mantidos por CÓPIA idêntica nos dois. Este script
# aponta qualquer divergência entre as cópias.
#
# Uso, com os dois repositórios clonados lado a lado:
#   bash scripts/comparar_componentes_comuns.sh ../<outro-repositorio>
#
# Divergência não se resolve sozinha: decida qual versão é a correta,
# copie-a para o outro repositório e rode o CI dos dois.
# ============================================================
set -euo pipefail

OUTRO="${1:?Uso: bash scripts/comparar_componentes_comuns.sh <caminho do outro repositório>}"
cd "$(dirname "$0")/.."
[ -d "$OUTRO" ] || { echo "Diretório não encontrado: $OUTRO" >&2; exit 2; }

COMUNS=(
  supabase/functions/_shared/mailer.ts
  supabase/functions/_shared/mailer_test.ts
  supabase/functions/_shared/html.ts
  supabase/functions/_shared/fcm.ts
  .github/workflows/ci.yml
  scripts/check_brand.sh
  scripts/comparar_componentes_comuns.sh
)

diverge=0
for f in "${COMUNS[@]}"; do
  if [ ! -f "$f" ]; then
    echo "AUSENTE aqui:      $f"; diverge=1
  elif [ ! -f "$OUTRO/$f" ]; then
    echo "AUSENTE no outro:  $f"; diverge=1
  elif ! cmp -s "$f" "$OUTRO/$f"; then
    echo "DIFERE:            $f"; diverge=1
  fi
done

if [ "$diverge" -eq 0 ]; then
  echo "Componentes comuns idênticos (${#COMUNS[@]} arquivos)."
else
  echo "Há divergências. Escolha a versão correta e copie para o outro repositório."
  exit 1
fi
