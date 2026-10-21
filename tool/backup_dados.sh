#!/usr/bin/env bash
# Faz o BACKUP do banco de dados (respostas dos usuários) do RespirAR Amazonas, para ser
# reaproveitado na próxima versão (tool/restaurar_dados.sh).
#
# Por que existe: cada pasta extraída vira um projeto Docker diferente (respirar-amazonas-v1170,
# respirar-amazonas-v1171...) e cada projeto tem o PRÓPRIO volume `pgdata`. Subir uma versão em outra
# pasta cria um banco VAZIO; `docker compose down -v` e `tool/parar_tudo.sh --apagar` apagam o banco.
#
# Uso:
#   bash tool/backup_dados.sh                      # banco desta pasta (ou o único que existir)
#   bash tool/backup_dados.sh --container NOME     # escolhe o contêiner db (veja `docker ps -a`)
#   bash tool/backup_dados.sh --todos              # um backup de cada banco que tiver dados
#   bash tool/backup_dados.sh --rotulo antes-v1171 # acrescenta um rótulo ao nome do arquivo
# Pasta dos backups: $BACKUP_DIR (padrão ~/respirar-backups, FORA da pasta do projeto, para
# sobreviver à troca de pasta de versão).
#
# Gera, para cada banco: respirar-AAAAMMDD-HHMMSS[-rotulo].dump (formato custom do pg_dump),
# .sha256 (integridade) e .txt (data, versão, contagem de linhas por tabela).
# O .env (senhas, TUNNEL_TOKEN) NÃO é copiado para os backups; copie-o você mesmo para a pasta nova.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/_backup_comum.sh
source "$RAIZ/tool/_backup_comum.sh"

ALVO=""; TODOS=0; ROTULO=""; SILENCIO=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) ALVO="${2:-}"; shift 2 ;;
    --todos) TODOS=1; shift ;;
    --rotulo) ROTULO="-${2:-}"; shift 2 ;;
    --silencio) SILENCIO=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $1"; exit 2 ;;
  esac
done

preparar_docker || exit 1
DBS=(); while IFS= read -r l; do [[ -n "$l" ]] && DBS+=("$l"); done < <(listar_dbs)
if [[ ${#DBS[@]} -eq 0 ]]; then echo "Nenhum banco do RespirAR Amazonas encontrado no Docker (nada a salvar)."; [[ $TODOS -eq 1 ]] && exit 0 || exit 1; fi

escolher() {
  if [[ -n "$ALVO" ]]; then echo "$ALVO"; return; fi
  # banco do projeto desta pasta, se estiver no compose
  local daqui=""
  if "${D[@]}" compose version >/dev/null 2>&1; then
    daqui="$(cd "$RAIZ" && "${D[@]}" compose ps -a -q db 2>/dev/null | head -n 1)"
    [[ -n "$daqui" ]] && daqui="$("${D[@]}" inspect -f '{{.Name}}' "$daqui" 2>/dev/null | tr -d '/')"
  fi
  if [[ -n "$daqui" ]]; then echo "$daqui"; return; fi
  if [[ ${#DBS[@]} -eq 1 ]]; then echo "${DBS[0]}"; return; fi
  echo "Há ${#DBS[@]} bancos no Docker; escolha um com --container NOME (ou use --todos):" >&2
  local c
  for c in "${DBS[@]}"; do
    garantir_db_ativo "$c" >/dev/null 2>&1 && echo "  $c  ($(contar_linhas "$c" respostas) respostas)" >&2 || echo "  $c  (não consegui abrir)" >&2
  done
  return 1
}

salvar() {
  local c="$1" n ts base saida
  garantir_db_ativo "$c" || return 1
  n="$(contar_linhas "$c" respostas)"
  if [[ "$TODOS" -eq 1 && ( -z "$n" || "$n" == "0" ) ]]; then echo "[$c] sem dados (respostas=${n:-ausente}); ignorado."; return 0; fi
  mkdir -p "$BACKUP_DIR" || return 1
  ts="$(date +%Y%m%d-%H%M%S)"; base="$BACKUP_DIR/respirar-$ts$ROTULO"
  [[ -e "$base.dump" ]] && base="$base-$$"
  saida="$base.dump"
  if ! "${D[@]}" exec "$c" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$saida.parcial"; then
    rm -f "$saida.parcial"; echo "[$c] FALHA no pg_dump."; return 1
  fi
  # confere que o arquivo é um dump legível (lista o conteúdo)
  if [[ ! -s "$saida.parcial" ]] || ! "${D[@]}" exec -i "$c" pg_restore -l < "$saida.parcial" >/dev/null 2>&1; then
    rm -f "$saida.parcial"; echo "[$c] o dump gerado está vazio ou ilegível; backup descartado."; return 1
  fi
  mv "$saida.parcial" "$saida"
  echo "$(hash_arquivo "$saida")  $(basename "$saida")" > "$base.sha256"
  {
    echo "contêiner=$c"
    echo "data=$(date -Iseconds 2>/dev/null || date)"
    echo "versao_do_projeto=$(cat "$RAIZ/VERSION" 2>/dev/null || echo desconhecida)"
    resumo_contagens "$c"
  } > "$base.txt"
  chmod 600 "$saida" "$base.sha256" "$base.txt" 2>/dev/null || true
  [[ $SILENCIO -eq 1 ]] || { echo "[$c] backup salvo: $saida ($(wc -c < "$saida" | tr -d ' ') bytes)"; sed 's/^/    /' "$base.txt"; }
  return 0
}

falhas=0
if [[ $TODOS -eq 1 ]]; then
  for c in "${DBS[@]}"; do salvar "$c" || falhas=$((falhas + 1)); done
else
  c="$(escolher)" || exit 1
  salvar "$c" || falhas=1
fi
[[ $falhas -eq 0 ]] || { echo "$falhas backup(s) falharam."; exit 1; }
exit 0
