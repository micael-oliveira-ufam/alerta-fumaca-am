#!/usr/bin/env bash
# Diagnostica por que o servidor não obtém os focos de calor do INPE.
# Roda os testes DENTRO do contêiner da API (a mesma rede e o mesmo DNS que o servidor usa).
# Uso (na raiz do projeto):  bash tool/diagnostico_inpe.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if docker compose version >/dev/null 2>&1; then COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE=(docker-compose)
else echo "Docker Compose não encontrado."; exit 1; fi
if ! docker info >/dev/null 2>&1; then COMPOSE=(sudo "${COMPOSE[@]}"); fi

echo "== 1) Logs recentes da API sobre o INPE"
"${COMPOSE[@]}" logs --tail 200 api 2>&1 | grep -i "inpe\|focos" | tail -n 15 || echo "(nenhuma linha sobre o INPE)"

echo
echo "== 2) Teste dentro do contêiner (DNS, HTTPS e resposta do INPE)"
"${COMPOSE[@]}" exec -T api python - <<'PY'
import socket, time, requests
host = "terrabrasilis.dpi.inpe.br"
try:
    print("DNS:", host, "->", sorted({a[4][0] for a in socket.getaddrinfo(host, 443)}))
except Exception as e:
    print("DNS FALHOU:", repr(e)); raise SystemExit(1)
url = f"https://{host}/queimadas/geoserver/ows"
params = {"service": "WFS", "version": "2.0.0", "request": "GetFeature",
          "typeName": "dados_abertos:focos_48h_br_todosats", "outputFormat": "application/json",
          "count": "3", "CQL_FILTER": "estado='AMAZONAS'"}
t = time.time()
try:
    r = requests.get(url, params=params, timeout=(10, 90), headers={"User-Agent": "RespirAR-Amazonas/diagnostico"})
    print(f"HTTP {r.status_code} em {time.time()-t:.1f}s, {len(r.content)} bytes")
    print("Início da resposta:", r.content[:200])
except Exception as e:
    print(f"FALHOU em {time.time()-t:.1f}s:", type(e).__name__, str(e)[:300])
PY

echo
echo "== 3) Procura o endereço atual do WFS do INPE (GetCapabilities em caminhos candidatos)"
"${COMPOSE[@]}" exec -T api python - <<'PY'
import re, requests
base = "https://terrabrasilis.dpi.inpe.br"
candidatos = ["/queimadas/geoserver/ows", "/queimadas/geoserver/wfs", "/geoserver/ows", "/geoserver/wfs",
              "/queimadas/bdqueimadas/geoserver/ows", "/queimadas/portal/geoserver/ows"]
for c in candidatos:
    try:
        r = requests.get(base + c, params={"service": "WFS", "version": "2.0.0", "request": "GetCapabilities"},
                         timeout=(10, 60), headers={"User-Agent": "RespirAR-Amazonas/diagnostico"})
        nomes = sorted(set(re.findall(rb"<(?:wfs:)?Name>([^<]*focos[^<]*)</", r.content)))[:12]
        print(f"{c}: HTTP {r.status_code}, {len(r.content)} bytes, camadas com 'focos': {[n.decode() for n in nomes]}")
    except Exception as e:
        print(f"{c}: FALHOU {type(e).__name__}")
PY
echo
echo "Envie esta saída completa para o suporte. O motivo também aparece na página (aviso amarelo de focos)."
