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
export function speak(text, code, { onResult } = {}) {
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
    utterance.rate = 0.9
    synth.cancel()
    synth.speak(utterance)
    if (onResult) onResult({ hasVoice: !!voice, lang: LANG_TAGS[code] || code })
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

export { LANG_TAGS }
