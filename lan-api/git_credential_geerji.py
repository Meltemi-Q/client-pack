# -*- coding: utf-8 -*-
"""Git credential helper: only fills GitHub for geerji/medical_version_client-.

Never answers for other GitHub repos, so a token sitting on the pack PC
cannot be reused to clone personal repositories.
"""
from __future__ import annotations

import sys
from pathlib import Path

ALLOWED_HOST = "github.com"
ALLOWED_PATH = "geerji/medical_version_client-"
TOKEN_FILE = Path(__file__).with_name("git.token")


def _fields():
    data = {}
    for line in sys.stdin.read().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action != "get":
        return
    fields = _fields()
    host = fields.get("host", "")
    path = fields.get("path", "")
    if host != ALLOWED_HOST or ALLOWED_PATH not in path:
        return
    if not TOKEN_FILE.is_file():
        return
    token = TOKEN_FILE.read_text(encoding="utf-8").strip()
    if not token:
        return
    sys.stdout.write("username=x-access-token\n")
    sys.stdout.write("password=%s\n" % token)


if __name__ == "__main__":
    main()
