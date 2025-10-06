import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "commitButton", "queuedCount", "bufferList" ]
  static values  = { eventId: Number }

  connect() {
    this.buffer = [] // {type:"clear"|"replace", match_id, slot, member_id?}
    this.refreshToolbar()
  }

  // ========== ビュー側から呼ぶハンドラ ==========
  queueClear(e) {
    const matchId = Number(e.currentTarget.dataset.matchId)
    const slotKey = e.currentTarget.dataset.slotKey
    this._push({ type: "clear", match_id: matchId, slot: slotKey }, `クリア: #${matchId} ${slotKey}`)
  }

  queueReplaceFromSelect(e) {
    const select  = e.currentTarget
    const memberId = select.value ? Number(select.value) : null
    const matchId = Number(select.dataset.matchId)
    const slotKey = select.dataset.slotKey
    this._push({ type: "replace", match_id: matchId, slot: slotKey, member_id: memberId },
               `差替: #${matchId} ${slotKey} → ${memberId || "（空）"}`)
  }

  // DnDなどから直接呼びたい時用
  queueReplace({ matchId, slotKey, memberId }) {
    this._push({ type: "replace", match_id: Number(matchId), slot: slotKey, member_id: memberId ? Number(memberId) : null },
               `差替: #${matchId} ${slotKey} → ${memberId || "（空）"}`)
  }

  reset() {
    this.buffer = []
    this.refreshToolbar(true)
  }

  async commit() {
    if (this.buffer.length === 0) return

    const res = await fetch("/admin/matches/bulk_update", {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({ operations: this.buffer })
    })

    const json = await res.json()
    if (!res.ok || !json.ok) {
      alert(`保存に失敗: ${json.error || res.statusText}`)
      return
    }

    // 反映後はバッファを空にして、画面を再読込 or 局所的にDOM更新（簡易はreload）
    this.reset()
    location.reload()
  }

  // ========== 内部 ==========
  _push(op, label) {
    this.buffer.push(op)
    this.refreshToolbar()
    if (this.hasBufferListTarget) {
      const li = document.createElement("li")
      li.textContent = label
      this.bufferListTarget.appendChild(li)
    }
  }

  refreshToolbar(clear = false) {
    const n = clear ? 0 : this.buffer.length
    if (this.hasQueuedCountTarget) this.queuedCountTarget.textContent = String(n)
    if (this.hasCommitButtonTarget) this.commitButtonTarget.disabled = n === 0
  }
}