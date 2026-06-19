import { Controller } from "@hotwired/stimulus"
import { speak as pronounce } from "speech"

const DIFFICULTY_METER = { easy: "● ○ ○", medium: "● ● ○", hard: "● ● ●" }

// Keyboard-driven drill. Prompt -> type -> Enter checks (and reveals the full
// multi-language card) -> arrows/Space/Enter move. Keys handled on window so
// navigation works after the input locks. Cards are graded in-browser.
export default class extends Controller {
  static targets = [
    "prompt", "kindTag", "input", "feedback", "answer", "given", "answerSpeak",
    "difficulty", "alts", "detail", "nextBtn", "checkBtn", "backBtn",
    "progress", "score", "bar", "card", "summary", "summaryText", "missed", "auto", "autoWrong", "voiceHint"
  ]
  static values = { cards: Array, sentences: Array, from: String, to: String, recordUrl: String }

  connect() {
    this.cards = this.buildSequence(this.cardsValue, this.hasSentencesValue ? this.sentencesValue : [])
    this.results = this.cards.map(() => ({ graded: false, correct: false, given: "" }))
    this.index = 0
    this.autoOn = localStorage.getItem("drill-autoplay") === "1"
    if (this.hasAutoTarget) this.autoTarget.checked = this.autoOn
    this.autoWrongOn = localStorage.getItem("drill-autoplay-wrong") === "1"
    if (this.hasAutoWrongTarget) this.autoWrongTarget.checked = this.autoWrongOn
    this.ownedThisRun = 0
    this.onKey = this.onKey.bind(this)
    window.addEventListener("keydown", this.onKey)
    this.bindSwipe()
    this.render()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
    this.unbindSwipe()
  }

  // Touch: swipe right = forward (reveal, then next), swipe left = back.
  // Mirrors Enter/ArrowRight so phone-in-bed practice needs no keyboard.
  bindSwipe() {
    if (!this.hasCardTarget) return
    this.touchStartX = null
    this.onTouchStart = (event) => {
      const t = event.changedTouches[0]
      this.touchStartX = t.clientX
      this.touchStartY = t.clientY
    }
    this.onTouchEnd = (event) => {
      if (this.touchStartX == null) return
      const t = event.changedTouches[0]
      const dx = t.clientX - this.touchStartX
      const dy = t.clientY - this.touchStartY
      this.touchStartX = null
      // Need a clear, mostly-horizontal flick to count as a swipe.
      if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy)) return
      if (dx > 0) this.forward()
      else this.prev()
    }
    this.cardTarget.addEventListener("touchstart", this.onTouchStart, { passive: true })
    this.cardTarget.addEventListener("touchend", this.onTouchEnd, { passive: true })
  }

  unbindSwipe() {
    if (!this.hasCardTarget) return
    this.cardTarget.removeEventListener("touchstart", this.onTouchStart)
    this.cardTarget.removeEventListener("touchend", this.onTouchEnd)
  }

  // One forward step: reveal the answer if still answering, else advance.
  // Same overload as Enter / the big → button / swipe-right.
  forward() {
    if (this.results[this.index].graded) this.next()
    else this.grade()
  }

  // Shuffle words, then sprinkle sentences in after a word (~1 in 3); rest at end.
  buildSequence(words, sentences) {
    const w = this.shuffle([...words])
    const s = this.shuffle([...sentences])
    if (s.length === 0) return w

    const seq = []
    let si = 0
    w.forEach((word) => {
      seq.push(word)
      if (si < s.length && Math.random() < 0.34) seq.push(s[si++])
    })
    while (si < s.length) seq.push(s[si++])
    return seq
  }

  onKey(event) {
    const result = this.results[this.index]

    // Answering: Enter checks; everything else (incl. Space for multi-word) types normally.
    if (!result.graded) {
      if (event.key === "Enter") { event.preventDefault(); this.grade() }
      return
    }

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
    const saved = this.record(card.id, result.correct, result.given)
    this.render()

    if (result.correct) {
      // Server tells us when this answer first reaches 2 corrects (enters the collection).
      saved.then((data) => { if (data && data.newly_owned) this.celebrate(card) })
    } else if (this.autoWrongOn) {
      this.speakAnswer()
    }
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
    const isSentence = card.kind === "sentence"

    this.promptTarget.textContent = card.prompt
    this.promptTarget.className = isSentence
      ? "mt-2 text-2xl font-medium leading-snug"
      : "mt-2 text-4xl font-semibold tracking-tight sm:text-5xl"
    if (this.hasKindTagTarget) this.kindTagTarget.textContent = isSentence ? " · sentence" : ""

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
      this.renderDetail(card)
      if (this.hasNextBtnTarget) this.nextBtnTarget.classList.remove("hidden")
      if (this.hasCheckBtnTarget) this.checkBtnTarget.classList.add("hidden")

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
      if (this.hasDetailTarget) { this.detailTarget.innerHTML = ""; this.detailTarget.classList.add("hidden") }
      if (this.hasNextBtnTarget) this.nextBtnTarget.classList.add("hidden")
      if (this.hasCheckBtnTarget) this.checkBtnTarget.classList.remove("hidden")
      this.inputTarget.focus()
      if (this.autoOn) this.speakPrompt()
    }

    // Back is available whenever there's a previous card, in either state.
    if (this.hasBackBtnTarget) this.backBtnTarget.classList.toggle("hidden", this.index === 0)
  }

  // The "all languages" card from the show page, rendered inline on reveal.
  // Stimulus auto-connects the injected speak buttons.
  renderDetail(card) {
    if (!this.hasDetailTarget) return
    const esc = (s) => (s || "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
    this.detailTarget.innerHTML = (card.translations || []).map((t) => {
      const surfaced = t.lang === this.fromValue || t.lang === this.toValue
      return `<div class="flex items-center justify-between py-1.5">
        <div class="flex items-baseline gap-3">
          <span class="w-6 text-[11px] uppercase text-gray-400">${esc(t.lang)}</span>
          <span class="text-sm ${surfaced ? "font-medium" : "text-gray-500 dark:text-gray-400"}">${esc(t.text)}</span>
        </div>
        <button type="button" data-controller="speak" data-speak-text-value="${esc(t.text)}" data-speak-lang-value="${esc(t.lang)}" data-action="speak#say" class="rounded-md px-2 py-1 text-sm text-gray-400 hover:bg-gray-100 hover:text-gray-700 dark:hover:bg-gray-800 dark:hover:text-gray-200" aria-label="pronounce">🔊</button>
      </div>`
    }).join("")
    this.detailTarget.classList.remove("hidden")
  }

  finish() {
    const correct = this.results.filter((r) => r.correct).length
    const pct = Math.round((correct / this.cards.length) * 100)
    const missed = this.cards
      .filter((_, i) => this.results[i].graded && !this.results[i].correct)
      .map((c) => c.prompt)

    const owned = this.ownedThisRun ? `🎉 ${this.ownedThisRun} newly owned. ` : ""
    this.summaryTextTarget.textContent = `${correct} / ${this.cards.length} correct (${pct}%)`
    this.missedTarget.textContent = owned + (missed.length ? `Missed: ${missed.join(", ")}` : "Clean run — nothing missed.")
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

  // A short celebration when a word crosses into the owned collection.
  celebrate(card) {
    this.ownedThisRun++
    if (!this.hasCelebrateTarget) return
    this.celebrateTextTarget.textContent = `🎉 Owned! “${card.answer}” is in your collection`
    const el = this.celebrateTarget
    const bubble = el.firstElementChild
    el.classList.remove("hidden"); el.classList.add("flex")
    bubble.classList.remove("animate-celebrate")
    void bubble.offsetWidth // restart the animation
    bubble.classList.add("animate-celebrate")
    clearTimeout(this._celebrateTimer)
    this._celebrateTimer = setTimeout(() => { el.classList.add("hidden"); el.classList.remove("flex") }, 2000)
  }

  // --- speech (browser TTS, no backend) ---

  toggleAuto() {
    this.autoOn = this.autoTarget.checked
    localStorage.setItem("drill-autoplay", this.autoOn ? "1" : "0")
    if (this.autoOn) this.speakPrompt()
  }

  toggleAutoWrong() {
    this.autoWrongOn = this.autoWrongTarget.checked
    localStorage.setItem("drill-autoplay-wrong", this.autoWrongOn ? "1" : "0")
  }

  speakPrompt() { this.speak(this.cards[this.index].prompt, this.fromValue) }
  speakAnswer() { this.speak(this.cards[this.index].answer, this.toValue) }

  speak(text, code) {
    pronounce(text, code, { onResult: ({ hasVoice, lang }) => this.flagMissingVoice(hasVoice, lang) })
  }

  flagMissingVoice(hasVoice, lang) {
    if (!this.hasVoiceHintTarget) return
    if (hasVoice) {
      this.voiceHintTarget.classList.add("hidden")
    } else {
      this.voiceHintTarget.textContent =
        `No ${lang} voice installed — audio falls back to English (wrong). ` +
        `Install one: System Settings → Accessibility → Spoken Content → System Voices → add a Dutch voice, then reload.`
      this.voiceHintTarget.classList.remove("hidden")
    }
  }

  // --- persistence ---

  record(termId, correct, given) {
    if (!this.hasRecordUrlValue || !this.recordUrlValue) return Promise.resolve(null)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(this.recordUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ term_id: termId, from: this.fromValue, to: this.toValue, correct, given }),
      keepalive: true,
    }).then((r) => (r.ok ? r.json() : null)).catch(() => null)
  }

  // Forgiving compare: case/whitespace/diacritics/punctuation-insensitive, ignores leading articles.
  normalize(value) {
    return (value || "")
      .toLowerCase()
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[.,!?;:]/g, "")
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
