import { Controller } from "@hotwired/stimulus"

// Copies the value/text of a target element to the clipboard.
// Usage: data-controller="clipboard" with a data-clipboard-target="source"
// element and a button with data-action="clipboard#copy".
export default class extends Controller {
  static targets = ["source"]
  static values = { successMessage: { type: String, default: "Copied!" } }

  copy(event) {
    event.preventDefault()
    const el = this.sourceTarget
    const text = el.value !== undefined && el.value !== "" ? el.value : el.textContent.trim()

    const done = () => {
      const btn = event.currentTarget
      const original = btn.dataset.originalLabel || btn.textContent
      btn.dataset.originalLabel = original
      btn.textContent = this.successMessageValue
      setTimeout(() => { btn.textContent = original }, 1500)
    }

    if (navigator.clipboard) {
      navigator.clipboard.writeText(text).then(done).catch(() => this.fallbackCopy(el, done))
    } else {
      this.fallbackCopy(el, done)
    }
  }

  fallbackCopy(el, done) {
    if (el.select) { el.select() }
    try { document.execCommand("copy"); done() } catch (_) { /* no-op */ }
  }
}
