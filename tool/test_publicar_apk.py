"""Testa tool/publicar_apk.sh com um `docker` de mentira (sem Docker de verdade)."""

import os
import shutil
import stat
import subprocess
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

DOCKER = """#!/usr/bin/env bash
# docker de mentira: um contêiner "abc" com /srv/dist montado de $FAKE_DESTINO
case "$1" in
  ps) echo abc ;;
  inspect) if [[ "$2" == "-f" && "$3" == *Mounts* ]]; then echo "$FAKE_DESTINO"; else echo /respirar-api; fi ;;
  exec) shift; shift
        if [[ "$1" == test ]]; then
          alvo="${3/\\/srv\\/dist/$FAKE_DESTINO}"; test "$2" "$alvo"
        fi ;;
esac
"""


def _projeto(tmp_path):
    proj = tmp_path / "proj"
    (proj / "tool").mkdir(parents=True)
    shutil.copy(RAIZ / "tool" / "publicar_apk.sh", proj / "tool")
    dist = proj / "dist"
    dist.mkdir()
    (dist / "RespirAR-Amazonas-v9.9.9.apk").write_bytes(b"apk")
    (dist / "VERSION.txt").write_text("9.9.9\n")
    (dist / "SHA256SUMS.txt").write_text("abc  RespirAR-Amazonas-v9.9.9.apk\n")
    (dist / "Manual-RespirAR-Amazonas.pdf").write_bytes(b"%PDF")
    return proj


def _rodar(proj, destino, com_docker=True, extra_path=None):
    bin_ = proj / "bin"
    bin_.mkdir(exist_ok=True)
    if com_docker:
        d = bin_ / "docker"
        d.write_text(DOCKER)
        d.chmod(d.stat().st_mode | stat.S_IEXEC)
    env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}", FAKE_DESTINO=str(destino))
    return subprocess.run(["bash", "tool/publicar_apk.sh"], cwd=proj, env=env, capture_output=True, text=True)


def test_copia_para_pasta_montada_por_outro_servidor_e_apaga_apk_antigo(tmp_path):
    proj = _projeto(tmp_path)
    outro = tmp_path / "outra_pasta" / "dist"
    outro.mkdir(parents=True)
    (outro / "RespirAR-Amazonas-v1.0.0.apk").write_bytes(b"velho")
    (outro / "Alerta-Fumaca-AM.apk").write_bytes(b"muito velho")
    r = _rodar(proj, outro)
    assert r.returncode == 0, r.stderr
    assert (outro / "RespirAR-Amazonas-v9.9.9.apk").read_bytes() == b"apk"
    assert not (outro / "RespirAR-Amazonas-v1.0.0.apk").exists() and not (outro / "Alerta-Fumaca-AM.apk").exists()
    assert (outro / "VERSION.txt").read_text().strip() == "9.9.9"
    assert (outro / "Manual-RespirAR-Amazonas.pdf").exists()
    assert "enxerga RespirAR-Amazonas-v9.9.9.apk" in r.stdout


def test_sem_docker_avisa_e_nao_falha(tmp_path):
    proj = _projeto(tmp_path)
    r = subprocess.run(["bash", "tool/publicar_apk.sh"], cwd=proj, capture_output=True, text=True,
                       env=dict(os.environ, PATH="/usr/bin:/bin"))
    assert r.returncode == 0
    assert "ok  " in r.stdout or "Nenhum servidor" in r.stdout


def test_apk_host_dir_do_env(tmp_path):
    proj = _projeto(tmp_path)
    destino = tmp_path / "publico"
    destino.mkdir()
    (proj / ".env").write_text(f"APK_HOST_DIR={destino}\n")
    r = subprocess.run(["bash", "tool/publicar_apk.sh"], cwd=proj, capture_output=True, text=True,
                       env=dict(os.environ, PATH="/usr/bin:/bin"))
    assert r.returncode == 0, r.stderr
    assert (destino / "RespirAR-Amazonas-v9.9.9.apk").exists()
