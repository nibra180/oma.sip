.pragma library

// Normaliza o alvo digitado para algo que o comando dial do baresip aceita:
// número/ramal puro passa direto (o baresip completa com o domínio da conta),
// "sip:..." passa intacto, "usuario@host" vira "sip:usuario@host".
function normalizeTarget(raw) {
  var t = String(raw || "").trim()
  if (t === "") return ""
  if (t.indexOf("sip:") === 0 || t.indexOf("sips:") === 0) return t
  if (t.indexOf("@") > 0) return "sip:" + t
  return t.replace(/[^0-9+*#]/g, "")
}

// Nome curto para exibir: "sip:203@gb.quicksip.com.br" -> "203"
function peerDisplay(uri) {
  var t = String(uri || "")
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
  return display !== "" ? display + " (" + user + ")" : user
}

// Interpreta a resposta textual do comando reginfo ("--- User Agents (N) ---"
// com "OK" por conta registrada). Usado para ressincronizar o estado quando a
// ponte conecta depois dos eventos de registro (ex.: baresip reiniciado).
function parseReginfo(data) {
  // O baresip colore a saída com escapes ANSI (ex.: ESC[32mOK); sem
  // removê-los, "mOK" não casa com \bOK\b.
  var clean = String(data || "").replace(/\[[0-9;]*m/g, "")
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
    aor: aorMatch ? aorMatch[1] : ""
  }
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
