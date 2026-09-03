#!/usr/bin/env python3
"""Lê/grava os dispositivos de áudio em ~/.baresip/config para o plugin oma.sip.

read : imprime JSON {"output": "<node.name>|", "input": "<node.name>|"}
       (vazio = dispositivo padrão do sistema).
write: lê UMA linha JSON do stdin {"output": ..., "input": ...} e reescreve
       apenas as linhas audio_player / audio_alert (= output) e audio_source
       (= input), preservando o resto do arquivo. Imprime {"ok": true}.

Gravação endurecida como no account-tool: lock exclusivo (flock), temp com
nome aleatório (mkstemp) no mesmo diretório, fsync em arquivo e diretório,
os.replace atômico, leitura com O_NOFOLLOW (recusa symlink) e entrada
limitada (linha <= 8 KiB, nome de dispositivo <= 255).

Formato do baresip: `audio_player pipewire,<node.name>`; sem vírgula/dispositivo
o módulo pipewire usa o padrão do sistema.
"""

import fcntl
import json
import os
import re
import sys
import tempfile

BARESIP_DIR = os.path.expanduser("~/.baresip")
PATH = os.path.join(BARESIP_DIR, "config")
LOCK = os.path.join(BARESIP_DIR, ".oma.sip.lock")
DRIVER = "pipewire"
MAX_LINE = 8192
MAX_FIELD = 255

_PT = os.environ.get(
    "LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))
).startswith("pt")


def tr(en, pt):
    return pt if _PT else en


KEYS = {"audio_player": "output", "audio_alert": "output", "audio_source": "input"}
LINE_RE = re.compile(r"^\s*(audio_player|audio_alert|audio_source)\s+(\S*)")
FORBIDDEN = re.compile(r"[\s,\x00-\x1f]")


def lock_exclusive():
    fd = os.open(LOCK, os.O_WRONLY | os.O_CREAT | os.O_CLOEXEC, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def atomic_write(path, data, mode):
    fd, tmp = tempfile.mkstemp(prefix=".config.", dir=BARESIP_DIR)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
        dfd = os.open(BARESIP_DIR, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def parse_device(value):
    """'pipewire,alsa_output.x' -> 'alsa_output.x'; 'pipewire' -> ''."""
    parts = value.split(",", 1)
    return parts[1].strip() if len(parts) == 2 else ""


def read_lines():
    try:
        fd = os.open(PATH, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        with os.fdopen(fd, encoding="utf-8") as fh:
            return fh.read().splitlines()
    except FileNotFoundError:
        return None
    except OSError:
        return None  # symlink (ELOOP) ou falha de leitura


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


def fail(msg):
    print(json.dumps({"ok": False, "error": msg}))
    return 1


def do_write():
    raw = sys.stdin.buffer.readline(MAX_LINE + 1)
    if len(raw) > MAX_LINE:
        return fail(tr("request too long", "requisição longa demais"))
    try:
        req = json.loads(raw)
    except ValueError:
        return fail(tr("invalid JSON", "JSON inválido"))
    if not isinstance(req, dict):
        return fail(tr("invalid JSON", "JSON inválido"))
    devices = {
        "output": (req.get("output") or "").strip(),
        "input": (req.get("input") or "").strip(),
    }
    for name, value in devices.items():
        if len(value) > MAX_FIELD or FORBIDDEN.search(value):
            return fail(name + tr(": invalid device name",
                                  ": nome de dispositivo inválido"))

    lock_fd = lock_exclusive()
    try:
        if os.path.islink(PATH):
            return fail(tr("~/.baresip/config is a symlink — refusing to write",
                           "~/.baresip/config é um symlink — gravação recusada"))
        lines = read_lines()
        if lines is None:
            return fail(tr("~/.baresip/config does not exist (run setup.sh)",
                           "~/.baresip/config não existe (rode o setup.sh)"))

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

        atomic_write(PATH, "\n".join(out) + "\n", 0o644)
    finally:
        os.close(lock_fd)
    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "read"
    sys.exit(do_read() if mode == "read" else do_write())
