// app/javascript/controllers/lineup_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="lineup"
export default class extends Controller {
  static values = {
    bulkEndpoint: String, // data-lineup-bulk-endpoint-value
    eventId: Number       // data-lineup-event-id-value
  }

  connect() {
    // バッファ（未保存オペレーション）: {match_id, slot_key, member_id|null, type:"replace"|"clear"}
    this.buffer = []

    // 「取り消し」「まとめて保存」ボタンにイベントを付与
    this.resetBtn  = this.element.querySelector("[data-bulk-reset]")
    this.commitBtn = this.element.querySelector("[data-bulk-commit]")
    this.countEl   = this.element.querySelector("[data-bulk-count]")

    if (this.resetBtn)  this.resetBtn.addEventListener("click", (e) => { e.preventDefault(); this.resetBuffer() })
    if (this.commitBtn) this.commitBtn.addEventListener("click", (e) => { e.preventDefault(); this.commitBuffer() })

    this.updateCount()
  }

  // ================================
  // 外部（_card.html.erb）からのアクション
  // ================================

  // セレクトが変更されたら自動で“バッファに積む”
  bufferReplaceFromSelect(event) {
    const select = event.currentTarget
    const memberId = select.value || null
    const matchId  = Number(select.dataset.matchId)
    const slotKey  = select.dataset.slotKey

    if (!matchId || !slotKey) return
    if (!memberId) return // プロンプト選択に戻したら無視

    this.addToBuffer({ type: "replace", match_id: matchId, slot_key: slotKey, member_id: Number(memberId) })
    // 未保存ハイライト
    this.markPending(matchId, slotKey)
  }

  // 「⏱ 差し替えをバッファ」ボタンクリック時（近くの select を参照）
  bufferReplace(event) {
    const btn = event.currentTarget
    const matchId = Number(btn.dataset.matchId)
    const slotKey = btn.dataset.slotKey
    if (!matchId || !slotKey) return

    // 近傍の select[data-member-select] を拾う
    const wrap = btn.closest(".slot-editor")
    const select = wrap ? wrap.querySelector("select[data-member-select]") : null
    if (!select || !select.value) return

    this.addToBuffer({ type: "replace", match_id: matchId, slot_key: slotKey, member_id: Number(select.value) })
    this.markPending(matchId, slotKey)
  }

  // （任意で呼べる）スロットを空にする操作もバッファに積める
  bufferClear(event) {
    const btn = event.currentTarget
    const matchId = Number(btn.dataset.matchId)
    const slotKey = btn.dataset.slotKey
    if (!matchId || !slotKey) return

    this.addToBuffer({ type: "clear", match_id: matchId, slot_key: slotKey, member_id: null })
    this.markPending(matchId, slotKey)
  }

  // ================================
  // バッファ操作
  // ================================
  addToBuffer(op) {
    // 同じ match_id + slot_key の旧オペは除去して最新だけ保持
    this.buffer = this.buffer.filter(o => !(o.match_id === op.match_id && o.slot_key === op.slot_key))
    this.buffer.push(op)
    this.updateCount()
  }

  resetBuffer() {
    this.buffer = []
    this.updateCount()
    this.clearAllPending()
  }

  updateCount() {
    if (this.countEl) this.countEl.textContent = this.buffer.length
  }

  // ================================
  // 未保存ハイライト
  // ================================
  markPending(matchId, slotKey) {
    // スロット枠の黄色
    const slot = this.findSlotEl(matchId, slotKey)
    if (slot) slot.classList.add("pending-slot")

    // 試合カード全体の紫枠 + 「未保存」バッジ表示
    const card = this.findMatchEl(matchId)
    if (card) {
      card.classList.add("pending-match")
      const badge = card.querySelector("[data-unsaved-badge]")
      if (badge) badge.style.display = ""
    }
  }

  clearAllPending() {
    // 全カード・全スロットから pending クラスを外す
    document.querySelectorAll("[data-match-el].pending-match").forEach(el => {
      el.classList.remove("pending-match")
      const badge = el.querySelector("[data-unsaved-badge]")
      if (badge) badge.style.display = "none"
    })
    document.querySelectorAll("[data-slot-el].pending-slot").forEach(el => {
      el.classList.remove("pending-slot")
    })
  }

  // ================================
  // まとめて保存
  // ================================
  async commitBuffer() {
    if (!this.bulkEndpointValue || this.buffer.length === 0) return

    try {
      const token = this.csrfToken()
      const res = await fetch(this.bulkEndpointValue, {
        method: "POST",
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
        const data = await res.json().catch(() => ({}))
        throw new Error(data.error || `保存に失敗しました（${res.status}）`)
      }

      // 成功：バッファをクリアし、未保存ハイライトを解除。画面を再読込して確定状態に。
      this.resetBuffer()
      // Turbo/普通リロードどちらでもOK
      if (window.Turbo && Turbo.visit) {
        Turbo.visit(window.location.href, { action: "replace" })
      } else {
        window.location.reload()
      }
    } catch (e) {
      alert(e.message || "保存に失敗しました")
    }
  }

  // ================================
  // ユーティリティ
  // ================================
  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta && meta.content
  }

  findMatchEl(matchId) {
    // 同じ match-card でもこのページ内だけを対象にする
    return document.querySelector(`[data-match-el][data-match-id="${matchId}"]`)
  }

  findSlotEl(matchId, slotKey) {
    // 指定カード内の該当スロットを返す
    const card = this.findMatchEl(matchId)
    if (!card) return null
    return card.querySelector(`[data-slot-el][data-drop-slot="${slotKey}"]`)
  }
}