"""CSV público, qualidade do ar (modelo), download do app e horário de consulta dos focos."""

import csv
import datetime as dt
import io
import json

import pytest

from app import download_app, exportacao, focos, qualidade_ar as qar

from .conftest import payload


def _enviar(client, n, **over):
    for _ in range(n):
        assert client.post("/respostas", json=payload(**over)).status_code == 201


def _linhas(resp):
    texto = resp.content.decode("utf-8")
    assert texto.startswith("﻿"), "o CSV deve começar com BOM (Excel)"
    return list(csv.reader(io.StringIO(texto[1:])))


# ------------------------------------------------------------------------------- CSV


@pytest.mark.parametrize("conjunto", ["sintomas", "niveis", "serie_diaria", "areas", "perfil_contexto", "bairros"])
def test_csv_agregado_com_respostas_suficientes(client, conjunto):
    _enviar(client, 6)
    r = client.get(f"/publico/export.csv?conjunto={conjunto}&dias=30")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    assert f"respirar-amazonas_{conjunto}_30d_" in r.headers["content-disposition"]
    linhas = _linhas(r)
    assert linhas[0][:2] == ["periodo_dias", "gerado_em_utc"]
    if conjunto != "bairros":  # bairros dependem do geocodificador (desligado nos testes)
        assert len(linhas) > 1


def test_csv_de_sintomas_tem_os_numeros_do_painel(client):
    _enviar(client, 6, sintomas={"cough": 2, "headache": 1})
    painel = client.get("/publico/painel?dias=30").json()
    linhas = _linhas(client.get("/publico/export.csv?conjunto=sintomas&dias=30"))
    cab = linhas[0]
    por_id = {l[cab.index("sintoma_id")]: l for l in linhas[1:]}
    for s in painel["sintomas"]:
        assert int(por_id[s["id"]][cab.index("relatos")]) == s["relatos"]
        assert int(por_id[s["id"]][cab.index("intenso")]) == s["intenso"]


def test_csv_abaixo_do_minimo_traz_so_o_cabecalho(client):
    _enviar(client, 3)  # mínimo público = 5
    for conjunto in ("sintomas", "niveis", "serie_diaria", "areas", "perfil_contexto", "bairros"):
        linhas = _linhas(client.get(f"/publico/export.csv?conjunto={conjunto}&dias=30"))
        assert len(linhas) == 1, conjunto


def test_csv_nunca_traz_dado_individual(client):
    _enviar(client, 6)
    for conjunto in ("sintomas", "niveis", "serie_diaria", "areas", "perfil_contexto", "bairros"):
        cab = _linhas(client.get(f"/publico/export.csv?conjunto={conjunto}&dias=30"))[0]
        for proibido in ("submission_id", "registrado_em", "criado_em", "id", "ip"):
            assert proibido not in cab, (conjunto, proibido)


def test_csv_conjunto_ou_periodo_invalidos(client):
    assert client.get("/publico/export.csv?conjunto=respostas").status_code == 422
    assert client.get("/publico/export.csv").status_code == 422
    assert client.get("/publico/export.csv?conjunto=sintomas&dias=999").status_code == 422


def test_csv_protege_contra_formula_em_planilha():
    dados = exportacao.serializar(["a", "b"], [["=1+1", 1], ["+cmd", 2], ["@x", 3], ["-2x", 4], ["normal", -5], ["ok", None]])
    texto = dados.decode("utf-8-sig").splitlines()
    assert texto[1:] == ["'=1+1,1", "'+cmd,2", "'@x,3", "'-2x,4", "normal,-5", "ok,"]


def test_csv_de_focos_converte_horario_para_manaus(client, monkeypatch):
    geojson = json.dumps({"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": None, "properties": {
            "data_hora_gmt": "2026-10-20 14:30:00", "satelite": "NOAA-20", "municipio": "LÁBREA", "estado": "AMAZONAS",
            "bioma": "Amazônia", "latitude": -7.26, "longitude": -64.79, "frp": 12.5, "risco_fogo": 0.9,
            "numero_dias_sem_chuva": 6}},
        {"type": "Feature", "geometry": None, "properties": {
            "data_hora_gmt": "2026-10-20T20:00:00Z", "satelite": "AQUA_M-T", "municipio": "=HUMAITÁ", "estado": "AMAZONAS",
            "latitude": -7.5, "longitude": -63.0}},
    ]}).encode()
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: geojson)
    r = client.get("/publico/export.csv?conjunto=focos")
    assert r.status_code == 200
    linhas = _linhas(r)
    cab = linhas[0]
    # mais recente primeiro; 20:00Z = 16:00 em Manaus
    assert linhas[1][cab.index("data_hora_utc")] == "2026-10-20T20:00:00Z"
    assert linhas[1][cab.index("data_hora_manaus")] == "2026-10-20T16:00:00-04:00"
    assert linhas[1][cab.index("municipio")] == "'=HUMAITÁ"
    assert linhas[2][cab.index("data_hora_manaus")] == "2026-10-20T10:30:00-04:00"
    assert linhas[2][cab.index("consultado_em_utc")].startswith("20")


def test_focos_informa_quando_o_servidor_consultou_o_inpe(client, monkeypatch):
    corpo = json.dumps({"type": "FeatureCollection", "features": []}).encode()
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: corpo)
    r1 = client.get("/focos?window=last48h&scope=amazonas")
    assert r1.headers["x-cache"] == "MISS"
    consultado = r1.headers["x-consultado-em"]
    assert dt.datetime.fromisoformat(consultado).tzinfo is not None
    r2 = client.get("/focos?window=last48h&scope=amazonas")
    assert r2.headers["x-cache"] == "HIT" and r2.headers["x-consultado-em"] == consultado  # não muda no cache


# ------------------------------------------------------------------- qualidade do ar


def _resposta_modelo(n=62, **atual):
    base = {"us_aqi": 42, "pm2_5": 8.4, "pm10": 14.2, "time": "2026-10-20T14:00"}
    base.update(atual)
    return [{"current": dict(base)} for _ in range(n)]


class _Resp:
    def __init__(self, corpo, status=200):
        self._c, self.status_code = corpo, status

    def json(self):
        return self._c


def _servico(corpo, status=200, ttl=1800, relogio=None):
    chamadas = []

    def http_get(url, params=None, timeout=None, headers=None):
        chamadas.append(params)
        resp = corpo() if callable(corpo) else corpo
        if isinstance(resp, Exception):
            raise resp
        return _Resp(resp, status)

    kw = {"clock": relogio} if relogio else {}
    return qar.QualidadeAr("http://x", ttl, http_get=http_get, **kw), chamadas


def test_municipios_do_amazonas_sao_62_e_coerentes():
    m = qar.municipios()
    assert len(m) == 62 and len({x.codigo for x in m}) == 62
    assert any(x.nome == "Manaus" for x in m)
    assert all(str(x.codigo).startswith("13") for x in m)
    assert all(-10 < x.lat < 3 and -74 < x.lon < -56 for x in m)


@pytest.mark.parametrize("aqi,esperado", [(0, "boa"), (50, "boa"), (51, "moderada"), (100, "moderada"), (101, "sensivel"),
                                         (150, "sensivel"), (151, "ruim"), (200, "ruim"), (201, "muito_ruim"),
                                         (300, "muito_ruim"), (301, "perigosa")])
def test_faixas_do_us_aqi_iguais_as_do_app(aqi, esperado):
    assert qar.categoria(aqi)[0] == esperado


def test_qualidade_ar_endpoint_traz_municipios_manaus_e_ressalvas(make_client):
    servico, chamadas = _servico(_resposta_modelo())
    client = make_client()
    client.app.state.qualidade_ar = servico
    r = client.get("/publico/qualidade-ar")
    assert r.status_code == 200
    d = r.json()
    assert d["estimativa"] is True and d["resolucao_km"] == 45
    assert len(d["municipios"]) == 62 and d["manaus"]["municipio"] == "Manaus"
    assert d["manaus"]["us_aqi"] == 42 and d["manaus"]["categoria"] == "boa"
    assert d["manaus"]["fracao_fina_pct"] == 59  # 8,4 / 14,2
    assert d["referencia_modelo"] == "2026-10-20T14:00Z"
    assert "bairros" in d["nota_bairros"] and "Open-Meteo" in d["atribuicao"]
    assert not any("bairro" in k for k in d["manaus"])  # nenhum valor por bairro
    assert d["desatualizado"] is False
    # os 62 locais vão numa única consulta, na ordem do arquivo
    assert len(chamadas) == 1 and chamadas[0]["latitude"].count(",") == 61
    assert chamadas[0]["current"] == "us_aqi,pm2_5,pm10"


def test_qualidade_ar_usa_cache_e_respeita_ttl():
    t = [0.0]
    servico, chamadas = _servico(_resposta_modelo(), ttl=100, relogio=lambda: t[0])
    servico.obter(); servico.obter()
    assert len(chamadas) == 1
    t[0] = 101
    servico.obter()
    assert len(chamadas) == 2


def test_qualidade_ar_devolve_a_ultima_boa_marcada_se_o_servico_cair():
    t = [0.0]
    estado = {"quebrar": False}
    servico, _ = _servico(lambda: ValueError("x") if estado["quebrar"] else _resposta_modelo(), ttl=10, relogio=lambda: t[0])
    assert servico.obter()["desatualizado"] is False
    estado["quebrar"] = True; t[0] = 50
    d = servico.obter()
    assert d["desatualizado"] is True and len(d["municipios"]) == 62


def test_qualidade_ar_sem_nada_guardado_e_servico_fora_vira_502(make_client):
    client = make_client()
    client.app.state.qualidade_ar, _ = _servico(ValueError("fora"))
    assert client.get("/publico/qualidade-ar").status_code == 502
    assert client.get("/publico/export.csv?conjunto=qualidade_ar").status_code == 502


@pytest.mark.parametrize("corpo", [_resposta_modelo(5), {"error": True, "reason": "limite"}, "texto", 42])
def test_qualidade_ar_rejeita_respostas_invalidas(corpo):
    servico, _ = _servico(corpo)
    with pytest.raises(ValueError):
        servico.obter()


def test_qualidade_ar_campos_ausentes_viram_vazio_sem_inventar():
    itens = _resposta_modelo()
    itens[0] = {"current": {"us_aqi": None, "pm2_5": "ruim", "pm10": -3}}
    itens[1] = {}
    linhas = qar.interpretar(itens, qar.municipios())
    for x in linhas[:2]:
        assert x["us_aqi"] is None and x["pm2_5"] is None and x["pm10"] is None
        assert x["categoria"] is None and x["fracao_fina_pct"] is None
    assert qar.resumir(linhas)["com_dado"] == 60


def test_qualidade_ar_csv(make_client):
    client = make_client()
    client.app.state.qualidade_ar, _ = _servico(_resposta_modelo(us_aqi=130, pm2_5=40.0, pm10=55.0))
    r = client.get("/publico/export.csv?conjunto=qualidade_ar")
    linhas = _linhas(r)
    cab = linhas[0]
    assert len(linhas) == 63
    manaus = next(l for l in linhas[1:] if l[cab.index("municipio")] == "Manaus")
    assert manaus[cab.index("us_aqi")] == "130" and manaus[cab.index("categoria")] == "Ruim para grupos sensíveis"
    assert manaus[cab.index("pm2_5_ugm3")] == "40.0" and manaus[cab.index("resolucao_modelo_km")] == "45"


def test_qualidade_ar_desativada(make_client):
    client = make_client(qualidade_ar_ativa=False)
    assert client.get("/publico/qualidade-ar").status_code == 404


# ---------------------------------------------------------------- download do app


def test_app_indisponivel_sem_apk(make_client, tmp_path):
    client = make_client(apk_dir=str(tmp_path))
    assert client.get("/publico/app").json() == {"disponivel": False}
    assert client.get("/baixar/app.apk").status_code == 404


def test_app_disponivel_com_hash_tamanho_e_versao(make_client, tmp_path):
    import hashlib
    conteudo = b"PK\x03\x04 apk de mentira " * 100
    (tmp_path / "Alerta-Fumaca-AM.apk").write_bytes(conteudo)
    (tmp_path / "VERSION.txt").write_text("1.8.0\n")
    client = make_client(apk_dir=str(tmp_path))
    info = client.get("/publico/app").json()
    assert info["disponivel"] is True and info["plataforma"] == "Android"
    assert info["tamanho_bytes"] == len(conteudo)
    assert info["sha256"] == hashlib.sha256(conteudo).hexdigest()
    assert info["versao"] == "1.8.0" and info["url"] == "/baixar/app.apk"
    r = client.get("/baixar/app.apk")
    assert r.status_code == 200 and r.content == conteudo
    assert r.headers["content-type"] == "application/vnd.android.package-archive"
    assert "RespirAR-Amazonas.apk" in r.headers["content-disposition"]


def test_app_versao_invalida_e_ignorada_e_arquivo_vazio_nao_conta(make_client, tmp_path):
    (tmp_path / "Alerta-Fumaca-AM.apk").write_bytes(b"x")
    (tmp_path / "VERSION.txt").write_text("<script>alert(1)</script>")
    client = make_client(apk_dir=str(tmp_path))
    assert client.get("/publico/app").json()["versao"] is None
    (tmp_path / "Alerta-Fumaca-AM.apk").write_bytes(b"")
    assert client.get("/publico/app").json() == {"disponivel": False}


def test_qr_do_download_e_svg(client):
    r = client.get("/publico/qr.svg?alvo=app")
    assert r.status_code == 200 and r.headers["content-type"] == "image/svg+xml"
    assert b"<svg" in r.content
    assert client.get("/publico/qr.svg?alvo=outro").status_code == 422


def test_base_publica_do_qr():
    assert download_app.base_publica("https://respirar-amazonas.cloud", "x", "", "http", "h") == "https://respirar-amazonas.cloud"
    assert download_app.base_publica("", "respirar-amazonas.cloud", "https", "http", "h") == "https://respirar-amazonas.cloud"
    assert download_app.base_publica("", "a.b:8080", "", "http", "h") == "http://a.b:8080"
    # Host malformado ou protocolo estranho não entram no QR
    assert download_app.base_publica("", "evil.com/<x>", "javascript", "http", "fallback:1") == "http://fallback:1"


# ------------------------------------------------------------ atualização (app e página)

def test_app_versao_sem_apk_nao_inventa(client):
    r = client.get("/app/versao")
    assert r.status_code == 200
    j = r.json()
    assert j["disponivel"] is False and j["ultima"] is None and j["url"] is None


def test_app_versao_com_apk(tmp_path):
    from app.download_app import atualizacao_app
    (tmp_path / "Alerta-Fumaca-AM.apk").write_bytes(b"apk")
    (tmp_path / "VERSION.txt").write_text("1.8.0\n")
    j = atualizacao_app(str(tmp_path), "1.6.0", "https://x.example")
    assert j["ultima"] == "1.8.0" and j["minima"] == "1.6.0"
    assert j["url"] == "https://x.example/baixar/app.apk" and len(j["sha256"]) == 64
    # versão mínima inválida é ignorada, não repassada ao app
    assert atualizacao_app(str(tmp_path), "lixo", "https://x")["minima"] is None


def test_build_do_site_muda_com_o_conteudo(tmp_path):
    from app.download_app import build_site
    (tmp_path / "a.js").write_text("1")
    b1 = build_site(tmp_path, "1.0.0")
    assert b1 == build_site(tmp_path, "1.0.0")
    (tmp_path / "a.js").write_text("2")
    assert build_site(tmp_path, "1.0.0") != b1


def test_publico_versao(client):
    j = client.get("/publico/versao").json()
    assert len(j["build"]) == 12 and j["servidor"]


def test_pagina_tem_secoes_e_scripts_novos(client):
    import re
    from pathlib import Path
    html = client.get("/").text
    for i in ["app-conteudo", "sec-csv", "csv-lista", "sec-ar", "ar-tab", "mapa-ar",
              "amz-progresso", "amz-nota-base", "amz-legenda", "mapa-aviso"]:
        assert f'id="{i}"' in html, i
    # A seção de focos do INPE foi removida do painel (o serviço mudou de endereço; ver CLAUDE.md 4.32/4.34).
    assert 'id="sec-focos"' not in html and "/assets/focos.js" not in html
    pasta = Path(__file__).parent.parent / "app" / "static_publico"
    for arq in re.findall(r'src="/assets/([^"?]+)', html):
        assert (pasta / arq).is_file(), arq
        assert client.get(f"/assets/{arq}").status_code == 200


def test_app_ar_devolve_so_o_municipio_pedido(make_client):
    servico, _ = _servico(_resposta_modelo())
    client = make_client()
    client.app.state.qualidade_ar = servico
    r = client.get("/app/ar", params={"cod": 1302603})
    assert r.status_code == 200
    d = r.json()
    assert d["municipio"] == "Manaus" and d["us_aqi"] == 42 and d["estimativa"] is True
    assert "municipios" not in d and d["resolucao_km"] == 45
    assert client.get("/app/ar", params={"cod": 1399999}).status_code == 404
    assert client.get("/app/ar", params={"cod": 5}).status_code == 422
    assert client.get("/app/ar").status_code == 422


def test_app_ar_sem_servico_e_desativado(make_client):
    client = make_client(qualidade_ar_ativa=False)
    assert client.get("/app/ar", params={"cod": 1302603}).status_code == 404


# ------------------------------------------------------------ focos perto do município (alertas do app)

def _foco(lat, lon, quando, frp=10.0):
    return {"type": "Feature", "geometry": None, "properties": {
        "data_hora_gmt": quando, "satelite": "NOAA-20", "municipio": "X", "estado": "AMAZONAS",
        "latitude": lat, "longitude": lon, "frp": frp}}


def test_distancia_conhecida():
    from app.focos_proximos import distancia_km
    # 1 grau de latitude ≈ 111,2 km
    assert abs(distancia_km(0, 0, 1, 0) - 111.2) < 0.5
    assert distancia_km(-3.1, -60.0, -3.1, -60.0) == 0


def test_resumir_conta_no_raio_e_na_janela():
    from app.focos_proximos import resumir
    agora = dt.datetime(2026, 10, 20, 20, 0, tzinfo=dt.timezone.utc)
    geo = json.dumps({"type": "FeatureCollection", "features": [
        _foco(-3.12, -60.02, "2026-10-20 19:00:00", frp=30.5),       # em cima da sede, 1 h atrás
        _foco(-3.20, -60.02, "2026-10-20T08:00:00Z", frp=5),         # ~9 km, 12 h atrás
        _foco(-3.12, -60.02, "2026-10-19T00:00:00Z"),                # 44 h atrás: só entra em 48 h
        _foco(-3.12, -60.02, "2026-10-17T00:00:00Z"),                # velho: fora
        _foco(-5.00, -60.02, "2026-10-20 19:00:00"),                 # ~208 km: fora do raio
        {"type": "Feature", "geometry": None, "properties": {"data_hora_gmt": None, "latitude": -3.12, "longitude": -60.02}},
    ]}).encode()
    r = resumir(geo, -3.12, -60.02, 50, agora)
    assert (r["focos_24h"], r["focos_48h"]) == (2, 3)
    assert r["mais_proximo_km"] == 0.0 and r["frp_max_mw"] == 30.5
    assert r["ultima_deteccao_utc"] == "2026-10-20T19:00:00Z"
    vazio = resumir(geo, -3.12, -60.02, 10, agora)
    assert vazio["focos_48h"] == 3  # os três estão a ≤ 10 km
    longe = resumir(json.dumps({"features": []}).encode(), -3.12, -60.02, 50, agora)
    assert longe["focos_24h"] == 0 and longe["mais_proximo_km"] is None and longe["ultima_deteccao_utc"] is None


def test_app_focos_endpoint(client, monkeypatch):
    agora = dt.datetime.now(dt.timezone.utc)
    quando = (agora - dt.timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S")
    geo = json.dumps({"type": "FeatureCollection", "features": [_foco(-3.12, -60.02, quando, frp=20)]}).encode()
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: geo)
    r = client.get("/app/focos", params={"cod": 1302603, "raio_km": 25})
    assert r.status_code == 200
    d = r.json()
    assert d["municipio"] == "Manaus" and d["focos_24h"] == 1 and d["desatualizado"] is False
    assert "não incêndio confirmado" in d["nota"]
    assert client.get("/app/focos", params={"cod": 1302603, "raio_km": 7}).status_code == 422
    assert client.get("/app/focos", params={"cod": 1399999}).status_code == 404
    assert client.get("/app/focos").status_code == 422


# ------------------------------------------------------------ INPE: motivo, tentativas e logo

def test_motivo_do_erro_do_inpe_e_curto_e_sem_dados():
    import requests
    assert focos.motivo(requests.exceptions.ReadTimeout()) == "tempo esgotado esperando resposta"
    assert focos.motivo(requests.exceptions.ConnectTimeout()) == "tempo esgotado ao conectar"
    assert focos.motivo(requests.exceptions.SSLError()) == "falha de certificado HTTPS"
    assert focos.motivo(requests.exceptions.ConnectionError("Failed to resolve 'x' (getaddrinfo)")) == "falha de DNS"
    assert focos.motivo(ValueError("status 503")) == "o INPE respondeu status 503"
    assert focos.motivo(ValueError("resposta fora do formato GeoJSON")) == "resposta do INPE fora do formato"


def test_fetch_upstream_tenta_de_novo_em_falha_de_rede(monkeypatch):
    import requests
    chamadas = []
    corpo = json.dumps({"type": "FeatureCollection", "features": []}).encode()

    class R:
        status_code, content = 200, corpo

    def get(url, **kw):
        chamadas.append(kw["headers"]["User-Agent"])
        if len(chamadas) == 1:
            raise requests.exceptions.ConnectTimeout()
        return R()

    monkeypatch.setattr(focos.requests, "get", get)
    monkeypatch.setattr(focos.time, "sleep", lambda s: None)
    assert focos.fetch_upstream("last48h", "amazonas", []) == corpo
    assert len(chamadas) == 2 and chamadas[0].startswith("RespirAR-Amazonas")


def test_502_do_inpe_informa_o_motivo(client, monkeypatch):
    import requests

    def falha(*a, **k):
        raise requests.exceptions.ReadTimeout()

    monkeypatch.setattr(focos, "fetch_upstream", falha)
    r = client.get("/focos?window=last48h&scope=amazonas")
    assert r.status_code == 502 and "tempo esgotado esperando resposta" in r.json()["detail"]


def test_pagina_tem_logo_icone_e_previa_de_compartilhamento(client):
    html = client.get("/", headers={"host": "exemplo.test"}).text
    assert "class=\"logo\" src=\"data:image/png;base64," in html  # embutida: não depende de /assets nem de cache do Cloudflare
    assert 'property="og:image" content="http://exemplo.test/assets/og-imagem.png"' in html
    assert 'name="twitter:card" content="summary_large_image"' in html
    assert "{{BASE}}" not in html
    for caminho in ["/assets/logo.png", "/assets/og-imagem.png", "/assets/apple-touch-icon.png", "/favicon.ico"]:
        r = client.get(caminho)
        assert r.status_code == 200 and len(r.content) > 500, caminho


def test_secao_amazonia_camadas_e_csp(client):
    html = client.get("/").text
    assert 'id="sec-amazonia"' in html and "/assets/amazonia.js" in html
    csp = client.get("/").headers["content-security-policy"]
    assert "https://terrabrasilis.dpi.inpe.br" in csp and "script-src 'self'" in csp
    js = client.get("/assets/amazonia.js")
    assert js.status_code == 200
    for camada in ["deter-amz:deter_amz", "prodes-amazon-nb:yearly_deforestation_biome",
                   "prodes-amazon-nb:indigenous_area_amazon_biome", "prodes-amazon-nb:conservation_units_amazon_biome"]:
        assert camada in js.text


def test_assets_do_painel_revalidam_sempre(client):
    r = client.get("/assets/logo.png")
    assert r.status_code == 200 and r.headers["cache-control"] == "no-cache"
    r2 = client.get("/assets/logo.png", headers={"If-None-Match": r.headers["etag"]})
    assert r2.status_code == 304


def test_amazonia_js_restringe_desmatamento_ao_satelite_e_tem_progresso_e_legenda(client):
    js = client.get("/assets/amazonia.js").text
    assert "DESMAT" in js and "trocarBase('sat')" in js and "GetLegendGraphic" in js and "tileloadstart" in js


def test_arquivos_do_painel_levam_a_versao_na_url_contra_cache_antigo(client):
    html = client.get("/").text
    assert "{{VERSAO}}" not in html
    for arq in ["publico.css", "amazonia.js", "mapas.js", "publico.js"]:
        assert f"/assets/{arq}?v=" in html, arq
    assert 'id="mapa-amazonia" style="height:460px"' in html  # o mapa nunca colapsa se o CSS estiver velho
    assert client.get("/assets/publico.css?v=1.0").status_code == 200
