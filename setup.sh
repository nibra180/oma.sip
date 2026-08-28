#!/usr/bin/env bash
set -euo pipefail

# Setup do Softfone (Vinicius Galleti) para Omarchy 4+ (uma vez por máquina).
# Idempotente: pode rodar de novo sem perder config existente.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BARESIP_DIR="$HOME/.baresip"
UNIT_DIR="$HOME/.config/systemd/user"

echo "== Softfone (Vinicius Galleti) — setup =="

if ! pacman -Q baresip &>/dev/null; then
  echo "-> instalando baresip (vai pedir sudo)…"
  sudo pacman -S --noconfirm --needed baresip
fi

mkdir -p "$BARESIP_DIR"
if [[ ! -f "$BARESIP_DIR/config" ]]; then
  install -m 644 "$DIR/templates/config.tmpl" "$BARESIP_DIR/config"
  echo "-> config criado em ~/.baresip/config"
fi

if [[ ! -s "$BARESIP_DIR/accounts" ]] || ! grep -q "^<sip:" "$BARESIP_DIR/accounts"; then
  read -rp "Ramal (ex.: 201): " RAMAL
  read -rp "Usuário de autenticação [${RAMAL}]: " AUTH_USER
  AUTH_USER="${AUTH_USER:-$RAMAL}"
  read -rsp "Senha SIP: " SENHA
  echo
  umask 077
  RAMAL="$RAMAL" AUTH_USER="$AUTH_USER" SENHA="$SENHA" \
    python3 - "$DIR/templates/accounts.tmpl" > "$BARESIP_DIR/accounts" <<'PYEOF'
import os, sys
text = open(sys.argv[1], encoding="utf-8").read()
for key in ("RAMAL", "AUTH_USER", "SENHA"):
    text = text.replace("{{%s}}" % key, os.environ[key])
sys.stdout.write(text)
PYEOF
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
echo "AVISO de segurança: transporte UDP sem criptografia (mesmo padrão do"
echo "MicroSIP usado hoje na empresa). Controle local restrito a 127.0.0.1."
echo
echo "Pronto! Se o widget não aparecer na barra:"
echo "  omarchy plugin enable oma.sip && omarchy bar put oma.sip --section right"
