#!/usr/bin/env python3
"""Aplica as permissões de plataforma exigidas pelo app, de forma idempotente.

Por que existe
--------------
O pacote não inclui as pastas android/ e ios/ (elas são geradas por
`flutter create`). Sem a permissão INTERNET no AndroidManifest.xml principal, um
build de *release* não acessa a rede: o INPE falha com "Failed host lookup", os
mapas não carregam. Sem ACCESS_FINE/COARSE_LOCATION, o Android nunca mostra o
pedido de GPS. Este script elimina a edição manual desses arquivos.

Uso (na raiz do projeto, depois de `flutter create --platforms=android,ios .`):

    python3 tool/apply_platform_config.py            # aplica
    python3 tool/apply_platform_config.py --check    # só verifica (código 1 se faltar algo)

Rodar duas vezes não duplica nada.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
PLIST = Path("ios/Runner/Info.plist")

ANDROID_PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]

DIAL_INTENT = (
    "        <intent>\n"
    '            <action android:name="android.intent.action.DIAL"/>\n'
    '            <data android:scheme="tel"/>\n'
    "        </intent>\n"
)

LOCATION_TEXT = (
    "Usamos sua localização para centralizar o mapa e, somente quando você "
    "decide compartilhar, para mapear áreas de risco de fumaça de forma anonimizada."
)


def patch_manifest(text: str) -> tuple[str, list[str]]:
    """Retorna (novo_texto, lista_do_que_foi_adicionado)."""
    added: list[str] = []

    # 1) Permissões, logo após a tag <manifest ...>.
    missing = [p for p in ANDROID_PERMISSIONS if f'android:name="{p}"' not in text]
    if missing:
        start = text.find("<manifest")
        if start == -1:
            raise ValueError("AndroidManifest.xml sem tag <manifest>.")
        end = text.find(">", start) + 1
        block = "".join(f'\n    <uses-permission android:name="{p}"/>' for p in missing)
        text = text[:end] + block + text[end:]
        added += missing

    # 2) <queries> com a intenção DIAL (necessária para discar no Android 11+).
    if 'android.intent.action.DIAL' not in text:
        if "</queries>" in text:
            text = text.replace("</queries>", DIAL_INTENT + "    </queries>", 1)
        else:
            marker = "<application"
            idx = text.find(marker)
            if idx == -1:
                raise ValueError("AndroidManifest.xml sem tag <application>.")
            queries = "<queries>\n" + DIAL_INTENT + "    </queries>\n    "
            text = text[:idx] + queries + text[idx:]
        added.append("queries/DIAL")

    return text, added


def patch_plist(text: str) -> tuple[str, list[str]]:
    added: list[str] = []
    entries = ""

    if "NSLocationWhenInUseUsageDescription" not in text:
        entries += (
            "\t<key>NSLocationWhenInUseUsageDescription</key>\n"
            f"\t<string>{LOCATION_TEXT}</string>\n"
        )
        added.append("NSLocationWhenInUseUsageDescription")

    if "LSApplicationQueriesSchemes" not in text:
        entries += (
            "\t<key>LSApplicationQueriesSchemes</key>\n"
            "\t<array>\n\t\t<string>tel</string>\n\t</array>\n"
        )
        added.append("LSApplicationQueriesSchemes")

    if entries:
        idx = text.rfind("</dict>")
        if idx == -1:
            raise ValueError("Info.plist sem </dict>.")
        text = text[:idx] + entries + text[idx:]
    return text, added


def process(path: Path, patcher, check_only: bool) -> list[str] | None:
    if not path.exists():
        print(f"[ausente] {path} (rode `flutter create --platforms=android,ios .` antes)")
        return None
    original = path.read_text(encoding="utf-8")
    patched, added = patcher(original)
    if added and not check_only:
        path.write_text(patched, encoding="utf-8")
    status = "faltava" if check_only else "adicionado"
    print(f"[{path}] " + (f"{status}: {', '.join(added)}" if added else "já estava correto"))
    return added


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=".", help="raiz do projeto Flutter")
    parser.add_argument("--check", action="store_true", help="não altera; só verifica")
    args = parser.parse_args()

    root = Path(args.root)
    results = [
        process(root / MANIFEST, patch_manifest, args.check),
        process(root / PLIST, patch_plist, args.check),
    ]
    if any(r is None for r in results):
        return 2
    if args.check and any(results):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
