import { Controller } from "@hotwired/stimulus"

// ISO 639-1 -> BCP-47 so the browser picks the right voice.
const LANG_TAGS = {
  en: "en-GB", nl: "nl-NL", es: "es-ES", fr: "fr-FR", it: "it-IT", ro: "ro-RO", ru: "ru-RU",
}

const DIFFICULTY_METER = { easy: "● ○ ○", medium: "● ● ○", hard: "● ● ●" }

// Keyboard-driven drill. Prompt -> type -> Enter checks -> arrows/Space/Enter move.
// Keys are handled on window (not the input) so navigation works after the input
// is locked on reveal. Cards arrive as JSON, graded in-browser — no round-trip.
export default class extends Controller {
  static targets = [
    "prompt", "input", "feedback", "answer", "given", "answerSpeak", "difficulty", "alts",
    "progress", "score", "bar", "card", "summary", "summaryText", "missed", "auto"
  ]
  static values = { cards: Array, from: String, to: String, recordUrl: String }

  connect() {
    this.cards = this.shuffle([...this.cardsValue])
    this.results = this.cards.map(() => ({ graded: false, correct: false, given: "" }))
    this.index = 0
    this.autoOn = localStorage.getItem("drill-autoplay") === "1"
    if (this.hasAutoTarget) this.autoTarget.checked = this.autoOn
    this.onKey = this.onKey.bind(this)
    window.addEventListener("keydown", this.onKey)
    this.render()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
  }

  onKey(event) {
    const result = this.results[this.index]

    // Answering: Enter checks; everything else (incl. Space for multi-word) types normally.
    if (!result.graded) {
      if (event.key === "Enter") { event.preventDefault(); this.grade() }
      return
    }

    // Reveal: navigate.
    switch (event.key) {
      case "ArrowRight":
      case "ArrowDown":
      case " ":
      case "Enter":
        event.preventDefault(); this.next(); break
      case "ArrowLeft":
      case "ArrowUp":
        event.preventDefault(); this.prev(); break
    }
  }

  grade() {
    const card = this.cards[this.index]
    const result = this.results[this.index]
    result.given = this.inputTarget.value
    const accepted = (card.accept && card.accept.length ? card.accept : [card.answer]).map((a) => this.normalize(a))
    result.correct = accepted.includes(this.normalize(result.given))
    result.graded = true
    this.record(card.id, result.correct, result.given)
    this.render()
  }

  next() {
    if (this.index >= this.cards.length - 1) {
      if (this.results.every((r) => r.graded)) return this.finish()
    }
    this.index = Math.min(this.index + 1, this.cards.length - 1)
    this.render()
  }

  prev() {
    this.index = Math.max(this.index - 1, 0)
    this.render()
  }

  render() {
    const card = this.cards[this.index]
    const result = this.results[this.index]

    this.promptTarget.textContent = card.prompt
    this.progressTarget.textContent = `${this.index + 1} / ${this.cards.length}`
    this.barTarget.style.width = `${((this.index + 1) / this.cards.length) * 100}%`
    this.updateScore()

    if (result.graded) {
      const full = card.answer_article ? `${card.answer_article} ${card.answer}` : card.answer
      this.inputTarget.value = result.given
      this.inputTarget.disabled = true
      this.inputTarget.blur()
      this.feedbackTarget.textContent = result.correct ? "✓ correct" : "✗ not quite"
      this.feedbackTarget.className = result.correct
        ? "text-sm font-medium text-emerald-600 dark:text-emerald-400"
        : "text-sm font-medium text-rose-600 dark:text-rose-400"
      this.answerTarget.textContent = full
      this.answerTarget.classList.remove("invisible")
      if (this.hasAnswerSpeakTarget) this.answerSpeakTarget.classList.remove("hidden")
      this.showDifficulty(card.difficulty)
      this.showAlts(card)

      if (!result.correct && this.normalize(result.given) !== "") {
        this.givenTarget.textContent = `you typed: ${result.given}`
        this.givenTarget.classList.remove("hidden")
      } else {
        this.givenTarget.classList.add("hidden")
      }
    } else {
      this.inputTarget.value = ""
      this.inputTarget.disabled = false
      this.feedbackTarget.textContent = ""
      this.answerTarget.textContent = ""
      this.answerTarget.classList.add("invisible")
      this.givenTarget.classList.add("hidden")
      if (this.hasAnswerSpeakTarget) this.answerSpeakTarget.classList.add("hidden")
      if (this.hasDifficultyTarget) this.difficultyTarget.textContent = ""
      if (this.hasAltsTarget) this.altsTarget.textContent = ""
      this.inputTarget.focus()
      if (this.autoOn) this.speakPrompt()
    }
  }

  finish() {
    const correct = this.results.filter((r) => r.correct).length
    const pct = Math.round((correct / this.cards.length) * 100)
    const missed = this.cards
      .filter((_, i) => this.results[i].graded && !this.results[i].correct)
      .map((c) => c.prompt)

    this.summaryTextTarget.textContent = `${correct} / ${this.cards.length} correct (${pct}%)`
    this.missedTarget.textContent = missed.length ? `Missed: ${missed.join(", ")}` : "Clean run — nothing missed."
    this.cardTarget.classList.add("hidden")
    this.summaryTarget.classList.remove("hidden")
  }

  restart() {
    window.removeEventListener("keydown", this.onKey)
    this.connect()
    this.cardTarget.classList.remove("hidden")
    this.summaryTarget.classList.add("hidden")
  }

  updateScore() {
    const correct = this.results.filter((r) => r.correct).length
    const graded = this.results.filter((r) => r.graded).length
    this.scoreTarget.textContent = graded ? `${correct}/${graded}` : ""
  }

  showDifficulty(level) {
    if (!this.hasDifficultyTarget) return
    this.difficultyTarget.textContent = DIFFICULTY_METER[level] ? `${DIFFICULTY_METER[level]}  ${level}` : ""
  }

  showAlts(card) {
    if (!this.hasAltsTarget) return
    const extra = (card.accept || []).filter((a) => this.normalize(a) !== this.normalize(card.answer))
    this.altsTarget.textContent = extra.length ? `also accepted: ${extra.join(", ")}` : ""
  }

  // --- speech (browser TTS, no backend) ---

  toggleAuto() {
    this.autoOn = this.autoTarget.checked
    localStorage.setItem("drill-autoplay", this.autoOn ? "1" : "0")
    if (this.autoOn) this.speakPrompt()
  }

  speakPrompt() { this.speak(this.cards[this.index].prompt, this.fromValue) }
  speakAnswer() { this.speak(this.cards[this.index].answer, this.toValue) }

  speak(text, code) {
    if (!("speechSynthesis" in window) || !text) return
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.lang = LANG_TAGS[code] || code
    window.speechSynthesis.cancel()
    window.speechSynthesis.speak(utterance)
  }

  // --- persistence ---

  // Fire-and-forget: persist the answer without blocking the drill rhythm.
  record(termId, correct, given) {
    if (!this.hasRecordUrlValue || !this.recordUrlValue) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.recordUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ term_id: termId, from: this.fromValue, to: this.toValue, correct, given }),
      keepalive: true,
    }).catch(() => {})
  }

  // Forgiving compare: case/whitespace/diacritics-insensitive, ignores leading articles.
  normalize(value) {
    return (value || "")
      .toLowerCase()
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/^(de|het|een|the|a|an)\s+/, "")
      .replace(/\s+/g, " ")
      .trim()
  }

  shuffle(array) {
    for (let i = array.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[array[i], array[j]] = [array[j], array[i]]
    }
    return array
  }
}
