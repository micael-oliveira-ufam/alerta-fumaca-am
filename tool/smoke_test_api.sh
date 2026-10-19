#!/usr/bin/env bash
# Teste de fumaça da API em execução (use depois de `docker compose up -d --build`).
#
#   tool/smoke_test_api.sh [URL_BASE]      # padrão: http://localhost:8000
#
# Envia UMA resposta de teste, reenvia a mesma (deve ser reconhecida como duplicada) e
# confere /health, /estatisticas e /mapa. ATENÇÃO: grava 1 registro de teste no banco.
# Use um banco de desenvolvimento, não o de produção.
set -euo pipefail

BASE="${1:-http://localhost:8000}"
ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PAYLOAD="$(cat <<JSON
{"submission_id":"$ID","registrado_em":"$NOW","lat":-3.12,"lon":-60.02,
 "nivel":"moderate","pontos":9,"exposicao":"between1and4h",
 "perfil":{"idoso":false,"gestante":false,"crianca":false,"doenca_respiratoria":false,"doenca_cardiaca":false},
 "sintomas":{"cough":2,"throat":1,"eyes":0},"app_version":"smoke-test"}
JSON
)"

fail() { echo "FALHOU: $*" >&2; exit 1; }
code() { curl -sS -o /tmp/smoke_body.json -w '%{http_code}' "$@"; }

[ "$(code "$BASE/health")" = 200 ] || fail "/health não devolveu 200"
echo "ok  GET  /health"

c="$(code -X POST "$BASE/respostas" -H 'content-type: application/json' -d "$PAYLOAD")"
[ "$c" = 201 ] || fail "POST /respostas devolveu $c (esperado 201): $(cat /tmp/smoke_body.json)"
echo "ok  POST /respostas -> 201"

c="$(code -X POST "$BASE/respostas" -H 'content-type: application/json' -d "$PAYLOAD")"
[ "$c" = 200 ] || fail "reenvio devolveu $c (esperado 200, idempotente)"
grep -q '"duplicado":true' /tmp/smoke_body.json || fail "reenvio não marcou duplicado"
echo "ok  POST /respostas (reenvio) -> 200 duplicado"

c="$(code "$BASE/estatisticas?dias=30")"
[ "$c" = 200 ] || fail "/estatisticas devolveu $c"
python3 - <<'PY'
import json
d = json.load(open("/tmp/smoke_body.json"))
assert d["total_respostas"] >= 1, d
assert "sintomas" in d and "niveis" in d, d
print("ok  GET  /estatisticas -> total_respostas =", d["total_respostas"], "| suficiente =", d["suficiente"])
PY

[ "$(code "$BASE/mapa?horas=72")" = 200 ] || fail "/mapa não devolveu 200"
echo "ok  GET  /mapa"
echo "Tudo certo."
