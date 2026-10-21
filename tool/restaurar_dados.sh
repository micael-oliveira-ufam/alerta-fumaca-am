#!/usr/bin/env bash
# RESTAURA no banco desta pasta um backup feito por tool/backup_dados.sh, para a nova versão
# reaproveitar as respostas salvas.
#
# Uso (na pasta da versão NOVA, depois de copiar o .env da antiga):
#   bash tool/iniciar_servidor.sh                       # sobe o banco (vazio) da versão nova
#   bash tool/restaurar_dados.sh                        # usa o backup mais recente de $BACKUP_DIR
#   bash tool/restaurar_dados.sh ~/respirar-backups/respirar-20261021-013000.dump
#   bash tool/restaurar_dados.sh --sim                  # não pergunta (automação)
#
# Passos: confere o SHA-256 → (se o banco atual tiver dados) faz backup dele com rótulo
# "antes-da-restauracao" → para API e painel → pg_restore (--clean) → compara a contagem de linhas
# com a do .txt do backup → sobe API e painel. A API da versão nova adiciona sozinha as colunas
# novas que faltarem (server/app/db.py), então um backup de versão anterior é aceito.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/_backup_comum.sh
source "$RAIZ/tool/_backup_comum.sh"

ARQ=""; SIM=0
for a in "$@"; do
  case "$a" in
    --sim) SIM=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "Opção desconhecida: $a"; exit 2 ;;
    *) ARQ="$a" ;;
  esac
done

if [[ -z "$ARQ" ]]; then
  ARQ="$(ls -1t "$BACKUP_DIR"/respirar-*.dump 2>/dev/null | grep -v 'antes-da-restauracao' | head -n 1 || true)"
  [[ -n "$ARQ" ]] || ARQ="$(ls -1t "$BACKUP_DIR"/respirar-*.dump 2>/dev/null | head -n 1 || true)"
  [[ -n "$ARQ" ]] || { echo "Nenhum backup em $BACKUP_DIR. Passe o caminho do .dump."; exit 1; }
fi
[[ -f "$ARQ" ]] || { echo "Arquivo não encontrado: $ARQ"; exit 1; }
BASE="${ARQ%.dump}"

# 1. Integridade
if [[ -f "$BASE.sha256" ]]; then
  esperado="$(awk '{print $1}' "$BASE.sha256")"
  if [[ "$(hash_arquivo "$ARQ")" != "$esperado" ]]; then echo "SHA-256 DIFERENTE do registrado: o backup está corrompido. Nada foi alterado."; exit 1; fi
  echo "Integridade conferida (SHA-256 confere)."
else
  echo "AVISO: não há $(basename "$BASE").sha256; a integridade não pôde ser conferida."
fi

preparar_docker || exit 1
"${D[@]}" compose version >/dev/null 2>&1 || { echo "Docker Compose indisponível."; exit 1; }
COMPOSE=("${D[@]}" compose)
cd "$RAIZ" || exit 1
[[ -f .env ]] || { echo "Falta o .env nesta pasta. Copie o da versão anterior (ou rode tool/iniciar_servidor.sh)."; exit 1; }

"${COMPOSE[@]}" up -d db >/dev/null || { echo "Não consegui subir o banco desta pasta."; exit 1; }
DB="$("${D[@]}" inspect -f '{{.Name}}' "$("${COMPOSE[@]}" ps -q db | head -n 1)" | tr -d '/')"
garantir_db_ativo "$DB" || exit 1

atual="$(contar_linhas "$DB" respostas)"
echo "Banco de destino: $DB  (respostas agora: ${atual:-ausente})"
echo "Backup:           $ARQ"
[[ -f "$BASE.txt" ]] && sed 's/^/    /' "$BASE.txt"

if [[ $SIM -ne 1 ]]; then
  echo
  echo "ATENÇÃO: o conteúdo do banco de destino será SUBSTITUÍDO pelo do backup."
  printf 'Digite RESTAURAR para confirmar: '; read -r resp
  [[ "$resp" == "RESTAURAR" ]] || { echo "Cancelado. Nada foi alterado."; exit 1; }
fi

# 2. Rede de segurança: guarda o que existe agora, se houver dados
if [[ -n "$atual" && "$atual" != "0" ]]; then
  echo "O banco de destino tem dados; salvando-os antes (rótulo antes-da-restauracao)..."
  bash "$RAIZ/tool/backup_dados.sh" --container "$DB" --rotulo antes-da-restauracao || { echo "Backup de segurança falhou; restauração abortada."; exit 1; }
fi

# 3. Restaura com API e painel parados
"${COMPOSE[@]}" stop api painel >/dev/null 2>&1 || true
"${D[@]}" exec -i "$DB" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges' < "$ARQ"
rc=$?
echo "pg_restore terminou com código $rc (avisos sobre objetos inexistentes antes do --clean são normais)."

# 4. Conferência
ok=1
if [[ -f "$BASE.txt" ]]; then
  while IFS='=' read -r tabela esperado; do
    case "$tabela" in respostas|respostas_sintomas|celulas_bairro) ;; *) continue ;; esac
    obtido="$(contar_linhas "$DB" "$tabela")"; obtido="${obtido:-ausente}"
    if [[ "$obtido" == "$esperado" ]]; then echo "  OK    $tabela: $obtido"; else echo "  DIFERE $tabela: backup=$esperado, banco=$obtido"; ok=0; fi
  done < "$BASE.txt"
fi

"${COMPOSE[@]}" up -d api painel >/dev/null 2>&1 || echo "Suba API e painel com: docker compose up -d"
if [[ $ok -eq 1 && $rc -le 1 ]]; then echo "Restauração concluída e conferida."; exit 0; fi
echo "Restauração terminada COM DIVERGÊNCIAS: confira acima. O banco anterior está em $BACKUP_DIR (rótulo antes-da-restauracao), se existia."
exit 1
