#!/usr/bin/env python3
"""Lê/grava ~/.baresip/accounts (uma conta) para o plugin oma.sip.

read : imprime JSON {configured, username, domain, server, login, hasPassword}
       — a senha NUNCA sai deste script.
write: lê UMA linha JSON do stdin {server, username, domain, login, password}
       (senha via stdin para nunca aparecer em argv/processos). Senha vazia
       mantém a atual. Grava com permissão 0600 e imprime {"ok": true}.
"""

import json
import os
import re
import sys

PATH = os.path.expanduser("~/.baresip/accounts")
HEADER = (
    "# Conta SIP — gerenciada pelo plugin oma.sip (widget ou setup.sh).\n"
    "# Contém a senha do ramal: permissão 600 obrigatória.\n"
    "# Para TLS+SRTP: adicione ;transport=tls no URI e no outbound e ;mediaenc=srtp\n"
    "# (o widget sobrescreve esta linha ao salvar a conta).\n"
)
FORBIDDEN = re.compile(r'[;"<>\s]')


def parse():
    info = {
        "configured": False,
        "username": "",
        "domain": "",
        "server": "",
        "login": "",
        "hasPassword": False,
    }
    cur_pass = ""
    try:
        with open(PATH, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                m = re.search(r"<sips?:([^@>]+)@([^;>]+)>", line)
                if not m:
                    continue
                info["configured"] = True
                info["username"] = m.group(1)
                info["domain"] = m.group(2)
                pm = re.search(r"auth_pass=([^;]*)", line)
                if pm:
                    cur_pass = pm.group(1)
                    info["hasPassword"] = cur_pass != ""
                lm = re.search(r"auth_user=([^;]*)", line)
                if lm:
                    info["login"] = lm.group(1)
                sm = re.search(r'outbound="sips?:([^";]+)"', line)
                if sm:
                    info["server"] = sm.group(1)
                break
    except FileNotFoundError:
        pass
    return info, cur_pass


def do_read():
    info, _ = parse()
    print(json.dumps(info))
    return 0


def do_write():
    try:
        req = json.loads(sys.stdin.readline())
    except ValueError:
        print(json.dumps({"ok": False, "error": "JSON inválido"}))
        return 1

    _, cur_pass = parse()
    server = (req.get("server") or "").strip()
    username = (req.get("username") or "").strip()
    domain = (req.get("domain") or "").strip() or server
    login = (req.get("login") or "").strip() or username
    password = req.get("password") or ""
    if password == "":
        password = cur_pass

    if not server or not username:
        print(json.dumps({"ok": False, "error": "servidor e usuário são obrigatórios"}))
        return 1
    if password == "":
        print(json.dumps({"ok": False, "error": "defina a senha (ainda não há uma salva)"}))
        return 1
    for name, value in (("servidor", server), ("usuário", username),
                        ("domínio", domain), ("login", login), ("senha", password)):
        if FORBIDDEN.search(value):
            print(json.dumps({"ok": False,
                              "error": name + " contém caractere não suportado (; \" < > ou espaço)"}))
            return 1

    line = ('<sip:%s@%s>;auth_user=%s;auth_pass=%s;outbound="sip:%s";'
            "answermode=manual;regint=300;fbregint=30;"
            "audio_codecs=opus/48000/2,pcma,pcmu\n"
            % (username, domain, login, password, server))
    fd = os.open(PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(HEADER + line)
    os.chmod(PATH, 0o600)
    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "read"
    sys.exit(do_read() if mode == "read" else do_write())
