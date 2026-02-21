<script setup>
import { ref, onMounted, onActivated, computed, watch } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { Chart as ChartJS, ArcElement, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Title } from 'chart.js'
import { Doughnut, Line } from 'vue-chartjs'
import { PhEye, PhEyeSlash, PhTrendUp, PhTrendDown } from '@phosphor-icons/vue'

ChartJS.register(ArcElement, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Title)

const props = defineProps({
  expenses: {
    type: Array,
    required: true,
    default: () => []
  },
  incomes: {
    type: Array,
    required: true,
    default: () => []
  }
})

const emit = defineEmits(['edit-expense'])

const totalIncome = computed(() => {
  return props.incomes.reduce((sum, item) => sum + Number(item.amount), 0)
})
const totalExpense = computed(() => {
  return props.expenses.reduce((sum, item) => sum + Number(item.amount), 0)
})
const totalInvestmentValue = ref(0)
const totalAssets = ref(0)
const usdTwdRate = ref(32)

// 淨資產 = 帳戶資產 + 投資市值 + 現金流（收入 - 支出）
const cashBalance = computed(() => totalIncome.value - totalExpense.value)
const netWorth = computed(() => totalAssets.value + cashBalance.value + totalInvestmentValue.value)

// Privacy Mode
const isHidden = ref(true)
const togglePrivacy = () => {
  isHidden.value = !isHidden.value
}

// Timeframe Analysis


const isInitialDataLoaded = ref(false)

const fetchFinancialData = async () => {
  // 1. 抓 USD/TWD 匯率
  try {
    const res = await fetch('https://api.exchangerate-api.com/v4/latest/USD')
    const rateData = await res.json()
    usdTwdRate.value = rateData.rates?.TWD ?? 32
  } catch {
    usdTwdRate.value = 32
  }

  // 2. 抓投資資料，依幣別換算成 TWD
  const { data: investments } = await supabase
    .from('investments')
    .select('quantity, current_price, currency, asset_class, buy_price, average_cost, buy_date, created_at')

  if (investments) {
    totalInvestmentValue.value = investments.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const price = Number(item.current_price || 0)
      const raw = qty * price
      const currency = item.currency || (item.asset_class === 'us_stock' ? 'USD' : 'TWD')
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)

    // 建立每月投入金額 map（用於半年走勢圖）
    // key: 'YYYY-M'
    monthlyInvestMap.value = {}
    for (const item of investments) {
      const dateStr = item.buy_date || item.created_at?.split('T')[0]
      if (!dateStr) continue
      const d = new Date(dateStr)
      const key = `${d.getFullYear()}-${d.getMonth()}`
      const qty = Number(item.quantity || 0)
      const buyPrice = Number(item.buy_price ?? item.average_cost ?? 0)
      const cost = qty * buyPrice
      const currency = item.currency || (item.asset_class === 'us_stock' ? 'USD' : 'TWD')
      const costTwd = currency === 'USD' ? cost * usdTwdRate.value : cost
      monthlyInvestMap.value[key] = (monthlyInvestMap.value[key] || 0) + costTwd
    }
  }

  // 3. 抓帳戶餘額
  const { data: accounts } = await supabase.from('accounts').select('balance')
  if (accounts) {
    totalAssets.value = accounts.reduce((sum, item) => sum + Number(item.balance), 0)
  }

  isInitialDataLoaded.value = true
}

// 每月投入金額 map（key: 'YYYY-M'）
const monthlyInvestMap = ref({})

// 圓餅圖：帳戶資產 / 投資組合 / 現金流（收入-支出）
const chartData = computed(() => {
  const inv = totalInvestmentValue.value
  const assets = totalAssets.value
  const flow = cashBalance.value  // 收入-支出

  const hasData = inv > 0 || assets > 0 || flow !== 0
  if (!hasData) {
    return {
      labels: ['無資料'],
      datasets: [{ backgroundColor: ['#334155'], data: [1], borderWidth: 0 }]
    }
  }

  const labels = []
  const data = []
  const colors = []

  if (assets > 0) { labels.push('帳戶資產'); data.push(assets); colors.push('#3b82f6') }
  if (inv > 0)    { labels.push('投資組合'); data.push(inv);    colors.push('#8b5cf6') }
  if (flow > 0)   { labels.push('現金流'); data.push(flow);   colors.push('#10b981') }
  // 支出超過收入時顯示貕字
  if (flow < 0)   { labels.push('收支赤字'); data.push(Math.abs(flow)); colors.push('#ef4444') }

  return {
    labels,
    datasets: [{
      backgroundColor: colors,
      data,
      borderWidth: 0,
      hoverOffset: 4
    }]
  }
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '65%',
  plugins: {
    legend: {
      display: true,
      position: 'right',
      labels: {
        color: '#9ca3af',
        usePointStyle: true,
        pointStyleWidth: 8,
        font: { size: 10 },
        padding: 8,
        boxWidth: 8
      }
    },
    tooltip: {
      callbacks: {
        label: (ctx) => ` ${ctx.label}: ${formatCurrency(ctx.parsed)}`
      }
    }
  }
}

// Filtered Transactions Logic


const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', {
    style: 'currency',
    currency: 'TWD',
    minimumFractionDigits: 0
  }).format(amount)
}

// --- Consumption Analysis (Category Breakdown) ---
const categoryColors = {
  'Food': '#fbbf24',
  'Transport': '#60a5fa',
  'Utilities': '#f87171',
  'Entertainment': '#a78bfa',
  'Health': '#34d399',
  'Shopping': '#ec4899',
  'Other': '#9ca3af',
  'Salary': '#34d399',
  'Bonus': '#fbbf24',
  'Investment': '#60a5fa',
  'Gift': '#ec4899',
  'Subscription': '#818cf8'
}

const categoryLabels = {
  'Food': '餐飲',
  'Transport': '交通',
  'Utilities': '水電',
  'Entertainment': '娛樂',
  'Health': '醫療',
  'Shopping': '購物',
  'Other': '其他',
  'Salary': '薪資',
  'Bonus': '獎金',
  'Investment': '投資',
  'Gift': '禮金',
  'Subscription': '訂閱'
}

const consumptionChartData = computed(() => {
  const currentMonthExpenses = props.expenses.filter(e => {
    const d = new Date(e.date)
    const now = new Date()
    return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
  })

  const categoryTotals = {}
  currentMonthExpenses.forEach(exp => {
    const cat = exp.category || 'Other'
    categoryTotals[cat] = (categoryTotals[cat] || 0) + Number(exp.amount)
  })

  const labels = Object.keys(categoryTotals).map(cat => categoryLabels[cat] || cat)
  const data = Object.values(categoryTotals)
  const backgroundColors = Object.keys(categoryTotals).map(cat => categoryColors[cat] || categoryColors['Other'])

  if (labels.length === 0) {
     return {
        labels: ['無資料'],
        datasets: [{ data: [1], backgroundColor: ['#334155'] }] // Placeholder
     }
  }

  return {
    labels,
    datasets: [{
      backgroundColor: backgroundColors,
      data,
      borderWidth: 0,
      hoverOffset: 4
    }]
  }
})

const consumptionChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '70%',
  plugins: {
    legend: {
      position: 'right',
      labels: {
        color: '#9ca3af',
        font: { size: 12 },
        usePointStyle: true,
        padding: 15
      }
    },
    tooltip: {
      callbacks: {
        label: function(context) {
          let label = context.label || '';
          if (label) { label += ': '; }
          if (context.parsed !== null) { label += formatCurrency(context.parsed); }
          return label;
        }
      }
    }
  }
}

// --- Trend Analysis (Month over Month) ---
const trendData = computed(() => {
  const now = new Date()
  const thisMonth = now.getMonth()
  const thisYear = now.getFullYear()
  
  // Handle January wrap-around
  const lastMonth = thisMonth === 0 ? 11 : thisMonth - 1
  const lastMonthYear = thisMonth === 0 ? thisYear - 1 : thisYear

  let thisMonthInc = 0, thisMonthExp = 0
  let lastMonthInc = 0, lastMonthExp = 0

  props.incomes.forEach(i => {
    const d = new Date(i.date)
    if (d.getMonth() === thisMonth && d.getFullYear() === thisYear) thisMonthInc += Number(i.amount)
    if (d.getMonth() === lastMonth && d.getFullYear() === lastMonthYear) lastMonthInc += Number(i.amount)
  })

  props.expenses.forEach(e => {
    const d = new Date(e.date)
    if (d.getMonth() === thisMonth && d.getFullYear() === thisYear) thisMonthExp += Number(e.amount)
    if (d.getMonth() === lastMonth && d.getFullYear() === lastMonthYear) lastMonthExp += Number(e.amount)
  })

  const incGrowth = lastMonthInc === 0 ? 100 : ((thisMonthInc - lastMonthInc) / lastMonthInc) * 100
  const expGrowth = lastMonthExp === 0 ? 100 : ((thisMonthExp - lastMonthExp) / lastMonthExp) * 100
  
  const thisMonthNet = thisMonthInc - thisMonthExp
  const lastMonthNet = lastMonthInc - lastMonthExp
  // Absolute difference for net worth
  const netDiff = thisMonthNet - lastMonthNet

  return {
    thisMonthInc, thisMonthExp, thisMonthNet,
    lastMonthInc, lastMonthExp, lastMonthNet,
    incGrowth: isFinite(incGrowth) ? Number(incGrowth.toFixed(1)) : 0,
    expGrowth: isFinite(expGrowth) ? Number(expGrowth.toFixed(1)) : 0,
    netDiff
  }
})

// --- 6-Month Historical Trend Chart ---
const monthlyTrendData = computed(() => {
  const months = []
  const incomeData = []
  const expenseData = []
  const investData = []

  const now = new Date()

  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const monthLabel = `${d.getMonth() + 1}月`
    months.push(monthLabel)

    const mInc = props.incomes.filter(inc => {
      const incDate = new Date(inc.date)
      return incDate.getMonth() === d.getMonth() && incDate.getFullYear() === d.getFullYear()
    }).reduce((sum, item) => sum + Number(item.amount), 0)

    const mExp = props.expenses.filter(exp => {
      const expDate = new Date(exp.date)
      return expDate.getMonth() === d.getMonth() && expDate.getFullYear() === d.getFullYear()
    }).reduce((sum, item) => sum + Number(item.amount), 0)

    // 投資：从 monthlyInvestMap 取該月投入資金
    const key = `${d.getFullYear()}-${d.getMonth()}`
    const mInvest = monthlyInvestMap.value[key] || 0

    incomeData.push(mInc)
    expenseData.push(mExp)
    investData.push(mInvest)
  }

  return {
    labels: months,
    datasets: [
      {
        label: '收入',
        data: incomeData,
        borderColor: '#10b981',
        backgroundColor: 'rgba(16, 185, 129, 0.1)',
        tension: 0.4,
        borderWidth: 2,
        pointRadius: 3
      },
      {
        label: '支出',
        data: expenseData,
        borderColor: '#ef4444',
        backgroundColor: 'rgba(239, 68, 68, 0.1)',
        tension: 0.4,
        borderWidth: 2,
        pointRadius: 3
      },
      {
        label: '投入投資',
        data: investData,
        borderColor: '#8b5cf6',
        backgroundColor: 'rgba(139, 92, 246, 0.1)',
        tension: 0.4,
        borderWidth: 2,
        pointRadius: 3
      }
    ]
  }
})

const trendChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: {
    mode: 'index',
    intersect: false,
  },
  plugins: {
    legend: {
      position: 'top',
      labels: {
        color: '#9ca3af',
        usePointStyle: true,
        boxWidth: 8
      }
    },
    tooltip: {
      callbacks: {
        label: function(context) {
          return `${context.dataset.label}: ${formatCurrency(context.parsed.y)}`
        }
      }
    }
  },
  scales: {
    y: {
      display: false, // Hide Y axis labels for cleaner look
      beginAtZero: true
    },
    x: {
      grid: {
        color: 'rgba(255,255,255,0.05)',
        drawBorder: false
      },
      ticks: {
        color: '#9ca3af' // Muted text color
      }
    }
  }
}



onMounted(() => {
  fetchFinancialData()
})

onActivated(() => {
  fetchFinancialData()
})
</script>

<template>
  <div class="dashboard-container" v-if="isInitialDataLoaded">
    <!-- Header Section -->
    <div class="dashboard-header">
      <div class="summary-card card-gradient">
        <div class="summary-header">
           <div class="net-worth-compact">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span class="label">總資產</span>
              <button @click="togglePrivacy" class="privacy-btn">
                <component :is="isHidden ? PhEyeSlash : PhEye" size="16" />
              </button>
            </div>
            <div class="amount">{{ isHidden ? '****' : formatCurrency(netWorth) }}</div>
           </div>
        </div>

        <!-- Allocation Chart - 獨立一行，有足夠空間顯示 legend -->
        <div class="chart-row">
          <div class="alloc-chart-wrap">
            <Doughnut :data="chartData" :options="chartOptions" />
          </div>
        </div>

        <div class="stats-row">
          <div class="stat-item">
            <label>💚 收入</label>
            <div class="val income">{{ isHidden ? '****' : '+' + formatCurrency(totalIncome) }}</div>
          </div>
          <div class="stat-item">
            <label>❤️ 支出</label>
            <div class="val expense">{{ isHidden ? '****' : '-' + formatCurrency(totalExpense) }}</div>
          </div>
          <div class="stat-item">
            <label>💜 投資組合</label>
            <div class="val invest">{{ isHidden ? '****' : formatCurrency(totalInvestmentValue) }}</div>
          </div>
          <div class="stat-item">
            <label>💙 帳戶資產</label>
            <div class="val assets">{{ isHidden ? '****' : formatCurrency(totalAssets) }}</div>
          </div>
        </div>
      </div>


    </div>

    <!-- Analytics Section -->
    <div class="analytics-section">
      <!-- Trend Chart Card -->
      <div class="card analysis-card trend-card">
        <h3>收支趨勢 (本月 vs 上月)</h3>
        <div class="trend-grid">
          <div class="trend-item">
            <span class="trend-label">淨結餘變化</span>
            <div class="trend-val" :class="trendData.netDiff >= 0 ? 'success-text' : 'danger-text'">
              {{ trendData.netDiff >= 0 ? '+' : '' }}{{ formatCurrency(trendData.netDiff) }}
              <component :is="trendData.netDiff >= 0 ? PhTrendUp : PhTrendDown" size="16"/>
            </div>
            <div class="trend-subtext">本月結餘 {{ formatCurrency(trendData.thisMonthNet) }}</div>
          </div>
          <div class="trend-item compact-trends">
             <div class="sub-trend">
               <span>支出 <span :class="trendData.expGrowth > 0 ? 'danger-text' : 'success-text'"><component :is="trendData.expGrowth > 0 ? PhTrendUp : PhTrendDown" size="12" style="vertical-align: middle;"/> {{ Math.abs(trendData.expGrowth) }}%</span></span>
             </div>
             <div class="sub-trend">
               <span>收入 <span :class="trendData.incGrowth > 0 ? 'success-text' : 'danger-text'"><component :is="trendData.incGrowth > 0 ? PhTrendUp : PhTrendDown" size="12" style="vertical-align: middle;"/> {{ Math.abs(trendData.incGrowth) }}%</span></span>
             </div>
          </div>
        </div>
        
        <!-- Line Chart -->
        <h4 style="margin: 1.5rem 0 0.5rem 0; font-size: 0.9rem; color: var(--color-text-muted); font-weight: normal;">近半年走勢</h4>
        <div class="chart-container" style="height: 180px; width: 100%;">
           <Line :data="monthlyTrendData" :options="trendChartOptions" />
        </div>
      </div>

      <!-- Consumption Analysis Card -->
      <div class="card analysis-card consumption-card">
        <h3>本月消費分析</h3>
        <div class="chart-container large-chart">
           <Doughnut :data="consumptionChartData" :options="consumptionChartOptions" v-if="consumptionChartData.labels[0] !== '無資料'" />
           <div v-else class="empty-state" style="height: 150px; display: flex; align-items: center; justify-content: center;">尚無消費紀錄</div>
        </div>
      </div>
    </div>
  </div>
  <div class="dashboard-container" v-else style="display: flex; align-items: center; justify-content: center; color: var(--color-text-muted);">
    <div class="loading-spinner"></div>
    <span style="margin-left: 10px;">資料同步中...</span>
  </div>
</template>

<style scoped>
.dashboard-container {
  max-width: 800px;
  margin: 0 auto;
  height: 100%;
  display: flex;
  flex-direction: column;
  overflow-y: auto; 
  padding: 0 1rem 140px 1rem; /* Combined padding including bottom for nav */
  position: relative;
  -webkit-overflow-scrolling: touch;
}

/* Header Section */
.dashboard-header {
  flex-shrink: 0;
}

.summary-card {
  padding: 1rem;
  margin-bottom: 0.8rem;
}
.card-gradient {
  background: linear-gradient(145deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.02) 100%);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px;
}

.summary-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 0.8rem;
}

.net-worth-compact {
  text-align: left;
}
.net-worth-compact .label { color: var(--color-text-muted); font-size: 0.85rem; }
.net-worth-compact .amount { font-size: 1.8rem; font-weight: bold; color: var(--color-text); line-height: 1.2; margin-top: 0.2rem; }

.privacy-btn {
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
.privacy-btn:hover { color: var(--color-text); }

/* 圓餅圖獨立一行 */
.chart-row {
  width: 100%;
  margin-bottom: 0.8rem;
}
.alloc-chart-wrap {
  height: 140px;
  width: 100%;
}

.stats-row {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  border-top: 1px solid rgba(255,255,255,0.1);
  padding-top: 0.8rem;
  gap: 0.5rem 0;
}

.stat-item { text-align: center; flex: 1 0 22%; }
.stat-item label { display: block; color: var(--color-text-muted); font-size: 0.68rem; margin-bottom: 0.1rem; white-space: nowrap; }
.stat-item .val { font-size: 0.8rem; font-weight: 600; }
.income { color: var(--color-success); }
.expense { color: var(--color-danger); }
.invest { color: #8b5cf6; }
.assets { color: #3b82f6; }
.cash { color: var(--color-text); }


.success-text { color: var(--color-success); }
.danger-text { color: var(--color-danger); }

/* Analytics Section */
.analytics-section {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin-bottom: 1rem;
}

.analysis-card {
  padding: 1.2rem;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 16px;
}

.analysis-card h3 {
  margin: 0 0 1rem 0;
  font-size: 1rem;
  color: var(--color-text);
  font-weight: 600;
}

/* Trend Card */
.trend-grid {
  display: flex;
  gap: 1rem;
  align-items: center;
}

.trend-item {
  flex: 1;
}

.trend-label {
  display: block;
  font-size: 0.8rem;
  color: var(--color-text-muted);
  margin-bottom: 0.3rem;
  white-space: nowrap;
}

.trend-val {
  font-size: 1.4rem;
  font-weight: bold;
  display: flex;
  align-items: center;
  gap: 0.3rem;
  margin-bottom: 0.2rem;
  white-space: nowrap;
}

.trend-subtext {
  font-size: 0.75rem;
  color: var(--color-text-muted);
  white-space: nowrap;
}

.compact-trends {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  border-left: 1px solid rgba(255,255,255,0.1);
  padding-left: 1rem;
}

.sub-trend {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  white-space: nowrap;
  display: flex;
  align-items: center;
}

.large-chart {
  position: relative;
  height: 200px;
  width: 100%;
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
