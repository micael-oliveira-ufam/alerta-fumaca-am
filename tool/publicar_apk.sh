#!/usr/bin/env bash
# Coloca o APK recém-gerado (dist/) onde o servidor publicado o encontra.
#
# O servidor lê o APK da pasta montada em /srv/dist. Esta pasta costuma ser ./dist deste projeto,
# mas, se o servidor foi iniciado de OUTRA pasta (ou APK_HOST_DIR aponta para outro lugar), o APK
# gerado aqui não chegaria a ele. Por isso este script:
#   1. copia dist/ para APK_HOST_DIR (do .env ou do ambiente), se definido;
#   2. procura contêineres Docker em execução com algo montado em /srv/dist e copia para a pasta
#      de origem dessa montagem;
#   3. confere, dentro de cada contêiner, que o arquivo aparece.
# Uso: bash tool/publicar_apk.sh [pasta_extra ...]      (roda sozinho ao fim de tool/gerar_apk.sh)
set -uo pipefail
cd "$(dirname "$0")/.."

[[ -d dist ]] || { echo "Nada a publicar: dist/ não existe (rode tool/gerar_apk.sh)."; exit 1; }
shopt -s nullglob
APKS=(dist/RespirAR-Amazonas-v*.apk)
[[ ${#APKS[@]} -gt 0 ]] || { echo "Nada a publicar: nenhum dist/RespirAR-Amazonas-vX.Y.Z.apk."; exit 1; }
NOME="$(basename "${APKS[${#APKS[@]}-1]}")"
AQUI="$(cd dist && pwd -P)"

DESTINOS=("$@")
if [[ -z "${APK_HOST_DIR:-}" && -f .env ]]; then
  APK_HOST_DIR="$(grep -E '^APK_HOST_DIR=' .env | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
fi
[[ -n "${APK_HOST_DIR:-}" ]] && DESTINOS+=("$APK_HOST_DIR")

if command -v docker >/dev/null 2>&1; then
  while read -r id; do
    [[ -n "$id" ]] || continue
    src="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/srv/dist"}}{{.Source}}{{end}}{{end}}' "$id" 2>/dev/null)"
    [[ -n "$src" ]] && DESTINOS+=("$src")
  done < <(docker ps -q 2>/dev/null)
fi

declare -A VISTOS=()
copiou=0
for d in "${DESTINOS[@]}"; do
  [[ -d "$d" ]] || { echo "  (pasta inexistente, ignorada: $d)"; continue; }
  real="$(cd "$d" && pwd -P)"
  [[ -n "${VISTOS[$real]:-}" ]] && continue
  VISTOS[$real]=1
  if [[ "$real" == "$AQUI" ]]; then echo "  ok  $real (dist/ deste projeto)"; copiou=1; continue; fi
  if rm -f "$real"/RespirAR-Amazonas-v*.apk "$real"/Alerta-Fumaca-AM.apk 2>/dev/null \
     && cp dist/RespirAR-Amazonas-v*.apk dist/VERSION.txt dist/SHA256SUMS.txt "$real"/ 2>/dev/null; then
    [[ -f dist/Manual-RespirAR-Amazonas.pdf ]] && cp dist/Manual-RespirAR-Amazonas.pdf "$real"/
    echo "  ok  copiado para $real"; copiou=1
  else
    echo "  FALHOU ao copiar para $real (permissão? tente: sudo cp dist/* \"$real\"/)"
  fi
done

if command -v docker >/dev/null 2>&1; then
  while read -r id; do
    [[ -n "$id" ]] || continue
    if docker exec "$id" test -d /srv/dist 2>/dev/null; then
      if docker exec "$id" test -s "/srv/dist/$NOME" 2>/dev/null; then
        echo "  servidor $(docker inspect -f '{{.Name}}' "$id" | tr -d /): enxerga $NOME"
      else
        echo "  ATENÇÃO: servidor $(docker inspect -f '{{.Name}}' "$id" | tr -d /) NÃO enxerga $NOME em /srv/dist"
      fi
    fi
  done < <(docker ps -q 2>/dev/null)
fi

if [[ $copiou -eq 0 ]]; then
  echo "Nenhum servidor em execução foi encontrado. Suba-o na pasta do projeto (docker compose up -d --build);"
  echo "ele lê o APK de ./dist (ou de APK_HOST_DIR, se definido no .env)."
fi
exit 0
