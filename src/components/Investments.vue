<script setup>
import { ref, onMounted, onActivated, computed } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { Doughnut } from 'vue-chartjs'
import { PhEye, PhEyeSlash } from '@phosphor-icons/vue'

ChartJS.register(ArcElement, Tooltip, Legend)

// ── State ─────────────────────────────────────────────────────────
const investments = ref([])
const showAddModal = ref(false)
const isRefreshing = ref(false)
const isSaving = ref(false)
const refreshError = ref('')
const saveError = ref('')
const lastUpdated = ref(null)
const usdTwdRate = ref(32)
const isInitialDataLoaded = ref(false)

// 隱藏金額
const isHidden = ref(true)
const togglePrivacy = () => { isHidden.value = !isHidden.value }
const h = (val) => isHidden.value ? '****' : val  // 快速 helper

// 展開某個群組的狀態（key = symbol）
const expandedSymbols = ref(new Set())

const newInv = ref({
  asset_class: 'tw_stock',
  symbol: '',
  name: '',
  quantity: '',
  buy_price: '',
  buy_date: new Date().toISOString().split('T')[0],
  currency: 'TWD'
})

// 'shares' = 直接輸入股數 | 'amount' = 輸入投入金額讓系統算
const inputMode = ref('shares')
const totalAmount = ref('')   // 例如：300 USD
const buyPrice = ref('')      // 例如：185 USD/股

const calculatedShares = computed(() => {
  const amt = Number(totalAmount.value)
  const price = Number(buyPrice.value)
  if (!amt || !price || price === 0) return null
  return amt / price
})

// ── Config ─────────────────────────────────────────────────────────
const ASSET_CONFIG = {
  tw_stock: { label: '台股', currency: 'TWD', color: '#10b981', emoji: '🇹🇼' },
  us_stock: { label: '美股', currency: 'USD', color: '#3b82f6', emoji: '🇺🇸' }
}

// ── Data Fetching ──────────────────────────────────────────────────
const fetchInvestments = async () => {
  const { data, error } = await supabase
    .from('investments')
    .select('*')
    .order('created_at', { ascending: false })
  if (error) {
    console.error('fetch investments error:', error)
  } else {
    investments.value = data
  }
}

// 1. USD/TWD Exchange Rate
const fetchUsdTwdRate = async () => {
  try {
    const res = await fetch('https://api.exchangerate-api.com/v4/latest/USD')
    const data = await res.json()
    return data.rates?.TWD ?? 32
  } catch {
    return usdTwdRate.value
  }
}

// Yahoo Finance symbol resolver
const getYahooSymbol = (symbol, assetClass) => {
  if (!symbol) return ''
  const sym = symbol.trim().toUpperCase()
  const cls = (assetClass || '').trim().toLowerCase()
  
  // If it already has a suffix like .TW, .TWO, -USD, =X, return as is
  if (sym.endsWith('.TW') || sym.endsWith('.TWO') || sym.includes('-') || sym.includes('=')) {
    return sym
  }
  
  // Taiwan stock: 4-6 digit numeric code or tw_stock class
  if (cls === 'tw_stock' || /^\d{4,6}$/.test(sym)) {
    return `${sym}.TW`
  }
  
  // Crypto: BTC, etc. -> BTC-USD
  if (cls === 'crypto' || ['BTC', 'ETH', 'SOL', 'USDT', 'USDC', 'DOGE', 'BNB'].includes(sym)) {
    return `${sym}-USD`
  }
  
  // Default to symbol as is (for US stocks)
  return sym
}

// 2. Stock price via Vite proxy (dev) / allorigins proxy (prod) → Yahoo Finance
const fetchYahooPrice = async (symbol) => {
  try {
    const isProd = import.meta.env.PROD
    const yhUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=1d`
    
    // 1. If in local development, try local dev proxy first
    if (!isProd) {
      try {
        const res = await fetch(`/yahoo-finance/v8/finance/chart/${symbol}?interval=1d&range=1d`)
        if (res.ok) {
          const data = await res.json()
          return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
        }
      } catch {}
    }

    // 2. In Production (or fallback in Local): Try the serverless API proxy
    try {
      const res = await fetch(`/api/yahoo-proxy?symbol=${symbol}`)
      if (res.ok) {
        const data = await res.json()
        return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
      }
    } catch (e) {
      console.warn('Serverless API proxy failed, falling back to public proxies...', e)
    }

    // 3. Fallback: Try corsproxy.io
    try {
      const res = await fetch(`https://corsproxy.io/?${encodeURIComponent(yhUrl)}`)
      if (res.ok) {
        const data = await res.json()
        return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
      }
    } catch (e) {
      console.warn('corsproxy.io failed, falling back to allorigins...', e)
    }

    // 4. Fallback: Try allorigins.win
    try {
      const res = await fetch(`https://api.allorigins.win/raw?url=${encodeURIComponent(yhUrl)}`)
      if (res.ok) {
        const data = await res.json()
        return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
      }
    } catch (e) {
      console.warn('allorigins fallback failed...', e)
    }

    return null
  } catch {
    return null
  }
}

// ── Main: Refresh all prices ────────────────────────────────────────
const refreshPrices = async () => {
  if (isRefreshing.value) return
  isRefreshing.value = true
  refreshError.value = ''

  let successCount = 0
  let failCount = 0

  usdTwdRate.value = await fetchUsdTwdRate()

  // 只對每個 symbol 抓一次報價，全部符合的 row 都更新
  const symbolMap = {}
  for (const inv of investments.value) {
    const key = inv.symbol.toUpperCase()
    if (!symbolMap[key]) symbolMap[key] = { cls: inv.asset_class, ids: [] }
    symbolMap[key].ids.push(inv.id)
  }

  for (const [sym, info] of Object.entries(symbolMap)) {
    const querySym = getYahooSymbol(sym, info.cls)
    const price = await fetchYahooPrice(querySym)

    if (price !== null) {
      const now = new Date().toISOString()
      for (const id of info.ids) {
        const { error } = await supabase
          .from('investments')
          .update({ current_price: price, price_updated_at: now })
          .eq('id', id)
        if (!error) {
          const inv = investments.value.find(i => i.id === id)
          if (inv) { inv.current_price = price; inv.price_updated_at = now }
        }
      }
      successCount++
    } else {
      failCount++
    }
  }

  lastUpdated.value = new Date()
  if (failCount > 0) {
    refreshError.value = `${failCount} 筆報價取得失敗（代號錯誤或網路限制），其餘 ${successCount} 筆已更新`
  }
  isRefreshing.value = false
}

// ── Grouped Holdings ───────────────────────────────────────────────
// 相同 symbol 合併成一個群組，計算總股數 & 均成本
const groupedHoldings = computed(() => {
  const groups = {}

  for (const inv of investments.value) {
    const sym = inv.symbol.toUpperCase()
    if (!groups[sym]) {
      groups[sym] = {
        symbol: sym,
        name: inv.name || sym,
        asset_class: inv.asset_class,
        currency: inv.currency || 'TWD',
        current_price: Number(inv.current_price || 0),
        price_updated_at: inv.price_updated_at,
        lots: []
      }
    }
    groups[sym].lots.push({
      id: inv.id,
      quantity: Number(inv.quantity || 0),
      // 新欄位 buy_price，舊資料 fallback 到 average_cost
      buy_price: Number(inv.buy_price ?? inv.average_cost ?? 0),
      buy_date: inv.buy_date || inv.created_at?.split('T')[0] || '未知',
      current_price: Number(inv.current_price || 0),
      price_updated_at: inv.price_updated_at
    })
    // 保持最新報價同步
    const latestPrice = Number(inv.current_price || 0)
    if (latestPrice > groups[sym].current_price) {
      groups[sym].current_price = latestPrice
      groups[sym].price_updated_at = inv.price_updated_at
    }
  }

  // 計算每個群組的彙總數字
  return Object.values(groups).map(g => {
    const totalQty = g.lots.reduce((s, l) => s + l.quantity, 0)
    const totalCost = g.lots.reduce((s, l) => s + l.quantity * l.buy_price, 0)
    const avgCost = totalQty > 0 ? totalCost / totalQty : 0
    const currentValueTwd = toTwd(totalQty * g.current_price, g.currency)
    const costTwd = toTwd(totalCost, g.currency)
    const pnl = currentValueTwd - costTwd
    const pnlPct = costTwd > 0 ? (pnl / costTwd) * 100 : 0

    return {
      ...g,
      totalQty,
      avgCost,
      totalCost,
      currentValueTwd,
      costTwd,
      pnl,
      pnlPct
    }
  }).sort((a, b) => b.currentValueTwd - a.currentValueTwd)
})

// Groups by asset class
const groupedByClass = computed(() => {
  const result = {}
  for (const [cls, cfg] of Object.entries(ASSET_CONFIG)) {
    const items = groupedHoldings.value.filter(g => g.asset_class === cls)
    if (items.length > 0) result[cls] = { cfg, items }
  }
  return result
})

// ── P&L Helpers ────────────────────────────────────────────────────
const toTwd = (amount, currency) =>
  currency === 'USD' ? amount * usdTwdRate.value : amount

// ── Computed: Totals ───────────────────────────────────────────────
const totalValueTwd = computed(() =>
  groupedHoldings.value.reduce((s, g) => s + g.currentValueTwd, 0)
)
const totalCostTwd = computed(() =>
  groupedHoldings.value.reduce((s, g) => s + g.costTwd, 0)
)
const totalPnl = computed(() => totalValueTwd.value - totalCostTwd.value)
const totalPnlPct = computed(() =>
  totalCostTwd.value > 0 ? (totalPnl.value / totalCostTwd.value) * 100 : 0
)

// ── Chart ──────────────────────────────────────────────────────────
const allocationChartData = computed(() => {
  const groups = {}
  groupedHoldings.value.forEach(g => {
    const cls = g.asset_class
    groups[cls] = (groups[cls] || 0) + g.currentValueTwd
  })
  const entries = Object.entries(groups).filter(([, v]) => v > 0)
  return {
    labels: entries.map(([k]) => ASSET_CONFIG[k]?.label ?? k),
    datasets: [{
      data: entries.map(([, v]) => v),
      backgroundColor: entries.map(([k]) => ASSET_CONFIG[k]?.color ?? '#94a3b8'),
      borderWidth: 0,
      hoverOffset: 4
    }]
  }
})

const allocationChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '65%',
  plugins: {
    legend: {
      position: 'right',
      labels: { color: '#94a3b8', usePointStyle: true, padding: 14, font: { size: 12 } }
    },
    tooltip: {
      callbacks: {
        label: (ctx) => ` ${ctx.label}: ${formatTwd(ctx.parsed)}`
      }
    }
  }
}

// ── Format helpers ─────────────────────────────────────────────────
const formatTwd = (n) =>
  new Intl.NumberFormat('zh-TW', { style: 'currency', currency: 'TWD', minimumFractionDigits: 0 }).format(n)

const formatUsd = (n) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(n)

const formatQty = (n) =>
  new Intl.NumberFormat('en-US', { maximumFractionDigits: 4 }).format(n)

const formatPct = (n) => `${n > 0 ? '+' : ''}${n.toFixed(2)}%`

const formatPrice = (price, currency) =>
  currency === 'USD' ? formatUsd(price) : formatTwd(price)

const formatUpdatedAt = (dateStr) => {
  if (!dateStr) return '未更新'
  const d = new Date(dateStr)
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
}

const formatDate = (dateStr) => {
  if (!dateStr || dateStr === '未知') return '未知'
  const d = new Date(dateStr)
  return `${d.getFullYear()}/${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`
}

// ── Expand / Collapse ──────────────────────────────────────────────
const toggleExpand = (symbol) => {
  if (expandedSymbols.value.has(symbol)) {
    expandedSymbols.value.delete(symbol)
  } else {
    expandedSymbols.value.add(symbol)
  }
}
const isExpanded = (symbol) => expandedSymbols.value.has(symbol)

// ── CRUD ───────────────────────────────────────────────────────────
const onAssetClassChange = () => {
  const cls = newInv.value.asset_class
  newInv.value.currency = ASSET_CONFIG[cls]?.currency ?? 'TWD'
  totalAmount.value = ''
  buyPrice.value = ''
  newInv.value.quantity = ''
  newInv.value.buy_price = ''
}

const addInvestment = async () => {
  saveError.value = ''

  if (!newInv.value.symbol) {
    saveError.value = '請填入股票代號'
    return
  }

  let quantity, buy_price_val

  if (inputMode.value === 'amount') {
    if (!totalAmount.value || !buyPrice.value) {
      saveError.value = '請填入投入金額與買入時股價'
      return
    }
    buy_price_val = Number(buyPrice.value)
    quantity = Number(totalAmount.value) / buy_price_val
  } else {
    if (!newInv.value.quantity || !newInv.value.buy_price) {
      saveError.value = '請填入買入股數與買入價格'
      return
    }
    quantity = Number(newInv.value.quantity)
    buy_price_val = Number(newInv.value.buy_price)
  }

  const { symbol, name, buy_date, asset_class, currency } = newInv.value

  // 只放資料庫確定有的欄位，buy_price / buy_date 用 upsert 相容處理
  const payload = {
    asset_class,
    symbol: symbol.toUpperCase(),
    name: name || symbol.toUpperCase(),
    quantity,
    average_cost: buy_price_val,
    currency,
    type: 'Stock',
    current_price: 0
  }

  // 如果 buy_price / buy_date 欄位存在就一起帶（migrate 後才有）
  // 用 try 避免欄位不存在時炸掉
  try {
    payload.buy_price = buy_price_val
    payload.buy_date = buy_date || new Date().toISOString().split('T')[0]
  } catch {}

  isSaving.value = true
  const { data, error } = await supabase.from('investments').insert([payload]).select()
  isSaving.value = false

  if (error) {
    console.error('insert error:', error)
    saveError.value = `儲存失敗：${error.message}（請確認是否已執行資料庫 Migration）`
    return
  }

  investments.value.unshift(data[0])
  showAddModal.value = false
  saveError.value = ''
  newInv.value = {
    asset_class: 'tw_stock',
    symbol: '',
    name: '',
    quantity: '',
    buy_price: '',
    buy_date: new Date().toISOString().split('T')[0],
    currency: 'TWD'
  }
  totalAmount.value = ''
  buyPrice.value = ''
}

const deleteLot = async (id) => {
  const { error } = await supabase.from('investments').delete().eq('id', id)
  if (!error) investments.value = investments.value.filter(i => i.id !== id)
}

const initInvestments = async () => {
  await fetchInvestments()
  const oldest = investments.value.reduce((earliest, inv) => {
    if (!inv.price_updated_at) return null
    if (!earliest) return new Date(inv.price_updated_at)
    return new Date(inv.price_updated_at) < earliest ? new Date(inv.price_updated_at) : earliest
  }, new Date())

  const oneHourAgo = new Date(Date.now() - 3600000)
  if (!oldest || oldest < oneHourAgo) {
    await refreshPrices()
  } else {
    usdTwdRate.value = await fetchUsdTwdRate()
  }
  isInitialDataLoaded.value = true
}

onMounted(() => {
  initInvestments()
})

onActivated(() => {
  initInvestments()
})
</script>

<template>
  <div class="inv-container" v-if="isInitialDataLoaded">

    <!-- ── Header Summary Card ────────────────────────────────── -->
    <div class="summary-card">
      <div class="summary-top">
        <div>
          <div class="summary-label" style="display: flex; align-items: center; gap: 0.5rem;">
            <span>投資組合總值</span>
            <button class="privacy-icon-btn" @click="togglePrivacy">
              <component :is="isHidden ? PhEyeSlash : PhEye" size="16" />
            </button>
          </div>
          <div class="summary-total">{{ isHidden ? '****' : formatTwd(totalValueTwd) }}</div>
          <div class="summary-pnl" :class="totalPnl >= 0 ? 'gain' : 'loss'">
            {{ totalPnl >= 0 ? '▲' : '▼' }}
            {{ isHidden ? '****' : formatTwd(Math.abs(totalPnl)) }}
            <span v-if="!isHidden">({{ formatPct(totalPnlPct) }})</span>
          </div>
          <div class="rate-info">USD/TWD ≈ {{ usdTwdRate.toFixed(1) }}</div>
        </div>

        <!-- Chart -->
        <div v-if="groupedHoldings.length > 0" class="alloc-chart">
          <Doughnut :data="allocationChartData" :options="allocationChartOptions" />
        </div>
      </div>

      <!-- Actions row -->
      <div class="action-row">
        <button class="refresh-btn" @click="refreshPrices" :disabled="isRefreshing">
          <span :class="{ spin: isRefreshing }">⟳</span>
          <span style="white-space: nowrap;">{{ isRefreshing ? '更新中...' : '更新報價' }}</span>
        </button>
        <button class="add-btn" @click="showAddModal = !showAddModal">
          {{ showAddModal ? '✕取消' : '+ 新增買入' }}
        </button>
      </div>
      <div class="last-updated-row" v-if="lastUpdated">
        最後更新：{{ formatUpdatedAt(lastUpdated) }}
      </div>

      <!-- Error Message -->
      <div v-if="refreshError" class="refresh-error">⚠️ {{ refreshError }}</div>
    </div>

    <!-- ── Add Form ───────────────────────────────────────────── -->
    <transition name="form-slide">
      <div v-if="showAddModal" class="add-form">
        <div class="form-title">📥 新增買入紀錄</div>

        <!-- Asset class selector -->
        <div class="class-selector">
          <button
            v-for="(cfg, key) in ASSET_CONFIG" :key="key"
            class="class-btn"
            :class="{ active: newInv.asset_class === key }"
            @click="newInv.asset_class = key; onAssetClassChange()"
          >
            {{ cfg.emoji }} {{ cfg.label }}
          </button>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label>
              代號
              <span class="hint">
                {{ newInv.asset_class === 'tw_stock' ? '例: 2330, 0050' : '例: AAPL, NVDA' }}
              </span>
            </label>
            <input v-model="newInv.symbol"
              :placeholder="newInv.asset_class === 'tw_stock' ? '2330' : 'AAPL'" />
          </div>
          <div class="form-group">
            <label>名稱 <span class="hint">(選填)</span></label>
            <input v-model="newInv.name" placeholder="例: 台積電" />
          </div>
        </div>

        <!-- ── 輸入模式切換 ── -->
        <div class="mode-toggle">
          <button :class="{ active: inputMode === 'shares' }" @click="inputMode = 'shares'">📊 股數模式</button>
          <button :class="{ active: inputMode === 'amount' }" @click="inputMode = 'amount'">💰 金額模式</button>
        </div>
        <div class="mode-hint">
          <span v-if="inputMode === 'shares'">直接輸入持有股數和買入價格</span>
          <span v-else>輸入花了多少錢，系統自動算出股數</span>
        </div>

        <!-- 股數模式 -->
        <div v-if="inputMode === 'shares'" class="form-row">
          <div class="form-group">
            <label>買入股數</label>
            <input v-model="newInv.quantity" type="number" step="0.000001" placeholder="0" />
          </div>
          <div class="form-group">
            <label>買入價格 ({{ newInv.currency }}/股)</label>
            <input v-model="newInv.buy_price" type="number" step="0.01"
              :placeholder="newInv.currency === 'USD' ? '185.50' : '950'" />
          </div>
        </div>

        <!-- 金額模式 -->
        <div v-if="inputMode === 'amount'" class="form-row">
          <div class="form-group">
            <label>投入金額 ({{ newInv.currency }})</label>
            <input v-model="totalAmount" type="number" step="0.01"
              :placeholder="newInv.currency === 'USD' ? '300' : '10000'" />
          </div>
          <div class="form-group">
            <label>買入時股價 ({{ newInv.currency }}/股)</label>
            <input v-model="buyPrice" type="number" step="0.01"
              :placeholder="newInv.currency === 'USD' ? '185.50' : '950'" />
          </div>
        </div>

        <!-- 金額模式預覽：計算出的股數 -->
        <div v-if="inputMode === 'amount' && calculatedShares !== null" class="shares-preview">
          ≈ {{ calculatedShares.toFixed(6) }} 股（{{ formatPrice(Number(buyPrice), newInv.currency) }} / 股）
        </div>

        <div class="form-group">
          <label>買入日期</label>
          <input v-model="newInv.buy_date" type="date" />
        </div>

        <!-- Preview (股數模式) -->
        <div v-if="inputMode === 'shares' && newInv.quantity && newInv.buy_price" class="cost-preview">
          💰 此筆成本：{{ formatPrice(Number(newInv.quantity) * Number(newInv.buy_price), newInv.currency) }}
          &nbsp;·&nbsp; {{ formatQty(Number(newInv.quantity)) }} 股 @
          {{ formatPrice(Number(newInv.buy_price), newInv.currency) }}
        </div>

        <!-- Preview (金額模式) -->
        <div v-if="inputMode === 'amount' && calculatedShares !== null && totalAmount" class="cost-preview">
          💰 投入金額：{{ formatPrice(Number(totalAmount), newInv.currency) }}
          &nbsp;·&nbsp; ≈ {{ calculatedShares.toFixed(4) }} 股
        </div>

        <!-- 錯誤訊息 -->
        <div v-if="saveError" class="save-error">⚠️ {{ saveError }}</div>

        <button class="save-btn" @click="addInvestment" :disabled="isSaving">
          {{ isSaving ? '儲存中...' : '✓ 儲存買入' }}
        </button>
      </div>
    </transition>

    <!-- ── Holdings List ──────────────────────────────────────── -->
    <div class="holdings-list">
      <div v-if="groupedHoldings.length === 0" class="empty-state">
        <div style="font-size: 2.5rem; margin-bottom: 0.5rem;">📈</div>
        <div>尚無投資紀錄</div>
        <div style="font-size: 0.82rem; margin-top: 0.3rem; opacity: 0.6;">點擊「+ 新增買入」來建立第一筆持倉</div>
      </div>

      <!-- Group by asset class -->
      <template v-for="(clsData, cls) in groupedByClass" :key="cls">
        <div class="class-group">
          <!-- Class Header -->
          <div class="class-header">
            <span>{{ clsData.cfg.emoji }} {{ clsData.cfg.label }}</span>
            <span class="class-pct">
              {{ totalValueTwd > 0 
                ? ((clsData.items.reduce((s,g)=>s+g.currentValueTwd,0)/totalValueTwd*100).toFixed(1))+'%'
                : '--' }}
            </span>
          </div>

          <!-- Each Stock Group -->
          <div v-for="group in clsData.items" :key="group.symbol" class="stock-group">

            <!-- ── Main Row (Always Visible) ── -->
            <div class="holding-card" @click="toggleExpand(group.symbol)">
              <!-- Icon -->
              <div class="holding-icon" :style="{ background: clsData.cfg.color + '22', color: clsData.cfg.color }">
                {{ (group.name || group.symbol).charAt(0).toUpperCase() }}
              </div>

              <!-- Info -->
              <div class="holding-info">
                <div class="holding-symbol">
                  {{ group.symbol }}
                  <span v-if="group.name && group.name !== group.symbol" class="holding-name"> · {{ group.name }}</span>
                </div>
                <div class="holding-meta">
                  <span class="badge-qty">{{ formatQty(group.totalQty) }} 股</span>
                  <span class="separator">·</span>
                  均成本 {{ isHidden ? '****' : formatPrice(group.avgCost, group.currency) }}
                </div>
                <div class="holding-updated">
                  報價更新：{{ formatUpdatedAt(group.price_updated_at) }}
                  <span class="lot-count">{{ group.lots.length }} 筆買入</span>
                </div>
              </div>

              <!-- Right: Value & PnL -->
              <div class="holding-right">
                <div class="holding-value">{{ isHidden ? '****' : formatTwd(group.currentValueTwd) }}</div>
                <div class="holding-price">
                  現價 {{ isHidden ? '---' : formatPrice(group.current_price, group.currency) }}
                </div>
                <div class="holding-pnl" :class="group.pnl >= 0 ? 'gain' : 'loss'">
                  {{ isHidden ? '****' : (group.pnl >= 0 ? '+' : '') + formatTwd(group.pnl) }}
                  <span class="pnl-pct" v-if="!isHidden">({{ formatPct(group.pnlPct) }})</span>
                </div>
              </div>

              <!-- Expand Arrow -->
              <div class="expand-arrow" :class="{ open: isExpanded(group.symbol) }">›</div>
            </div>

            <!-- ── Collapsible: Buy Lots ── -->
            <transition name="lots-slide">
              <div v-if="isExpanded(group.symbol)" class="lots-panel">
                <div class="lots-header">
                  <span>買入明細</span>
                  <span class="lots-sum">共 {{ formatQty(group.totalQty) }} 股 ·
                    總成本 {{ isHidden ? '****' : formatPrice(group.totalCost, group.currency) }}</span>
                </div>

                <div v-for="lot in group.lots" :key="lot.id" class="lot-row">
                  <div class="lot-date">{{ formatDate(lot.buy_date) }}</div>
                  <div class="lot-details">
                    <span class="lot-qty">{{ formatQty(lot.quantity) }} 股</span>
                    <span class="lot-at">@</span>
                    <span class="lot-price">{{ isHidden ? '****' : formatPrice(lot.buy_price, group.currency) }}</span>
                  </div>
                  <div class="lot-cost">
                    = {{ isHidden ? '****' : formatPrice(lot.quantity * lot.buy_price, group.currency) }}
                  </div>
                  <button class="lot-del" @click.stop="deleteLot(lot.id)" title="刪除此筆">✕</button>
                </div>
              </div>
            </transition>

          </div>
        </div>
      </template>
    </div>

  </div>
  <div class="inv-container" v-else style="display: flex; align-items: center; justify-content: center; color: var(--color-text-muted);">
    <div class="loading-spinner"></div>
    <span style="margin-left: 10px;">資料同步中...</span>
  </div>
</template>

<style scoped>
.inv-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 0 1rem 140px 1rem;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

/* ── Summary Card ── */
.summary-card {
  background: linear-gradient(135deg, rgba(99,102,241,0.15) 0%, rgba(16,185,129,0.08) 100%);
  border: 1px solid rgba(99,102,241,0.25);
  border-radius: 18px;
  padding: 1.2rem;
}
.summary-top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}
.summary-label { font-size: 0.78rem; color: var(--color-text-muted); margin-bottom: 0.2rem; }
.summary-total { font-size: 1.8rem; font-weight: 800; color: var(--color-text); letter-spacing: -1px; }
.summary-pnl { font-size: 0.9rem; font-weight: 600; margin-top: 0.2rem; }
.summary-pnl.gain { color: #10b981; }
.summary-pnl.loss { color: #ef4444; }
.rate-info { font-size: 0.72rem; color: var(--color-text-muted); margin-top: 0.3rem; }

.alloc-chart { width: 130px; height: 90px; }

.action-row { display: flex; align-items: center; gap: 0.6rem; }
.refresh-btn {
  flex: 1;
  display: flex; align-items: center; justify-content: center; gap: 0.4rem;
  background: rgba(255,255,255,0.07);
  border: 1px solid rgba(255,255,255,0.12);
  color: var(--color-text);
  padding: 0.5rem 0.75rem;
  border-radius: 10px;
  font-size: 0.85rem;
  cursor: pointer;
  transition: background 0.2s;
}
.refresh-btn:hover:not(:disabled) { background: rgba(255,255,255,0.12); }
.refresh-btn:disabled { opacity: 0.6; cursor: not-allowed; }

.last-updated-row { 
  font-size: 0.75rem; 
  color: var(--color-text-muted); 
  text-align: right; 
  margin-top: 0.6rem; 
  opacity: 0.8;
}

.spin { display: inline-block; animation: rotate 1s linear infinite; }
@keyframes rotate { to { transform: rotate(360deg); } }

.add-btn {
  background: #6366f1; color: white;
  border: none; padding: 0.5rem 1rem;
  border-radius: 10px; font-size: 0.85rem; font-weight: 600;
  cursor: pointer; white-space: nowrap;
  transition: opacity 0.2s;
}
.add-btn:hover { opacity: 0.85; }

.privacy-icon-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 0 !important;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
}
.privacy-icon-btn:hover { color: var(--color-text); }

.refresh-error {
  margin-top: 0.6rem;
  font-size: 0.78rem;
  color: #fb923c;
  background: rgba(249,115,22,0.1);
  padding: 0.4rem 0.6rem;
  border-radius: 8px;
}

/* ── Add Form ── */
.add-form {
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 16px;
  padding: 1.2rem;
}
.form-title { font-size: 0.95rem; font-weight: 600; margin-bottom: 1rem; }
.class-selector { display: flex; gap: 0.4rem; margin-bottom: 1rem; }
.class-btn {
  flex: 1; padding: 0.5rem 0.4rem;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 10px;
  color: var(--color-text-muted);
  font-size: 0.8rem; cursor: pointer;
  transition: all 0.2s;
}
.class-btn.active {
  background: rgba(99,102,241,0.2);
  border-color: rgba(99,102,241,0.5);
  color: #a5b4fc;
}
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
.form-group { margin-bottom: 0.75rem; }
.form-group label { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.3rem; }
.form-group input[type="text"],
.form-group input[type="number"],
.form-group input[type="date"],
.form-group input {
  width: 100%;
  box-sizing: border-box;
  padding: 0.55rem 0.7rem;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 8px;
  color: white;
  font-size: 0.9rem;
}
.hint { font-size: 0.68rem; opacity: 0.6; margin-left: 4px; }

.mode-toggle {
  display: flex; gap: 0.4rem; margin-bottom: 0.4rem;
}
.mode-toggle button {
  flex: 1; padding: 0.45rem;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 8px;
  color: var(--color-text-muted);
  font-size: 0.8rem; cursor: pointer;
  transition: all 0.2s;
}
.mode-toggle button.active {
  background: rgba(99,102,241,0.2);
  border-color: rgba(99,102,241,0.5);
  color: #a5b4fc;
}
.mode-hint {
  font-size: 0.72rem; color: var(--color-text-muted);
  margin-bottom: 0.75rem; opacity: 0.8;
}
.shares-preview {
  background: rgba(99,102,241,0.08);
  border: 1px solid rgba(99,102,241,0.2);
  border-radius: 8px;
  padding: 0.45rem 0.7rem;
  font-size: 0.8rem;
  color: #a5b4fc;
  margin-bottom: 0.5rem;
}

.cost-preview {
  background: rgba(99,102,241,0.1);
  border: 1px solid rgba(99,102,241,0.25);
  border-radius: 8px;
  padding: 0.5rem 0.75rem;
  font-size: 0.82rem;
  color: #a5b4fc;
  margin-bottom: 0.75rem;
}
.save-btn {
  width: 100%; padding: 0.7rem;
  background: #6366f1; color: white;
  border: none; border-radius: 12px;
  font-size: 0.95rem; font-weight: 600;
  cursor: pointer;
}
.save-btn:hover:not(:disabled) { opacity: 0.85; }
.save-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.save-error {
  font-size: 0.8rem;
  color: #fb923c;
  background: rgba(249,115,22,0.1);
  border: 1px solid rgba(249,115,22,0.25);
  border-radius: 8px;
  padding: 0.45rem 0.7rem;
  margin-bottom: 0.6rem;
}
.form-slide-enter-active { transition: all 0.25s ease; }
.form-slide-leave-active { transition: all 0.2s ease; }
.form-slide-enter-from, .form-slide-leave-to { opacity: 0; transform: translateY(-8px); }

/* ── Holdings ── */
.holdings-list { display: flex; flex-direction: column; gap: 1rem; }
.empty-state { text-align: center; color: var(--color-text-muted); padding: 3rem 1rem; }

.class-group { display: flex; flex-direction: column; gap: 0.5rem; }
.class-header {
  display: flex; justify-content: space-between; align-items: center;
  padding: 0 0.2rem 0.2rem;
  font-size: 0.78rem; font-weight: 600; color: var(--color-text-muted);
}
.class-pct { font-size: 0.72rem; background: rgba(255,255,255,0.08); padding: 1px 8px; border-radius: 20px; }

/* ── Stock Group (wrapper for card + lots) ── */
.stock-group {
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid rgba(255,255,255,0.07);
}

/* ── Main Holding Card ── */
.holding-card {
  display: flex; align-items: center; gap: 0.75rem;
  background: rgba(255,255,255,0.03);
  padding: 0.85rem 0.75rem;
  cursor: pointer;
  transition: background 0.2s;
  user-select: none;
}
.holding-card:hover { background: rgba(255,255,255,0.07); }

.holding-icon {
  width: 38px; height: 38px;
  border-radius: 10px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  font-size: 1rem; font-weight: 800;
}
.holding-info { flex: 1; min-width: 0; }
.holding-symbol { font-weight: 700; font-size: 0.95rem; }
.holding-name { font-weight: 400; color: var(--color-text-muted); font-size: 0.85rem; }
.holding-meta {
  display: flex; align-items: center; gap: 0.25rem;
  font-size: 0.78rem; color: var(--color-text-muted); margin-top: 0.15rem;
}
.badge-qty {
  background: rgba(255,255,255,0.08);
  border-radius: 6px;
  padding: 1px 6px;
  font-size: 0.74rem;
  font-weight: 600;
  color: var(--color-text);
}
.holding-updated {
  display: flex; align-items: center; gap: 0.5rem;
  font-size: 0.68rem; color: var(--color-text-muted); opacity: 0.6; margin-top: 0.15rem;
}
.lot-count {
  background: rgba(99,102,241,0.15);
  color: #a5b4fc;
  border-radius: 6px;
  padding: 1px 6px;
  font-size: 0.66rem;
}
.separator { margin: 0 0.2rem; opacity: 0.4; }

.holding-right {
  display: flex; flex-direction: column;
  align-items: flex-end; gap: 0.15rem;
  flex-shrink: 0;
}
.holding-value { font-size: 0.95rem; font-weight: 700; }
.holding-price { font-size: 0.72rem; color: var(--color-text-muted); }
.holding-pnl { font-size: 0.8rem; font-weight: 600; }
.holding-pnl.gain { color: #10b981; }
.holding-pnl.loss { color: #ef4444; }
.pnl-pct { font-size: 0.72rem; }

/* ── Expand Arrow ── */
.expand-arrow {
  font-size: 1.2rem;
  color: var(--color-text-muted);
  opacity: 0.5;
  transition: transform 0.25s ease;
  flex-shrink: 0;
  margin-left: -0.25rem;
}
.expand-arrow.open {
  transform: rotate(90deg);
  opacity: 1;
}

/* ── Lots Panel ── */
.lots-panel {
  background: rgba(0,0,0,0.2);
  border-top: 1px solid rgba(255,255,255,0.06);
  padding: 0.6rem 0.85rem 0.75rem;
}

.lots-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.72rem;
  color: var(--color-text-muted);
  margin-bottom: 0.5rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}
.lots-sum { font-weight: 400; opacity: 0.7; }

.lot-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.45rem 0;
  border-bottom: 1px solid rgba(255,255,255,0.04);
  font-size: 0.82rem;
}
.lot-row:last-child { border-bottom: none; }

.lot-date {
  color: var(--color-text-muted);
  font-size: 0.76rem;
  min-width: 82px;
  flex-shrink: 0;
}
.lot-details {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 0.3rem;
}
.lot-qty { font-weight: 600; color: var(--color-text); }
.lot-at { opacity: 0.4; font-size: 0.72rem; }
.lot-price { color: var(--color-text-muted); }
.lot-cost {
  font-weight: 600;
  color: var(--color-text);
  font-size: 0.8rem;
  flex-shrink: 0;
}
.lot-del {
  background: transparent;
  border: 1px solid rgba(255,255,255,0.08);
  color: var(--color-text-muted);
  width: 22px; height: 22px;
  display: flex; align-items: center; justify-content: center;
  border-radius: 5px;
  font-size: 0.7rem;
  cursor: pointer;
  flex-shrink: 0;
  transition: all 0.2s;
  padding: 0;
}
.lot-del:hover { border-color: #ef4444; color: #ef4444; }

/* ── Lot Transition ── */
.lots-slide-enter-active { transition: all 0.28s ease; }
.lots-slide-leave-active { transition: all 0.2s ease; }
.lots-slide-enter-from, .lots-slide-leave-to {
  opacity: 0;
  transform: translateY(-6px);
  max-height: 0;
}

.loading-spinner {
  width: 24px;
  height: 24px;
  border: 3px solid rgba(255, 255, 255, 0.1);
  border-top: 3px solid var(--color-primary);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
</style>
