// app/javascript/controllers/lineup_controller.js
import { Controller } from "@hotwired/stimulus"

// ✅ lineup_controller.js（まとめて保存・バッファ対応）
export default class extends Controller {
  static values = {
    bulkEndpoint: String, // data-lineup-bulk-endpoint-value
    eventId: Number       // data-lineup-event-id-value
  }

  static targets = ["bulkCount"]

  connect() {
    // 未保存オペレーションを格納
    this.buffer = []  // [{ match_id, slot_key, member_id }]
    this.slotMap = new Map()
    this.updateCount()
  }

  // =========================================
  // ① セレクト変更時 → 自動的にバッファに積む
  // =========================================
  bufferReplaceFromSelect(e) {
    e?.preventDefault()
    const select = e.currentTarget
    const memberId = select?.value
    if (!memberId) return

    const matchId = Number(select.dataset.matchId)
    const slotKey = select.dataset.slotKey
    if (!matchId || !slotKey) return

    // バッファ登録
    this.pushBuffer(matchId, slotKey, Number(memberId))
    this.markSlotEdited(select.closest("[data-slot-el]"))
    this.markCardUnsaved(select.closest("[data-match-el]"))

    // 見た目上の即時反映
    const strong = select.closest("[data-slot-el]")?.querySelector("[data-current-name]")
    if (strong) {
      const label = select.options[select.selectedIndex]?.text || ""
      strong.textContent = label.split("（")[0] || label
    }
  }

  // =========================================
  // ② 「⏱ 差し替えをバッファ」ボタンクリック
  // =========================================
  bufferReplace(e) {
    e?.preventDefault()
    const btn = e.currentTarget
    const matchId = Number(btn.dataset.matchId)
    const slotKey = btn.dataset.slotKey
    if (!matchId || !slotKey) return

    // 近くの select を探す
    const select = btn.closest("[data-slot-el]")?.querySelector("select[data-member-select]")
    if (!select || !select.value) return

    this.pushBuffer(matchId, slotKey, Number(select.value))
    this.markSlotEdited(btn.closest("[data-slot-el]"))
    this.markCardUnsaved(btn.closest("[data-match-el]"))
  }

  // =========================================
  // ③ 「まとめて保存」ボタン
  // =========================================
  async commitBuffer(e) {
    e?.preventDefault()
    if (!this.bulkEndpointValue) return
    if (this.buffer.length === 0) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.bulkEndpointValue, {
        method: "PATCH", // ルーティングで POST も許可しているなら POST でもOK
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({
          event_id: this.eventIdValue,
          operations: this.buffer
        })
      })

      if (!res.ok) {
        let msg = ""
        try {
          msg = (await res.json()).error
        } catch {
          msg = await res.text()
        }
        throw new Error(msg || `一括保存に失敗しました（${res.status}）`)
      }

      // 成功したらリセット＆リロード
      this.resetInternal()
      if (window.Turbo?.visit) {
        Turbo.visit(window.location.href, { action: "replace" })
      } else {
        window.location.reload()
      }
    } catch (err) {
      alert(err?.message || "通信エラーが発生しました")
    }
  }

  // =========================================
  // ④ 「取り消し」ボタン
  // =========================================
  resetBuffer(e) {
    e?.preventDefault()
    this.resetInternal()
  }

  // =========================================
  // 内部ユーティリティ群
  // =========================================
  resetInternal() {
    this.buffer = []
    this.slotMap.clear()
    this.updateCount()
    this.clearEditedMarks()
  }

  pushBuffer(matchId, slotKey, memberId) {
    // ✅ バグ修正: テンプレートリテラル記法
    const key = ${matchId}:${slotKey}
    this.slotMap.set(key, memberId)

    // 同一スロットの旧オペを削除
    this.buffer = this.buffer.filter(op => !(op.match_id === matchId && op.slot_key === slotKey))
    this.buffer.push({ match_id: matchId, slot_key: slotKey, member_id: memberId })
    this.updateCount()
  }

  updateCount() {
    // Stimulus target 更新
    if (this.hasBulkCountTarget) {
      this.bulkCountTarget.textContent = String(this.buffer.length)
    } else {
      // 互換対応
      const el = this.element.querySelector("[data-bulk-count]")
      if (el) el.textContent = String(this.buffer.length)
    }
  }

  markSlotEdited(el) {
    if (el) el.classList.add("slot-editor--edited")
  }

  markCardUnsaved(card) {
    if (!card) return
    card.classList.add("match-card--unsaved")
    const badge = card.querySelector("[data-unsaved-badge]")
    if (badge) badge.style.display = ""
  }

  clearEditedMarks() {
    document.querySelectorAll(".slot-editor--edited").forEach(e => e.classList.remove("slot-editor--edited"))
    document.querySelectorAll(".match-card--unsaved").forEach(card => {
      card.classList.remove("match-card--unsaved")
      const badge = card.querySelector("[data-unsaved-badge]")
      if (badge) badge.style.display = "none"
    })
  }
}