#!/usr/bin/env python3
"""Ponte entre o omarchy-shell (NDJSON em stdin/stdout) e o ctrl_dbus do
baresip no barramento de sessão D-Bus (com.github.Baresip em /baresip).

O barramento de sessão é por usuário e autenticado pelo kernel (SO_PEERCRED):
só processos do mesmo UID alcançam o baresip — nenhum socket TCP fica aberto.

stdin  : uma linha = um JSON {"command","params","token"} -> invoke()
stdout : sinais `event` e respostas de invoke -> uma linha JSON cada

Limites (entrada e saída são de produtores não confiáveis ou semi-confiáveis):
comando <= 8 KiB/linha, params <= 2 KiB, evento <= 64 KiB, resposta <= 64 KiB,
invoke com deadline de 10 s. Sai com código != 0 quando o baresip some do
barramento; o Service religa a ponte com backoff.
"""

import json
import os
import re
import sys
import threading

from gi.repository import Gio, GLib

BUS_NAME = "com.github.Baresip"
OBJ_PATH = "/baresip"
IFACE = "com.github.Baresip"

MAX_LINE = 8192            # linha de comando vinda do shell
MAX_PARAMS = 2048
MAX_EVENT = 65536          # payload de evento vindo do baresip
MAX_RESPONSE = 65536       # resposta de invoke repassada ao shell
INVOKE_TIMEOUT_MS = 10000  # deadline por comando
CMD_RE = re.compile(r"^[a-z_]{1,32}$")

_out_lock = threading.Lock()


def emit(obj):
    with _out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def main():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as exc:
        emit({"bridge": "error", "detail": str(exc)})
        return 1

    loop = GLib.MainLoop()
    state = {"up": False, "rc": 1}

    def on_event(_conn, _sender, _path, _iface, signal, params):
        if signal != "event" or params.n_children() < 3:
            return
        raw = params.unpack()[2]
        if not isinstance(raw, str) or len(raw) > MAX_EVENT:
            return
        try:
            ev = json.loads(raw)
        except ValueError:
            return
        if not isinstance(ev, dict):
            return
        ev["event"] = True
        emit(ev)

    def on_appeared(_conn, _name, _owner):
        state["up"] = True
        emit({"bridge": "connected"})

    def on_vanished(_conn, _name):
        if state["up"]:
            emit({"bridge": "closed"})
        else:
            emit({"bridge": "error",
                  "detail": "baresip (ctrl_dbus) is not on the session bus"})
        state["rc"] = 1
        loop.quit()

    bus.signal_subscribe(BUS_NAME, IFACE, "event", OBJ_PATH, None,
                         Gio.DBusSignalFlags.NONE, on_event)
    Gio.bus_watch_name_on_connection(bus, BUS_NAME,
                                     Gio.BusNameWatcherFlags.NONE,
                                     on_appeared, on_vanished)

    def reply_err(detail, token):
        out = {"response": True, "ok": False, "data": detail}
        if token:
            out["token"] = token
        emit(out)

    def invoke(cmdline, token):
        try:
            res = bus.call_sync(BUS_NAME, OBJ_PATH, IFACE, "invoke",
                                GLib.Variant("(s)", (cmdline,)),
                                GLib.VariantType("(s)"),
                                Gio.DBusCallFlags.NONE, INVOKE_TIMEOUT_MS,
                                None)
            out = {"response": True, "ok": True,
                   "data": res.unpack()[0][:MAX_RESPONSE]}
            if token:
                out["token"] = token
            emit(out)
        except GLib.Error as exc:
            reply_err(str(exc.message)[:512], token)

    def stdin_loop():
        stdin = sys.stdin.buffer
        while True:
            line = stdin.readline(MAX_LINE + 1)
            if not line:
                state["rc"] = 0  # shell encerrou a ponte
                loop.quit()
                return
            if len(line) > MAX_LINE:
                while not line.endswith(b"\n"):  # descarta o excedente
                    line = stdin.readline(MAX_LINE)
                    if not line:
                        state["rc"] = 0
                        loop.quit()
                        return
                reply_err("command line too long", "")
                continue
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                reply_err("invalid JSON command", "")
                continue
            if not isinstance(msg, dict):
                reply_err("invalid JSON command", "")
                continue
            cmd = str(msg.get("command") or "")
            params = str(msg.get("params") or "")
            token = str(msg.get("token") or "")[:64]
            if not CMD_RE.match(cmd):
                reply_err("invalid command name", token)
                continue
            if len(params) > MAX_PARAMS or any(ord(c) < 32 for c in params):
                reply_err("invalid params", token)
                continue
            invoke(cmd + (" " + params if params else ""), token)

    threading.Thread(target=stdin_loop, daemon=True).start()
    loop.run()
    # os._exit: a thread de stdin pode estar bloqueada em readline segurando o
    # lock do buffer — a finalização normal do interpretador abortaria (cada
    # emit já faz flush, nada fica pendente).
    with _out_lock:
        os._exit(state["rc"])


if __name__ == "__main__":
    sys.exit(main())
