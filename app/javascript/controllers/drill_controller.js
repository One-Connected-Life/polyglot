import { Controller } from "@hotwired/stimulus"
import { speak as pronounce, stop as stopSpeech } from "speech"

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
    "progress", "score", "bar", "card", "summary", "summaryText", "missed", "voiceHint",
    // FLOW MODE: hands-free auto-play controls (single-card path only).
    "flowControls", "flowToggle", "keyHint",
    // Multi-language targets (only present when @multi == true in the view):
    "multiCard", "multiFrom", "multiPrompt", "multiStep",
    "multiDone", "multiLangLabel", "multiInput", "multiUpcoming",
    "multiCheck", "multiNext", "celebrateText", "celebrate",
    // PHONETICS: containers for IPA + translit under the prompt and answer words
    "promptPhonetics", "answerPhonetics",
    // EASE: mid-drill ease-nudge pips (FSRS only; guarded with hasEaseNudgeTarget)
    "easeNudge",
    // ETYMOLOGY: prominent "from:" + 💡 block shown under the answer on reveal
    "etymology",
    // FSRS retire targets — the bigger "Retired" overlay (#axis-4).
    // Only present when FSRS_ENABLED=1; guarded with hasRetireOverlayTarget.
    "retireOverlay", "retireBubble", "retireWord",
  ]
  static values = {
    cards: Array, sentences: Array, from: String, to: String,
    recordUrl: String, easeUrlTemplate: String, multi: Boolean, fsrsEnabled: Boolean,
    // Autoplay prefs come from the server (saved per-user in Settings); no longer
    // a localStorage source of truth. (Finding A)
    autoplayPrompt: Boolean, autoplayWrong: Boolean,
    // What to play on a correct answer: "word" (an enthusiastic "Yes!"),
    // "sound" (a quick synth chime), "answer" (speak the English word), "none".
    correctFeedback: String,
    // FLOW MODE: hands-free listen. flowMode on → speak prompt, wait
    // flowGapPrompt sec, reveal+speak answer, wait flowGapNext sec, next card,
    // looping. No typing. Gaps are user-tunable in Settings.
    flowMode: Boolean, flowGapPrompt: Number, flowGapNext: Number,
  }

  connect() {
    this.cards = this.buildSequence(this.cardsValue, this.hasSentencesValue ? this.sentencesValue : [])
    this.results = this.cards.map((card) => this.initResult(card))
    this.index = 0
    this.autoOn = this.autoplayPromptValue
    this.autoWrongOn = this.autoplayWrongValue
    this.ownedThisRun = 0
    this.onKey = this.onKey.bind(this)
    window.addEventListener("keydown", this.onKey)

    // Finding B: stop any in-flight/queued speech the moment the drill loses the
    // foreground, so autoplay can't keep firing across cards after you leave.
    // - disconnect()  : Stimulus teardown (Turbo navigation, controller removed)
    // - visibilitychange : tab hidden / app backgrounded
    // - turbo:before-cache : Turbo snapshots the page before caching/restoring
    // - pagehide       : bfcache / hard navigation away
    this.onHide = () => { if (document.hidden) { this.stopSpeech(); if (this.flowActive && !this.flowPaused) this.pauseFlow() } }
    this.onCachePurge = () => this.stopSpeech()
    document.addEventListener("visibilitychange", this.onHide)
    document.addEventListener("turbo:before-cache", this.onCachePurge)
    window.addEventListener("pagehide", this.onCachePurge)

    this.bindSwipe()

    // FLOW MODE: hands-free auto-play. Takes over the single-card DOM and runs
    // the speak→gap→speak→gap→next loop instead of the interactive grade flow.
    this.flowActive = this.hasFlowModeValue && this.flowModeValue && this.cards.length > 0
    if (this.flowActive) {
      this.startFlow()
      return
    }

    this.render()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
    document.removeEventListener("visibilitychange", this.onHide)
    document.removeEventListener("turbo:before-cache", this.onCachePurge)
    window.removeEventListener("pagehide", this.onCachePurge)
    this.stopSpeech()
    if (this.flowActive) { this.flowToken = (this.flowToken || 0) + 1; clearTimeout(this._flowTimer) }
    this.unbindSwipe()
  }

  // Cancel any speech currently playing or queued.
  stopSpeech() { stopSpeech() }

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
    if (this.flowActive) return  // flow drives itself; swipe/keys don't grade
    if (this.results[this.index].graded) this.next()
    else this.grade()
  }

  // Shuffle words, then sprinkle sentences in after a word (~1 in 3); rest at end.
  // Under FSRS the server already orders words most-overdue/new first — preserve
  // that order (don't shuffle) so the coaching survives the trip to the browser.
  buildSequence(words, sentences) {
    const w = this.fsrsEnabledValue ? [...words] : this.shuffle([...words])
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
    // FLOW MODE: Space toggles pause/resume; nothing else interacts.
    if (this.flowActive) {
      if (event.key === " ") { event.preventDefault(); this.toggleFlow() }
      return
    }

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
    if (this.flowActive) return  // flow mode never grades — it's a listen, not a quiz
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
      this.cheer(card)  // audio reward on correct (Settings: "On a correct answer")
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
      // Drop the soft keyboard so "Next concept" + the reveal aren't hidden
      // under it (the single-card path already blurs on grade). (#1 mobile UX)
      if (this.hasMultiInputTarget) this.multiInputTarget.blur()
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

    // Detail panel (all translations) + etymology — shown after all targets done.
    if (allDone) {
      this.renderDetail(card)
      this.renderEtymology(card)
    } else {
      if (this.hasDetailTarget) { this.detailTarget.innerHTML = ""; this.detailTarget.classList.add("hidden") }
      if (this.hasEtymologyTarget) { this.etymologyTarget.innerHTML = ""; this.etymologyTarget.classList.add("hidden") }
    }

    // Buttons: Check while answering, Next concept when done.
    if (this.hasMultiCheckTarget) this.multiCheckTarget.classList.toggle("hidden", allDone || !currentTarget)
    if (this.hasMultiNextTarget)  this.multiNextTarget.classList.toggle("hidden", !allDone)
    if (allDone) this.scrollActionIntoView(this.hasMultiNextTarget ? this.multiNextTarget : null)
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
      this.renderEtymology(card)
      this.renderEaseNudge(card)
      if (this.hasNextBtnTarget) this.nextBtnTarget.classList.remove("hidden")
      if (this.hasCheckBtnTarget) this.checkBtnTarget.classList.add("hidden")

      if (!result.correct && this.normalize(result.given) !== "") {
        this.givenTarget.textContent = `you typed: ${result.given}`
        this.givenTarget.classList.remove("hidden")
      } else {
        this.givenTarget.classList.add("hidden")
      }
      this.scrollActionIntoView(this.hasNextBtnTarget ? this.nextBtnTarget : null)
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
      if (this.hasEtymologyTarget) { this.etymologyTarget.innerHTML = ""; this.etymologyTarget.classList.add("hidden") }
      if (this.hasEaseNudgeTarget) { this.easeNudgeTarget.innerHTML = ""; this.easeNudgeTarget.classList.add("hidden") }
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

    this.detailTarget.innerHTML = translationsHtml
    this.detailTarget.classList.remove("hidden")
  }

  // Bring an action button into view above where the iOS keyboard sat — after a
  // reveal the answer + Next render low on the card and can otherwise be hidden
  // behind the dismissing keyboard. (#1 mobile UX)
  scrollActionIntoView(el) {
    if (!el) return
    requestAnimationFrame(() => el.scrollIntoView({ block: "center", behavior: "smooth" }))
  }

  // [ETYMOLOGY] Prominent insight block shown right under the answer on reveal.
  // Pulled out of the quiet translations list (where it sat at the very bottom,
  // next to Russian) into its own bigger, set-apart card. Hidden when absent.
  renderEtymology(card) {
    if (!this.hasEtymologyTarget) return
    const { etymology, mnemonic } = card
    if (!etymology && !mnemonic) {
      this.etymologyTarget.innerHTML = ""
      this.etymologyTarget.classList.add("hidden")
      return
    }
    let html = `<div class="rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 text-left dark:border-gray-800 dark:bg-gray-900/40">`
    if (etymology) html += `<p class="text-sm text-gray-700 dark:text-gray-200"><span class="font-semibold text-gray-500 dark:text-gray-400">from</span> ${this._esc(etymology)}</p>`
    if (mnemonic)  html += `<p class="${etymology ? "mt-1 " : ""}text-sm text-gray-600 dark:text-gray-300">💡 ${this._esc(mnemonic)}</p>`
    html += `</div>`
    this.etymologyTarget.innerHTML = html
    this.etymologyTarget.classList.remove("hidden")
  }

  // [EASE] Mid-drill ease nudge — five quiet pips (1 = easy … 5 = hard).
  // FSRS-only: inert when the flag is off (the legacy path has no scheduling
  // rows and card.ease is null). The current ease is AI-prefilled; tapping a
  // pip persists the learner's adjustment for future scheduling.
  renderEaseNudge(card) {
    if (!this.hasEaseNudgeTarget) return
    if (!this.fsrsEnabledValue || !card.ease) {
      this.easeNudgeTarget.innerHTML = ""
      this.easeNudgeTarget.classList.add("hidden")
      return
    }
    const current = card.ease
    const pips = [1, 2, 3, 4, 5].map((n) => {
      const on = n === current
      const cls = on
        ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-900"
        : "text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800"
      return `<button type="button" data-action="click->drill#nudgeEase" data-ease="${n}"
        class="h-11 w-11 rounded-md text-sm tabular-nums ${cls}" aria-label="ease ${n}">${n}</button>`
    }).join("")
    this.easeNudgeTarget.innerHTML = `
      <div class="flex items-center justify-center gap-1.5">
        <span class="mr-1 text-[10px] uppercase tracking-wide text-gray-400">easy</span>
        ${pips}
        <span class="ml-1 text-[10px] uppercase tracking-wide text-gray-400">hard</span>
      </div>`
    this.easeNudgeTarget.classList.remove("hidden")
  }

  // Persist an ease nudge and reflect it immediately in the pips.
  nudgeEase(event) {
    const ease = parseInt(event.currentTarget.dataset.ease, 10)
    if (!ease) return
    const card = this.cards[this.index]
    card.ease = ease                 // local echo so the pip highlight updates
    this.renderEaseNudge(card)
    if (!this.hasEaseUrlTemplateValue || !this.easeUrlTemplateValue) return
    const url = this.easeUrlTemplateValue.replace("__ID__", card.id)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ ease, from: this.fromValue, to: this.toValue }),
      keepalive: true,
    }).catch(() => {})
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
    // Brand the score: coral when on a clean streak (all-correct so far), indigo otherwise.
    // A small warm "you've got it" beat without repainting the calm card. (BRANDING accent)
    const onStreak = graded > 0 && correct === graded
    this.scoreTarget.className = graded
      ? (onStreak
          ? "font-semibold text-brand-coral"
          : "font-medium text-brand-indigo dark:text-brand-sky")
      : ""
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
  // Autoplay prefs (this.autoOn / this.autoWrongOn) are set from server values in
  // connect(); they're toggled in Settings, not on the drill screen. (Finding A)

  speakPrompt() { this.speak(this.cards[this.index].prompt, this.fromValue) }
  speakAnswer() {
    const card = this.cards[this.index]
    if (card.kind === "multi") return  // multi: each target has its own lang; skip auto-speak
    this.speak(card.answer, this.toValue)
  }

  speak(text, code) {
    pronounce(text, code, { onResult: ({ hasVoice, lang }) => this.flagMissingVoice(hasVoice, lang) })
  }

  // ─── FLOW MODE ────────────────────────────────────────────────────────────
  // Hands-free listen: speak prompt → wait flowGapPrompt → reveal + speak answer
  // → wait flowGapNext → next card, looping. No typing. Single-card path only
  // (the controller forces @multi off when flow is on). A token cancels any
  // in-flight sequence when the user pauses / leaves so audio never runs away.

  startFlow() {
    this.flowPaused = false
    this.flowToken = 0
    // Hide the interactive bits; show the flow controls.
    if (this.hasInputTarget) { this.inputTarget.disabled = true; this.inputTarget.classList.add("hidden") }
    if (this.hasCheckBtnTarget) this.checkBtnTarget.classList.add("hidden")
    if (this.hasNextBtnTarget) this.nextBtnTarget.classList.add("hidden")
    if (this.hasBackBtnTarget) this.backBtnTarget.classList.add("hidden")
    if (this.hasKeyHintTarget) this.keyHintTarget.classList.add("hidden")
    if (this.hasCardTarget) this.cardTarget.classList.remove("hidden")
    this.showFlowControls(true)
    this.updateFlowToggle()
    this.runFlow()
  }

  showFlowControls(on) {
    if (!this.hasFlowControlsTarget) return
    this.flowControlsTarget.classList.toggle("hidden", !on)
    this.flowControlsTarget.classList.toggle("flex", on)
  }

  updateFlowToggle() {
    if (this.hasFlowToggleTarget) this.flowToggleTarget.textContent = this.flowPaused ? "Resume" : "Pause"
  }

  toggleFlow() {
    if (this.flowPaused) this.resumeFlow()
    else this.pauseFlow()
  }

  pauseFlow() {
    this.flowPaused = true
    this.flowToken++              // invalidate the running sequence
    clearTimeout(this._flowTimer)
    this.stopSpeech()
    this.updateFlowToggle()
  }

  resumeFlow() {
    if (!this.flowActive) return
    this.flowPaused = false
    this.updateFlowToggle()
    this.runFlow()
  }

  // The driver loop. Each pass plays the current card, then advances (wrapping
  // at the end — flow is continuous until paused).
  async runFlow() {
    const token = ++this.flowToken
    while (!this.flowPaused && token === this.flowToken) {
      await this.flowPlayCard(token)
      if (this.flowPaused || token !== this.flowToken) break
      this.index = (this.index + 1) % this.cards.length
    }
  }

  flowCancelled(token) {
    return this.flowPaused || token !== this.flowToken
  }

  async flowPlayCard(token) {
    const card = this.cards[this.index]
    if (!card || card.kind === "multi") return  // defensive — flow is single-card

    this.flowShowPrompt(card)
    await this.flowSpeak(card.prompt, this.fromValue)
    if (this.flowCancelled(token)) return

    await this.flowWait(this.flowGapPromptValue)
    if (this.flowCancelled(token)) return

    this.flowRevealAnswer(card)
    await this.flowSpeak(card.answer, this.toValue)
    if (this.flowCancelled(token)) return

    await this.flowWait(this.flowGapNextValue)
  }

  // Speak and resolve when the utterance ends — OR after a length-based safety
  // timeout, since WebKit (iOS WKWebView) doesn't always fire `onend`.
  flowSpeak(text, code) {
    return new Promise((resolve) => {
      let done = false
      const finish = () => { if (done) return; done = true; resolve() }
      const ms = Math.min(9000, 1200 + (text ? text.length : 0) * 90)
      const timer = setTimeout(finish, ms)
      pronounce(text, code, {
        flush: false,  // flow awaits each utterance + a gap, so never overlaps;
                       // skipping cancel() avoids the WebKit start-of-word clip.
        onResult: ({ hasVoice, lang }) => this.flagMissingVoice(hasVoice, lang),
        onEnd: () => { clearTimeout(timer); finish() },
      })
    })
  }

  flowWait(seconds) {
    return new Promise((resolve) => {
      this._flowTimer = setTimeout(resolve, Math.max(0, Number(seconds) || 0) * 1000)
    })
  }

  // Prompt-only view: the word, its IPA, answer area cleared. Reuses the
  // single-card DOM elements.
  flowShowPrompt(card) {
    const isSentence = card.kind === "sentence"
    this.promptTarget.textContent = card.prompt
    this.promptTarget.className = isSentence
      ? "mt-2 text-2xl font-medium leading-snug"
      : "mt-2 text-4xl font-semibold tracking-tight sm:text-5xl"
    if (this.hasKindTagTarget) this.kindTagTarget.textContent = isSentence ? " · sentence" : ""
    this.renderPhonetics("prompt", card.prompt_ipa, card.prompt_translit, card.prompt_non_latin)
    this.clearPhonetics("answer")
    if (this.hasAnswerTarget) { this.answerTarget.textContent = ""; this.answerTarget.classList.add("invisible") }
    if (this.hasFeedbackTarget) this.feedbackTarget.textContent = ""
    if (this.hasAnswerSpeakTarget) this.answerSpeakTarget.classList.add("hidden")
    if (this.hasGivenTarget) this.givenTarget.classList.add("hidden")
    if (this.hasDetailTarget) { this.detailTarget.innerHTML = ""; this.detailTarget.classList.add("hidden") }
    if (this.hasEtymologyTarget) { this.etymologyTarget.innerHTML = ""; this.etymologyTarget.classList.add("hidden") }
    if (this.hasProgressTarget) this.progressTarget.textContent = `${this.index + 1} / ${this.cards.length}`
    if (this.hasBarTarget) this.barTarget.style.width = `${((this.index + 1) / this.cards.length) * 100}%`
  }

  flowRevealAnswer(card) {
    const full = card.answer_article ? `${card.answer_article} ${card.answer}` : card.answer
    if (this.hasAnswerTarget) { this.answerTarget.textContent = full; this.answerTarget.classList.remove("invisible") }
    this.renderPhonetics("answer", card.answer_ipa, card.answer_translit, card.answer_non_latin)
  }

  // Audio reward on a correct answer, per the user's Settings choice. Fires from
  // grade(), which is always user-initiated (Enter / tap / Check) — so the
  // AudioContext can unlock even in the iOS WKWebView shell.
  cheer(card) {
    switch (this.correctFeedbackValue) {
      case "word":   // an enthusiastic "Yes!" — faster + higher than normal TTS
        pronounce("Yes!", "en", { rate: 1.1, pitch: 1.4 })
        break
      case "answer": // speak the English word (falls back to the answer language)
        if (card.english) pronounce(card.english, "en")
        else this.speak(card.answer, this.toValue)
        break
      case "sound":
        this.playChime()
        break
      // "none" (and anything unknown): stay silent
    }
  }

  // A short bright two-note chime via Web Audio — no asset to ship, works in the
  // browser and the WKWebView shell. Context is created lazily and reused.
  playChime() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext
      if (!Ctx) return
      this.audioCtx ||= new Ctx()
      const ctx = this.audioCtx
      if (ctx.state === "suspended") ctx.resume()
      const now = ctx.currentTime
      ;[784, 1175].forEach((freq, i) => {   // G5 → D6, a bright rising fifth
        const osc = ctx.createOscillator()
        const gain = ctx.createGain()
        osc.type = "sine"
        osc.frequency.value = freq
        const t = now + i * 0.09
        gain.gain.setValueAtTime(0.0001, t)
        gain.gain.exponentialRampToValueAtTime(0.25, t + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.18)
        osc.connect(gain).connect(ctx.destination)
        osc.start(t)
        osc.stop(t + 0.2)
      })
    } catch (_e) { /* audio unavailable — stay silent */ }
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
