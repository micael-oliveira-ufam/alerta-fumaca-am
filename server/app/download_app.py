"""Download do aplicativo (APK) pelo painel público.

O APK NÃO fica no repositório: `tool/gerar_apk.sh` o gera em `dist/` e o `docker-compose.yml`
monta essa pasta, somente leitura, em `/srv/dist`. Se o arquivo não existir, a página diz que o
download ainda não está disponível. O SHA-256 é mostrado para quem quiser conferir a integridade.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import re
from pathlib import Path
from typing import Any

APK_NOME = "Alerta-Fumaca-AM.apk"
_VERSAO = re.compile(r"^\d+\.\d+\.\d+$")
_HOST = re.compile(r"^[A-Za-z0-9.-]+(:\d{1,5})?$")
_hashes: dict[tuple[str, int, int], str] = {}


def caminho(apk_dir: str) -> Path:
    return Path(apk_dir) / APK_NOME


def _sha256(path: Path, st) -> str:  # noqa: ANN001
    chave = (str(path), st.st_mtime_ns, st.st_size)
    if chave not in _hashes:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for bloco in iter(lambda: f.read(1024 * 1024), b""):
                h.update(bloco)
        _hashes.clear()  # guarda só o hash do arquivo atual
        _hashes[chave] = h.hexdigest()
    return _hashes[chave]


def info(apk_dir: str) -> dict[str, Any]:
    path = caminho(apk_dir)
    try:
        st = path.stat()
    except OSError:
        return {"disponivel": False}
    if not path.is_file() or st.st_size == 0:
        return {"disponivel": False}
    versao = None
    try:
        texto = (Path(apk_dir) / "VERSION.txt").read_text(encoding="utf-8").strip()
        versao = texto if _VERSAO.match(texto) else None
    except OSError:
        pass
    return {
        "disponivel": True,
        "plataforma": "Android",
        "arquivo": "RespirAR-Amazonas.apk",
        "tamanho_bytes": st.st_size,
        "sha256": _sha256(path, st),
        "versao": versao,
        "atualizado_em": dt.datetime.fromtimestamp(st.st_mtime, dt.timezone.utc).isoformat(),
        "url": "/baixar/app.apk",
    }


def base_publica(public_url: str, host: str, proto: str, esquema_padrao: str, netloc_padrao: str) -> str:
    """Endereço público para o QR code: `PUBLIC_URL` se definido; senão o Host da requisição."""
    if public_url:
        return public_url
    proto = proto.split(",")[0].strip().lower()
    proto = proto if proto in ("http", "https") else esquema_padrao
    host = host.strip() if _HOST.match(host.strip()) else netloc_padrao
    return f"{proto}://{host}"


def versao_valida(texto: str) -> str | None:
    """Devolve `texto` se for X.Y.Z, senão None."""
    texto = (texto or "").strip()
    return texto if _VERSAO.match(texto) else None


def atualizacao_app(apk_dir: str, versao_minima: str, base: str) -> dict[str, Any]:
    """Resposta de `GET /app/versao`: o que o aplicativo instalado consulta para saber se há versão nova.

    Nada é inventado: sem APK em `dist/` ou sem `VERSION.txt` válido, `ultima` é None e o app não
    mostra aviso. O app compara por números (1.10.0 > 1.9.0), não por texto.
    """
    dados = info(apk_dir)
    disponivel = bool(dados["disponivel"])
    return {
        "disponivel": disponivel,
        "ultima": dados.get("versao") if disponivel else None,
        "minima": versao_valida(versao_minima),
        "url": f"{base}{dados['url']}" if disponivel else None,
        "sha256": dados.get("sha256") if disponivel else None,
        "tamanho_bytes": dados.get("tamanho_bytes") if disponivel else None,
        "atualizado_em": dados.get("atualizado_em") if disponivel else None,
    }


def build_site(pasta: Path, versao_servidor: str) -> str:
    """Identificador da versão da página: muda quando qualquer arquivo da página muda.

    Calculado sobre nome, tamanho e conteúdo dos arquivos (determinístico e reprodutível).
    """
    h = hashlib.sha256()
    h.update(versao_servidor.encode())
    for arq in sorted(p for p in pasta.rglob("*") if p.is_file()):
        h.update(str(arq.relative_to(pasta)).encode())
        h.update(arq.read_bytes())
    return h.hexdigest()[:12]
