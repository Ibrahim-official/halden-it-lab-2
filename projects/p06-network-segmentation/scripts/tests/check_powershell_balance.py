#!/usr/bin/env python3
"""Local lint helper: check PowerShell brace/paren balance, ignoring strings and comments.

This is not PowerShell itself (no pwsh in the lab editor environment), so it is deliberately simple:
strip here-strings, single/double quoted strings (including PowerShell "``" escapes) and comments,
then compare bracket counts. It catches typo'd scripts before they reach the lab. The real check is
`Invoke-ScriptAnalyzer -Recurse` on a Windows host, per AGENTS.md 4.4.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def strip_powershell(text: str) -> str:
    # Here-strings first: @" ... "@ and @' ... '@ (terminator at line start).
    text = re.sub(r'@"\r?\n.*?\r?\n"@', 'HERESTRING', text, flags=re.S)
    text = re.sub(r"@'\r?\n.*?\r?\n'@", 'HERESTRING', text, flags=re.S)
    # Block comments <# ... #>
    text = re.sub(r'<#.*?#>', '', text, flags=re.S)
    # Single-quoted strings ('' is an escaped quote) and double-quoted strings with ` escapes.
    text = re.sub(r"'(?:[^']|'')*'", "STR", text)
    text = re.sub(r'"(?:[^"`]|`.|"")*"', "STR", text)
    # Line comments
    text = re.sub(r'(?m)(?<!\S)#.*$', '', text)
    return text


def check(path: Path) -> bool:
    stripped = strip_powershell(path.read_text(encoding="utf-8"))
    ok = True
    for opener, closer in (("{", "}"), ("(", ")"), ("[", "]")):
        if stripped.count(opener) != stripped.count(closer):
            ok = False
            print(f"  UNBALANCED {opener}{closer}: {stripped.count(opener)} vs {stripped.count(closer)}")
    print(("  balanced OK  " if ok else "  CHECK        ") + str(path))
    return ok


def main(argv: list[str]) -> int:
    targets = [Path(p) for p in argv[1:]] or sorted(Path("scripts").glob("*.ps1"))
    all_ok = True
    for target in targets:
        all_ok = check(target) and all_ok
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
