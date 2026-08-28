import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Serviço do softfone: único dono da conexão de controle com o baresip
// (ctrl_tcp aceita um cliente só), máquina de estados de registro/chamada,
// gestão da conta SIP e alvo IPC para atalhos do Hyprland
// (omarchy-shell oma.sip <método>).
Item {
  id: root

  property var shell: null
  property var settings: ({})

  // conexão
  property bool bridgeUp: false
  property bool baresipUp: false
  // registro
  property bool registered: false
  property string regDetail: "conectando…"
  // conta (a senha nunca chega ao QML — fica só em ~/.baresip/accounts)
  property bool accountConfigured: false
  property bool accountHasPassword: false
  property string accountServer: ""
  property string accountUsername: ""
  property string accountDomain: ""
  property string accountLogin: ""
  property bool savingAccount: false
  // chamada — MVP: uma por vez
  property string callState: "idle" // idle | incoming | outgoing | active
  property string peer: ""
  property bool muted: false
  property bool dnd: false
  property double callStartMs: 0
  property int callSeconds: 0
  property string lastError: ""

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  property int _tokenSeq: 0
  property string _pendingReginfo: ""
  property string _debugReginfo: ""

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
    if (token !== "") _pendingReginfo = token
  }

  function dial(target) {
    var uri = Model.normalizeTarget(target)
    if (uri === "") return "alvo vazio"
    if (callState !== "idle") return "já existe chamada em andamento"
    if (!registered) return "sem registro no servidor"
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
  function saveAccount(server, username, domain, login, password) {
    if (savingAccount) return "salvando…"
    if (callState !== "idle") return "não é possível trocar a conta durante uma chamada"
    if (String(server).trim() === "" || String(username).trim() === "")
      return "servidor e usuário são obrigatórios"
    savingAccount = true
    lastError = ""
    writeAccount.payload = JSON.stringify({
      server: String(server).trim(),
      username: String(username).trim(),
      domain: String(domain).trim(),
      login: String(login).trim(),
      password: String(password)
    })
    writeAccount.running = true
    return "ok"
  }

  function restartBaresip() {
    regDetail = "reiniciando baresip…"
    registered = false
    Quickshell.execDetached(["systemctl", "--user", "restart", "baresip.service"])
  }

  function notify(summary, body) {
    Quickshell.execDetached(["notify-send", "-a", "Softfone", summary, body || ""])
  }

  function handleLine(line) {
    var obj
    try { obj = JSON.parse(line) } catch (e) {
      console.log("oma.sip: linha inválida da ponte:", line)
      return
    }
    if (obj.bridge !== undefined) {
      if (obj.bridge === "connected") {
        baresipUp = true
        lastError = ""
        if (regDetail === "conectando…" || regDetail === "reconectando…") regDetail = "verificando registro…"
        requestReginfo()
      } else {
        baresipUp = false
        registered = false
        regDetail = "baresip fora do ar"
        if (obj.detail) lastError = obj.detail
      }
      return
    }
    if (obj.event === "true" || obj.event === true) { handleEvent(obj); return }
    if (obj.response !== undefined) {
      if (obj.token && obj.token === _pendingReginfo) {
        _pendingReginfo = ""
        _debugReginfo = String(obj.data || "")
        var info = Model.parseReginfo(obj.data)
        if (info.known) {
          if (info.count === 0) {
            registered = false
            regDetail = accountConfigured ? "conta não carregada — reinicie o baresip" : "sem conta configurada"
          } else if (info.registered) {
            registered = true
            regDetail = info.aor !== "" ? info.aor : "registrado"
          } else if (!registered) {
            regDetail = "registrando…"
          }
        }
        return
      }
      if (obj.ok === false) {
        lastError = String(obj.data || "comando falhou")
        console.log("oma.sip: comando falhou:", JSON.stringify(obj))
      }
    }
  }

  function handleEvent(ev) {
    var cls = ev.class
    var type = ev.type
    if (cls === "register") {
      if (type === "REGISTER_OK") {
        registered = true
        regDetail = ev.accountaor ? ev.accountaor.replace(/^sips?:/, "") : "registrado"
      } else if (type === "REGISTER_FAIL") {
        registered = false
        regDetail = "falha de registro" + (ev.param ? ": " + ev.param : "")
      } else if (type === "UNREGISTERING") {
        registered = false
        regDetail = "desregistrado"
      }
      return
    }
    if (cls !== "call") return
    switch (type) {
    case "CALL_INCOMING": {
      var who = Model.peerDisplay(ev.peerdisplay || ev.peeruri || "")
      if (dnd || callState !== "idle") {
        send("hangup")
        notify(dnd ? "Chamada recusada (DND)" : "Chamada recusada (ocupado)", who)
        return
      }
      callState = "incoming"
      peer = who
      notify("Chamada recebida", who)
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
      if (wasIncoming) notify("Chamada perdida", lostPeer)
      break
    }
    }
  }

  Component.onCompleted: readAccount.running = true

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
      if (root.regDetail !== "reiniciando baresip…") root.regDetail = "reconectando…"
      retry.start()
    }
  }

  // A ponte cai junto com o baresip (ex.: restart ao salvar conta);
  // religa rápido para não perder a janela dos eventos de registro.
  Timer {
    id: retry
    interval: 1200
    onTriggered: bridge.running = true
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
          root.accountServer = info.server || ""
          root.accountUsername = info.username || ""
          root.accountDomain = info.domain || ""
          root.accountLogin = info.login || ""
          if (!info.configured) root.regDetail = "sem conta configurada"
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
        try { result = JSON.parse(line) } catch (e) { result = { ok: false, error: "resposta inválida" } }
        root.savingAccount = false
        if (result.ok) {
          root.lastError = ""
          readAccount.running = true
          root.restartBaresip()
        } else {
          root.lastError = result.error || "falha ao salvar conta"
        }
      }
    }
    onExited: function(code, status) { root.savingAccount = false }
  }

  IpcHandler {
    target: "oma.sip"

    function dial(target: string): string { return root.dial(target) }
    function answer(): string { root.answer(); return "ok" }
    function hangup(): string { root.hangup(); return "ok" }
    function toggleMute(): string { root.toggleMute(); return root.muted ? "mudo" : "com áudio" }
    function toggleDnd(): string { root.toggleDnd(); return root.dnd ? "dnd ligado" : "dnd desligado" }
    function reregister(): string { root.restartBaresip(); return "ok" }
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
          hasPassword: root.accountHasPassword
        },
        call: root.callState,
        peer: root.peer,
        muted: root.muted,
        dnd: root.dnd,
        seconds: root.callSeconds,
        lastError: root.lastError,
        debugReginfo: root._debugReginfo
      })
    }
  }
}
