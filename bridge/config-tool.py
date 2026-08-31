#!/usr/bin/env python3
"""Lê/grava os dispositivos de áudio em ~/.baresip/config para o plugin oma.sip.

read : imprime JSON {"output": "<node.name>|", "input": "<node.name>|"}
       (vazio = dispositivo padrão do sistema).
write: lê UMA linha JSON do stdin {"output": ..., "input": ...} e reescreve
       apenas as linhas audio_player / audio_alert (= output) e audio_source
       (= input), preservando o resto do arquivo. Imprime {"ok": true}.

Formato do baresip: `audio_player pipewire,<node.name>`; sem vírgula/dispositivo
o módulo pipewire usa o padrão do sistema.
"""

import json
import os
import re
import sys

PATH = os.path.expanduser("~/.baresip/config")
DRIVER = "pipewire"

_PT = os.environ.get(
    "LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))
).startswith("pt")


def tr(en, pt):
    return pt if _PT else en


KEYS = {"audio_player": "output", "audio_alert": "output", "audio_source": "input"}
LINE_RE = re.compile(r"^\s*(audio_player|audio_alert|audio_source)\s+(\S*)")
FORBIDDEN = re.compile(r"[\s,]")


def parse_device(value):
    """'pipewire,alsa_output.x' -> 'alsa_output.x'; 'pipewire' -> ''."""
    parts = value.split(",", 1)
    return parts[1].strip() if len(parts) == 2 else ""


def read_lines():
    try:
        with open(PATH, encoding="utf-8") as fh:
            return fh.read().splitlines()
    except FileNotFoundError:
        return None


def do_read():
    info = {"output": "", "input": ""}
    for line in read_lines() or []:
        m = LINE_RE.match(line)
        if not m or m.group(1) == "audio_alert":
            continue
        info[KEYS[m.group(1)]] = parse_device(m.group(2))
    print(json.dumps(info))
    return 0


def render(key, device):
    value = DRIVER + ("," + device if device else "")
    return "%-24s%s" % (key, value)


def do_write():
    try:
        req = json.loads(sys.stdin.readline())
    except ValueError:
        print(json.dumps({"ok": False, "error": tr("invalid JSON", "JSON inválido")}))
        return 1
    devices = {
        "output": (req.get("output") or "").strip(),
        "input": (req.get("input") or "").strip(),
    }
    for name, value in devices.items():
        if FORBIDDEN.search(value):
            print(json.dumps({"ok": False, "error": name + tr(
                ": invalid device name", ": nome de dispositivo inválido")}))
            return 1

    lines = read_lines()
    if lines is None:
        print(json.dumps({"ok": False, "error": tr(
            "~/.baresip/config does not exist (run setup.sh)",
            "~/.baresip/config não existe (rode o setup.sh)")}))
        return 1

    seen = set()
    out = []
    for line in lines:
        m = LINE_RE.match(line)
        if m:
            key = m.group(1)
            seen.add(key)
            out.append(render(key, devices[KEYS[key]]))
        else:
            out.append(line)
    for key in ("audio_player", "audio_source", "audio_alert"):
        if key not in seen:
            out.append(render(key, devices[KEYS[key]]))

    tmp = PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    os.replace(tmp, PATH)
    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "read"
    sys.exit(do_read() if mode == "read" else do_write())
