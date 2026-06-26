// Browser speech recognition (Web Speech API) for "answer by speaking".
// Thin wrapper over SpeechRecognition / webkitSpeechRecognition so the drill
// controller can listen for a spoken answer, transcribe it, and grade it exactly
// like a typed one.
//
// IMPORTANT (the iOS trap): the Hotwire Native iOS shell's WKWebView EXPOSES
// webkitSpeechRecognition but it does NOT actually work there. Callers must
// detect the native shell separately (via the OCL-App/H UA token) and treat
// speech as unavailable — isListenSupported() only checks for the API's
// presence, which the shell lies about.

import { LANG_TAGS } from "speech"

function Recognition() {
  return window.SpeechRecognition || window.webkitSpeechRecognition || null
}

// Is the Web Speech recognition API present at all? (Does NOT account for the
// iOS WKWebView shell, which exposes-but-breaks it — caller handles that.)
export function isListenSupported() {
  return !!Recognition()
}

// Listen once for a spoken answer in language `code` (ISO 639-1).
//   onResult(transcript)  — fires with the best transcript on a match
//   onError(err)          — fires on recognition error or no-match
//   onEnd()               — always fires when the session ends (cleanup hook)
// Returns a handle with .stop() / .abort() so the caller can cancel (e.g. on
// disconnect or when the user starts typing instead).
export function listen(code, { onResult, onError, onEnd } = {}) {
  const Ctor = Recognition()
  if (!Ctor) {
    if (onError) onError(new Error("speech-recognition-unsupported"))
    if (onEnd) onEnd()
    return { stop() {}, abort() {} }
  }

  const recognition = new Ctor()
  recognition.lang = LANG_TAGS[code] || code || "en-US"
  recognition.interimResults = false
  recognition.maxAlternatives = 1
  recognition.continuous = false

  let settled = false

  recognition.onresult = (event) => {
    const result = event.results && event.results[0] && event.results[0][0]
    const transcript = result ? (result.transcript || "").trim() : ""
    if (transcript) {
      settled = true
      if (onResult) onResult(transcript)
    } else if (onError) {
      onError(new Error("no-transcript"))
    }
  }

  recognition.onnomatch = () => { if (onError) onError(new Error("no-match")) }
  recognition.onerror = (event) => { if (onError) onError(event.error ? new Error(event.error) : new Error("recognition-error")) }
  recognition.onend = () => { if (onEnd) onEnd(settled) }

  try {
    recognition.start()
  } catch (_e) {
    // start() throws if called while already running — surface as an error.
    if (onError) onError(_e)
    if (onEnd) onEnd(false)
  }

  return {
    stop() { try { recognition.stop() } catch (_e) {} },
    abort() { try { recognition.abort() } catch (_e) {} },
  }
}
