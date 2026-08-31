# SIP Softphone for Omarchy (oma.sip)

A softphone built into the Omarchy 4+ bar: SIP registration, dialing,
answer/reject, mute, DND and audio device selection — from the widget or via
keyboard shortcuts. Audio/SIP is handled by
[baresip](https://github.com/baresip/baresip) running as a user service; the
plugin is UI and orchestration only.

The UI follows the system language: English by default, Brazilian Portuguese
on `pt_*` locales.

## Requirements

- Omarchy 4.0 or later (omarchy-shell)
- `baresip` (`setup.sh` offers to install it via `pacman`)
- `python3` and `jq` (already present on Omarchy)
- PipeWire for audio (Omarchy default)

## Install

```bash
omarchy plugin add https://github.com/Vinicius-Galleti/oma.sip --enable
bash ~/.config/omarchy/plugins/oma.sip/setup.sh
```

`omarchy plugin add` only clones and enables the plugin — it never runs
plugin code. `setup.sh` is a manual step that:

1. installs the `baresip` package if missing (asks before using `sudo`);
2. creates `~/.baresip/config` from `templates/config.tmpl`;
3. asks for server, extension and password and writes `~/.baresip/accounts`
   with `600` permissions (the password never goes through process argv);
4. installs and starts the `baresip.service` unit under `systemctl --user`.

The account can also be created/changed later from the widget's gear button.

## Uninstall

```bash
bash ~/.config/omarchy/plugins/oma.sip/uninstall.sh   # stops baresip and removes the unit
omarchy plugin remove oma.sip
```

By default `uninstall.sh` preserves `~/.baresip` (config + credentials) and
the `baresip` package. Optional flags: `--purge` (delete `~/.baresip`) and
`--pkg` (remove the package via pacman).

## Suggested keybindings (~/.config/hypr/bindings.lua)

```lua
o.bind("SUPER", "F8",  "exec", "omarchy-shell shell toggle oma.sip '{}'")  -- open/close the dialer
o.bind("SUPER", "F9",  "exec", "omarchy-shell oma.sip answer")
o.bind("SUPER", "F10", "exec", "omarchy-shell oma.sip hangup")
o.bind("SUPER", "F11", "exec", "omarchy-shell oma.sip toggleMute")
```

Dial from the command line: `omarchy-shell oma.sip dial 203`

IPC methods (`omarchy-shell oma.sip <method>`): `dial <target>`, `answer`,
`hangup`, `toggleMute`, `toggleDnd`, `reregister`, `setAudioOutput <node>`,
`setAudioInput <node>`, `state`.

## Audio devices

The 󰓃 button in the popout selects the **output** (speaker/headset) and
**input** (microphone) among the PipeWire nodes. The choice:

- is applied immediately, even mid-call (baresip `auplay`/`ausrc`; the
  ringtone follows the output);
- is saved to `~/.baresip/config` (`audio_player`, `audio_alert`,
  `audio_source` as `pipewire,<node.name>`), so it survives restarts;
- "System default" lets baresip follow the PipeWire/WirePlumber default
  device.

From the command line: `omarchy-shell oma.sip setAudioOutput <node.name>`
(names from `wpctl status` / `pw-cli ls Node`; empty = default).

## Security

- The baresip control channel (`ctrl_tcp`, unauthenticated) listens only on
  `127.0.0.1:4444` — never expose that port outside localhost.
- The extension password lives only in `~/.baresip/accounts` (`600`); it
  never reaches QML nor process arguments.
- SIP transport defaults to unencrypted UDP. For TLS+SRTP, edit
  `~/.baresip/accounts` (`;transport=tls` on the URI and `outbound`,
  `;mediaenc=srtp`).
- Omarchy plugins run unsandboxed inside `omarchy-shell`; review the code
  before enabling.

## Architecture (summary)

- `baresip` (systemd --user) speaks SIP/RTP to your PBX and exposes local
  JSON control on `127.0.0.1:4444` (`ctrl_tcp`).
- `Service.qml` is the only `ctrl_tcp` client, via
  `bridge/baresip-bridge.py` (netstring ↔ NDJSON, reconnection with
  backoff), and owns the registration/call state machine. One call at a
  time (`call_max_calls 1`): a second incoming call gets 486 Busy.
- `BarWidget.qml` shows the state and opens the popout with the dialer and
  controls.
- `bridge/account-tool.py` reads/writes `~/.baresip/accounts` (used by the
  widget and by `setup.sh`); `bridge/config-tool.py` persists the audio
  devices in `~/.baresip/config`.
- UI strings live in `Model.js` (`tr()`), chosen by `Qt.locale()`; the
  Python/bash helpers pick the language from `LANG`/`LC_MESSAGES`.

## Diagnostics

```bash
systemctl --user status baresip          # SIP service
journalctl --user -u baresip -f          # baresip log
omarchy-shell oma.sip state              # plugin state (JSON)
```

## License

[MIT](LICENSE) — © 2026 Vinicius Galleti.
