#!/usr/bin/env bash
set -euo pipefail

# oma.sip setup for Omarchy 4+ — run once per machine. Idempotent.
# Setup do oma.sip para Omarchy 4+ — uma vez por máquina. Idempotente.
#
# What it does / o que faz (`omarchy plugin add` does NOT run this script):
#   1. installs the baresip package if missing (asks before sudo)
#   2. creates ~/.baresip/config from the template (if missing)
#   3. asks for server/extension/password and writes ~/.baresip/accounts (600)
#      via bridge/account-tool.py — the password never touches argv
#   4. installs and (re)starts the baresip.service systemd --user unit

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BARESIP_DIR="$HOME/.baresip"
UNIT_DIR="$HOME/.config/systemd/user"
ACCOUNT_TOOL="$DIR/bridge/account-tool.py"

# Messages follow the system language: English default, pt-BR on pt_* locales.
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) PT=1 ;; *) PT=0 ;; esac
t() { if (( PT )); then echo "$2"; else echo "$1"; fi; }

echo "== oma.sip — setup =="

for cmd in python3 jq systemctl; do
  command -v "$cmd" &>/dev/null || { echo "$(t "error: '$cmd' not found" "erro: '$cmd' não encontrado")" >&2; exit 1; }
done

if ! pacman -Q baresip &>/dev/null; then
  read -rp "$(t "baresip is not installed. Install it now with sudo pacman? [y/N] " "O pacote baresip não está instalado. Instalar agora com sudo pacman? [s/N] ")" ok
  if [[ "${ok,,}" == s* || "${ok,,}" == y* ]]; then
    sudo pacman -S --needed baresip
  else
    echo "$(t "install it manually (sudo pacman -S baresip) and run setup again." "instale manualmente (sudo pacman -S baresip) e rode o setup de novo.")" >&2
    exit 1
  fi
fi

mkdir -p "$BARESIP_DIR"
if [[ ! -f "$BARESIP_DIR/config" ]]; then
  install -m 644 "$DIR/templates/config.tmpl" "$BARESIP_DIR/config"
  echo "-> $(t "config created at ~/.baresip/config" "config criado em ~/.baresip/config")"
fi

if [[ "$(python3 "$ACCOUNT_TOOL" read | jq -r '.configured')" != "true" ]]; then
  read -rp "$(t "SIP server (e.g. sip.example.com): " "Servidor SIP (ex.: sip.exemplo.com.br): ")" SERVER
  read -rp "$(t "Extension/username (e.g. 201): " "Ramal/usuário (ex.: 201): ")" USERNAME
  read -rp "$(t "Auth login [${USERNAME}]: " "Login de autenticação [${USERNAME}]: ")" LOGIN
  read -rsp "$(t "SIP password: " "Senha SIP: ")" PASSWORD
  echo
  # jq builds the JSON with proper escaping; account-tool writes it as 0600.
  if ! result="$(jq -cn --arg server "$SERVER" --arg username "$USERNAME" \
        --arg login "${LOGIN:-}" --arg password "$PASSWORD" \
        '{server: $server, username: $username, domain: "", login: $login, password: $password}' \
      | python3 "$ACCOUNT_TOOL" write)"; then
    echo "$(t "failed to write the account:" "erro ao gravar a conta:") $(jq -r '.error // .' <<<"$result" 2>/dev/null || echo "$result")" >&2
    exit 1
  fi
  echo "-> $(t "account written to ~/.baresip/accounts (600)" "conta gravada em ~/.baresip/accounts (600)")"
fi
chmod 600 "$BARESIP_DIR/accounts"

mkdir -p "$UNIT_DIR"
install -m 644 "$DIR/systemd/baresip.service" "$UNIT_DIR/baresip.service"
systemctl --user daemon-reload
systemctl --user enable baresip.service
# restart (not enable --now): an already-running service must reload the account
systemctl --user restart baresip.service
echo "-> $(t "baresip service enabled and (re)started" "serviço baresip habilitado e (re)iniciado")"

echo
t "SECURITY NOTE: transport defaults to unencrypted UDP." "AVISO de segurança: por padrão o transporte é UDP sem criptografia."
t "For TLS+SRTP, edit ~/.baresip/accounts (transport=tls, mediaenc=srtp)." "Para TLS+SRTP, edite ~/.baresip/accounts (transport=tls, mediaenc=srtp)."
t "The local baresip control (ctrl_tcp) stays bound to 127.0.0.1." "O controle local do baresip (ctrl_tcp) fica restrito a 127.0.0.1."
echo
t "Done! If the widget does not show up in the bar:" "Pronto! Se o widget não aparecer na barra:"
echo "  omarchy plugin enable oma.sip && omarchy bar put oma.sip --section right"
