#!/usr/bin/env bash
# Funções comuns de backup/restauração do banco do RespirAR Amazonas. Use: source tool/_backup_comum.sh
# Não executa nada sozinho.

BACKUP_DIR="${BACKUP_DIR:-$HOME/respirar-backups}"
PREFIXO_PROJETO='^respirar-amazonas'

# Define o array D (docker, com sudo se o usuário não tiver permissão).
preparar_docker() {
  command -v docker >/dev/null 2>&1 || { echo "Docker não encontrado."; return 1; }
  D=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null || [[ -t 0 ]]; then D=(sudo docker); else echo "Sem acesso ao Docker."; return 1; fi
  fi
  return 0
}

# Nomes de todos os contêineres "db" de projetos respirar-amazonas* (parados ou não).
listar_dbs() {
  "${D[@]}" ps -a --filter label=com.docker.compose.service=db --format '{{.Names}}' 2>/dev/null | grep -E "$PREFIXO_PROJETO" || true
}

# Garante que o contêiner está rodando e aceitando conexões.
garantir_db_ativo() {
  local c="$1" estado
  estado="$("${D[@]}" inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo false)"
  [[ "$estado" == "true" ]] || "${D[@]}" start "$c" >/dev/null
  local i
  for i in $(seq 1 30); do
    if "${D[@]}" exec "$c" sh -c 'pg_isready -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "O banco de $c não ficou pronto em 30 s."; return 1
}

# psql dentro do contêiner: contar_linhas CONTAINER TABELA  -> número (ou vazio se a tabela não existe)
contar_linhas() {
  "${D[@]}" exec "$1" sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tA -c 'SELECT count(*) FROM $2'" 2>/dev/null | tr -d ' \r' || true
}

# Linhas "tabela=N" das tabelas do projeto (as que não existirem aparecem como =ausente).
resumo_contagens() {
  local t n
  for t in respostas respostas_sintomas celulas_bairro; do
    n="$(contar_linhas "$1" "$t")"; echo "$t=${n:-ausente}"
  done
}

hash_arquivo() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
