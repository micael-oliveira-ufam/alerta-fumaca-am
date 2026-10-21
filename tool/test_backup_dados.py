"""Testa backup_dados.sh, restaurar_dados.sh e parar_tudo.sh --apagar com um `docker` de mentira."""

import os
import shutil
import subprocess
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

DOCKER = """#!/usr/bin/env bash
echo "$@" >> "$FAKE_LOG"
case "$1" in
  info) exit 0 ;;
  ps) echo respirar-amazonas-vteste-db-1 ;;
  start) ;;
  volume) [[ "$2" == ls ]] && echo respirar-amazonas-vteste_pgdata ;;
  network|image) ;;
  inspect) if [[ "$3" == *Running* ]]; then echo true; else echo /respirar-amazonas-vteste-db-1; fi ;;
  compose) shift
    case "$1" in version) echo v2 ;; ps) echo cid1 ;; esac ;;
  exec) shift; [[ "$1" == -i ]] && { shift; ENTRADA=1; }; shift
    cmd="$*"
    case "$cmd" in
      *pg_dump*) [[ -n "$FAKE_DUMP_FALHA" ]] && exit 1; printf 'PGDMP-dados-de-teste' ;;
      *"pg_restore -l"*|*"pg_restore -U"*) cat >/dev/null ;;
      *pg_isready*) ;;
      *count*) echo "${FAKE_CONTAGEM:-5}" ;;
    esac ;;
esac
"""


def _preparar(tmp_path):
    proj = tmp_path / "proj"
    (proj / "tool").mkdir(parents=True)
    for f in ("_backup_comum.sh", "backup_dados.sh", "restaurar_dados.sh", "parar_tudo.sh"):
        shutil.copy(RAIZ / "tool" / f, proj / "tool")
    (proj / "VERSION").write_text("9.9.9\n")
    (proj / ".env").write_text("X=1\n")
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    d = bin_ / "docker"
    d.write_text(DOCKER)
    d.chmod(0o755)
    return proj, bin_


def _rodar(proj, bin_, tmp_path, *args, entrada="", **extra_env):
    env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}", BACKUP_DIR=str(tmp_path / "bk"),
               FAKE_LOG=str(tmp_path / "docker.log"), HOME=str(tmp_path), **extra_env)
    return subprocess.run(["bash", *args], cwd=proj, env=env, input=entrada, text=True, capture_output=True)


def test_backup_gera_dump_hash_e_manifesto(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    r = _rodar(proj, bin_, tmp_path, "tool/backup_dados.sh")
    assert r.returncode == 0, r.stdout + r.stderr
    dumps = list((tmp_path / "bk").glob("respirar-*.dump"))
    assert len(dumps) == 1 and dumps[0].read_bytes() == b"PGDMP-dados-de-teste"
    assert dumps[0].with_suffix(".sha256").read_text().split()[0]
    manifesto = dumps[0].with_suffix(".txt").read_text()
    assert "versao_do_projeto=9.9.9" in manifesto and "respostas=5" in manifesto
    assert not list((tmp_path / "bk").glob("*.parcial"))


def test_backup_falho_nao_deixa_arquivo(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    r = _rodar(proj, bin_, tmp_path, "tool/backup_dados.sh", FAKE_DUMP_FALHA="1")
    assert r.returncode != 0
    assert not list((tmp_path / "bk").glob("*"))


def test_restaurar_recusa_backup_corrompido(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    assert _rodar(proj, bin_, tmp_path, "tool/backup_dados.sh").returncode == 0
    dump = next((tmp_path / "bk").glob("respirar-*.dump"))
    dump.write_bytes(dump.read_bytes() + b"x")
    r = _rodar(proj, bin_, tmp_path, "tool/restaurar_dados.sh", "--sim")
    assert r.returncode == 1 and "corrompido" in r.stdout
    assert "pg_restore -U" not in (tmp_path / "docker.log").read_text()


def test_restaurar_ok_confere_contagem_e_guarda_o_banco_atual(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    assert _rodar(proj, bin_, tmp_path, "tool/backup_dados.sh").returncode == 0
    r = _rodar(proj, bin_, tmp_path, "tool/restaurar_dados.sh", "--sim")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Restauração concluída e conferida" in r.stdout
    # o banco de destino tinha dados (5): foi feito backup de segurança antes de restaurar
    assert len(list((tmp_path / "bk").glob("*antes-da-restauracao.dump"))) == 1


def test_restaurar_exige_confirmacao(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    assert _rodar(proj, bin_, tmp_path, "tool/backup_dados.sh").returncode == 0
    r = _rodar(proj, bin_, tmp_path, "tool/restaurar_dados.sh", entrada="nao\n")
    assert r.returncode == 1 and "Cancelado" in r.stdout


def test_apagar_faz_backup_antes_e_nao_apaga_se_falhar(tmp_path):
    proj, bin_ = _preparar(tmp_path)
    r = _rodar(proj, bin_, tmp_path, "tool/parar_tudo.sh", "--apagar", entrada="APAGAR\n")
    assert r.returncode == 0, r.stdout + r.stderr
    log = (tmp_path / "docker.log").read_text()
    assert log.index("pg_dump") < log.index("volume rm")
    assert list((tmp_path / "bk").glob("respirar-*.dump"))

    # backup falha -> nada é apagado
    (tmp_path / "docker.log").write_text("")
    r = _rodar(proj, bin_, tmp_path, "tool/parar_tudo.sh", "--apagar", entrada="APAGAR\n", FAKE_DUMP_FALHA="1")
    assert r.returncode == 1 and "nada foi apagado" in r.stdout
    assert "volume rm" not in (tmp_path / "docker.log").read_text()

    # --sem-backup ignora o backup (escolha explícita)
    (tmp_path / "docker.log").write_text("")
    r = _rodar(proj, bin_, tmp_path, "tool/parar_tudo.sh", "--apagar", "--sem-backup", entrada="APAGAR\n", FAKE_DUMP_FALHA="1")
    assert r.returncode == 0 and "volume rm" in (tmp_path / "docker.log").read_text()
