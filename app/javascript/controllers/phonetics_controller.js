import { Controller } from "@hotwired/stimulus"

// Glossika-style notation switcher for the mock. Swaps which phonetic
// transcription (IPA / romanized / native) is visible, and restyles the
// segmented toggle. Pure presentation — touches no drill state.
//
// Targets:
//   toggle  — each segmented button (carries data-notation)
//   line    — each phonetic line (carries data-notation); the matching one shows
export default class extends Controller {
  static targets = ["toggle", "line"]

  switch(event) {
    const notation = event.currentTarget.dataset.notation
    this.show(notation)
  }

  show(notation) {
    this.lineTargets.forEach((el) => {
      el.classList.toggle("hidden", el.dataset.notation !== notation)
    })
    this.toggleTargets.forEach((btn) => {
      const on = btn.dataset.notation === notation
      btn.setAttribute("aria-pressed", on)
      btn.classList.toggle("bg-white", on)
      btn.classList.toggle("shadow-sm", on)
      btn.classList.toggle("text-gray-900", on)
      btn.classList.toggle("dark:bg-gray-700", on)
      btn.classList.toggle("dark:text-gray-100", on)
      btn.classList.toggle("text-gray-500", !on)
      btn.classList.toggle("dark:text-gray-400", !on)
    })
  }
}
