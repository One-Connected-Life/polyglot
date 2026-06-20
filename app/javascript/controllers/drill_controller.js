import { Controller } from "@hotwired/stimulus"
import { speak as pronounce } from "speech"

const DIFFICULTY_METER = { easy: "● ○ ○", medium: "● ● ○", hard: "● ● ●" }

// Keyboard-driven drill. Prompt -> type -> Enter checks (and reveals the full
// multi-language card) -> arrows/Space/Enter move. Keys handled on window so
// navigation works after the input locks. Cards are graded in-browser.
//
// MULTI-LANGUAGE MODE (kind === "multi"):
//   Each card has a `targets` array (one entry per learning language).
//   The card loops through targets one at a time:
//     - source word pins at top
//     - ONE target input is live at a time
//     - on Check: answer settles into a completed band above, next target becomes live
//     - when all targets done: "Next concept →" button appears
//   One Attempt is recorded per target (from_language → to_language = target.lang).
//   The regular single-target flow is entirely unchanged.
export default class extends Controller {
  static targets = [
    "prompt", "kindTag", "input", "feedback", "answer", "given", "answerSpeak",
    "difficulty", "alts", "detail", "nextBtn", "checkBtn", "backBtn",
    "progress", "score", "bar", "card", "summary", "summaryText", "missed", "auto", "autoWrong", "voiceHint",
    // Multi-language targets (only present when @multi == true in the view):
    "multiCard", "multiFrom", "multiPrompt", "multiStep",
    "multiDone", "multiLangLabel", "multiInput", "multiUpcoming",
    "multiCheck", "multiNext", "celebrateText", "celebrate",
    // PHONETICS: containers for IPA + translit under the prompt and answer words
    "promptPhonetics", "answerPhonetics",
    // FSRS retire targets — the bigger "Retired" overlay (#axis-4).
    // Only present when FSRS_ENABLED=1; guarded with hasRetireOverlayTarget.
    "retireOverlay", "retireBubble", "retireWord",
  ]
  static values = { cards: Array, sentences: Array, from: String, to: String, recordUrl: String, multi: Boolean, fsrsEnabled: Boolean }

  connect() {
    this.cards = this.buildSequence(this.cardsValue, this.hasSentencesValue ? this.sentencesValue : [])
    this.results = this.cards.map((card) => this.initResult(card))
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

  // Initialise a per-card result object.
  // Multi cards carry per-target state in result.targets[].
  initResult(card) {
    if (card.kind === "multi") {
      return {
        graded: false,      // true once ALL targets done
        targetIndex: 0,     // which target is currently live
        targets: card.targets.map(() => ({ graded: false, correct: false, given: "" })),
      }
    }
    return { graded: false, correct: false, given: "" }
  }

  // Touch: swipe right = forward (reveal, then next), swipe left = back.
  // Mirrors Enter/ArrowRight so phone-in-bed practice needs no keyboard.
  bindSwipe() {
    const el = this.hasMultiCardTarget ? this.multiCardTarget : (this.hasCardTarget ? this.cardTarget : null)
    if (!el) return
    this._swipeEl = el
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
    el.addEventListener("touchstart", this.onTouchStart, { passive: true })
    el.addEventListener("touchend", this.onTouchEnd, { passive: true })
  }

  unbindSwipe() {
    if (!this._swipeEl) return
    this._swipeEl.removeEventListener("touchstart", this.onTouchStart)
    this._swipeEl.removeEventListener("touchend", this.onTouchEnd)
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

    // --- MULTI-LANGUAGE grade: one target at a time ---
    if (card.kind === "multi") {
      this.gradeMultiTarget()
      return
    }

    // --- SINGLE-LANGUAGE grade (unchanged) ---
    const result = this.results[this.index]
    result.given = this.inputTarget.value
    const accepted = (card.accept && card.accept.length ? card.accept : [card.answer]).map((a) => this.normalize(a))
    result.correct = accepted.includes(this.normalize(result.given))
    result.graded = true
    const saved = this.record(card.id, result.correct, result.given, this.fromValue, this.toValue)
    this.render()

    if (result.correct) {
      saved.then((data) => {
        if (!data) return
        // FSRS path: fire the bigger "retired" overlay at the crossing moment.
        if (data.newly_retired) {
          this.celebrateRetire(card)
        } else if (data.newly_owned) {
          // Legacy path: small "owned" pill.
          this.celebrate(card)
        }
      })
    } else if (this.autoWrongOn) {
      this.speakAnswer()
    }
  }

  // Grade the currently live target in a multi-language card.
  gradeMultiTarget() {
    const card = this.cards[this.index]
    const result = this.results[this.index]
    const ti = result.targetIndex
    const target = card.targets[ti]
    const tResult = result.targets[ti]

    tResult.given = this.multiInputTarget.value
    const accepted = (target.accept && target.accept.length ? target.accept : [target.answer]).map((a) => this.normalize(a))
    tResult.correct = accepted.includes(this.normalize(tResult.given))
    tResult.graded = true

    // Record one Attempt per target language direction.
    this.record(card.id, tResult.correct, tResult.given, this.fromValue, target.lang)

    const allDone = result.targets.every((t) => t.graded)
    if (allDone) {
      result.graded = true
    } else {
      result.targetIndex = ti + 1
    }
    this.renderMulti()
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
    if (card.kind === "multi") {
      this.renderMulti()
    } else {
      this.renderSingle()
    }
  }

  // ─── MULTI-LANGUAGE RENDER ────────────────────────────────────────────────
  // The multi card is a separate DOM section (`data-drill-target="multiCard"`)
  // so it can coexist with the single-card DOM without clashing targets.

  renderMulti() {
    if (!this.hasMultiCardTarget) return
    const card = this.cards[this.index]
    const result = this.results[this.index]
    const ti = result.targetIndex
    const allDone = result.graded

    // Unhide multi card, hide single card if present.
    this.multiCardTarget.classList.remove("hidden")
    if (this.hasCardTarget) this.cardTarget.classList.add("hidden")

    // Progress bar + counter (counts concepts, not individual target answers).
    if (this.hasProgressTarget) this.progressTarget.textContent = `${this.index + 1} / ${this.cards.length}`
    if (this.hasBarTarget) this.barTarget.style.width = `${((this.index + 1) / this.cards.length) * 100}%`
    this.updateScore()

    // From-language label and source word (pin at top throughout the card).
    if (this.hasMultiFromTarget) this.multiFromTarget.textContent = card.from_lang_name || ""
    if (this.hasMultiPromptTarget) this.multiPromptTarget.textContent = card.prompt

    // Step counter: "2 of 3" etc. (counts only THIS card's targets, not all concepts).
    const total = card.targets.length
    const stepNum = allDone ? total : Math.min(ti + 1, total)
    if (this.hasMultiStepTarget) this.multiStepTarget.textContent = `${stepNum} of ${total}`

    // Completed band: answered targets, settled and quiet above the live input.
    if (this.hasMultiDoneTarget) {
      const doneBands = result.targets
        .slice(0, allDone ? result.targets.length : ti)
        .map((tRes, i) => {
          const t = card.targets[i]
          if (!tRes.graded) return ""
          const esc = (s) => (s || "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
          if (tRes.correct) {
            return `<div class="flex items-baseline justify-between py-1">
              <span class="text-[11px] uppercase tracking-wide text-gray-400 dark:text-gray-500">${esc(t.lang_name)}</span>
              <span class="flex items-baseline gap-1.5 text-sm">
                <span class="text-emerald-600 dark:text-emerald-400">✓</span>
                <span>${esc(tRes.given)}</span>
              </span>
            </div>`
          } else {
            const full = t.answer_article ? `${t.answer_article} ${t.answer}` : t.answer
            return `<div class="flex items-baseline justify-between py-1">
              <span class="text-[11px] uppercase tracking-wide text-gray-400 dark:text-gray-500">${esc(t.lang_name)}</span>
              <span class="flex items-baseline gap-1.5 text-sm">
                <span class="text-rose-500 dark:text-rose-400">✗</span>
                <span class="text-gray-400 line-through dark:text-gray-500">${esc(tRes.given)}</span>
                <span class="font-medium">${esc(full)}</span>
              </span>
            </div>`
          }
        })
        .join("")
      this.multiDoneTarget.innerHTML = doneBands
      this.multiDoneTarget.classList.toggle("hidden", doneBands.trim() === "")
    }

    // Live input section (hidden when all targets are done).
    const currentTarget = !allDone && card.targets[ti]
    if (this.hasMultiLangLabelTarget) {
      this.multiLangLabelTarget.textContent = currentTarget ? currentTarget.lang_name : ""
    }
    if (this.hasMultiInputTarget) {
      const inputSection = this.multiInputTarget.closest("[data-multi-input-section]")
      if (inputSection) inputSection.classList.toggle("hidden", !currentTarget)
      if (currentTarget) {
        this.multiInputTarget.value = ""
        this.multiInputTarget.disabled = false
        this.multiInputTarget.placeholder = `${(currentTarget.lang_name || "").toLowerCase()}…`
        this.multiInputTarget.focus()
      }
    }

    // Upcoming: faint marker showing remaining languages after the live one.
    if (this.hasMultiUpcomingTarget) {
      const upcomingNames = allDone ? [] : card.targets.slice(ti + 1).map((t) => t.lang_name)
      this.multiUpcomingTarget.textContent = upcomingNames.length ? `then ${upcomingNames.join(" · ")}` : ""
    }

    // Detail panel (all translations) — shown after all targets done.
    if (this.hasDetailTarget) {
      if (allDone) {
        this.renderDetail(card)
      } else {
        this.detailTarget.innerHTML = ""
        this.detailTarget.classList.add("hidden")
      }
    }

    // Buttons: Check while answering, Next concept when done.
    if (this.hasMultiCheckTarget) this.multiCheckTarget.classList.toggle("hidden", allDone || !currentTarget)
    if (this.hasMultiNextTarget)  this.multiNextTarget.classList.toggle("hidden", !allDone)
    if (this.hasBackBtnTarget) this.backBtnTarget.classList.toggle("hidden", this.index === 0)
  }

  // ─── SINGLE-LANGUAGE RENDER (unchanged from original) ─────────────────────

  renderSingle() {
    const card = this.cards[this.index]
    const result = this.results[this.index]
    const isSentence = card.kind === "sentence"

    // Show single card, hide multi card if present.
    if (this.hasMultiCardTarget) this.multiCardTarget.classList.add("hidden")
    if (this.hasCardTarget) this.cardTarget.classList.remove("hidden")

    this.promptTarget.textContent = card.prompt
    this.promptTarget.className = isSentence
      ? "mt-2 text-2xl font-medium leading-snug"
      : "mt-2 text-4xl font-semibold tracking-tight sm:text-5xl"
    if (this.hasKindTagTarget) this.kindTagTarget.textContent = isSentence ? " · sentence" : ""

    // PHONETICS: render IPA (+ translit toggle) under the prompt and, after grading, the answer.
    this.renderPhonetics("prompt", card.prompt_ipa, card.prompt_translit, card.prompt_non_latin)
    if (result.graded) {
      this.renderPhonetics("answer", card.answer_ipa, card.answer_translit, card.answer_non_latin)
    } else {
      this.clearPhonetics("answer")
    }

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
    const translationsHtml = (card.translations || []).map((t) => {
      const surfaced = t.lang === this.fromValue || t.lang === this.toValue
      return `<div class="flex items-center justify-between py-1.5">
        <div class="flex items-baseline gap-3">
          <span class="w-6 text-[11px] uppercase text-gray-400">${esc(t.lang)}</span>
          <span class="text-sm ${surfaced ? "font-medium" : "text-gray-500 dark:text-gray-400"}">${esc(t.text)}</span>
        </div>
        <button type="button" data-controller="speak" data-speak-text-value="${esc(t.text)}" data-speak-lang-value="${esc(t.lang)}" data-action="speak#say" class="rounded-md px-2 py-1 text-sm text-gray-400 hover:bg-gray-100 hover:text-gray-700 dark:hover:bg-gray-800 dark:hover:text-gray-200" aria-label="pronounce">🔊</button>
      </div>`
    }).join("")

    // [ETYMOLOGY] Quiet annotation below the translation list — only when present.
    const { etymology, mnemonic } = card
    let etymologyHtml = ""
    if (etymology || mnemonic) {
      etymologyHtml = `<div class="mt-2 border-t border-gray-100 pt-2 dark:border-gray-800">`
      if (etymology) etymologyHtml += `<p class="text-xs text-gray-400 dark:text-gray-500"><span class="font-medium text-gray-500 dark:text-gray-400">from:</span> ${esc(etymology)}</p>`
      if (mnemonic)  etymologyHtml += `<p class="${etymology ? "mt-0.5" : ""} text-xs text-gray-400 dark:text-gray-500">💡 ${esc(mnemonic)}</p>`
      etymologyHtml += `</div>`
    }

    this.detailTarget.innerHTML = translationsHtml + etymologyHtml
    this.detailTarget.classList.remove("hidden")
  }

  // --- phonetics helpers ---

  // Render IPA + optional translit into the slot's phonetics target container.
  // Slot must be "prompt" or "answer"; each maps to a data-drill-target in the view.
  renderPhonetics(slot, ipa, translit, nonLatin) {
    const container = slot === "prompt"
      ? (this.hasPromptPhoneticsTarget ? this.promptPhoneticsTarget : null)
      : (this.hasAnswerPhoneticsTarget ? this.answerPhoneticsTarget : null)
    if (!container) return
    if (!ipa) { container.innerHTML = ""; return }

    const showTranslit = nonLatin && translit && localStorage.getItem("phonetics-translit") === "1"

    container.innerHTML = `
      <p class="mt-2 text-sm text-gray-400 dark:text-gray-500 tabular-nums">${this._esc(ipa)}</p>
      ${nonLatin && translit ? `
        <p class="${showTranslit ? "" : "hidden"} text-sm text-gray-400 dark:text-gray-500" data-phonetics-translit-line="${slot}">${this._esc(translit)}</p>
        <div class="mt-0.5 flex items-center justify-center gap-2">
          <button type="button"
                  class="text-[10px] text-gray-300 hover:text-gray-500 dark:text-gray-600 dark:hover:text-gray-400"
                  data-action="click->drill#toggleTranslit"
                  data-phonetics-translit-slot="${slot}"
                  aria-label="Toggle spelling guide">${showTranslit ? "ipa" : "abc"}</button>
        </div>` : ""}
    `.trim()
  }

  clearPhonetics(slot) {
    const container = slot === "prompt"
      ? (this.hasPromptPhoneticsTarget ? this.promptPhoneticsTarget : null)
      : (this.hasAnswerPhoneticsTarget ? this.answerPhoneticsTarget : null)
    if (container) container.innerHTML = ""
  }

  toggleTranslit(event) {
    const btn = event.currentTarget
    const slot = btn.dataset.phoneticsTranslitSlot
    const line = btn.closest("[data-phonetics-slot]")?.querySelector(`[data-phonetics-translit-line="${slot}"]`)
    if (!line) return

    const showing = !line.classList.contains("hidden")
    if (showing) {
      line.classList.add("hidden")
      btn.textContent = "abc"
      localStorage.setItem("phonetics-translit", "0")
    } else {
      line.classList.remove("hidden")
      btn.textContent = "ipa"
      localStorage.setItem("phonetics-translit", "1")
    }
  }

  _esc(s) {
    return (s || "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
  }

  finish() {
    // Count a multi-card as correct only if ALL its targets were correct.
    const correct = this.results.filter((r, i) => {
      if (this.cards[i].kind === "multi") return r.targets && r.targets.every((t) => t.correct)
      return r.correct
    }).length
    const pct = Math.round((correct / this.cards.length) * 100)
    const missed = this.cards
      .filter((_, i) => this.results[i].graded && (
        this.cards[i].kind === "multi"
          ? !this.results[i].targets.every((t) => t.correct)
          : !this.results[i].correct
      ))
      .map((c) => c.prompt)

    const owned = this.ownedThisRun ? `🎉 ${this.ownedThisRun} newly owned. ` : ""
    this.summaryTextTarget.textContent = `${correct} / ${this.cards.length} correct (${pct}%)`
    this.missedTarget.textContent = owned + (missed.length ? `Missed: ${missed.join(", ")}` : "Clean run — nothing missed.")
    if (this.hasCardTarget) this.cardTarget.classList.add("hidden")
    if (this.hasMultiCardTarget) this.multiCardTarget.classList.add("hidden")
    this.summaryTarget.classList.remove("hidden")
  }

  restart() {
    window.removeEventListener("keydown", this.onKey)
    this.connect()
    if (this.hasCardTarget) this.cardTarget.classList.remove("hidden")
    if (this.hasMultiCardTarget) this.multiCardTarget.classList.add("hidden")
    this.summaryTarget.classList.add("hidden")
  }

  updateScore() {
    const correct = this.results.filter((r, i) => {
      if (this.cards[i].kind === "multi") return r.targets && r.targets.every((t) => t.graded && t.correct)
      return r.correct
    }).length
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

  // A short celebration when a word crosses into the owned collection (legacy path).
  celebrate(card) {
    this.ownedThisRun++
    if (!this.hasCelebrateTarget) return
    this.celebrateTextTarget.textContent = `🎉 Owned! "${card.prompt}" is in your collection`
    const el = this.celebrateTarget
    const bubble = el.firstElementChild
    el.classList.remove("hidden"); el.classList.add("flex")
    bubble.classList.remove("animate-celebrate")
    void bubble.offsetWidth // restart the animation
    bubble.classList.add("animate-celebrate")
    clearTimeout(this._celebrateTimer)
    this._celebrateTimer = setTimeout(() => { el.classList.add("hidden"); el.classList.remove("flex") }, 2000)
  }

  // FSRS retire celebration — quieter and grander than the “owned” pill.
  // Centered card overlay, backdrop blur, emerald border; no confetti.
  // Auto-dismisses after 2.8 s; drill flows on to the next card. (#axis-4)
  celebrateRetire(card) {
    this.ownedThisRun++
    if (!this.hasRetireOverlayTarget) return
    const word = card.answer_article ? `${card.answer_article} ${card.answer}` : card.answer
    if (this.hasRetireWordTarget) this.retireWordTarget.textContent = `”${word}”`
    const el = this.retireOverlayTarget
    el.classList.remove("hidden"); el.classList.add("flex")
    clearTimeout(this._retireTimer)
    this._retireTimer = setTimeout(() => {
      el.classList.add("hidden"); el.classList.remove("flex")
    }, 2800)
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
  speakAnswer() {
    const card = this.cards[this.index]
    if (card.kind === "multi") return  // multi: each target has its own lang; skip auto-speak
    this.speak(card.answer, this.toValue)
  }

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

  // Records one attempt. fromLang/toLang are passed explicitly so multi-target
  // cards can record each target language independently.
  record(termId, correct, given, fromLang, toLang) {
    if (!this.hasRecordUrlValue || !this.recordUrlValue) return Promise.resolve(null)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(this.recordUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ term_id: termId, from: fromLang || this.fromValue, to: toLang || this.toValue, correct, given }),
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
