import QtQuick
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
  function close() { popupOpen = false }

  onPopupOpenChanged: {
    if (popupOpen) {
      showAccount = sip ? !sip.accountConfigured : false
      if (showAccount) fillAccountForm()
    }
    focusPreferred()
  }
  onShowAccountChanged: {
    if (showAccount) fillAccountForm()
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
      ? "Softfone: " + (root.sip ? root.sip.regDetail : "")
      : "Softfone sem registro" + (root.sip && root.sip.regDetail ? " · " + root.sip.regDetail : ""))
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
            width: parent.width - gearButton.width - Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (!root.up) return "baresip fora do ar"
              if (!root.registered) return root.sip ? root.sip.regDetail : "sem registro"
              return "Registrado: " + root.sip.regDetail
            }
            color: root.registered ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: gearButton
            iconText: "󰒓"
            tooltipText: "Configurar conta SIP"
            foreground: root.bar.foreground
            selected: root.showAccount
            onClicked: root.showAccount = !root.showAccount
          }
        }

        // ---- Conta (SIP server / usuário / domínio / login / senha) ----
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.showAccount

          Text {
            text: "Servidor SIP"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: serverField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: "ex.: gb.quicksip.com.br"
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: "Usuário (ramal)"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: usernameField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: "ex.: 2939"
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: "Domínio (vazio = servidor)"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: domainField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: "igual ao servidor"
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: "Login de autenticação (vazio = usuário)"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: loginField
            width: parent.width
            foreground: root.bar.foreground
            placeholderText: "igual ao usuário"
            Keys.onEscapePressed: root.popupOpen = false
          }

          Text {
            text: "Senha"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: passwordField
            width: parent.width
            foreground: root.bar.foreground
            password: true
            placeholderText: root.sip && root.sip.accountHasPassword ? "•••• (vazio mantém a atual)" : "obrigatória"
            Keys.onEscapePressed: root.popupOpen = false
          }

          Button {
            id: saveButton
            text: root.sip && root.sip.savingAccount ? "Salvando…" : "Salvar e registrar"
            foreground: root.bar.foreground
            accent: Color.accent
            bordered: true
            enabled: root.sip && !root.sip.savingAccount && root.callState === "idle"
              && serverField.text.trim() !== "" && usernameField.text.trim() !== ""
            onClicked: {
              var result = root.sip.saveAccount(serverField.text, usernameField.text,
                                                domainField.text, loginField.text, passwordField.text)
              if (result === "ok") passwordField.text = ""
              else root.sip.lastError = result
            }
          }

          Text {
            width: parent.width
            text: "Salvar grava a conta e reinicia o baresip."
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          visible: !root.showAccount && root.callState !== "idle"
          text: {
            if (root.callState === "incoming") return "Recebendo: " + root.peer
            if (root.callState === "outgoing") return "Chamando: " + root.peer
            return "Em chamada: " + root.peer + " · " + Model.fmtDuration(root.callSeconds)
          }
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: !root.showAccount && root.callState === "idle"

          TextField {
            id: dialField
            width: parent.width - dialButton.width - Style.space(6)
            foreground: root.bar.foreground
            placeholderText: "ramal ou usuario@host"
            enabled: root.registered
            onAccepted: dialButton.doDial()
            Keys.onEscapePressed: root.popupOpen = false
          }

          Button {
            id: dialButton
            iconText: "󰏲"
            text: "Ligar"
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
          visible: !root.showAccount && root.callState !== "idle"

          Button {
            visible: root.callState === "incoming"
            iconText: "󰏲"
            text: "Atender"
            foreground: root.bar.foreground
            accent: Color.accent
            onClicked: if (root.sip) root.sip.answer()
          }

          Button {
            iconText: "󰍭"
            text: root.muted ? "Ativar som" : "Mudo"
            visible: root.callState === "active"
            selected: root.muted
            foreground: root.bar.foreground
            onClicked: if (root.sip) root.sip.toggleMute()
          }

          Button {
            iconText: "󰏷"
            text: root.callState === "incoming" ? "Recusar" : "Desligar"
            foreground: root.bar.foreground
            onClicked: if (root.sip) root.sip.hangup()
          }
        }

        PanelSeparator {
          visible: !root.showAccount
          foreground: root.bar.foreground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.showAccount

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
            text: "Não perturbe"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          width: parent.width
          visible: root.sip && root.sip.lastError !== ""
          text: root.sip ? root.sip.lastError : ""
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
