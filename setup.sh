#!/usr/bin/env bash
set -euo pipefail

# Setup do Softfone SIP (oma.sip) para Omarchy 4+ — uma vez por máquina.
# Idempotente: pode rodar de novo sem perder config existente.
#
# O que faz (o `omarchy plugin add` NÃO roda este script; ele é manual):
#   1. instala o pacote baresip se faltar (pede confirmação e sudo)
#   2. cria ~/.baresip/config a partir do template (se não existir)
#   3. pergunta servidor/ramal/senha e grava ~/.baresip/accounts (600)
#      via bridge/account-tool.py — a senha nunca passa por argv
#   4. instala e (re)inicia a unit systemd --user baresip.service

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BARESIP_DIR="$HOME/.baresip"
UNIT_DIR="$HOME/.config/systemd/user"
ACCOUNT_TOOL="$DIR/bridge/account-tool.py"

echo "== Softfone SIP (oma.sip) — setup =="

for cmd in python3 jq systemctl; do
  command -v "$cmd" &>/dev/null || { echo "erro: '$cmd' não encontrado" >&2; exit 1; }
done

if ! pacman -Q baresip &>/dev/null; then
  read -rp "O pacote baresip não está instalado. Instalar agora com sudo pacman? [s/N] " ok
  if [[ "${ok,,}" == s* ]]; then
    sudo pacman -S --needed baresip
  else
    echo "instale manualmente (sudo pacman -S baresip) e rode o setup de novo." >&2
    exit 1
  fi
fi

mkdir -p "$BARESIP_DIR"
if [[ ! -f "$BARESIP_DIR/config" ]]; then
  install -m 644 "$DIR/templates/config.tmpl" "$BARESIP_DIR/config"
  echo "-> config criado em ~/.baresip/config"
fi

if [[ "$(python3 "$ACCOUNT_TOOL" read | jq -r '.configured')" != "true" ]]; then
  read -rp "Servidor SIP (ex.: sip.exemplo.com.br): " SERVER
  read -rp "Ramal/usuário (ex.: 201): " USERNAME
  read -rp "Login de autenticação [${USERNAME}]: " LOGIN
  read -rsp "Senha SIP: " PASSWORD
  echo
  # jq monta o JSON com escape correto; account-tool grava com 0600.
  if ! result="$(jq -cn --arg server "$SERVER" --arg username "$USERNAME" \
        --arg login "${LOGIN:-}" --arg password "$PASSWORD" \
        '{server: $server, username: $username, domain: "", login: $login, password: $password}' \
      | python3 "$ACCOUNT_TOOL" write)"; then
    echo "erro ao gravar a conta: $(jq -r '.error // .' <<<"$result" 2>/dev/null || echo "$result")" >&2
    exit 1
  fi
  echo "-> conta gravada em ~/.baresip/accounts (600)"
fi
chmod 600 "$BARESIP_DIR/accounts"

mkdir -p "$UNIT_DIR"
install -m 644 "$DIR/systemd/baresip.service" "$UNIT_DIR/baresip.service"
systemctl --user daemon-reload
systemctl --user enable baresip.service
# restart (e não enable --now): um serviço já ativo precisa recarregar a conta
systemctl --user restart baresip.service
echo "-> serviço baresip habilitado e (re)iniciado"

echo
echo "AVISO de segurança: por padrão o transporte é UDP sem criptografia."
echo "Para TLS+SRTP, edite ~/.baresip/accounts (transport=tls, mediaenc=srtp)."
echo "O controle local do baresip (ctrl_tcp) fica restrito a 127.0.0.1."
echo
echo "Pronto! Se o widget não aparecer na barra:"
echo "  omarchy plugin enable oma.sip && omarchy bar put oma.sip --section right"
