# Softfone SIP para Omarchy (oma.sip)

Softfone integrado à barra do Omarchy 4+: registro no PABX SIP, discagem,
atender/recusar, mute e DND — tudo pelo widget ou por atalhos de teclado.
O áudio/SIP fica por conta do [baresip](https://github.com/baresip/baresip)
rodando como serviço do usuário; o plugin é só UI e orquestração.

## Instalação

```bash
omarchy plugin add https://github.com/Vinicius-Galleti/oma.sip --enable
bash ~/.config/omarchy/plugins/oma.sip/setup.sh   # pede ramal e senha
```

## Desinstalação

```bash
bash ~/.config/omarchy/plugins/oma.sip/uninstall.sh   # para/desabilita o baresip e remove a unit
omarchy plugin remove oma.sip
```

Por padrão o `uninstall.sh` preserva `~/.baresip` (config + credenciais) e o
pacote `baresip`. Flags opcionais: `--purge` (apaga `~/.baresip`) e `--pkg`
(remove o pacote via pacman).

## Atalhos sugeridos (~/.config/hypr/bindings.lua)

```lua
o.bind("SUPER", "F9", "exec", "omarchy-shell oma.sip answer")
o.bind("SUPER", "F10", "exec", "omarchy-shell oma.sip hangup")
o.bind("SUPER", "F11", "exec", "omarchy-shell oma.sip toggleMute")
```

Discar por linha de comando: `omarchy-shell oma.sip dial 203`

## Arquitetura (resumo)

- `baresip` (systemd --user) fala SIP/RTP com `gb.quicksip.com.br` e expõe
  controle JSON local em `127.0.0.1:4444` (ctrl_tcp, sem auth — nunca
  expor fora do localhost).
- `Service.qml` é o único cliente do ctrl_tcp, via
  `bridge/baresip-bridge.py` (netstring ↔ NDJSON), e mantém a máquina de
  estados de registro/chamada.
- `BarWidget.qml` mostra o estado e abre o popout com discador/controles.

## Diagnóstico

```bash
systemctl --user status baresip          # serviço SIP
journalctl --user -u baresip -f          # log do baresip
omarchy-shell oma.sip state          # estado do plugin (JSON)
```

## Licença

[MIT](LICENSE) — © 2026 Vinicius Galleti.
