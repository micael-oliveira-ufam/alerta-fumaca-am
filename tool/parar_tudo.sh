#!/usr/bin/env bash
# Para (ou apaga) TODOS os conjuntos do RespirAR Amazonas que estiverem no Docker desta máquina:
# contêineres (api, painel, db), túneis (tunnel e tunnel_dominio), e, com --apagar, também
# volumes (BANCO DE DADOS), redes e imagens.
#
# Por que existe: cada pasta extraída vira um projeto Docker diferente (prefixo = nome da pasta).
# Vários conjuntos rodando ao mesmo tempo, com o mesmo token do túnel, fazem a Cloudflare
# distribuir as visitas entre versões diferentes (visto em 20/10/2026).
#
# Uso:
#   bash tool/parar_tudo.sh            # só PARA os contêineres (não apaga nada; os dados ficam nos volumes)
#   bash tool/parar_tudo.sh --apagar   # APAGA contêineres, volumes, redes e imagens (pede confirmação)
#                                      # ANTES faz backup do banco em ~/respirar-backups (tool/backup_dados.sh);
#                                      # se o backup falhar, NÃO apaga.
#   bash tool/parar_tudo.sh --apagar --sem-backup   # apaga sem backup (perde as respostas salvas)
# Para reaproveitar os dados na versão nova:  bash tool/restaurar_dados.sh
#
# Só mexe em nomes que começam com "respirar-amazonas". Outros projetos (gaia, icam, atlas...) não são tocados.
set -uo pipefail

MODO=parar; BACKUP=1
for arg in "$@"; do
  case "$arg" in
    --apagar) MODO=apagar ;;
    --sem-backup) BACKUP=0 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $arg (use --apagar, --sem-backup ou nenhuma)"; exit 2 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then echo "Docker não encontrado."; exit 1; fi
D=(docker)
if ! docker info >/dev/null 2>&1; then D=(sudo docker); fi

PREFIXO='^respirar-amazonas'
containers=$("${D[@]}" ps -a --format '{{.Names}}' | grep -E "$PREFIXO" || true)
volumes=$("${D[@]}" volume ls --format '{{.Name}}' | grep -E "$PREFIXO" || true)
redes=$("${D[@]}" network ls --format '{{.Name}}' | grep -E "$PREFIXO" || true)
imagens=$("${D[@]}" image ls --format '{{.Repository}}:{{.Tag}}' | grep -E "$PREFIXO" || true)

contar() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
echo "Encontrado: $(contar "$containers") contêiner(es), $(contar "$volumes") volume(s), $(contar "$redes") rede(s), $(contar "$imagens") imagem(ns)."

if [ "$MODO" = parar ]; then
  if [ -z "$containers" ]; then echo "Nada para parar."; exit 0; fi
  # shellcheck disable=SC2086
  printf '%s\n' "$containers" | xargs "${D[@]}" stop >/dev/null
  echo "Parados (volumes e imagens mantidos). Para apagar tudo: bash tool/parar_tudo.sh --apagar"
  exit 0
fi

if [ "$BACKUP" = 1 ] && [ -n "$volumes" ]; then
  echo "Fazendo backup do banco antes de apagar..."
  if ! bash "$(dirname "$0")/backup_dados.sh" --todos; then
    echo "O backup FALHOU; nada foi apagado. Resolva o erro acima, ou use --sem-backup se aceitar perder os dados."
    exit 1
  fi
  echo "Backups em: ${BACKUP_DIR:-$HOME/respirar-backups}"
fi

echo
echo "ATENÇÃO: vai APAGAR, para sempre, os volumes (banco de dados com as respostas), contêineres, redes e imagens:"
for l in "$containers" "$volumes" "$redes" "$imagens"; do [ -n "$l" ] && printf '  %s\n' $l; done
echo
printf 'Digite APAGAR (em maiúsculas) para confirmar: '
read -r resp
if [ "$resp" != "APAGAR" ]; then echo "Cancelado. Nada foi apagado."; exit 1; fi

[ -n "$containers" ] && printf '%s\n' "$containers" | xargs "${D[@]}" rm -f >/dev/null
[ -n "$redes" ] && printf '%s\n' "$redes" | xargs "${D[@]}" network rm >/dev/null 2>&1
[ -n "$volumes" ] && printf '%s\n' "$volumes" | xargs "${D[@]}" volume rm >/dev/null
[ -n "$imagens" ] && printf '%s\n' "$imagens" | xargs "${D[@]}" rmi -f >/dev/null 2>&1
echo "Pronto. Para subir de novo, na pasta do projeto: bash tool/iniciar_servidor.sh"
if [ "$BACKUP" = 1 ]; then echo "Depois de subir, para recuperar os dados salvos: bash tool/restaurar_dados.sh"; fi
