#!/usr/bin/env bash
# Sobe o servidor (PostgreSQL + API + painel + túnel Cloudflare) com Docker.
#
# Uso: bash tool/iniciar_servidor.sh
#
# Funciona no macOS (bash 3.2, BSD sed/awk) e no Linux. Na primeira execução cria o
# arquivo .env com senhas e token aleatórios gerados aqui.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v docker >/dev/null || { echo "Docker não encontrado. Instale o Docker Desktop (macOS) ou o Docker Engine (Linux)."; exit 1; }
docker info >/dev/null 2>&1 || { echo "O Docker não está rodando. Abra o Docker Desktop e tente de novo."; exit 1; }

# Troca o valor de uma variável no .env sem sed -i (a sintaxe de -i difere entre macOS e Linux).
definir_var() {
  local chave="$1" valor="$2" tmp
  tmp="$(mktemp)"
  awk -v k="$chave" -v v="$valor" '
    index($0, k "=") == 1 { print k "=" v; next }
    { print }
  ' .env > "$tmp"
  mv "$tmp" .env
}

if [[ ! -f .env ]]; then
  cp .env.example .env
  senha_db="$(openssl rand -hex 24)"
  token="$(openssl rand -hex 24)"
  definir_var POSTGRES_PASSWORD "$senha_db"
  definir_var ADMIN_TOKEN "$token"
  echo "Arquivo .env criado. ADMIN_TOKEN (guarde para o painel e a exportação CSV): $token"
fi

docker compose up -d --build

echo "Aguardando a API..."
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "API no ar: http://127.0.0.1:8000/health"
    break
  fi
  sleep 2
done

echo "Painel em tempo real: http://127.0.0.1:8080 (digite o ADMIN_TOKEN do .env na tela de entrada)"
echo "Link público do túnel (muda a cada início): docker compose logs tunnel | grep trycloudflare"
