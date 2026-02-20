<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { Doughnut } from 'vue-chartjs'
import { PhEye, PhEyeSlash } from '@phosphor-icons/vue'

ChartJS.register(ArcElement, Tooltip, Legend)

const props = defineProps({
  expenses: {
    type: Array,
    required: true,
    default: () => []
  }
})

const emit = defineEmits(['edit-expense'])

const totalIncome = ref(0)
const totalExpense = computed(() => {
  return props.expenses.reduce((sum, item) => sum + Number(item.amount), 0)
})
const totalInvestmentCost = ref(0)
const totalInvestmentValue = ref(0)
const cashBalance = computed(() => totalIncome.value - totalExpense.value - totalInvestmentCost.value)
const netWorth = computed(() => cashBalance.value + totalInvestmentValue.value)

// Privacy Mode
const isHidden = ref(false)
const togglePrivacy = () => {
  isHidden.value = !isHidden.value
}

// Timeframe Analysis
const expenseTimeframe = ref('month') // week, month, year
const expandedDate = ref('')

const fetchFinancialData = async () => {
  // Fetch Incomes
  const { data: incomes } = await supabase.from('incomes').select('amount')
  totalIncome.value = incomes?.reduce((sum, item) => sum + Number(item.amount), 0) || 0

  // Fetch Investments
  const { data: investments } = await supabase.from('investments').select('quantity, current_price')
  if (investments) {
    totalInvestmentValue.value = investments.reduce((sum, item) => sum + (Number(item.quantity) * Number(item.current_price || 0)), 0)
    totalInvestmentCost.value = totalInvestmentValue.value // simplified assumption
  }
}

const chartData = computed(() => {
  return {
    labels: ['總支出', '投資', '現金結餘'],
    datasets: [{
      backgroundColor: ['#ef4444', '#3b82f6', '#10b981'],
      data: [totalExpense.value, totalInvestmentCost.value, Math.max(0, cashBalance.value)]
    }]
  }
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false } // Hide legend for compact view
  }
}

// Filtered Expenses Logic
const filteredExpenses = computed(() => {
  const now = new Date()
  const currentMonth = now.getMonth()
  const currentYear = now.getFullYear()
  
  return props.expenses.filter(expense => {
    const expenseDate = new Date(expense.date)
    
    if (expenseTimeframe.value === 'month') {
      return expenseDate.getMonth() === currentMonth && expenseDate.getFullYear() === currentYear
    } else if (expenseTimeframe.value === 'year') {
      return expenseDate.getFullYear() === currentYear
    } else if (expenseTimeframe.value === 'week') {
      const oneWeekAgo = new Date()
      oneWeekAgo.setDate(now.getDate() - 7)
      return expenseDate >= oneWeekAgo
    }
    return true
  })
})

const filteredTotal = computed(() => {
  return filteredExpenses.value.reduce((sum, item) => sum + Number(item.amount), 0)
})

// Group by Date for the list
const expensesByDate = computed(() => {
  const groups = {}
  filteredExpenses.value.forEach(expense => {
    if (!groups[expense.date]) {
      groups[expense.date] = { total: 0, items: [] }
    }
    groups[expense.date].total += Number(expense.amount)
    groups[expense.date].items.push(expense)
  })
  // Sort by date desc
  return Object.keys(groups).sort((a, b) => new Date(b) - new Date(a)).map(date => ({
    date,
    total: groups[date].total,
    items: groups[date].items
  }))
})

const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', {
    style: 'currency',
    currency: 'TWD',
    minimumFractionDigits: 0
  }).format(amount)
}

const formatDate = (dateString) => {
  const options = { year: 'numeric', month: 'long', day: 'numeric' }
  return new Date(dateString).toLocaleDateString('zh-TW', options)
}

const toggleExpand = (date) => {
  if (expandedDate.value === date) {
    expandedDate.value = ''
  } else {
    expandedDate.value = date
  }
}

const setTimeframe = (frame) => {
  expenseTimeframe.value = frame
}

onMounted(() => {
  fetchFinancialData()
})
</script>

<template>
  <div class="dashboard-container">
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
          <!-- Mini Chart -->
          <div class="mini-chart">
             <Doughnut :data="chartData" :options="chartOptions" />
          </div>
        </div>
        
        <div class="stats-row">
          <div class="stat-item">
            <label>收入</label>
            <div class="val income">{{ isHidden ? '****' : '+' + formatCurrency(totalIncome) }}</div>
          </div>
          <div class="stat-item">
            <label>支出</label>
            <div class="val expense">{{ isHidden ? '****' : '-' + formatCurrency(totalExpense) }}</div>
          </div>
          <div class="stat-item">
            <label>投資</label>
            <div class="val invest">{{ isHidden ? '****' : formatCurrency(totalInvestmentValue) }}</div>
          </div>
          <div class="stat-item">
            <label>現金</label>
            <div class="val cash">{{ isHidden ? '****' : formatCurrency(cashBalance) }}</div>
          </div>
        </div>
      </div>

      <!-- Analysis Controls -->
      <div class="analysis-controls">
        <div class="segmented-control">
          <button @click="setTimeframe('week')" :class="{ active: expenseTimeframe === 'week' }">週</button>
          <button @click="setTimeframe('month')" :class="{ active: expenseTimeframe === 'month' }">月</button>
          <button @click="setTimeframe('year')" :class="{ active: expenseTimeframe === 'year' }">年</button>
        </div>
      </div>
       <div class="period-total">
          <span>總計:</span>
          <span class="total-val">{{ formatCurrency(filteredTotal) }}</span>
        </div>
    </div>

    <!-- List Section -->
    <div class="analysis-card card">
      <div class="details-list">
        <div v-if="expensesByDate.length === 0" class="empty-state">
          無支出紀錄
        </div>
        <div v-for="group in expensesByDate" :key="group.date" class="date-group">
          <div class="group-header" @click="toggleExpand(group.date)">
            <span class="date-label">{{ formatDate(group.date) }}</span>
            <div class="group-right">
              <span class="group-total">{{ formatCurrency(group.total) }}</span>
              <span class="arrow" :class="{ rotated: expandedDate === group.date }">▼</span>
            </div>
          </div>
          
          <div v-show="expandedDate === group.date" class="group-items">
            <div v-for="item in group.items" :key="item.id" class="detail-item">
              <div style="flex: 1; display:flex; align-items: center; gap: 0.5rem; overflow: hidden;">
                <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{ item.title }}</span>
                <span class="cat-tag">{{ item.category }}</span>
              </div>
              <div style="display: flex; align-items: center; gap: 0.5rem;">
                <span class="detail-amount">{{ formatCurrency(item.amount) }}</span>
                <button @click="emit('edit-expense', item)" class="edit-btn-small">✎</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
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
  padding: 0 1rem 100px 1rem; /* Combined padding including bottom for nav */
  position: relative;
  -webkit-overflow-scrolling: touch;
}

/* Header Section */
.dashboard-header {
  flex-shrink: 0;
  margin-bottom: 1rem;
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
  align-items: center;
  margin-bottom: 1rem;
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
  padding: 4px;
  display: flex;
  align-items: center;
}
.privacy-btn:hover { color: var(--color-text); }

.mini-chart {
  width: 60px;
  height: 60px;
  pointer-events: none; 
  overflow: hidden; 
}

.stats-row {
  display: flex;
  justify-content: space-between;
  border-top: 1px solid rgba(255,255,255,0.1);
  padding-top: 0.8rem;
}

.stat-item { text-align: center; }
.stat-item label { display: block; color: var(--color-text-muted); font-size: 0.75rem; margin-bottom: 0.1rem; }
.stat-item .val { font-size: 0.9rem; font-weight: 500; }
.income { color: var(--color-success); }
.expense { color: var(--color-danger); }
.invest { color: var(--color-primary); }
.cash { color: var(--color-text); }


/* Analysis Controls */
.analysis-controls {
  margin-bottom: 1rem;
  padding: 0 0.5rem;
}

.segmented-control {
  display: flex;
  background: rgba(255, 255, 255, 0.1);
  padding: 4px;
  border-radius: 12px;
}

.segmented-control button {
  flex: 1;
  padding: 8px 0;
  font-size: 0.9rem;
  background: transparent;
  border: none;
  border-radius: 8px;
  color: var(--color-text-muted);
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: 500;
}

.segmented-control button.active {
  background: var(--color-bg); /* Use page background or a solid color */
  color: var(--color-text);
  box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}

.period-total {
  text-align: left;
  margin-bottom: 0.5rem; 
  font-size: 0.9rem;
  padding: 0 0.5rem;
  color: var(--color-text-muted);
}
.total-val { margin-left: 0.5rem; font-weight: bold; color: var(--color-danger); font-size: 1rem; }


/* List Section */
.analysis-card {
  padding: 0;
  background: transparent;
  border: none;
}

.details-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.group-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.8rem;
  background: rgba(255,255,255,0.05);
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.2s;
}
.group-header:hover { background: rgba(255,255,255,0.08); }

.group-right { display: flex; align-items: center; gap: 0.5rem; }
.group-total { font-weight: bold; font-size: 0.95rem; }
.arrow { font-size: 0.7rem; color: var(--color-text-muted); transition: transform 0.3s; }
.arrow.rotated { transform: rotate(180deg); }

.group-items {
  background: rgba(0,0,0,0.2);
  border-radius: 0 0 8px 8px;
  overflow: hidden;
  margin-top: -4px;
}
.detail-item {
  display: flex;
  justify-content: space-between;
  padding: 0.8rem 1rem;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  font-size: 0.9rem;
  color: var(--color-text-muted);
}
.detail-item:last-child { border-bottom: none; }
.detail-amount { color: var(--color-text); font-weight: 500;}

.cat-tag {
  font-size: 0.7rem;
  background: rgba(255,255,255,0.1);
  padding: 1px 5px;
  border-radius: 4px;
}

.edit-btn-small {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  font-size: 0.8rem;
  padding: 2px;
  cursor: pointer;
}
.edit-btn-small:hover {
  color: var(--color-accent);
}

.empty-state { text-align: center; color: var(--color-text-muted); padding: 1rem; }
</style>
