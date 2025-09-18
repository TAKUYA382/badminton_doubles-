import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { roundId: Number, matchId: Number }

  connect() {
    this.dialog = document.getElementById("member-picker")
    this.query  = document.getElementById("picker-query")
    this.list   = document.getElementById("picker-list")
    this.current = null // {matchId, slot, roundId}
    this.query?.addEventListener("input", () => this.reloadCandidates())
  }

  // スロットクリック -> 候補表示
  openPicker(e) {
    const span    = e.currentTarget
    const slot    = span.dataset.slot
    const matchId = span.dataset.matchEditorMatchIdValue
    const roundId = span.dataset.matchEditorRoundIdValue
    this.current = { matchId, slot, roundId }
    this.query.value = ""
    this.reloadCandidates().then(() => this.dialog.showModal())
  }

  async reloadCandidates() {
    if (!this.current) return
    const q = encodeURIComponent(this.query.value || "")
    const res = await fetch(`/admin/events/${this.eventId()}/available_members?round_id=${this.current.roundId}&query=${q}`)
    const data = await res.json()
    this.list.innerHTML = ""
    data.forEach(m => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.textContent = `${m.name}（${m.grade}年・${m.gender}・${m.skill_level}）`
      btn.style.display = "block"
      btn.style.width = "100%"
      btn.style.textAlign = "left"
      btn.style.marginBottom = "4px"
      btn.addEventListener("click", () => this.replace(m.id))
      this.list.appendChild(btn)
    })
  }

  async replace(memberId) {
    const body = { slot: this.current.slot, member_id: memberId }
    const res = await fetch(`/admin/matches/${this.current.matchId}/replace_member`, {
      method: "PATCH",
      headers: this.headers(),
      body: JSON.stringify(body)
    })
    const json = await res.json()
    if (!res.ok) { alert(json.error || "置換に失敗しました"); return }
    this.dialog.close()
    // その場でテキストだけ更新（簡易）
    const selector = `.sortable-item[data-id="${this.current.matchId}"] .slot[data-slot="${this.current.slot}"]`
    const target = document.querySelector(selector)
    if (target) { target.textContent = this.list.querySelector("button").textContent.split("（")[0] }

    // NGなら赤ハイライト
    const li = document.querySelector(`.sortable-item[data-id="${this.current.matchId}"]`)
    if (li) {
      li.classList.toggle("ng-warning", !!json.has_ng)
    }
  }

  async clear(e) {
    const slot = e.currentTarget.dataset.slot
    const matchId = e.currentTarget.dataset.matchId
    const res = await fetch(`/admin/matches/${matchId}/clear_slot`, {
      method: "PATCH",
      headers: this.headers(),
      body: JSON.stringify({ slot })
    })
    if (!res.ok) { alert("クリアに失敗しました"); return }
    const span = document.querySelector(`.sortable-item[data-id="${matchId}"] .slot[data-slot="${slot}"]`)
    if (span) span.textContent = "(空)"
    const li = document.querySelector(`.sortable-item[data-id="${matchId}"]`)
    if (li) li.classList.remove("ng-warning")
  }

  headers() {
    return {
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      "Content-Type": "application/json"
    }
  }

  // URL から /admin/events/:id を拾う（show画面前提）
  eventId() {
    const m = location.pathname.match(/\/admin\/events\/(\d+)/)
    return m ? m[1] : null
  }
}
