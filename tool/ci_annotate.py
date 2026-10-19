#!/usr/bin/env python3
"""Converte a saída de `flutter analyze` / `flutter test` em anotações do GitHub Actions.

Uso: ci_annotate.py analyze analyze.txt | test test.txt
Limita a 10 anotações por chamada (limite do GitHub por passo).
"""
import re
import sys

mode, path = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
out = []

if mode == "analyze":
    # "  error • mensagem • lib/x.dart:12:3 • código"
    pat = re.compile(r"^\s*(error|warning|info)\s+[•-]\s+(.*?)\s+[•-]\s+(\S+?):(\d+):(\d+)\s+[•-]\s+(\S+)")
    for ln in lines:
        m = pat.match(ln)
        if m and m.group(1) != "info":
            lvl, msg, f, row, _, code = m.groups()
            out.append(f"::{'error' if lvl == 'error' else 'warning'} file={f},line={row}::{code}: {msg}")
else:
    # Mensagens de falha do reporter "expanded": linhas após "[E]" ou "Expected/Actual"
    for i, ln in enumerate(lines):
        if "[E]" in ln or ln.startswith("Expected:") or "Error:" in ln or "error:" in ln:
            out.append("::error::" + " ¶ ".join(l.strip() for l in lines[max(0, i - 1): i + 4])[:600])

for line in out[:10]:
    print(line)
