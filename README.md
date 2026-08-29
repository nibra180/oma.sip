# Softfone SIP para Omarchy (oma.sip)

Softfone integrado à barra do Omarchy 4+: registro no PABX SIP, discagem,
atender/recusar, mute e DND — tudo pelo widget ou por atalhos de teclado.
O áudio/SIP fica por conta do [baresip](https://github.com/baresip/baresip)
rodando como serviço do usuário; o plugin é só UI e orquestração.

## Requisitos

- Omarchy 4.0 ou superior (omarchy-shell)
- `baresip` (o `setup.sh` oferece instalar via `pacman`)
- `python3` e `jq` (já presentes no Omarchy)
- PipeWire para áudio (padrão do Omarchy)

## Instalação

```bash
omarchy plugin add https://github.com/Vinicius-Galleti/oma.sip --enable
bash ~/.config/omarchy/plugins/oma.sip/setup.sh
```

O `omarchy plugin add` só clona e habilita o plugin — ele nunca executa código
do plugin. O `setup.sh` é um passo manual que:

1. instala o pacote `baresip` se faltar (pede confirmação e `sudo`);
2. cria `~/.baresip/config` a partir de `templates/config.tmpl`;
3. pergunta servidor, ramal e senha e grava `~/.baresip/accounts` com
   permissão `600` (a senha nunca passa por argumentos de processo);
4. instala e inicia a unit `baresip.service` em `systemctl --user`.

A conta também pode ser criada/alterada depois pela engrenagem do widget.

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
o.bind("SUPER", "F8",  "exec", "omarchy-shell shell toggle oma.sip '{}'")  -- abre/fecha o discador
o.bind("SUPER", "F9",  "exec", "omarchy-shell oma.sip answer")
o.bind("SUPER", "F10", "exec", "omarchy-shell oma.sip hangup")
o.bind("SUPER", "F11", "exec", "omarchy-shell oma.sip toggleMute")
```

Discar por linha de comando: `omarchy-shell oma.sip dial 203`

Métodos IPC (`omarchy-shell oma.sip <método>`): `dial <alvo>`, `answer`,
`hangup`, `toggleMute`, `toggleDnd`, `reregister`, `state`.

## Segurança

- O controle do baresip (`ctrl_tcp`, sem autenticação) escuta só em
  `127.0.0.1:4444` — nunca exponha essa porta fora do localhost.
- A senha do ramal fica apenas em `~/.baresip/accounts` (`600`); ela não
  chega ao QML nem aparece em argumentos de processo.
- Por padrão o transporte SIP é UDP sem criptografia. Para TLS+SRTP, edite
  `~/.baresip/accounts` (`;transport=tls` no URI e no `outbound`,
  `;mediaenc=srtp`).
- Plugins do Omarchy rodam sem sandbox dentro do `omarchy-shell`; revise o
  código antes de habilitar.

## Arquitetura (resumo)

- `baresip` (systemd --user) fala SIP/RTP com o seu PABX e expõe controle
  JSON local em `127.0.0.1:4444` (`ctrl_tcp`).
- `Service.qml` é o único cliente do `ctrl_tcp`, via
  `bridge/baresip-bridge.py` (netstring ↔ NDJSON, reconexão com backoff), e
  mantém a máquina de estados de registro/chamada. Uma chamada por vez
  (`call_max_calls 1`): uma segunda chamada recebida ganha 486 Busy.
- `BarWidget.qml` mostra o estado e abre o popout com discador/controles.
- `bridge/account-tool.py` lê/grava `~/.baresip/accounts` (usado pelo widget
  e pelo `setup.sh`).

## Diagnóstico

```bash
systemctl --user status baresip          # serviço SIP
journalctl --user -u baresip -f          # log do baresip
omarchy-shell oma.sip state              # estado do plugin (JSON)
```

## Licença

[MIT](LICENSE) — © 2026 Vinicius Galleti.
