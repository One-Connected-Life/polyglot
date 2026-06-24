import { Controller } from "@hotwired/stimulus"

// Click a column header to sort the rows by that column; click again to reverse.
// Header cells opt in with: data-action="click->sortable-table#sort", data-col="<index>",
// and data-sort-type="string|number". Each body cell may carry data-sort-value to sort
// by a value distinct from its displayed text (e.g. an epoch behind a "Jun 24" date).
export default class extends Controller {
  static targets = ["body"]

  sort(event) {
    const th = event.currentTarget
    const col = parseInt(th.dataset.col, 10)
    const type = th.dataset.sortType || "string"
    const dir = th.dataset.dir === "asc" ? "desc" : "asc"

    this.element.querySelectorAll("th[data-col]").forEach((h) => {
      delete h.dataset.dir
      const arrow = h.querySelector("[data-arrow]")
      if (arrow) arrow.textContent = ""
    })
    th.dataset.dir = dir
    const arrow = th.querySelector("[data-arrow]")
    if (arrow) arrow.textContent = dir === "asc" ? " ▲" : " ▼"

    const rows = Array.from(this.bodyTarget.rows)
    rows.sort((a, b) => {
      const av = this.value(a.cells[col], type)
      const bv = this.value(b.cells[col], type)
      if (av < bv) return dir === "asc" ? -1 : 1
      if (av > bv) return dir === "asc" ? 1 : -1
      return 0
    })
    rows.forEach((row) => this.bodyTarget.appendChild(row))
  }

  value(cell, type) {
    const raw = (cell?.dataset.sortValue ?? cell?.textContent ?? "").trim()
    if (type === "number") return parseFloat(raw) || 0
    return raw.toLowerCase()
  }
}
