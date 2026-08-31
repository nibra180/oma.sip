#!/usr/bin/env bash
set -euo pipefail

# oma.sip uninstall — reverts what setup.sh did. Idempotent.
# Desinstalação do oma.sip — reverte o que o setup.sh fez. Idempotente.
#
# By default it PRESERVES ~/.baresip (SIP password + user config) and keeps
# the baresip package. Por padrão PRESERVA ~/.baresip e o pacote baresip.
#   --purge   remove ~/.baresip (config + credentials/credenciais)
#   --pkg     uninstall the baresip package via pacman (asks for sudo)

BARESIP_DIR="$HOME/.baresip"
UNIT="$HOME/.config/systemd/user/baresip.service"
PURGE=0
PKG=0

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) PT=1 ;; *) PT=0 ;; esac
t() { if (( PT )); then echo "$2"; else echo "$1"; fi; }

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    --pkg)   PKG=1 ;;
    -h|--help)
      sed -n '4,11p' "$0"
      exit 0
      ;;
    *) echo "$(t "unknown option:" "opção desconhecida:") $arg" >&2; exit 1 ;;
  esac
done

echo "== oma.sip — $(t "uninstall" "desinstalação") =="

if systemctl --user list-unit-files baresip.service &>/dev/null; then
  systemctl --user disable --now baresip.service 2>/dev/null || true
  echo "-> $(t "baresip service stopped and disabled" "serviço baresip parado e desabilitado")"
fi

if [[ -f "$UNIT" ]]; then
  rm -f "$UNIT"
  systemctl --user daemon-reload
  echo "-> $(t "unit removed:" "unit removida:") $UNIT"
fi

if (( PURGE )); then
  if [[ -d "$BARESIP_DIR" ]]; then
    rm -rf "$BARESIP_DIR"
    echo "-> $(t "removed:" "removido:") $BARESIP_DIR $(t "(config and credentials)" "(config e credenciais)")"
  fi
else
  [[ -d "$BARESIP_DIR" ]] && echo "-> $(t "kept:" "mantido:") $BARESIP_DIR $(t "(use --purge to remove)" "(use --purge para remover)")"
fi

if (( PKG )); then
  if pacman -Q baresip &>/dev/null; then
    echo "-> $(t "removing the baresip package (will ask for sudo)…" "removendo pacote baresip (vai pedir sudo)…")"
    sudo pacman -Rns --noconfirm baresip
  fi
else
  pacman -Q baresip &>/dev/null && echo "-> $(t "baresip package kept (use --pkg to remove)" "pacote baresip mantido (use --pkg para remover)")"
fi

echo
t "Done. To remove the plugin from Omarchy:" "Pronto. Para tirar o plugin do Omarchy:"
echo "  omarchy plugin remove oma.sip"
