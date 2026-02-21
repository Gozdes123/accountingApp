<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  subscriptions: { type: Array, required: true, default: () => [] },
  accounts: { type: Array, required: true, default: () => [] }
})

const emit = defineEmits(['add-subscription', 'delete-subscription'])

const showAddModal = ref(false)
const newSub = ref({ name: '', cost: '', billing_cycle: 'monthly', next_payment_date: '', account_id: '' })

// ── Helpers ──────────────────────────────────────────
const formatCurrency = (amount) =>
  new Intl.NumberFormat('zh-TW', { style: 'currency', currency: 'TWD', minimumFractionDigits: 0 }).format(amount)

const getAccountName = (id) => props.accounts.find(a => a.id === id)?.name ?? null

const getDaysUntil = (dateStr) => {
  if (!dateStr) return null
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const target = new Date(dateStr)
  return Math.ceil((target - today) / 86400000)
}

const formatShortDate = (dateStr) => {
  if (!dateStr) return '-'
  const d = new Date(dateStr)
  return `${d.getMonth() + 1}/${d.getDate()}`
}

const getServiceColor = (name) => {
  const colors = ['#6366f1','#8b5cf6','#ec4899','#f59e0b','#10b981','#3b82f6','#ef4444','#14b8a6']
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash)
  return colors[Math.abs(hash) % colors.length]
}

// ── Computed ──────────────────────────────────────────
const totalMonthlyCost = computed(() =>
  props.subscriptions.reduce((sum, sub) => {
    const amt = parseFloat(sub.cost) || 0
    return sum + (sub.billing_cycle === 'yearly' ? amt / 12 : amt)
  }, 0)
)

const totalYearlyCost = computed(() =>
  props.subscriptions.reduce((sum, sub) => {
    const amt = parseFloat(sub.cost) || 0
    return sum + (sub.billing_cycle === 'yearly' ? amt : amt * 12)
  }, 0)
)

const getUrgencyLevel = (days) => {
  if (days === null) return 'no-date'
  if (days < 0) return 'overdue'
  if (days <= 3) return 'critical'
  if (days <= 7) return 'soon'
  if (days <= 30) return 'this-month'
  return 'later'
}

const GROUPS = [
  { key: 'overdue',    label: '⚠️ 已到期',  levels: ['overdue'] },
  { key: 'critical',  label: '🔴 3天內',   levels: ['critical'] },
  { key: 'soon',      label: '🟡 本週內',   levels: ['soon'] },
  { key: 'this-month',label: '📅 本月',     levels: ['this-month'] },
  { key: 'later',     label: '🗓️ 較晚',    levels: ['later'] },
  { key: 'no-date',   label: '📋 未設定日期', levels: ['no-date'] },
]

const groupedSubscriptions = computed(() => {
  return GROUPS.map(g => {
    const items = props.subscriptions
      .filter(sub => g.levels.includes(getUrgencyLevel(getDaysUntil(sub.next_payment_date))))
      .sort((a, b) => {
        const da = getDaysUntil(a.next_payment_date) ?? 9999
        const db = getDaysUntil(b.next_payment_date) ?? 9999
        return da - db
      })
    return { ...g, items }
  }).filter(g => g.items.length > 0)
})

const overdueCount = computed(() =>
  props.subscriptions.filter(s => {
    const d = getDaysUntil(s.next_payment_date)
    return d !== null && d <= 3
  }).length
)

// ── Actions ──────────────────────────────────────────
const handleAdd = () => {
  if (!newSub.value.name || !newSub.value.cost) return
  const payload = { ...newSub.value }
  if (!payload.account_id) delete payload.account_id
  if (!payload.next_payment_date) delete payload.next_payment_date
  emit('add-subscription', payload)
  showAddModal.value = false
  newSub.value = { name: '', cost: '', billing_cycle: 'monthly', next_payment_date: '', account_id: '' }
}
</script>

<template>
  <div class="sub-container">

    <!-- ── Summary Card ── -->
    <div class="summary-card">
      <div class="summary-left">
        <div class="summary-label">每月訂閱支出</div>
        <div class="summary-amount">{{ formatCurrency(totalMonthlyCost) }}</div>
      </div>
      <div class="summary-right">
        <div class="count-badge">{{ subscriptions.length }} 項</div>
        <button class="add-btn" @click="showAddModal = !showAddModal">
          {{ showAddModal ? '✕' : '+' }}
        </button>
      </div>
    </div>

    <!-- ── Urgent Alert Banner ── -->
    <div v-if="overdueCount > 0" class="alert-banner">
      <span class="pulse-dot"></span>
      有 {{ overdueCount }} 筆訂閱即將或已到期，請確認是否已完成扣款
    </div>

    <!-- ── Add Form ── -->
    <transition name="form-slide">
      <div v-if="showAddModal" class="add-form">
        <div class="form-title">新增訂閱服務</div>
        <div class="form-group">
          <label>名稱</label>
          <input v-model="newSub.name" placeholder="例如: Netflix、Spotify" />
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>金額</label>
            <input v-model="newSub.cost" type="number" placeholder="0" />
          </div>
          <div class="form-group">
            <label>週期</label>
            <select v-model="newSub.billing_cycle">
              <option value="monthly">每月</option>
              <option value="yearly">每年</option>
            </select>
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>下次扣款日</label>
            <input v-model="newSub.next_payment_date" type="date" />
          </div>
          <div class="form-group">
            <label>扣款帳戶</label>
            <select v-model="newSub.account_id">
              <option value="">不指定</option>
              <option v-for="acc in accounts" :key="acc.id" :value="acc.id">{{ acc.name }}</option>
            </select>
          </div>
        </div>
        <button class="save-btn" @click="handleAdd">✓ 儲存</button>
      </div>
    </transition>

    <!-- ── Timeline Groups ── -->
    <div class="timeline-list">
      <div v-if="subscriptions.length === 0" class="empty-state">
        <div class="empty-icon">📋</div>
        <div>尚無訂閱項目</div>
        <div class="empty-hint">點上方「+」新增您的第一個訂閱服務</div>
      </div>

      <div v-for="group in groupedSubscriptions" :key="group.key" class="group-block">
        <!-- Group Header -->
        <div class="group-header">
          <span class="group-label">{{ group.label }}</span>
          <span class="group-count">{{ group.items.length }}</span>
        </div>

        <!-- Items -->
        <div
          v-for="sub in group.items"
          :key="sub.id"
          class="sub-item"
          :class="group.key"
        >
          <!-- Service Icon -->
          <div class="service-icon" :style="{ background: getServiceColor(sub.name) }">
            {{ sub.name.charAt(0).toUpperCase() }}
          </div>

          <!-- Info -->
          <div class="sub-info">
            <div class="sub-name">
              <span v-if="group.key === 'overdue' || group.key === 'critical'" class="pulse-dot small"></span>
              {{ sub.name }}
            </div>
            <div class="sub-tags">
              <span class="tag cycle">{{ sub.billing_cycle === 'monthly' ? '月繳' : '年繳' }}</span>
              <span v-if="getAccountName(sub.account_id)" class="tag account">🏦 {{ getAccountName(sub.account_id) }}</span>
            </div>
          </div>

          <!-- Right Side -->
          <div class="sub-right">
            <div class="sub-cost">{{ formatCurrency(sub.cost) }}</div>
            <div v-if="sub.next_payment_date" class="sub-date" :class="group.key">
              <template v-if="group.key === 'overdue'">已逾期</template>
              <template v-else-if="group.key === 'critical' || group.key === 'soon'">
                {{ getDaysUntil(sub.next_payment_date) }} 天後
              </template>
              <template v-else>{{ formatShortDate(sub.next_payment_date) }}</template>
            </div>
            <button class="del-btn" @click="$emit('delete-subscription', sub.id)">✕</button>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.sub-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 0 1rem 140px 1rem;
}

/* ── Summary Card ── */
.summary-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: linear-gradient(135deg, rgba(139,92,246,0.2) 0%, rgba(99,102,241,0.1) 100%);
  border: 1px solid rgba(139,92,246,0.3);
  border-radius: 16px;
  padding: 1.2rem;
}
.summary-label { color: var(--color-text-muted); font-size: 0.8rem; margin-bottom: 0.2rem; }
.summary-amount { font-size: 2rem; font-weight: 800; color: #a78bfa; letter-spacing: -1px; }
.summary-yearly { font-size: 0.78rem; color: var(--color-text-muted); margin-top: 0.2rem; }
.summary-right { display: flex; flex-direction: column; align-items: flex-end; gap: 0.5rem; }
.count-badge {
  font-size: 0.75rem;
  background: rgba(139,92,246,0.2);
  color: #a78bfa;
  padding: 2px 10px;
  border-radius: 20px;
  font-weight: 600;
}
.add-btn {
  width: 36px; height: 36px;
  background: #7c3aed;
  color: white;
  border: none;
  border-radius: 50%;
  font-size: 1.2rem;
  font-weight: bold;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  transition: transform 0.2s, background 0.2s;
}
.add-btn:hover { transform: scale(1.1); background: #6d28d9; }

/* ── Alert Banner ── */
.alert-banner {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  background: rgba(239,68,68,0.1);
  border: 1px solid rgba(239,68,68,0.3);
  border-radius: 10px;
  padding: 0.6rem 0.9rem;
  font-size: 0.82rem;
  color: #f87171;
}

/* ── Pulsing dot ── */
.pulse-dot {
  display: inline-block;
  width: 8px; height: 8px;
  background: #ef4444;
  border-radius: 50%;
  animation: pulse 1.5s infinite;
  flex-shrink: 0;
}
.pulse-dot.small { width: 6px; height: 6px; margin-right: 4px; vertical-align: middle; }
@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%       { opacity: 0.4; transform: scale(1.3); }
}

/* ── Add Form ── */
.add-form {
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px;
  padding: 1.25rem 1rem;
}
.form-title { font-size: 0.95rem; font-weight: 600; margin-bottom: 1rem; color: var(--color-text); }
.form-group { flex: 1; min-width: 120px; margin-bottom: 0.75rem; }
.form-group label { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.3rem; }
.form-group input, .form-group select { width: 100%; min-width: 0; }
.form-row { display: flex; flex-wrap: wrap; gap: 0.75rem; }
.save-btn {
  width: 100%; padding: 0.7rem;
  background: #7c3aed; color: white;
  border: none; border-radius: 12px;
  font-size: 0.95rem; font-weight: 600;
  cursor: pointer; margin-top: 0.25rem;
  transition: opacity 0.2s;
}
.save-btn:hover { opacity: 0.85; }

.form-slide-enter-active { transition: all 0.25s ease; }
.form-slide-leave-active { transition: all 0.2s ease; }
.form-slide-enter-from, .form-slide-leave-to { opacity: 0; transform: translateY(-8px); }

/* ── Timeline ── */
.timeline-list { display: flex; flex-direction: column; gap: 1rem; }

.empty-state { text-align: center; color: var(--color-text-muted); padding: 3rem 1rem; }
.empty-icon { font-size: 2.5rem; margin-bottom: 0.5rem; }
.empty-hint { font-size: 0.82rem; margin-top: 0.4rem; opacity: 0.6; }

.group-block { display: flex; flex-direction: column; gap: 0.4rem; }
.group-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 0.2rem 0.2rem;
}
.group-label { font-size: 0.78rem; font-weight: 600; color: var(--color-text-muted); letter-spacing: 0.5px; }
.group-count {
  font-size: 0.72rem;
  background: rgba(255,255,255,0.08);
  color: var(--color-text-muted);
  padding: 1px 8px; border-radius: 20px;
}

/* ── Item ── */
.sub-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 14px;
  padding: 0.9rem;
  transition: background 0.2s;
}
.sub-item:hover { background: rgba(255,255,255,0.06); }

/* Urgency left border - use border-left instead of absolute */
.sub-item.overdue  { border-left: 3px solid #ef4444; }
.sub-item.critical { border-left: 3px solid #f97316; }
.sub-item.soon     { border-left: 3px solid #fbbf24; }
.sub-item.this-month { border-left: 3px solid #60a5fa; }
.sub-item.later,
.sub-item.no-date  { border-left: 3px solid rgba(255,255,255,0.1); }

.service-icon {
  width: 38px; height: 38px;
  border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  font-size: 1rem; font-weight: 800;
  color: white;
  flex-shrink: 0;
}

.sub-info { flex: 1; min-width: 0; }
.sub-name {
  font-size: 0.95rem; font-weight: 600;
  display: flex; align-items: center;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.sub-tags { display: flex; gap: 0.3rem; margin-top: 0.3rem; flex-wrap: wrap; }
.tag {
  font-size: 0.7rem;
  padding: 1px 7px; border-radius: 20px;
}
.tag.cycle { background: rgba(255,255,255,0.08); color: var(--color-text-muted); }
.tag.account { background: rgba(99,102,241,0.15); color: #a5b4fc; }

.sub-right {
  display: flex; flex-direction: column;
  align-items: flex-end; gap: 0.3rem;
  flex-shrink: 0;
}
.sub-cost { font-size: 1rem; font-weight: 700; color: var(--color-text); }
.sub-date {
  font-size: 0.72rem; font-weight: 600;
  padding: 1px 7px; border-radius: 20px;
}
.sub-date.overdue  { background: rgba(239,68,68,0.2); color: #f87171; }
.sub-date.critical { background: rgba(249,115,22,0.2); color: #fb923c; }
.sub-date.soon     { background: rgba(251,191,36,0.2); color: #fbbf24; }
.sub-date.this-month { background: rgba(96,165,250,0.15); color: #93c5fd; }
.sub-date.later,
.sub-date.no-date  { background: rgba(255,255,255,0.07); color: var(--color-text-muted); }

.del-btn {
  background: transparent;
  border: 1px solid rgba(255,255,255,0.12);
  color: var(--color-text-muted);
  padding: 2px 7px; border-radius: 6px;
  font-size: 0.75rem; cursor: pointer;
  transition: all 0.2s;
}
.del-btn:hover { border-color: #ef4444; color: #ef4444; }
</style>
