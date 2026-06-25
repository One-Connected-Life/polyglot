// Browser text-to-speech with proper voice selection.
// Setting utterance.lang alone is NOT enough — Chrome will read foreign text with
// the default (English) voice unless you assign an actual matching voice.

const LANG_TAGS = {
  en: "en-GB", nl: "nl-NL", es: "es-ES", fr: "fr-FR", it: "it-IT", ro: "ro-RO", ru: "ru-RU",
}

function normLang(lang) {
  return (lang || "").replace("_", "-").toLowerCase()
}

function voiceFor(code) {
  const tag = normLang(LANG_TAGS[code] || code)
  const short = (code || "").slice(0, 2).toLowerCase()
  const voices = window.speechSynthesis.getVoices()
  return voices.find((v) => normLang(v.lang) === tag)
      || voices.find((v) => normLang(v.lang).startsWith(short))
      || null
}

// Speak `text` in language `code` (ISO 639-1). onResult({ hasVoice, lang }) reports
// whether a real voice was found, so callers can warn instead of mumbling English.
export function speak(text, code, { onResult, rate, pitch } = {}) {
  if (!("speechSynthesis" in window) || !text) return
  const synth = window.speechSynthesis

  const go = () => {
    const utterance = new SpeechSynthesisUtterance(text)
    const voice = voiceFor(code)
    if (voice) {
      utterance.voice = voice
      utterance.lang = voice.lang
    } else {
      utterance.lang = LANG_TAGS[code] || code
    }
    utterance.rate = rate ?? 0.9
    if (pitch != null) utterance.pitch = pitch

    // WebKit (iOS WKWebView/Safari) clips short utterances when speak() is called
    // immediately after cancel(): the cancel races the new utterance and chops it
    // to a blip (e.g. "zij" — Finding C). Only cancel when something is actually
    // playing, and give WebKit a beat to settle the cancel before speaking. When
    // nothing is in flight (the common deliberate-tap case) we skip cancel entirely.
    const emit = () => {
      synth.speak(utterance)
      if (onResult) onResult({ hasVoice: !!voice, lang: LANG_TAGS[code] || code })
    }
    if (synth.speaking || synth.pending) {
      synth.cancel()
      setTimeout(emit, 120)
    } else {
      emit()
    }
  }

  // Voices load async; if not ready, wait for them (once).
  if (synth.getVoices().length === 0) {
    let done = false
    const once = () => { if (done) return; done = true; go() }
    synth.addEventListener("voiceschanged", once, { once: true })
    setTimeout(() => { if (synth.getVoices().length) once() }, 250)
  } else {
    go()
  }
}

// Cancel any in-flight or queued speech. Safe to call when nothing is speaking.
// Used by the drill controller on disconnect / page-hide / Turbo cache so audio
// doesn't keep firing across cards after you leave. (Finding B)
export function stop() {
  if (!("speechSynthesis" in window)) return
  window.speechSynthesis.cancel()
}

export { LANG_TAGS }
