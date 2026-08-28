#!/usr/bin/env bash
set -euo pipefail

# Desinstalação do Softfone SIP (oma.sip) — reverte o que o setup.sh fez.
# Idempotente: pode rodar mais de uma vez sem erro.
#
# Por padrão PRESERVA ~/.baresip (contém a senha SIP e a config do usuário)
# e NÃO remove o pacote baresip. Use as flags para remover também:
#   --purge   remove ~/.baresip (config + credenciais)
#   --pkg     desinstala o pacote baresip via pacman (pede sudo)

BARESIP_DIR="$HOME/.baresip"
UNIT="$HOME/.config/systemd/user/baresip.service"
PURGE=0
PKG=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    --pkg)   PKG=1 ;;
    -h|--help)
      sed -n '3,10p' "$0"
      exit 0
      ;;
    *) echo "opção desconhecida: $arg" >&2; exit 1 ;;
  esac
done

echo "== Softfone SIP (oma.sip) — desinstalação =="

if systemctl --user list-unit-files baresip.service &>/dev/null; then
  systemctl --user disable --now baresip.service 2>/dev/null || true
  echo "-> serviço baresip parado e desabilitado"
fi

if [[ -f "$UNIT" ]]; then
  rm -f "$UNIT"
  systemctl --user daemon-reload
  echo "-> unit removida: $UNIT"
fi

if (( PURGE )); then
  if [[ -d "$BARESIP_DIR" ]]; then
    rm -rf "$BARESIP_DIR"
    echo "-> removido: $BARESIP_DIR (config e credenciais)"
  fi
else
  [[ -d "$BARESIP_DIR" ]] && echo "-> mantido: $BARESIP_DIR (use --purge para remover)"
fi

if (( PKG )); then
  if pacman -Q baresip &>/dev/null; then
    echo "-> removendo pacote baresip (vai pedir sudo)…"
    sudo pacman -Rns --noconfirm baresip
  fi
else
  pacman -Q baresip &>/dev/null && echo "-> pacote baresip mantido (use --pkg para remover)"
fi

echo
echo "Pronto. Para tirar o plugin do Omarchy:"
echo "  omarchy plugin remove oma.sip"
