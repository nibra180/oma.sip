import QtQuick
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "oma.sip"

  readonly property var sip: bar?.shell?.serviceFor("oma.sip")
  readonly property bool up: sip ? sip.baresipUp : false
  readonly property bool registered: sip ? sip.registered : false
  readonly property string callState: sip ? sip.callState : "idle"
  readonly property string peer: sip ? sip.peer : ""
  readonly property bool muted: sip ? sip.muted : false
  readonly property bool dnd: sip ? sip.dnd : false
  readonly property int callSeconds: sip ? sip.callSeconds : 0

  readonly property string glyph: {
    if (callState === "active") return muted ? "󰍭" : "󰏴"
    if (callState === "incoming" || callState === "outgoing") return "󰏴"
    if (dnd) return "󰂛"
    return "󰏲"
  }
  readonly property string label: {
    if (callState === "active") return Model.fmtDuration(callSeconds)
    if (callState === "incoming" || callState === "outgoing") return peer
    return ""
  }
  readonly property color tone: {
    if (!up || !registered) return Qt.darker(root.bar.barForeground, 1.8)
    if (callState !== "idle") return Color.accent
    return root.bar.barForeground
  }

  property bool popupOpen: false
  property bool showAccount: false
  property bool showAudio: false
  // Discador/controles/DND só aparecem quando nenhum sub-painel está aberto.
  readonly property bool mainView: !showAccount && !showAudio

  // Dispositivos PipeWire, com o mesmo filtro do painel de áudio built-in.
  // Só name/description/isSink/isStream/audio são lidos — node.properties não
  // (instável enquanto streams de captura aparecem).
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var outputNodes: {
    var list = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }
  readonly property var inputNodes: {
    var list = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (!n || n.isSink || n.isStream) continue
      if (String(n.name || "") === "quickshell") continue
      if (n.audio || /Source/.test(String(n.type || ""))) list.push(n)
    }
    return list
  }

  // ---- Contrato de painel do shell: Bar.findPanelWidget exige open/close/
  //      opened no root do widget para rotear `omarchy-shell shell
  //      summon|hide|toggle oma.sip` e a navegação por teclado entre painéis.
  //      Bar.requestPopout prefere closeForPopoutSwitch, e o KeyboardPanel lê
  //      popoutSwitchClosing do owner (mesmo formato de Ui/Panel.qml).
  readonly property bool opened: popupOpen
  property bool popoutSwitchClosing: false

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      showAccount = sip ? !sip.accountConfigured : false
      if (showAccount) fillAccountForm()
    }
    focusPreferred()
  }
  onShowAccountChanged: {
    if (showAccount) { showAudio = false; fillAccountForm() }
    focusPreferred()
  }
  onShowAudioChanged: {
    if (showAudio) showAccount = false
    focusPreferred()
  }

  // Campo que deve receber o teclado no estado atual (null = nenhum).
  function preferredField() {
    if (!popupOpen) return null
    if (showAccount) return serverField
    if (registered && callState === "idle") return dialField
    return null
  }

  // Reaplica o foco após o layout assentar. O KeyboardPanel só foca o
  // focusTarget na abertura; trocas de estado com o painel aberto (engrenagem,
  // registro confirmado) passam por aqui.
  function focusPreferred() {
    Qt.callLater(function() {
      var field = root.preferredField()
      if (field && field.visible && field.enabled) field.forceActiveFocus()
    })
  }

  function fillAccountForm() {
    if (!sip) return
    serverField.text = sip.accountServer
    usernameField.text = sip.accountUsername
    domainField.text = sip.accountDomain === sip.accountServer ? "" : sip.accountDomain
    loginField.text = sip.accountLogin === sip.accountUsername ? "" : sip.accountLogin
    passwordField.text = ""
    tlsToggle.checked = sip.accountSecure
  }

  // Registro confirmado enquanto o formulário está aberto → volta ao discador.
  Connections {
    target: root.sip
    function onRegisteredChanged() {
      if (root.sip.registered && root.showAccount) root.showAccount = false
    }
  }

  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.tone
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body

      SequentialAnimation on opacity {
        running: root.callState === "incoming"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1.0; to: 0.25; duration: 350 }
        NumberAnimation { from: 0.25; to: 1.0; duration: 350 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.label !== ""
      text: root.label
      textFormat: Text.PlainText
      color: root.tone
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.registered
      ? Model.tr("app_name") + ": " + (root.sip ? root.sip.regDetail : "")
      : Model.tr("no_registration_tip") + (root.sip && root.sip.regDetail ? " · " + root.sip.regDetail : ""))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // KeyboardPanel (e não PopupCard): popup xdg só recebe teclado depois de
  // clique; este painel layer-shell toma foco ao abrir — necessário para os
  // campos de discagem e de conta.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // O alvo de foco é o PRÓPRIO campo de texto do estado atual — apontar o
    // keyCatcher e refocar por timer cria disputa (a digitação funcionava
    // "às vezes", conforme quem ganhasse a corrida).
    focusTarget: root.preferredField() || keyCatcher
    // Nota histórica: houve um override de teclado Exclusive aqui para
    // contornar um bug de foco OnDemand multi-monitor do Omarchy 4.0.1,
    // corrigido em atualização do Omarchy (2026-08-28). O override quebrava
    // o fechar-ao-clicar em outro monitor — não reintroduzir.
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: serverField.activeFocus || usernameField.activeFocus || domainField.activeFocus
        || loginField.activeFocus || passwordField.activeFocus || dialField.activeFocus
        || outputDropdown.popupOpen || inputDropdown.popupOpen
      onCloseRequested: root.popupOpen = false
      // Se o foco cair no keyCatcher com um campo visível (ex.: clique em área
      // vazia), a primeira tecla devolve o foco ao campo em vez de sumir.
      onTextKey: function(t) { root.focusPreferred() }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width - gearButton.width - audioButton.width - Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (!root.up) return Model.tr("baresip_down")
              if (!root.registered) return root.sip ? root.sip.regDetail : Model.tr("no_registration")
              return Model.tr("registered_prefix") + root.sip.regDetail
            }
            textFormat: Text.PlainText
            color: root.registered ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: audioButton
            iconText: "󰓃"
            tooltipText: Model.tr("audio_devices")
            foreground: root.bar.foreground
            selected: root.showAudio
            onClicked: root.showAudio = !root.showAudio
          }

          Button {
            id: gearButton
            iconText: "󰒓"
            tooltipText: Model.tr("configure_account")
            foreground: root.bar.foreground
            selected: root.showAccount
            onClicked: root.showAccount = !root.showAccount
          }
        }

        // ---- Áudio (saída / entrada) ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.showAudio

          Dropdown {
            id: outputDropdown
            width: parent.width
            label: Model.tr("audio_output_label")
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            accent: Color.accent
            options: Model.deviceOptions(root.outputNodes, root.sip ? root.sip.audioOutput : "")
            value: root.sip ? root.sip.audioOutput : ""
            onChanged: function(v) { if (root.sip) root.sip.setAudioOutput(v) }
          }

          Dropdown {
            id: inputDropdown
            width: parent.width
            label: Model.tr("audio_input_label")
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            accent: Color.accent
            options: Model.deviceOptions(root.inputNodes, root.sip ? root.sip.audioInput : "")
            value: root.sip ? root.sip.audioInput : ""
            onChanged: function(v) { if (root.sip) root.sip.setAudioInput(v) }
          }

          Text {
            width: parent.width
            text: Model.tr("audio_hint")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- Conta (SIP server / usuário / domínio / login / senha) ----
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.showAccount

          Text {
            text: Model.tr("sip_server")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: serverField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: Model.tr("sip_server_ph")
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: Model.tr("username_ext")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: usernameField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: Model.tr("username_ph")
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: Model.tr("domain_label")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: domainField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: Model.tr("domain_ph")
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: Model.tr("login_label")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: loginField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: Model.tr("login_ph")
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: Model.tr("password")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: passwordField
            width: parent.width
            foreground: root.bar.foreground
            password: true
            placeholderText: Model.tr(root.sip && root.sip.accountHasPassword ? "password_keep_ph" : "password_required_ph")
            Keys.onEscapePressed: root.popupOpen = false
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            ToggleSwitch {
              id: tlsToggle
              anchors.verticalCenter: parent.verticalCenter
              // O ToggleSwitch é controlado pelo chamador: o clique só emite
              // toggled() e cabe a nós virar o valor (estado local do form,
              // aplicado de fato no salvar).
              checked: true
              onToggled: checked = !checked
              foreground: root.bar.foreground
              accent: Color.accent
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Model.tr("secure_label")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            text: Model.tr(tlsToggle.checked ? "secure_note" : "insecure_note")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: saveButton
            text: Model.tr(root.sip && root.sip.savingAccount ? "saving_btn" : "save_register")
            foreground: root.bar.foreground
            accent: Color.accent
            bordered: true
            enabled: root.sip && !root.sip.savingAccount && root.callState === "idle"
              && serverField.text.trim() !== "" && usernameField.text.trim() !== ""
            onClicked: {
              var result = root.sip.saveAccount(serverField.text, usernameField.text,
                                                domainField.text, loginField.text,
                                                passwordField.text, tlsToggle.checked)
              if (result === "ok") passwordField.text = ""
              else root.sip.lastError = result
            }
          }

          Text {
            width: parent.width
            text: Model.tr("save_note")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          visible: root.mainView && root.callState !== "idle"
          text: {
            if (root.callState === "incoming") return Model.tr("incoming_prefix") + root.peer
            if (root.callState === "outgoing") return Model.tr("calling_prefix") + root.peer
            return Model.tr("in_call_prefix") + root.peer + " · " + Model.fmtDuration(root.callSeconds)
          }
          textFormat: Text.PlainText
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: root.mainView && root.callState === "idle"

          TextField {
            id: dialField
            width: parent.width - dialButton.width - Style.space(6)
            foreground: root.bar.foreground
            placeholderText: Model.tr("dial_ph")
            enabled: root.registered
            onAccepted: dialButton.doDial()
            Keys.onEscapePressed: root.popupOpen = false
          }

          Button {
            id: dialButton
            iconText: "󰏲"
            text: Model.tr("call_btn")
            foreground: root.bar.foreground
            enabled: root.registered && dialField.text.trim() !== ""
            function doDial() {
              if (!root.sip || dialField.text.trim() === "") return
              var result = root.sip.dial(dialField.text)
              if (result === "ok") dialField.text = ""
            }
            onClicked: doDial()
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          visible: root.mainView && root.callState !== "idle"

          Button {
            visible: root.callState === "incoming"
            iconText: "󰏲"
            text: Model.tr("answer_btn")
            foreground: root.bar.foreground
            accent: Color.accent
            onClicked: if (root.sip) root.sip.answer()
          }

          Button {
            iconText: "󰍭"
            text: Model.tr(root.muted ? "unmute_btn" : "mute_btn")
            visible: root.callState === "active"
            selected: root.muted
            foreground: root.bar.foreground
            onClicked: if (root.sip) root.sip.toggleMute()
          }

          Button {
            iconText: "󰏷"
            text: Model.tr(root.callState === "incoming" ? "reject_btn" : "hangup_btn")
            foreground: root.bar.foreground
            onClicked: if (root.sip) root.sip.hangup()
          }
        }

        PanelSeparator {
          visible: root.mainView
          foreground: root.bar.foreground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.mainView

          ToggleSwitch {
            id: dndToggle
            anchors.verticalCenter: parent.verticalCenter
            checked: root.dnd
            foreground: root.bar.foreground
            accent: Color.accent
            onToggled: if (root.sip) root.sip.toggleDnd()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Model.tr("dnd_label")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          width: parent.width
          visible: root.sip && root.sip.lastError !== ""
          text: root.sip ? root.sip.lastError : ""
          textFormat: Text.PlainText
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
