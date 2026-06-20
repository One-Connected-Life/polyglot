import { Controller } from "@hotwired/stimulus"

// Mock-only: lets Mihai replay the retire-and-celebrate moment on demand so the
// timing/feel can be judged without running a whole drill. Reuses the existing
// `animate-celebrate` keyframe (same visual language as the "owned" pop).
export default class extends Controller {
  static targets = ["overlay", "bubble"]

  // Show the overlay, restart the pop animation, auto-dismiss after a beat.
  play() {
    const el = this.overlayTarget
    el.classList.remove("hidden")
    el.classList.add("flex")

    const bubble = this.bubbleTarget
    bubble.classList.remove("animate-celebrate")
    void bubble.offsetWidth // force reflow so the animation restarts
    bubble.classList.add("animate-celebrate")

    clearTimeout(this._timer)
    this._timer = setTimeout(() => {
      el.classList.add("hidden")
      el.classList.remove("flex")
    }, 2600)
  }
}
