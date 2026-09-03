#!/usr/bin/env bash
set -euo pipefail

# oma.sip setup for Omarchy 4+ — run once per machine. Idempotent.
# Setup do oma.sip para Omarchy 4+ — uma vez por máquina. Idempotente.
#
# What it does / o que faz (`omarchy plugin add` does NOT run this script):
#   1. installs the baresip and python-gobject packages if missing
#      (asks before sudo)
#   2. creates ~/.baresip (0700) and its config from the template (if
#      missing); migrates an old config from ctrl_tcp to ctrl_dbus
#   3. asks for server/extension/password and writes ~/.baresip/accounts (600)
#      via bridge/account-tool.py — the password never touches argv;
#      TLS+SRTP by default, unencrypted UDP only by explicit choice
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

missing=()
pacman -Q baresip &>/dev/null || missing+=(baresip)
python3 -c 'from gi.repository import Gio' &>/dev/null || missing+=(python-gobject)
if (( ${#missing[@]} )); then
  read -rp "$(t "Missing packages: ${missing[*]}. Install now with sudo pacman? [y/N] " "Pacotes faltando: ${missing[*]}. Instalar agora com sudo pacman? [s/N] ")" ok
  if [[ "${ok,,}" == s* || "${ok,,}" == y* ]]; then
    sudo pacman -S --needed "${missing[@]}"
  else
    echo "$(t "install manually (sudo pacman -S ${missing[*]}) and run setup again." "instale manualmente (sudo pacman -S ${missing[*]}) e rode o setup de novo.")" >&2
    exit 1
  fi
fi

# 0700: the directory holds the SIP password (accounts).
mkdir -p -m 700 "$BARESIP_DIR"
chmod 700 "$BARESIP_DIR"
if [[ ! -f "$BARESIP_DIR/config" ]]; then
  install -m 644 "$DIR/templates/config.tmpl" "$BARESIP_DIR/config"
  echo "-> $(t "config created at ~/.baresip/config" "config criado em ~/.baresip/config")"
elif grep -q "ctrl_tcp" "$BARESIP_DIR/config"; then
  # Migration: ctrl_tcp (unauthenticated TCP) -> ctrl_dbus (per-user session
  # bus, kernel-authenticated). Same command set; no TCP port left open.
  sed -i -e 's/^\(module_app[[:space:]]*\)ctrl_tcp\.so/\1ctrl_dbus.so/' \
         -e '/^ctrl_tcp_listen/d' "$BARESIP_DIR/config"
  grep -q "^ctrl_dbus_use" "$BARESIP_DIR/config" || echo "ctrl_dbus_use           session" >> "$BARESIP_DIR/config"
  echo "-> $(t "config migrated from ctrl_tcp to ctrl_dbus (session bus)" "config migrado de ctrl_tcp para ctrl_dbus (barramento de sessão)")"
fi

if [[ "$(python3 "$ACCOUNT_TOOL" read | jq -r '.configured')" != "true" ]]; then
  read -rp "$(t "SIP server (e.g. sip.example.com): " "Servidor SIP (ex.: sip.exemplo.com.br): ")" SERVER
  read -rp "$(t "Extension/username (e.g. 201): " "Ramal/usuário (ex.: 201): ")" USERNAME
  read -rp "$(t "Auth login [${USERNAME}]: " "Login de autenticação [${USERNAME}]: ")" LOGIN
  read -rsp "$(t "SIP password: " "Senha SIP: ")" PASSWORD
  echo
  read -rp "$(t "Encrypt with TLS + SRTP? (server must support it) [Y/n] " "Criptografar com TLS + SRTP? (o servidor precisa suportar) [S/n] ")" SEC
  case "${SEC,,}" in n*) SECURE=false ;; *) SECURE=true ;; esac
  # jq builds the JSON with proper escaping; account-tool writes it as 0600.
  if ! result="$(jq -cn --arg server "$SERVER" --arg username "$USERNAME" \
        --arg login "${LOGIN:-}" --arg password "$PASSWORD" --argjson secure "$SECURE" \
        '{server: $server, username: $username, domain: "", login: $login, password: $password, secure: $secure}' \
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
t "Security: local control uses the per-user D-Bus session bus (ctrl_dbus)." "Segurança: o controle local usa o barramento de sessão D-Bus por usuário (ctrl_dbus)."
t "Accounts default to TLS + SRTP; UDP only by explicit choice." "Contas usam TLS + SRTP por padrão; UDP só por escolha explícita."
t "An account saved earlier keeps its transport until re-saved in the widget." "Conta salva anteriormente mantém o transporte até ser regravada no widget."
echo
t "Done! If the widget does not show up in the bar:" "Pronto! Se o widget não aparecer na barra:"
echo "  omarchy plugin enable oma.sip && omarchy bar put oma.sip --section right"
