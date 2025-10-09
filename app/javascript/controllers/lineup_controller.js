// app/javascript/controllers/lineup_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    bulkEndpoint: String, // data-lineup-bulk-endpoint-value
    eventId: Number       // data-lineup-event-id-value
  }
  static targets = ["bulkCount"]

  connect() {
    // 未保存オペ: { match_id, slot_key, member_id }
    this.buffer = []
    this.slotMap = new Map()
    this.updateCount()
  }

  // =========================================
  // ① セレクト変更で自動的にバッファに積む
  // =========================================
  bufferReplaceFromSelect(e) {
    e?.preventDefault() // ← 念のため既定動作を抑止
    const select  = e.currentTarget
    const memberId = select?.value
    if (!memberId) return

    const matchId = Number(select.dataset.matchId)
    const slotKey = select.dataset.slotKey
    if (!matchId || !slotKey) return

    this.pushBuffer(matchId, slotKey, Number(memberId))
    this.markSlotEdited(select.closest("[data-slot-el]"))
    this.markCardUnsaved(select.closest("[data-match-el]"))

    // 表示名を仮更新（保存確定前の見た目）
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
    e?.preventDefault() // ← フォーム送信に負けないように
    const btn = e.currentTarget
    const matchId = Number(btn.dataset.matchId)
    const slotKey = btn.dataset.slotKey
    if (!matchId || !slotKey) return

    // 近傍のセレクト（data-member-select="true"）を拾う
    const select = btn.closest("[data-slot-el]")?.querySelector("select[data-member-select]")
    if (!select || !select.value) return

    this.pushBuffer(matchId, slotKey, Number(select.value))
    this.markSlotEdited(btn.closest("[data-slot-el]"))
    this.markCardUnsaved(btn.closest("[data-match-el]"))
  }

  // =========================================
  // ③ まとめて保存
  // =========================================
  async commitBuffer(e) {
    e?.preventDefault()
    if (!this.bulkEndpointValue) return
    if (this.buffer.length === 0) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.bulkEndpointValue, {
        method: "PATCH", // routes で POST も許可済みなら "POST" でもOK
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
        // なるべくサーバのメッセージを見せる
        let msg = ""
        try { msg = (await res.json()).error } catch { msg = await res.text() }
        throw new Error(msg || `一括保存に失敗しました（${res.status}）`)
      }

      // 成功：リセット＆再描画
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
  // ④ 取り消し（リセット）
  // =========================================
  resetBuffer(e) {
    e?.preventDefault()
    this.resetInternal()
  }

  // =========================================
  // 内部ユーティリティ
  // =========================================
  resetInternal() {
    this.buffer = []
    this.slotMap.clear()
    this.updateCount()
    this.clearEditedMarks()
  }

  pushBuffer(matchId, slotKey, memberId) {
    const key = ${matchId}:${slotKey}          // ← バグ修正（テンプレ文字列）
    this.slotMap.set(key, memberId)

    // 同一スロットの旧オペを除去して最新だけ残す
    this.buffer = this.buffer.filter(op => !(op.match_id === matchId && op.slot_key === slotKey))
    this.buffer.push({ match_id: matchId, slot_key: slotKey, member_id: memberId })
    this.updateCount()
  }

  updateCount() {
    if (this.hasBulkCountTarget) {
      this.bulkCountTarget.textContent = String(this.buffer.length)
    } else {
      // 後方互換: data-bulk-count がある場合も更新
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