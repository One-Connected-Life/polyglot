import { Controller } from "@hotwired/stimulus"

// Drives the multi-select language chip UI on the onboarding/settings form.
// When a checkbox changes, the paired visible chip span reflects the selection
// by swapping its CSS classes between selected (filled) and unselected (outline).
export default class extends Controller {
  static targets = ["checkbox", "chip"]

  connect() {
    // Sync visual state on page load (in case Rails re-renders with errors).
    this.checkboxTargets.forEach((checkbox, i) => this.applyState(checkbox, this.chipTargets[i]))
  }

  toggle(event) {
    const checkbox = event.target
    const chip = checkbox.closest("label").querySelector("[data-language-chips-target='chip']")
    this.applyState(checkbox, chip)
  }

  applyState(checkbox, chip) {
    if (!chip) return
    if (checkbox.checked) {
      chip.classList.add("border-gray-900", "bg-gray-900", "text-white", "dark:border-gray-100", "dark:bg-gray-100", "dark:text-gray-900")
      chip.classList.remove("border-gray-300", "text-gray-500", "dark:border-gray-700", "dark:text-gray-400")
    } else {
      chip.classList.remove("border-gray-900", "bg-gray-900", "text-white", "dark:border-gray-100", "dark:bg-gray-100", "dark:text-gray-900")
      chip.classList.add("border-gray-300", "text-gray-500", "dark:border-gray-700", "dark:text-gray-400")
    }
  }
}
