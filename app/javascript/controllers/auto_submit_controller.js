import { Controller } from "@hotwired/stimulus"

// Submit the surrounding form as soon as the input changes — used so picking/snapping
// a photo translates immediately, no extra tap. (issue #10)
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
