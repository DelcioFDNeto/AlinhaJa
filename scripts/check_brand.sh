#!/usr/bin/env bash
# ============================================================
# check_brand.sh — guard contra vazamento de marca entre os forks
#
# Fluxy (Shineray by Sabel) e AlinhaJá (DuBairro) são o mesmo código com
# deployments distintos, sincronizados por overlay/patch. Cada sync é uma
# chance de a marca de um vazar para o outro — e isso já aconteceu: o bot
# do AlinhaJá passou meses dizendo a colaborador do DuBairro que ele
# trabalhava na Shineray, porque o nome da empresa estava hardcoded no
# prompt e não constava do mapa de rebrand.
#
# Este script descobre a marca DESTE repositório a partir de
# AppConstants.appName e falha se encontrar qualquer token da marca oposta
# no código que vai para produção.
#
# Uso:
#   bash scripts/check_brand.sh
#
# Para permitir uma menção legítima às duas marcas (documentação da
# arquitetura dual-brand):
#   • linha:   acrescente o comentário  brand-guard:allow
#   • arquivo: inclua em qualquer linha  brand-guard:allow-file
#     (reservado a arquivos que tratam de branding por definição)
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."

CONSTANTS=lib/core/constants.dart
if [ ! -f "$CONSTANTS" ]; then
  echo "check_brand: $CONSTANTS não encontrado — rode a partir da raiz do repo." >&2
  exit 2
fi

OWN=$(sed -n "s/.*static const appName = '\([^']*\)'.*/\1/p" "$CONSTANTS" | head -1)
if [ -z "$OWN" ]; then
  echo "check_brand: não consegui ler AppConstants.appName de $CONSTANTS" >&2
  exit 2
fi

# Tokens de cada marca: nome do app, empresa, package Dart e host da landing.
FLUXY_TOKENS='Fluxy|FLUXY|fluxy|Shineray|SHINERAY'
ALINHA_TOKENS='AlinhaJá|AlinhaJa|Alinhaja|ALINHAJÁ|alinha_ja|alinha-ja|alinhaja|DuBairro|Du Bairro'
# NB: 'alinha' isolado NÃO entra — é raiz do português (alinhar, alinhamento).

case "$OWN" in
  Fluxy)    FOREIGN="$ALINHA_TOKENS"; OTHER="AlinhaJá/DuBairro" ;;
  AlinhaJá) FOREIGN="$FLUXY_TOKENS";  OTHER="Fluxy/Shineray" ;;
  *) echo "check_brand: appName '$OWN' desconhecido — atualize este script." >&2; exit 2 ;;
esac

echo "check_brand: marca desta build = '$OWN'; procurando por $OTHER..."

# Diretórios que vão para produção. `landing-page/` fica de fora: é um site
# por marca, com conteúdo próprio.
TARGETS=()
for d in lib supabase/functions web/manifest.json web/index.html; do
  [ -e "$d" ] && TARGETS+=("$d")
done

# Arquivos isentos por inteiro (tratam de branding por definição).
ALLOWED_FILES=$(grep -rlE 'brand-guard:allow-file' "${TARGETS[@]}" 2>/dev/null || true)

HITS=$(grep -rnE "$FOREIGN" "${TARGETS[@]}" 2>/dev/null \
       | grep -v 'brand-guard:allow' \
       || true)

# Remove os hits vindos de arquivos isentos.
if [ -n "$ALLOWED_FILES" ]; then
  while IFS= read -r af; do
    [ -n "$af" ] && HITS=$(printf '%s\n' "$HITS" | grep -v "^${af}:" || true)
  done <<< "$ALLOWED_FILES"
fi

if [ -n "$HITS" ]; then
  echo
  echo "❌ Marca de $OTHER encontrada nesta build ($OWN):"
  echo
  echo "$HITS" | sed 's/^/   /'
  echo
  echo "Use AppConstants.appName / AppConstants.companyName (Dart) ou"
  echo "_shared/brand.ts (Edge Functions). Se a menção às duas marcas for"
  echo "intencional, acrescente o comentário 'brand-guard:allow' na linha."
  exit 1
fi

echo "✅ Nenhum vazamento de marca encontrado."
