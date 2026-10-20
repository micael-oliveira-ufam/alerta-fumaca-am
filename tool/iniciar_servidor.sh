#!/usr/bin/env bash
# Sobe o servidor (PostgreSQL + API + painel + túnel Cloudflare) com Docker.
#
# Uso: bash tool/iniciar_servidor.sh
#
# Funciona no macOS (bash 3.2, BSD sed/awk) e no Linux (Docker Engine com plugin Compose v2
# ou docker-compose v1; usa sudo se o usuário não estiver no grupo docker). Na primeira execução cria o
# arquivo .env com senhas e token aleatórios gerados aqui.
set -euo pipefail
cd "$(dirname "$0")/.."

SISTEMA="$(uname -s)"

command -v docker >/dev/null || {
  echo "Docker não encontrado."
  if [[ "$SISTEMA" == "Linux" ]]; then
    echo "No Ubuntu/Debian:  sudo apt install docker.io docker-compose-v2   (ou siga https://docs.docker.com/engine/install/)"
  else
    echo "Instale o Docker Desktop (macOS)."
  fi
  exit 1
}

# Docker pode exigir sudo no Linux (usuário fora do grupo "docker"). Se for o caso, usa sudo.
DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if [[ "$SISTEMA" == "Linux" ]]; then
    erro_docker="$(docker info 2>&1 || true)"   # em variável: evita falha do pipefail com grep -q
    if grep -qi "permission denied" <<<"$erro_docker"; then
      echo "Sem permissão para falar com o Docker; usando sudo (digite sua senha se pedir)."
      echo "Para não precisar de sudo:  sudo usermod -aG docker \$USER   e depois saia e entre na sessão."
      DOCKER=(sudo docker)
    else
      echo "O Docker não está rodando. Inicie com:  sudo systemctl start docker"
      exit 1
    fi
  else
    echo "O Docker não está rodando. Abra o Docker Desktop e tente de novo."
    exit 1
  fi
fi

# Docker Compose: plugin novo ("docker compose") ou o antigo ("docker-compose").
# Em vários Linux o Docker vem SEM o plugin, e "docker compose up -d" falha com
# "unknown shorthand flag: 'd' in -d".
if "${DOCKER[@]}" compose version >/dev/null 2>&1; then
  COMPOSE=("${DOCKER[@]}" compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
  [[ "${DOCKER[0]}" == "sudo" ]] && COMPOSE=(sudo docker-compose)
else
  echo "O Docker Compose não está instalado. Instale um destes:"
  echo "  Ubuntu/Debian:  sudo apt install docker-compose-v2      (ou docker-compose-plugin, do repositório oficial da Docker)"
  echo "  Fedora:         sudo dnf install docker-compose-plugin"
  echo "  Arch:           sudo pacman -S docker-compose"
  echo "  Qualquer um:    https://docs.docker.com/compose/install/linux/"
  exit 1
fi

# Gera um segredo hexadecimal (openssl, ou /dev/urandom se o openssl não existir).
segredo() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

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
  senha_db="$(segredo)"
  token="$(segredo)"
  definir_var POSTGRES_PASSWORD "$senha_db"
  definir_var ADMIN_TOKEN "$token"
  echo "Arquivo .env criado. ADMIN_TOKEN (guarde para o painel e a exportação CSV): $token"
fi

# Lê o valor de uma variável do .env (vazio se não existir).
ler_var() { awk -F= -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' .env; }

# Testa se algo já escuta numa porta deste computador.
porta_em_uso() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

# Se uma porta do .env já estiver ocupada por OUTRO programa, escolhe a próxima livre e
# grava no .env ("port is already allocated" no Docker). Se o serviço deste projeto já está
# rodando, a porta é dele e nada é alterado.
for var in API_PORT PAINEL_PORT; do
  padrao=8000; servico=api
  [[ "$var" == "PAINEL_PORT" ]] && { padrao=8080; servico=painel; }
  if [[ -n "$("${COMPOSE[@]}" ps -q "$servico" 2>/dev/null || true)" ]]; then continue; fi
  porta="$(ler_var "$var")"; porta="${porta:-$padrao}"
  if porta_em_uso "$porta"; then
    nova=$((porta + 1))
    while porta_em_uso "$nova"; do nova=$((nova + 1)); done
    echo "A porta $porta já está em uso por outro programa (veja: ss -ltnp | grep :$porta). Usando $nova em $var."
    if grep -q "^$var=" .env; then definir_var "$var" "$nova"; else echo "$var=$nova" >> .env; fi
  fi
done

# Sobe os serviços. Se o Docker ainda recusar uma porta (alguém a ocupou depois do teste, ou
# ela só está ocupada em outra interface), troca a porta que falhou pela próxima livre e
# tenta de novo, até 5 vezes.
for tentativa in 1 2 3 4 5; do
  saida="$(mktemp)"
  if "${COMPOSE[@]}" up -d --build 2>&1 | tee "$saida"; then
    # pipefail: o status é o do compose, não o do tee
    rm -f "$saida"; break
  fi
  ocupada="$(grep -Eo '(Bind for [0-9.]+:|:)[0-9]+ failed: port is already allocated|address already in use' "$saida" | grep -Eo '[0-9]{2,5}' | head -n 1 || true)"
  rm -f "$saida"
  if [[ -z "$ocupada" ]]; then echo "Falha ao subir os serviços (veja a mensagem acima)."; exit 1; fi
  var=""
  [[ "$ocupada" == "$(ler_var API_PORT)" ]] && var=API_PORT
  [[ "$ocupada" == "$(ler_var PAINEL_PORT)" ]] && var=PAINEL_PORT
  if [[ -z "$var" ]]; then echo "A porta $ocupada está ocupada, mas não é a do painel nem a da API. Libere-a e rode de novo."; exit 1; fi
  nova=$((ocupada + 1))
  while porta_em_uso "$nova"; do nova=$((nova + 1)); done
  echo "A porta $ocupada foi recusada pelo Docker. Trocando $var para $nova e tentando de novo (tentativa $tentativa de 5)."
  definir_var "$var" "$nova"
  [[ $tentativa -eq 5 ]] && { echo "Não consegui uma porta livre depois de 5 tentativas."; exit 1; }
done

API_PORTA="$(ler_var API_PORT)"; API_PORTA="${API_PORTA:-8000}"
PAINEL_PORTA="$(ler_var PAINEL_PORT)"; PAINEL_PORTA="${PAINEL_PORTA:-8080}"

echo "Aguardando a API..."
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$API_PORTA/health" >/dev/null 2>&1; then
    echo "API no ar: http://127.0.0.1:$API_PORTA/health"
    break
  fi
  sleep 2
done

echo "Painel em tempo real: http://127.0.0.1:$PAINEL_PORTA (digite o ADMIN_TOKEN do .env na tela de entrada)"

# Link público do túnel (só existe se o perfil do túnel estiver ativo no .env).
link=""
for _ in $(seq 1 15); do
  link="$("${COMPOSE[@]}" logs tunnel 2>/dev/null | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1 || true)"
  [[ -n "$link" ]] && break
  sleep 2
done
if [[ -n "$link" ]]; then
  echo "Link público (muda a cada início): $link"
  echo "Para compilar o app apontando para ele:  bash tool/gerar_apk.sh $link"
else
  echo "Link público do túnel não apareceu. Veja:  ${COMPOSE[*]} logs tunnel"
fi
