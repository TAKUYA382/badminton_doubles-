// app/javascript/controllers/lineup_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    bulkEndpoint: String, // bulk_update_admin_matches_path
    eventId: Number
  }
  static targets = ["bulkCount"]

  connect () {
    this.buffer = []        // {match_id, slot_key, member_id}
    this.slotMap = new Map()
    this.updateCount()
  }

  // =========================================
  // ① セレクト変更で自動的にバッファに積む
  // =========================================
  bufferReplaceFromSelect (e) {
    const select = e.currentTarget
    const memberId = select.value
    if (!memberId) return

    const matchId = Number(select.dataset.matchId)
    const slotKey = select.dataset.slotKey

    this.pushBuffer(matchId, slotKey, Number(memberId))
    this.markSlotEdited(select.closest("[data-slot-el]"))
    this.markCardUnsaved(select.closest("[data-match-el]"))

    // 現在表示の名前を仮置きで更新
    const strong = select.closest("[data-slot-el]")?.querySelector("[data-current-name]")
    if (strong) strong.textContent = select.options[select.selectedIndex]?.text?.split("（")?.[0] || ""
  }

  // =========================================
  // ② ⏱差し替えをバッファ（手動ボタン版）
  // =========================================
  bufferReplace (e) {
    e.preventDefault()
    const btn = e.currentTarget
    const matchId = Number(btn.dataset.matchId)
    const slotKey = btn.dataset.slotKey
    const select = btn.closest("[data-slot-el]")?.querySelector('select[data-member-select]')
    if (!select || !select.value) return

    this.pushBuffer(matchId, slotKey, Number(select.value))
    this.markSlotEdited(btn.closest("[data-slot-el]"))
    this.markCardUnsaved(btn.closest("[data-match-el]"))
  }

  // =========================================
  // ③ まとめて保存
  // =========================================
  async commitBuffer (e) {
    e?.preventDefault()
    if (this.buffer.length === 0) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.bulkEndpointValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({ operations: this.buffer })
      })

      if (!res.ok) {
        const msg = await res.text()
        throw new Error(`一括保存に失敗しました：${msg}`)
      }

      // 成功時リセット＋リロード
      this.buffer = []
      this.slotMap.clear()
      this.updateCount()
      this.clearEditedMarks()
      Turbo.visit(window.location.href, { action: "replace" })
    } catch (err) {
      alert(err.message || "通信エラー")
    }
  }

  // =========================================
  // ④ 取り消し（リセット）
  // =========================================
  resetBuffer (e) {
    e?.preventDefault()
    this.buffer = []
    this.slotMap.clear()
    this.updateCount()
    this.clearEditedMarks()
  }

  // =========================================
  // 内部ユーティリティ
  // =========================================
  pushBuffer (matchId, slotKey, memberId) {
    const key = ${matchId}:${slotKey}
    this.slotMap.set(key, memberId)
    this.buffer = this.buffer.filter(op => !(op.match_id === matchId && op.slot_key === slotKey))
    this.buffer.push({ match_id: matchId, slot_key: slotKey, member_id: memberId })
    this.updateCount()
  }

  updateCount () {
    if (this.hasBulkCountTarget) this.bulkCountTarget.textContent = String(this.buffer.length)
  }

  markSlotEdited (el) {
    if (el) el.classList.add("slot-editor--edited")
  }

  markCardUnsaved (card) {
    if (!card) return
    card.classList.add("match-card--unsaved")
    const badge = card.querySelector("[data-unsaved-badge]")
    if (badge) badge.style.display = ""
  }

  clearEditedMarks () {
    document.querySelectorAll(".slot-editor--edited").forEach(e => e.classList.remove("slot-editor--edited"))
    document.querySelectorAll(".match-card--unsaved").forEach(card => {
      card.classList.remove("match-card--unsaved")
      const badge = card.querySelector("[data-unsaved-badge]")
      if (badge) badge.style.display = "none"
    })
  }
}