#!/usr/bin/env python3
"""Lê/grava ~/.baresip/contacts para o plugin oma.sip.

O baresip NÃO persiste contatos: o módulo contact.so escreve o template apenas
na primeira inicialização e /addcontact e /rmcontact mudam só a lista em
memória (module_close faz list_flush). Por isso este script é o dono do
arquivo, no mesmo padrão de account-tool/config-tool: lock exclusivo (flock),
temp com nome aleatório (mkstemp), fsync em arquivo e diretório, os.replace
atômico, leitura com O_NOFOLLOW (recusa symlink) e entrada limitada.

list  : imprime {"configured","contacts":[{"name","uri","params"}]}
add   : lê {"name","uri"} do stdin e acrescenta uma linha ao final
remove: lê {"uri"} do stdin e remove as linhas com essa uri exata

Linhas de comentário, parâmetros existentes (;access=..., ;presence=...) e
qualquer outra linha do arquivo ficam intactos. Efeito colateral conhecido: o
baresip lê o arquivo no start, então uma regra ;access= nova só vale depois de
reiniciar o serviço.

Mensagens seguem o idioma do sistema (LANG/LC_MESSAGES): en padrão, pt-BR.
"""

import contextlib
import fcntl
import json
import os
import re
import sys
import tempfile

BARESIP_DIR = os.path.expanduser("~/.baresip")
PATH = os.path.join(BARESIP_DIR, "contacts")
LOCK = os.path.join(BARESIP_DIR, ".oma.sip.lock")
MAX_LINE = 8192
MAX_NAME = 64
MAX_URI = 255

# "Nome" <sip:user@host>;params  |  <sip:user@host>
LINE_RE = re.compile(
    r'^\s*"?(?P<name>[^"<>]*?)"?\s*<(?P<uri>[^<>]+)>(?P<params>[^<>]*)\s*$')
# baresip decodifica a linha como SIP address: precisa de esquema e host.
URI_RE = re.compile(r"^sips?:[^<>\s;\"@]+@[^<>\s;\"]+$")
BAD_NAME = re.compile(r'["<>;\\\x00-\x1f]')

_PT = os.environ.get(
    "LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))
).startswith("pt")


def tr(en: str, pt: str) -> str:
    return pt if _PT else en


HEADER = tr(
    "#\n"
    "# SIP contacts - managed by the oma.sip plugin.\n"
    "# One contact per line: \"Display name\" <sip:user@host>;addr-params\n"
    "# See baresip's modules/contact for the addr-params\n"
    "# (;presence=, ;access=allow|block, ;audio=, ;video=).\n"
    "#\n"
    "\n",
    "#\n"
    "# Contatos SIP - gerenciados pelo plugin oma.sip.\n"
    "# Um contato por linha: \"Nome\" <sip:usuario@host>;addr-params\n"
    "# Veja modules/contact do baresip para os addr-params\n"
    "# (;presence=, ;access=allow|block, ;audio=, ;video=).\n"
    "#\n"
    "\n",
)


def fail(en, pt):
    print(json.dumps({"ok": False, "error": tr(en, pt)}))
    return 1


def lock_exclusive():
    fd = os.open(LOCK, os.O_WRONLY | os.O_CREAT | os.O_CLOEXEC, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def read_lines():
    try:
        fd = os.open(PATH, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        with os.fdopen(fd, encoding="utf-8") as fh:
            return fh.read().splitlines()
    except FileNotFoundError:
        return None
    except OSError:
        # symlink (ELOOP) ou falha de leitura: trata como inexistente
        return None


def parse_lines(lines):
    out = []
    for line in lines or []:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        out.append({"name": m.group("name").strip(),
                    "uri": m.group("uri").strip(),
                    "params": m.group("params").strip()})
    return out


def atomic_write(data, mode):
    fd, tmp = tempfile.mkstemp(prefix=".contacts.", dir=BARESIP_DIR)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, PATH)
        dfd = os.open(BARESIP_DIR, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def do_list():
    lines = read_lines()
    print(json.dumps({
        "configured": lines is not None,
        "contacts": parse_lines(lines),
    }))
    return 0


def read_request():
    raw = sys.stdin.buffer.readline(MAX_LINE + 1)
    if len(raw) > MAX_LINE:
        return None
    try:
        req = json.loads(raw)
    except ValueError:
        return None
    return req if isinstance(req, dict) else None


def validate(uri):
    if not uri or len(uri) > MAX_URI or not URI_RE.match(uri):
        return tr("enter an address like user@host or extension@host",
                  "informe um endereço como usuario@host ou ramal@host")
    return ""


def do_add():
    req = read_request()
    if req is None:
        return fail("invalid request", "requisição inválida")
    uri = (req.get("uri") or "").strip()
    name = (req.get("name") or "").strip()
    if len(name) > MAX_NAME or BAD_NAME.search(name):
        return fail("invalid name (no quotes, <, > or ;)",
                    "nome inválido (sem aspas, <, > nem ;)")
    err = validate(uri)
    if err:
        return fail(err, err)

    try:
        os.makedirs(BARESIP_DIR, mode=0o700, exist_ok=True)
    except OSError as exc:
        return fail(f"cannot create ~/.baresip ({exc})",
                    f"não foi possível criar ~/.baresip ({exc})")

    lock_fd = lock_exclusive()
    try:
        if os.path.islink(PATH):
            return fail("~/.baresip/contacts is a symlink — refusing to write",
                        "~/.baresip/contacts é um symlink — gravação recusada")
        lines = read_lines()
        mode = 0o600
        if lines is None:
            lines = HEADER.splitlines()
        else:
            with contextlib.suppress(OSError):
                mode = os.stat(PATH).st_mode & 0o777
        if any(c["uri"] == uri for c in parse_lines(lines)):
            return fail("contact already saved", "contato já salvo")
        lines.append(f'"{name}" <{uri}>' if name else f"<{uri}>")
        atomic_write("\n".join(lines) + "\n", mode)
    finally:
        os.close(lock_fd)
    print(json.dumps({"ok": True}))
    return 0


def do_remove():
    req = read_request()
    if req is None:
        return fail("invalid request", "requisição inválida")
    uri = (req.get("uri") or "").strip()

    lock_fd = lock_exclusive()
    try:
        if os.path.islink(PATH):
            return fail("~/.baresip/contacts is a symlink — refusing to write",
                        "~/.baresip/contacts é um symlink — gravação recusada")
        lines = read_lines()
        if lines is None:
            return fail("no contacts file", "sem arquivo de contatos")
        kept, removed = [], 0
        for line in lines:
            m = LINE_RE.match(line)
            if m and not line.lstrip().startswith("#") \
                    and m.group("uri").strip() == uri:
                removed += 1
                continue
            kept.append(line)
        if not removed:
            return fail("contact not found", "contato não encontrado")
        atomic_write("\n".join(kept) + "\n", os.stat(PATH).st_mode & 0o777)
    finally:
        os.close(lock_fd)
    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    if mode == "add":
        sys.exit(do_add())
    if mode == "remove":
        sys.exit(do_remove())
    sys.exit(do_list())
