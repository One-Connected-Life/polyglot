import { Controller } from "@hotwired/stimulus"

// Live mic capture for the Translate tab (#16). Adapted from OCL's reflection-audio
// recorder: records via MediaRecorder, but instead of POSTing JSON it drops the clip
// into the form's hidden file field and submits — so the recording rides the SAME
// synchronous translate→transcribe→results path as an uploaded file. The clip is then
// transcribed + kept 2 days server-side (Recording).
export default class extends Controller {
  static targets = ["fileInput", "icon", "label", "timer", "status", "player", "play"]

  connect() {
    this.recording = false
    this.chunks = []
    this.objectUrl = null
    if (this.hasPlayerTarget) this.playerTarget.addEventListener("ended", () => this._setPlay("▶ Play"))
  }

  disconnect() {
    this._stopTracks()
    this._stopTimer()
    this._revoke()
  }

  toggle() {
    this.recording ? this.stop() : this.start()
  }

  async start() {
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      this._setStatus("Recording isn't supported in this browser")
      return
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (e) {
      this._setStatus("Mic permission denied")
      return
    }
    this.chunks = []
    this.recorder = new MediaRecorder(this.stream)
    this.recorder.ondataavailable = (e) => { if (e.data.size > 0) this.chunks.push(e.data) }
    this.recorder.onstop = () => this._handleStop()
    this.recorder.start()
    this.recording = true

    this._revoke()
    if (this.hasPlayerTarget) this.playerTarget.pause()
    this._setPlay("▶ Play")
    this._setButton("stop")
    this._setStatus("")
    this._startTimer()
  }

  stop() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
    this._stopTracks()
    this.recording = false
    this._stopTimer()
  }

  playToggle() {
    if (!this.hasPlayerTarget || !this.playerTarget.src) return
    if (this.playerTarget.paused) {
      this.playerTarget.play()
      this._setPlay("⏸ Pause")
    } else {
      this.playerTarget.pause()
      this._setPlay("▶ Play")
    }
  }

  _handleStop() {
    const type = (this.recorder && this.recorder.mimeType) || "audio/webm"
    const blob = new Blob(this.chunks, { type })

    this.objectUrl = URL.createObjectURL(blob)
    if (this.hasPlayerTarget) {
      this.playerTarget.src = this.objectUrl
      this.playTarget?.classList.remove("hidden")
    }
    this._setPlay("▶ Play")

    // Inject the clip into the hidden <input type=file name=audio> and submit the
    // form. assignment via DataTransfer is the only cross-browser way to set .files.
    const file = new File([blob], `recording.${this._ext(type)}`, { type })
    const dt = new DataTransfer()
    dt.items.add(file)
    this.fileInputTarget.files = dt.files

    this._setButton("rerecord")
    this._setStatus("Translating…")
    this.element.requestSubmit ? this.element.requestSubmit() : this.element.submit()
  }

  _ext(type) {
    if (type.includes("mp4") || type.includes("m4a")) return "mp4"
    if (type.includes("ogg")) return "ogg"
    if (type.includes("wav")) return "wav"
    return "webm"
  }

  _startTimer() {
    this.seconds = 0
    if (this.hasTimerTarget) {
      this.timerTarget.classList.remove("hidden")
      this.timerTarget.textContent = "0:00"
    }
    this.timerId = setInterval(() => {
      this.seconds += 1
      if (this.hasTimerTarget) {
        const m = Math.floor(this.seconds / 60)
        const s = String(this.seconds % 60).padStart(2, "0")
        this.timerTarget.textContent = `${m}:${s}`
      }
    }, 1000)
  }

  _stopTimer() {
    if (this.timerId) { clearInterval(this.timerId); this.timerId = null }
    if (this.hasTimerTarget) this.timerTarget.classList.add("hidden")
  }

  _stopTracks() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  _revoke() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  }

  _setButton(mode) {
    const faces = { record: ["🎤", "Record"], stop: ["⏹", "Stop"], rerecord: ["🔄", "Re-record"] }
    const [icon, label] = faces[mode] || faces.record
    if (this.hasIconTarget) this.iconTarget.textContent = icon
    if (this.hasLabelTarget) this.labelTarget.textContent = label
  }

  _setPlay(text) {
    if (this.hasPlayTarget) this.playTarget.textContent = text
  }

  _setStatus(msg) {
    if (this.hasStatusTarget) this.statusTarget.textContent = msg
  }
}
