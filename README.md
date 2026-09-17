# SIP Softphone for Omarchy (oma.sip)

<img width="376" height="422" alt="image" src="https://github.com/user-attachments/assets/84e954b4-d47d-4574-9414-e8cad84986c3" /> <img width="374" height="421" alt="image" src="https://github.com/user-attachments/assets/ef3150dc-d129-466d-b222-5c088d58e21f" />


A softphone built into the Omarchy 4+ bar: SIP registration, dialing,
answer/reject, mute, DND and audio device selection — from the widget or via
keyboard shortcuts. Audio/SIP is handled by
[baresip](https://github.com/baresip/baresip) running as a user service; the
plugin is UI and orchestration only.

The UI follows the system language: English by default, Brazilian Portuguese
on `pt_*` locales.

## Requirements

- Omarchy 4.0 or later (omarchy-shell)
- `baresip` and `python-gobject` (`setup.sh` offers to install them via `pacman`)
- `python3` and `jq` (already present on Omarchy)
- PipeWire for audio (Omarchy default)

## Install

```bash
omarchy plugin add https://github.com/Vinicius-Galleti/oma.sip --enable
bash ~/.config/omarchy/plugins/oma.sip/setup.sh
```

`omarchy plugin add` only clones and enables the plugin — it never runs
plugin code. `setup.sh` is a manual step that:

1. installs the `baresip` and `python-gobject` packages if missing (asks
   before using `sudo`);
2. creates `~/.baresip` (mode `700`) and its `config` from
   `templates/config.tmpl` (migrating old configs from `ctrl_tcp` to
   `ctrl_dbus`);
3. asks for server, extension and password and writes `~/.baresip/accounts`
   with `600` permissions (the password never goes through process argv);
   TLS + SRTP by default, unencrypted UDP only by explicit choice;
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

- The baresip control channel is `ctrl_dbus` on the **per-user D-Bus session
  bus**: the bus socket lives in `$XDG_RUNTIME_DIR` (mode `700`) and peers
  are kernel-authenticated (same UID only). No TCP control port is opened;
  `ctrl_tcp`/`httpd`/`cons`/`mqtt` (unauthenticated) are never loaded. This
  says nothing about the SIP listener below, which is a separate port.
- **The SIP listener is open on every interface.** The template leaves
  `sip_listen` unset, and baresip binds a SIP transport (UDP and TCP) on every
  local address with an OS-assigned port. That covers the Wi-Fi or LAN address,
  a VPN interface such as Tailscale, and every container bridge. Those
  listeners accept unauthenticated INVITEs, so anything on the same network can
  make the phone ring; `call_accept no` only stops the plugin from answering by
  itself. Setting `sip_listen` to `address:port` restricts the listener to the
  matching interface and gives you a fixed port to firewall.
- SIP signaling and media default to **TLS + SRTP** with server-certificate
  validation (`sip_verify_server yes`). Unencrypted UDP is an explicit
  opt-out in the widget/setup, with a visible warning. The SRTP requirement is
  stored per account, so it covers your own calls; a call from an unknown
  caller arriving over the listener above is plain RTP.
- The extension password lives in `~/.baresip/accounts` (`600`, inside
  `~/.baresip` `700`). It is read back by nothing but the account tool: the
  widget shows only whether a password is set, and clears its input field after
  saving. During entry and saving it is in `omarchy-shell`'s memory and in a
  pipe to `bridge/account-tool.py`, but never in process arguments
  (`/proc/<pid>/cmdline` is readable by every local user). Writes to
  `accounts`/`config` are serialized with an exclusive lock and done
  atomically (random-name `mkstemp` + `fsync` + `rename`), refusing symlinks
  (`O_NOFOLLOW`).
- Passwords containing a space or any of `; " < >` are rejected by
  `bridge/account-tool.py`: baresip ends a URI parameter at `;` and whitespace,
  so such a password cannot be stored in `accounts` at all.
- Everything crossing a trust boundary is bounded: bridge command lines
  (8 KiB), params (2 KiB), events/responses (64 KiB) with a 10 s command
  deadline; remote text (peer names, error/status strings) is
  control-character-stripped, length-clamped and rendered as
  `Text.PlainText`; notification bodies are markup-stripped; IPC dial
  targets and device names are validated and capped.
- Omarchy plugins run unsandboxed inside `omarchy-shell`; review the code
  before enabling.

## Architecture (summary)

- `baresip` (systemd --user) speaks SIP/RTP to your PBX and exposes local
  control via `ctrl_dbus` (`com.github.Baresip` on the session bus).
- `Service.qml` owns the control bridge (`bridge/baresip-bridge.py`,
  D-Bus ↔ NDJSON with bounded parsing and reconnection with backoff) and
  the registration/call state machine. One call at a time
  (`call_max_calls 1`): a second incoming call gets 486 Busy.
- `BarWidget.qml` shows the state and opens the popout with the dialer and
  controls.
- `bridge/account-tool.py` reads/writes `~/.baresip/accounts` (used by the
  widget and by `setup.sh`); `bridge/config-tool.py` persists the audio
  devices in `~/.baresip/config`. Both use locked atomic writes.
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
