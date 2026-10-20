#!/usr/bin/env bash
# Sobe o servidor (PostgreSQL + API + painel + túnel Cloudflare) com Docker.
#
# Uso: tool/iniciar_servidor.sh
#
# Na primeira execução cria o arquivo .env com senhas e token fortes, gerados aqui.
set -euo pipefail
cd "$(dirname "$0")/../"

command -v docker >/dev/null || { echo "Docker não encontrado. Instale o Docker Desktop ou o Docker Engine."; exit 1; }

if [[ ! -f .env ]]; then
  cp .env.example .env
  # Troca os valores de exemplo por segredos aleatórios (o .env não vai para o Git).
  senha_db="$(openssl rand -hex 24)"
  token="$(openssl rand -hex 24)"
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$senha_db/" .env
  sed -i "s/^ADMIN_TOKEN=.*/ADMIN_TOKEN=$token/" .env
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
