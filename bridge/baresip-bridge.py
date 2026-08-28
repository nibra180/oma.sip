#!/usr/bin/env python3
"""Ponte entre o omarchy-shell (NDJSON em stdin/stdout) e o ctrl_tcp do
baresip (JSON com framing netstring em 127.0.0.1:4444).

stdin  : uma linha = um JSON de comando -> enviado como netstring
stdout : cada netstring recebida -> uma linha JSON
Sai com código != 0 quando o baresip fecha ou recusa a conexão; o Service
religa a ponte com backoff.
"""

import json
import select
import socket
import sys

HOST = "127.0.0.1"
PORT = 4444


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def parse_netstrings(buf):
    """Extrai payloads completos; retorna (payloads, resto_do_buffer)."""
    out = []
    while True:
        sep = buf.find(b":")
        if sep < 0:
            if len(buf) > 10:
                raise ValueError("prefixo de tamanho sem ':'")
            break
        try:
            length = int(buf[:sep])
        except ValueError:
            raise ValueError("tamanho netstring invalido: %r" % buf[:12])
        end = sep + 1 + length
        if len(buf) <= end:
            break
        if buf[end:end + 1] != b",":
            raise ValueError("netstring sem ',' terminal")
        out.append(buf[sep + 1:end])
        buf = buf[end + 1:]
    return out, buf


def main():
    try:
        sock = socket.create_connection((HOST, PORT), timeout=5)
    except OSError as exc:
        emit({"bridge": "error", "detail": str(exc)})
        return 1
    sock.setblocking(False)
    emit({"bridge": "connected"})

    buf = b""
    stdin = sys.stdin.buffer
    while True:
        ready, _, _ = select.select([sock, stdin], [], [])

        if stdin in ready:
            line = stdin.readline()
            if not line:
                return 0  # shell encerrou a ponte
            line = line.strip()
            if line:
                sock.sendall(b"%d:%s," % (len(line), line))

        if sock in ready:
            try:
                chunk = sock.recv(65536)
            except (BlockingIOError, InterruptedError):
                continue
            if not chunk:
                emit({"bridge": "closed"})
                return 1
            buf += chunk
            try:
                msgs, buf = parse_netstrings(buf)
            except ValueError as exc:
                emit({"bridge": "error", "detail": str(exc)})
                return 1
            for msg in msgs:
                sys.stdout.write(msg.decode("utf-8", "replace") + "\n")
            if msgs:
                sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main())
