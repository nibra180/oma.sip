import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Model.js" as Model

// Serviço do softfone: único dono da ponte de controle com o baresip
// (ctrl_dbus no barramento de sessão, via bridge/baresip-bridge.py),
// máquina de estados de registro/chamada, gestão da conta SIP e alvo IPC
// para atalhos do Hyprland (omarchy-shell oma.sip <método>).
Item {
  id: root

  property var shell: null
  property var settings: ({})

  // conexão
  property bool bridgeUp: false
  property bool baresipUp: false
  // registro
  property bool registered: false
  property string regDetail: Model.tr("connecting")
  // conta (a senha nunca chega ao QML — fica só em ~/.baresip/accounts)
  property bool accountConfigured: false
  property bool accountHasPassword: false
  property bool accountSecure: true
  property string accountServer: ""
  property string accountUsername: ""
  property string accountDomain: ""
  property string accountLogin: ""
  property bool savingAccount: false
  // áudio: node.name do PipeWire ("" = padrão do sistema), persistido em
  // ~/.baresip/config e aplicado ao vivo via auplay/ausrc
  property string audioOutput: ""
  property string audioInput: ""
  property bool savingAudio: false
  // chamada — MVP: uma por vez
  property string callState: "idle" // idle | incoming | outgoing | active
  property string peer: ""
  property bool muted: false
  property bool dnd: false
  property double callStartMs: 0
  property int callSeconds: 0
  property string lastError: ""

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  property int _tokenSeq: 0
  property string _pendingReginfo: ""
  property string _pendingAudio: ""
  // Backoff da reconexão da ponte: começa rápido (cobre o restart do baresip
  // ao salvar conta) e cresce até 15 s enquanto o baresip estiver fora do ar.
  readonly property int _retryMinMs: 1200
  readonly property int _retryMaxMs: 15000
  property int _retryMs: _retryMinMs

  function send(cmd, params) {
    if (!bridge.running || !baresipUp) return ""
    var msg = { command: cmd, token: "t" + (++_tokenSeq) }
    if (params !== undefined && params !== null && String(params) !== "")
      msg.params = String(params)
    bridge.write(JSON.stringify(msg) + "\n")
    return msg.token
  }

  function requestReginfo() {
    var token = send("reginfo")
    if (token !== "") {
      _pendingReginfo = token
      pendingWatchdog.restart()
    }
  }

  function dial(target) {
    var uri = Model.normalizeTarget(target)
    if (uri === "") return Model.tr("empty_target")
    if (callState !== "idle") return Model.tr("call_in_progress")
    if (!registered) return Model.tr("not_registered")
    peer = Model.peerDisplay(uri)
    callState = "outgoing"
    send("dial", uri)
    return "ok"
  }

  function answer() {
    if (callState !== "incoming") return
    send("accept")
  }

  function hangup() {
    if (callState === "idle") return
    send("hangup")
  }

  function toggleMute() {
    if (callState !== "active") return
    send("mute")
    muted = !muted
  }

  function toggleDnd() { dnd = !dnd }

  // Grava a conta via account-tool (senha só por stdin) e reinicia o baresip.
  // Senha vazia mantém a atual.
  function saveAccount(server, username, domain, login, password, secure) {
    if (savingAccount) return Model.tr("saving")
    if (callState !== "idle") return Model.tr("account_busy_call")
    if (String(server).trim() === "" || String(username).trim() === "")
      return Model.tr("server_user_required")
    savingAccount = true
    lastError = ""
    writeAccount.payload = JSON.stringify({
      server: String(server).trim(),
      username: String(username).trim(),
      domain: String(domain).trim(),
      login: String(login).trim(),
      password: String(password),
      secure: secure === undefined ? true : !!secure
    })
    writeAccount.running = true
    return "ok"
  }

  // Dispositivos de áudio. Persiste no config (vale após reinício) e aplica ao
  // vivo: o auplay/ausrc do baresip atualiza a config em memória e troca o
  // áudio das chamadas em andamento (auplay move o toque junto).
  function setAudioOutput(name) { return _setAudio("output", name) }
  function setAudioInput(name) { return _setAudio("input", name) }

  function _setAudio(kind, name) {
    name = String(name || "").trim()
    if (name.length > 255 || /[\s,\x00-\x1f]/.test(name)) return Model.tr("invalid_response")
    if (kind === "output") audioOutput = name
    else audioInput = name
    lastError = ""
    writeAudio.dirty = true
    if (!writeAudio.running) writeAudio.flush()
    applyAudioLive(kind)
    return "ok"
  }

  // O baresip rejeita dispositivo vazio no auplay/ausrc (valida contra a lista
  // de nós do PipeWire), então "padrão" ao vivo vira o nome do padrão atual;
  // no config fica vazio para seguir o padrão do sistema após reinício.
  function applyAudioLive(kind) {
    var name = kind === "output" ? audioOutput : audioInput
    if (name === "") {
      var node = kind === "output" ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
      name = node && node.name ? String(node.name) : ""
    }
    if (name === "") return
    var token = send(kind === "output" ? "auplay" : "ausrc", "pipewire," + name)
    if (token !== "") {
      _pendingAudio = token
      pendingWatchdog.restart()
    }
  }

  function restartBaresip() {
    regDetail = Model.tr("restarting_baresip")
    registered = false
    Quickshell.execDetached(["systemctl", "--user", "restart", "baresip.service"])
  }

  function notify(summary, body) {
    Quickshell.execDetached(["notify-send", "-a", Model.tr("app_name"), summary, Model.notifyText(body)])
  }

  function handleLine(line) {
    if (line.length > 65536) return // a ponte limita; linha maior é lixo
    var obj
    try { obj = JSON.parse(line) } catch (e) {
      console.log("oma.sip: linha inválida da ponte:", Model.clamp(line, 200))
      return
    }
    if (obj.bridge !== undefined) {
      if (obj.bridge === "connected") {
        baresipUp = true
        lastError = ""
        _retryMs = _retryMinMs
        if (regDetail === Model.tr("connecting") || regDetail === Model.tr("reconnecting"))
          regDetail = Model.tr("checking_registration")
        requestReginfo()
      } else {
        baresipUp = false
        registered = false
        regDetail = Model.tr("baresip_down")
        if (obj.detail) lastError = Model.clamp(obj.detail, 160)
      }
      return
    }
    if (obj.event === "true" || obj.event === true) { handleEvent(obj); return }
    if (obj.response !== undefined) {
      if (obj.token && obj.token === _pendingReginfo) {
        _pendingReginfo = ""
        var info = Model.parseReginfo(obj.data)
        if (info.known) {
          if (info.count === 0) {
            registered = false
            regDetail = accountConfigured ? Model.tr("account_not_loaded") : Model.tr("no_account")
          } else if (info.registered) {
            registered = true
            regDetail = info.aor !== "" ? info.aor : Model.tr("registered")
          } else if (!registered) {
            regDetail = Model.tr("registering")
          }
        }
        return
      }
      if (obj.token && obj.token === _pendingAudio) {
        _pendingAudio = ""
        var audioErr = Model.audioSwitchError(obj.data)
        if (audioErr !== "") lastError = audioErr
        return
      }
      if (obj.ok === false) {
        lastError = Model.clamp(obj.data || Model.tr("command_failed"), 160)
        console.log("oma.sip: comando falhou:", Model.clamp(JSON.stringify(obj), 300))
      }
    }
  }

  function handleEvent(ev) {
    var cls = ev.class
    var type = ev.type
    if (cls === "register") {
      if (type === "REGISTER_OK") {
        registered = true
        regDetail = ev.accountaor ? Model.clamp(String(ev.accountaor).replace(/^sips?:/, ""), 96) : Model.tr("registered")
      } else if (type === "REGISTER_FAIL") {
        registered = false
        regDetail = Model.tr("register_failed") + (ev.param ? ": " + Model.clamp(ev.param, 120) : "")
      } else if (type === "UNREGISTERING") {
        registered = false
        regDetail = Model.tr("unregistered")
      }
      return
    }
    if (cls !== "call") return
    switch (type) {
    case "CALL_INCOMING": {
      var who = Model.peerDisplay(ev.peerdisplay || ev.peeruri || "")
      if (dnd) {
        // Com call_max_calls 1 no config, o baresip responde 486 sozinho a uma
        // segunda chamada; aqui só chega a primeira, que é a chamada corrente —
        // o hangup sem id é seguro.
        send("hangup")
        notify(Model.tr("call_rejected_dnd"), who)
        return
      }
      if (callState !== "idle") {
        // Defensivo (config antigo sem call_max_calls 1): recusa pelo id do
        // evento para não derrubar a chamada em andamento.
        send("hangup", ev.id ? String(ev.id) : "")
        notify(Model.tr("call_rejected_busy"), who)
        return
      }
      callState = "incoming"
      peer = who
      notify(Model.tr("incoming_call"), who)
      break
    }
    case "CALL_ESTABLISHED":
      callState = "active"
      muted = false
      callStartMs = Date.now()
      callSeconds = 0
      break
    case "CALL_CLOSED": {
      var wasIncoming = callState === "incoming"
      var lostPeer = peer
      callState = "idle"
      peer = ""
      muted = false
      callSeconds = 0
      if (wasIncoming) notify(Model.tr("missed_call"), lostPeer)
      break
    }
    }
  }

  Component.onCompleted: {
    readAccount.running = true
    readAudio.running = true
  }

  Process {
    id: bridge
    command: ["python3", "-u", root.pluginDir + "bridge/baresip-bridge.py"]
    stdinEnabled: true
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.log("oma.sip ponte:", line) }
    }
    onStarted: root.bridgeUp = true
    onExited: function(code, status) {
      root.bridgeUp = false
      root.baresipUp = false
      root.registered = false
      if (root.regDetail !== Model.tr("restarting_baresip")) root.regDetail = Model.tr("reconnecting")
      retry.interval = root._retryMs
      retry.start()
      root._retryMs = Math.min(root._retryMs * 2, root._retryMaxMs)
    }
  }

  // A ponte cai junto com o baresip (ex.: restart ao salvar conta);
  // religa rápido para não perder a janela dos eventos de registro e vai
  // espaçando as tentativas se o baresip continuar fora do ar.
  Timer {
    id: retry
    onTriggered: bridge.running = true
  }

  // Watchdog dos comandos com resposta pendente: se o baresip não responder
  // (ponte caiu no meio, resposta perdida), limpa os tokens para o estado
  // não ficar preso esperando.
  Timer {
    id: pendingWatchdog
    interval: 15000
    onTriggered: {
      root._pendingReginfo = ""
      root._pendingAudio = ""
    }
  }

  // Ressincroniza o registro enquanto não confirmado (cobre eventos perdidos
  // entre o start do baresip e a conexão da ponte).
  Timer {
    running: root.baresipUp && !root.registered
    interval: 5000
    repeat: true
    onTriggered: root.requestReginfo()
  }

  Timer {
    running: root.callState === "active"
    interval: 1000
    repeat: true
    onTriggered: root.callSeconds = Math.round((Date.now() - root.callStartMs) / 1000)
  }

  Process {
    id: readAccount
    command: ["python3", root.pluginDir + "bridge/account-tool.py", "read"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var info = JSON.parse(line)
          root.accountConfigured = !!info.configured
          root.accountHasPassword = !!info.hasPassword
          root.accountSecure = info.secure === undefined ? true : !!info.secure
          root.accountServer = info.server || ""
          root.accountUsername = info.username || ""
          root.accountDomain = info.domain || ""
          root.accountLogin = info.login || ""
          if (!info.configured) root.regDetail = Model.tr("no_account")
        } catch (e) {
          console.log("oma.sip: leitura de conta falhou:", line)
        }
      }
    }
  }

  Process {
    id: writeAccount
    property string payload: ""
    command: ["python3", root.pluginDir + "bridge/account-tool.py", "write"]
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
    stdout: SplitParser {
      onRead: function(line) {
        var result
        try { result = JSON.parse(line) } catch (e) { result = { ok: false, error: Model.tr("invalid_response") } }
        root.savingAccount = false
        if (result.ok) {
          root.lastError = ""
          readAccount.running = true
          root.restartBaresip()
        } else {
          root.lastError = result.error || Model.tr("save_account_failed")
        }
      }
    }
    onExited: function(code, status) { root.savingAccount = false }
  }

  Process {
    id: readAudio
    command: ["python3", root.pluginDir + "bridge/config-tool.py", "read"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var info = JSON.parse(line)
          root.audioOutput = String(info.output || "")
          root.audioInput = String(info.input || "")
        } catch (e) {
          console.log("oma.sip: leitura de áudio falhou:", line)
        }
      }
    }
  }

  // Grava output/input no config. `dirty` acumula trocas feitas enquanto uma
  // gravação ainda roda; ao terminar, grava de novo com o estado mais recente.
  Process {
    id: writeAudio
    property bool dirty: false
    command: ["python3", root.pluginDir + "bridge/config-tool.py", "write"]
    stdinEnabled: true
    function flush() {
      dirty = false
      root.savingAudio = true
      running = true
    }
    onStarted: write(JSON.stringify({ output: root.audioOutput, input: root.audioInput }) + "\n")
    stdout: SplitParser {
      onRead: function(line) {
        var result
        try { result = JSON.parse(line) } catch (e) { result = { ok: false, error: Model.tr("invalid_response") } }
        if (!result.ok) root.lastError = result.error || Model.tr("save_audio_failed")
      }
    }
    onExited: function(code, status) {
      root.savingAudio = false
      if (dirty) flush()
    }
  }

  IpcHandler {
    target: "oma.sip"

    function dial(target: string): string { return root.dial(target) }
    function answer(): string { root.answer(); return "ok" }
    function hangup(): string { root.hangup(); return "ok" }
    function toggleMute(): string { root.toggleMute(); return Model.tr(root.muted ? "muted" : "unmuted") }
    function toggleDnd(): string { root.toggleDnd(); return Model.tr(root.dnd ? "dnd_on" : "dnd_off") }
    function reregister(): string { root.restartBaresip(); return "ok" }
    // node.name do PipeWire (veja `wpctl status` / `pw-cli ls Node`); vazio = padrão
    function setAudioOutput(name: string): string { return root.setAudioOutput(name) }
    function setAudioInput(name: string): string { return root.setAudioInput(name) }
    function state(): string {
      return JSON.stringify({
        bridge: root.bridgeUp,
        baresip: root.baresipUp,
        registered: root.registered,
        detail: root.regDetail,
        account: {
          configured: root.accountConfigured,
          server: root.accountServer,
          username: root.accountUsername,
          domain: root.accountDomain,
          login: root.accountLogin,
          hasPassword: root.accountHasPassword,
          secure: root.accountSecure
        },
        audio: { output: root.audioOutput, input: root.audioInput },
        call: root.callState,
        peer: root.peer,
        muted: root.muted,
        dnd: root.dnd,
        seconds: root.callSeconds,
        lastError: root.lastError
      })
    }
  }
}
