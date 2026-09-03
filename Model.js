.pragma library

// ---- Idioma da UI: inglês por padrão, pt-BR quando o locale do sistema é
// pt_* (Qt.locale() segue LANG/LC_MESSAGES). Strings novas entram aqui.
var _lang = (function() {
  try { return String(Qt.locale().name || "").indexOf("pt") === 0 ? "pt" : "en" }
  catch (e) { return "en" }
})()

var _msg = {
  connecting:            { en: "connecting…",                          pt: "conectando…" },
  reconnecting:          { en: "reconnecting…",                        pt: "reconectando…" },
  checking_registration: { en: "checking registration…",               pt: "verificando registro…" },
  baresip_down:          { en: "baresip is not running",               pt: "baresip fora do ar" },
  restarting_baresip:    { en: "restarting baresip…",                  pt: "reiniciando baresip…" },
  no_account:            { en: "no account configured",                pt: "sem conta configurada" },
  account_not_loaded:    { en: "account not loaded — restart baresip", pt: "conta não carregada — reinicie o baresip" },
  registering:           { en: "registering…",                         pt: "registrando…" },
  registered:            { en: "registered",                           pt: "registrado" },
  unregistered:          { en: "unregistered",                         pt: "desregistrado" },
  register_failed:       { en: "registration failed",                  pt: "falha de registro" },
  empty_target:          { en: "empty target",                         pt: "alvo vazio" },
  call_in_progress:      { en: "a call is already in progress",        pt: "já existe chamada em andamento" },
  not_registered:        { en: "not registered to the server",         pt: "sem registro no servidor" },
  saving:                { en: "saving…",                              pt: "salvando…" },
  account_busy_call:     { en: "can't change the account during a call", pt: "não é possível trocar a conta durante uma chamada" },
  server_user_required:  { en: "server and username are required",     pt: "servidor e usuário são obrigatórios" },
  command_failed:        { en: "command failed",                       pt: "comando falhou" },
  invalid_response:      { en: "invalid response",                     pt: "resposta inválida" },
  save_account_failed:   { en: "failed to save the account",           pt: "falha ao salvar conta" },
  save_audio_failed:     { en: "failed to save audio devices",         pt: "falha ao salvar áudio" },
  call_rejected_dnd:     { en: "Call rejected (DND)",                  pt: "Chamada recusada (DND)" },
  call_rejected_busy:    { en: "Call rejected (busy)",                 pt: "Chamada recusada (ocupado)" },
  incoming_call:         { en: "Incoming call",                        pt: "Chamada recebida" },
  missed_call:           { en: "Missed call",                          pt: "Chamada perdida" },
  muted:                 { en: "muted",                                pt: "mudo" },
  unmuted:               { en: "unmuted",                              pt: "com áudio" },
  dnd_on:                { en: "dnd on",                               pt: "dnd ligado" },
  dnd_off:               { en: "dnd off",                              pt: "dnd desligado" },
  app_name:              { en: "Softphone",                            pt: "Softfone" },
  no_registration_tip:   { en: "Softphone not registered",             pt: "Softfone sem registro" },
  no_registration:       { en: "not registered",                       pt: "sem registro" },
  registered_prefix:     { en: "Registered: ",                         pt: "Registrado: " },
  configure_account:     { en: "Configure SIP account",                pt: "Configurar conta SIP" },
  audio_devices:         { en: "Audio devices",                        pt: "Dispositivos de áudio" },
  audio_output_label:    { en: "Output (speaker / headset)",           pt: "Saída (alto-falante / fone)" },
  audio_input_label:     { en: "Input (microphone)",                   pt: "Entrada (microfone)" },
  system_default:        { en: "System default",                       pt: "Padrão do sistema" },
  unavailable_suffix:    { en: " (unavailable)",                       pt: " (indisponível)" },
  audio_hint:            { en: "Applied immediately (even mid-call) and saved to ~/.baresip/config. The ringtone follows the output.",
                           pt: "Aplicado na hora (inclusive em chamada) e salvo em ~/.baresip/config. O toque segue a saída." },
  sip_server:            { en: "SIP server",                           pt: "Servidor SIP" },
  sip_server_ph:         { en: "e.g. sip.example.com",                 pt: "ex.: sip.exemplo.com.br" },
  username_ext:          { en: "Username (extension)",                 pt: "Usuário (ramal)" },
  username_ph:           { en: "e.g. 201",                             pt: "ex.: 201" },
  domain_label:          { en: "Domain (empty = server)",              pt: "Domínio (vazio = servidor)" },
  domain_ph:             { en: "same as server",                       pt: "igual ao servidor" },
  login_label:           { en: "Auth login (empty = username)",        pt: "Login de autenticação (vazio = usuário)" },
  login_ph:              { en: "same as username",                     pt: "igual ao usuário" },
  password:              { en: "Password",                             pt: "Senha" },
  password_keep_ph:      { en: "•••• (empty keeps current)",           pt: "•••• (vazio mantém a atual)" },
  password_required_ph:  { en: "required",                             pt: "obrigatória" },
  saving_btn:            { en: "Saving…",                              pt: "Salvando…" },
  save_register:         { en: "Save and register",                    pt: "Salvar e registrar" },
  save_note:             { en: "Saving writes the account and restarts baresip.", pt: "Salvar grava a conta e reinicia o baresip." },
  incoming_prefix:       { en: "Incoming: ",                           pt: "Recebendo: " },
  calling_prefix:        { en: "Calling: ",                            pt: "Chamando: " },
  in_call_prefix:        { en: "In call: ",                            pt: "Em chamada: " },
  dial_ph:               { en: "extension or user@host",               pt: "ramal ou usuario@host" },
  call_btn:              { en: "Call",                                 pt: "Ligar" },
  answer_btn:            { en: "Answer",                               pt: "Atender" },
  mute_btn:              { en: "Mute",                                 pt: "Mudo" },
  unmute_btn:            { en: "Unmute",                               pt: "Ativar som" },
  reject_btn:            { en: "Reject",                               pt: "Recusar" },
  hangup_btn:            { en: "Hang up",                              pt: "Desligar" },
  dnd_label:             { en: "Do not disturb",                       pt: "Não perturbe" },
  secure_label:          { en: "Encryption (TLS + SRTP)",              pt: "Criptografia (TLS + SRTP)" },
  secure_note:           { en: "The server must offer SIP over TLS (default port 5061; use server:port if different).",
                           pt: "O servidor precisa oferecer SIP sobre TLS (porta padrão 5061; use servidor:porta se for outra)." },
  insecure_note:         { en: "Unencrypted UDP: password and audio are visible on the network.",
                           pt: "UDP sem criptografia: senha e áudio ficam visíveis na rede." }
}

function tr(key) {
  var m = _msg[key]
  return m ? (m[_lang] || m.en) : key
}

// Texto de origem remota ou de ferramenta: remove caracteres de controle e
// corta no tamanho máximo — nada disso deve chegar ilimitado à UI/IPC.
function clamp(text, max) {
  var t = String(text || "").replace(/[\x00-\x1f\x7f]/g, " ")
  return t.length > max ? t.substring(0, max - 1) + "…" : t
}

// Corpo de notificação: notify-send interpreta markup — além do clamp,
// remove os metacaracteres.
function notifyText(text) {
  return clamp(text, 80).replace(/[<>&"]/g, "")
}

// Normaliza o alvo digitado para algo que o comando dial do baresip aceita:
// número/ramal puro passa direto (o baresip completa com o domínio da conta),
// "sip:..." passa intacto, "usuario@host" vira "sip:usuario@host".
// Limites: 255 caracteres, só ASCII imprimível sem espaço em URIs.
function normalizeTarget(raw) {
  var t = String(raw || "").trim()
  if (t === "" || t.length > 255) return ""
  var isUri = t.indexOf("sip:") === 0 || t.indexOf("sips:") === 0
  if (isUri || t.indexOf("@") > 0) {
    if (!/^[\x21-\x7e]+$/.test(t)) return ""
    return isUri ? t : "sip:" + t
  }
  return t.replace(/[^0-9+*#]/g, "")
}

// Nome curto para exibir: "sip:203@sip.exemplo.com.br" -> "203"
function peerDisplay(uri) {
  var t = clamp(uri, 255)
  t = t.replace(/^"?([^"<]*)"?\s*</, "$1|<")
  var display = ""
  var pipe = t.indexOf("|<")
  if (pipe > 0) {
    display = t.substring(0, pipe).trim()
    t = t.substring(pipe + 1)
  }
  t = t.replace(/^<|>$/g, "").replace(/^sips?:/, "")
  var at = t.indexOf("@")
  var user = at > 0 ? t.substring(0, at) : t
  user = user.split(";")[0]
  return clamp(display !== "" ? display + " (" + user + ")" : user, 64)
}

// O baresip colore a saída com escapes ANSI (ex.: ESC[32mOK); sem removê-los,
// "mOK" não casa com \bOK\b e as mensagens ficam ilegíveis na UI.
function stripAnsi(text) {
  return String(text || "").replace(/\x1b\[[0-9;]*m/g, "")
}

// Interpreta a resposta textual do comando reginfo ("--- User Agents (N) ---"
// com "OK" por conta registrada). Usado para ressincronizar o estado quando a
// ponte conecta depois dos eventos de registro (ex.: baresip reiniciado).
function parseReginfo(data) {
  var clean = stripAnsi(data)
  var m = /User Agents \((\d+)\)/.exec(clean)
  if (!m) return { known: false }
  var count = parseInt(m[1], 10)
  var aorMatch = /sips?:([^;>\s]+)/.exec(clean)
  var ok = /\bOK\b/.test(clean)
  var fail = /\b(ERR|FAIL)/i.test(clean)
  return {
    known: true,
    count: count,
    registered: count > 0 && ok && !fail,
    failed: fail,
    aor: aorMatch ? clamp(aorMatch[1], 96) : ""
  }
}

// Resposta dos comandos auplay/ausrc: o baresip devolve código 0 mesmo quando
// recusa o dispositivo ("no such device for pipewire audio-player: x" seguido
// da lista); o erro só aparece no texto.
function audioSwitchError(data) {
  var first = stripAnsi(data).split("\n").filter(function(l) { return l.trim() !== "" })[0] || ""
  return /no such|Format should be|failed/i.test(first) ? clamp(first.trim(), 160) : ""
}

// Opções do Dropdown de dispositivos: "" = padrão do sistema; o dispositivo
// salvo que não está presente (ex.: fone desconectado) continua selecionável
// para não sumir da UI.
function deviceOptions(nodes, current) {
  var opts = [{ value: "", label: tr("system_default") }]
  var found = false
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n || !n.name) continue
    var name = String(n.name)
    if (name === current) found = true
    opts.push({ value: name, label: clamp(n.description || n.nickname || name, 64) })
  }
  if (current !== "" && !found) opts.push({ value: current, label: clamp(current, 64) + tr("unavailable_suffix") })
  return opts
}

function fmtDuration(totalSeconds) {
  var s = Math.max(0, Math.floor(totalSeconds))
  var m = Math.floor(s / 60)
  var h = Math.floor(m / 60)
  m = m % 60
  s = s % 60
  function pad(n) { return (n < 10 ? "0" : "") + n }
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}
