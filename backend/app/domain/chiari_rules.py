"""Estrazione delle regole datate dal testo operativo di Chiari."""
from __future__ import annotations

import re

_MARK = re.compile(r"\((perito|Ramona)\s+(\d{1,2}/\d{1,2})(?:/\d{2,4})?", re.IGNORECASE)


def extract_dated_rules(markdown: str) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw_line in markdown.splitlines():
        text = raw_line.strip()
        if text.startswith("- "):
            text = text[2:].strip()
        match = _MARK.search(text)
        if not match or len(text) < 40:
            continue
        if text in seen:
            continue
        seen.add(text)
        found.append(
            {
                "body": text,
                "rule_type": "istruzione",
                "author": match.group(1).capitalize() if match.group(1).lower() == "ramona" else "perito",
                "origin_label": f"{match.group(1).lower()} {match.group(2)}",
            }
        )
    return found
