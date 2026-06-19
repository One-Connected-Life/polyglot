import { Controller } from "@hotwired/stimulus"
import { speak } from "speech"

// Standalone pronounce button: data-speak-text-value + data-speak-lang-value.
export default class extends Controller {
  static values = { text: String, lang: String }
  static targets = ["hint"]

  say() {
    speak(this.textValue, this.langValue, { onResult: (r) => this.report(r) })
  }

  report({ hasVoice, lang }) {
    if (!this.hasHintTarget) return
    if (hasVoice) {
      this.hintTarget.classList.add("hidden")
    } else {
      this.hintTarget.textContent =
        `No ${lang} voice on this device — it falls back to English. ` +
        `Install one in System Settings → Accessibility → Spoken Content → System Voices, then reload.`
      this.hintTarget.classList.remove("hidden")
    }
  }
}
