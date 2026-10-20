#!/usr/bin/env python3
"""Versionamento do RespirAR Amazonas (app Flutter + servidor FastAPI, uma versão só).

Fonte única: o arquivo `VERSION` (SemVer: MAIOR.MENOR.PATCH). Este script mantém as cópias
sincronizadas e confere o changelog:

  pubspec.yaml            version: X.Y.Z+N   (N = número de build do Android/iOS, sobe 1 a cada release)
  lib/data/app_info.dart  kAppVersion        (mostrado em "Sobre" e enviado com as respostas)
  server/app/main.py      APP_VERSION        (GET /health e documentação da API)
  CHANGELOG.md            seção [X.Y.Z] com data

Comandos:
  python3 tool/versao.py mostrar                 # versão atual e situação das cópias
  python3 tool/versao.py verificar               # erro (código 1) se alguma cópia divergir
  python3 tool/versao.py sincronizar             # copia VERSION para todas as cópias
  python3 tool/versao.py nova patch|minor|major  # sobe a versão, o build e move o changelog
  python3 tool/versao.py nova 2.0.0              # ou define a versão explicitamente

Depois de `nova`: revise o CHANGELOG.md, faça o commit e marque com
`git tag -a vX.Y.Z -m "Versão X.Y.Z"` (o script imprime os comandos).
"""

from __future__ import annotations

import datetime as dt
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
UNRELEASED = "## [Não lançado]"


class ErroVersao(Exception):
    pass


def ler_versao() -> str:
    texto = (RAIZ / "VERSION").read_text(encoding="utf-8").strip()
    if not SEMVER.match(texto):
        raise ErroVersao(f"VERSION inválido: {texto!r} (use MAIOR.MENOR.PATCH)")
    return texto


def _pubspec_partes(texto: str) -> tuple[str, int]:
    m = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", texto, re.M)
    if not m:
        raise ErroVersao("pubspec.yaml: linha 'version: X.Y.Z+N' não encontrada")
    return m.group(1), int(m.group(2))


def _substituir(caminho: Path, padrao: str, novo: str, texto: str | None = None) -> str:
    conteudo = caminho.read_text(encoding="utf-8") if texto is None else texto
    nova, n = re.subn(padrao, novo, conteudo, count=1, flags=re.M)
    if n != 1:
        raise ErroVersao(f"{caminho.relative_to(RAIZ)}: padrão de versão não encontrado")
    return nova


def versoes_das_copias() -> dict[str, str]:
    pub, _ = _pubspec_partes((RAIZ / "pubspec.yaml").read_text(encoding="utf-8"))
    app = re.search(r"kAppVersion = '([^']+)'", (RAIZ / "lib/data/app_info.dart").read_text(encoding="utf-8"))
    srv = re.search(r'APP_VERSION = "([^"]+)"', (RAIZ / "server/app/main.py").read_text(encoding="utf-8"))
    return {
        "pubspec.yaml": pub,
        "lib/data/app_info.dart": app.group(1) if app else "(ausente)",
        "server/app/main.py": srv.group(1) if srv else "(ausente)",
    }


def problemas(versao: str) -> list[str]:
    erros = []
    for arquivo, valor in versoes_das_copias().items():
        if valor != versao:
            erros.append(f"{arquivo} tem {valor}, mas VERSION é {versao}")
    changelog = (RAIZ / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"## [{versao}]" not in changelog:
        erros.append(f"CHANGELOG.md não tem a seção [{versao}]")
    return erros


def sincronizar(versao: str, build: int | None = None) -> None:
    pubspec = RAIZ / "pubspec.yaml"
    _, build_atual = _pubspec_partes(pubspec.read_text(encoding="utf-8"))
    n_build = build if build is not None else build_atual
    texto = _substituir(pubspec, r"^version:\s*\S+\s*$", f"version: {versao}+{n_build}")
    pubspec.write_text(texto, encoding="utf-8")

    app_info = RAIZ / "lib/data/app_info.dart"
    app_info.write_text(
        _substituir(app_info, r"kAppVersion = '[^']+'", f"kAppVersion = '{versao}'"),
        encoding="utf-8",
    )
    main = RAIZ / "server/app/main.py"
    main.write_text(
        _substituir(main, r'APP_VERSION = "[^"]+"', f'APP_VERSION = "{versao}"'),
        encoding="utf-8",
    )


def mover_changelog(versao: str, data: str) -> None:
    caminho = RAIZ / "CHANGELOG.md"
    texto = caminho.read_text(encoding="utf-8")
    if f"## [{versao}]" in texto:
        raise ErroVersao(f"CHANGELOG.md já tem a seção [{versao}]")
    if UNRELEASED not in texto:
        raise ErroVersao(f"CHANGELOG.md precisa da seção '{UNRELEASED}' com as mudanças")
    texto = texto.replace(UNRELEASED, f"{UNRELEASED}\n\nNenhuma mudança desde a {versao}.\n\n## [{versao}] - {data}", 1)
    caminho.write_text(texto, encoding="utf-8")


def proxima(atual: str, tipo: str) -> str:
    maior, menor, patch = (int(x) for x in atual.split("."))
    if tipo == "major":
        return f"{maior + 1}.0.0"
    if tipo == "minor":
        return f"{maior}.{menor + 1}.0"
    if tipo == "patch":
        return f"{maior}.{menor}.{patch + 1}"
    raise ErroVersao(f"tipo desconhecido: {tipo}")


def mostrar() -> int:
    versao = ler_versao()
    print(f"Versão do projeto (VERSION): {versao}")
    for arquivo, valor in versoes_das_copias().items():
        marca = "ok" if valor == versao else "DIVERGE"
        print(f"  {arquivo:<26} {valor:<12} {marca}")
    erros = problemas(versao)
    print("Situação:", "consistente" if not erros else f"{len(erros)} problema(s)")
    for e in erros:
        print("  -", e)
    return 0 if not erros else 1


def verificar() -> int:
    erros = problemas(ler_versao())
    for e in erros:
        print("ERRO:", e)
    if not erros:
        print("Versões e changelog consistentes.")
    return 0 if not erros else 1


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    comando = argv[0]
    try:
        if comando == "mostrar":
            return mostrar()
        if comando == "verificar":
            return verificar()
        if comando == "sincronizar":
            sincronizar(ler_versao())
            print("Cópias sincronizadas com VERSION.")
            return verificar()
        if comando == "nova":
            if len(argv) != 2:
                raise ErroVersao("uso: nova patch|minor|major|X.Y.Z")
            alvo = argv[1]
            atual = ler_versao()
            nova = alvo if SEMVER.match(alvo) else proxima(atual, alvo)
            if nova == atual:
                raise ErroVersao("a nova versão é igual à atual")
            _, build = _pubspec_partes((RAIZ / "pubspec.yaml").read_text(encoding="utf-8"))
            (RAIZ / "VERSION").write_text(nova + "\n", encoding="utf-8")
            sincronizar(nova, build + 1)
            mover_changelog(nova, dt.date.today().isoformat())
            print(f"Versão {atual} -> {nova} (build {build + 1}).")
            print("Revise o CHANGELOG.md e depois:")
            print("  git add -A && git commit -m 'Release " + nova + "'")
            print(f"  git tag -a v{nova} -m 'Versão {nova}' && git push origin main v{nova}")
            return verificar()
        print(f"comando desconhecido: {comando}\n")
        print(__doc__)
        return 2
    except ErroVersao as e:
        print("ERRO:", e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
