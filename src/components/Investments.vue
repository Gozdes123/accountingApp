<script setup>
import { ref, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { Pie } from 'vue-chartjs'

ChartJS.register(ArcElement, Tooltip, Legend)

const investments = ref([])
const showAddModal = ref(false)
const newInv = ref({ 
  symbol: '', 
  type: 'Stock', 
  quantity: '', 
  average_cost: '', 
  current_price: '' 
})

const fetchInvestments = async () => {
  const { data, error } = await supabase
    .from('investments')
    .select('*')
    .order('created_at', { ascending: false })
  
  if (error) console.error('Error fetching investments:', error)
  else investments.value = data
}

const addInvestment = async () => {
  if (!newInv.value.symbol || !newInv.value.quantity) return
  
  const { data, error } = await supabase
    .from('investments')
    .insert([newInv.value])
    .select()

  if (error) {
    console.error('Error adding investment:', error)
  } else {
    investments.value.unshift(data[0])
    showAddModal.value = false
    newInv.value = { symbol: '', type: 'Stock', quantity: '', average_cost: '', current_price: '' }
  }
}

const deleteInvestment = async (id) => {
  const { error } = await supabase
    .from('investments')
    .delete()
    .eq('id', id)
  
  if (!error) {
    investments.value = investments.value.filter(i => i.id !== id)
  }
}

const totalPortfolioValue = computed(() => {
  return investments.value.reduce((sum, inv) => {
    return sum + (Number(inv.quantity) * Number(inv.current_price || 0))
  }, 0)
})

const chartData = computed(() => {
  const labels = investments.value.map(inv => inv.symbol)
  const data = investments.value.map(inv => Number(inv.quantity) * Number(inv.current_price || 0))
  
  return {
    labels,
    datasets: [{
      backgroundColor: ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#6366f1'],
      data
    }]
  }
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      position: 'bottom',
      labels: { color: '#94a3b8' }
    }
  }
}

const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', {
    style: 'currency',
    currency: 'TWD',
    minimumFractionDigits: 0
  }).format(amount)
}
const formatUSD = (amount) => {
   return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2
  }).format(amount)
}

onMounted(() => {
  fetchInvestments()
})
</script>

<template>
  <div class="investments-container">
    <div class="summary-card card">
      <h2>📈 投資組合</h2>
      <div class="total-value">
        <span>總市值 (估算)</span>
        <div class="amount">{{ formatCurrency(totalPortfolioValue) }}</div>
      </div>
      
      <div v-if="investments.length > 0" class="chart-container">
        <Pie :data="chartData" :options="chartOptions" />
      </div>

      <button @click="showAddModal = !showAddModal" class="add-btn mt-4">
        {{ showAddModal ? '取消' : '+ 新增投資' }}
      </button>
    </div>

    <!-- Add Form -->
    <div v-if="showAddModal" class="add-form card">
      <div class="form-row">
        <div class="form-group flex-1">
          <label>代號 (Symbol)</label>
          <input v-model="newInv.symbol" placeholder="例如: 2330 / AAPL / BTC" />
        </div>
        <div class="form-group flex-1">
          <label>類型</label>
          <select v-model="newInv.type">
            <option value="Stock">股票</option>
            <option value="Crypto">加密貨幣</option>
          </select>
        </div>
      </div>
      <div class="form-row">
        <div class="form-group flex-1">
          <label>持有數量</label>
          <input v-model="newInv.quantity" type="number" placeholder="0" step="0.0001" />
        </div>
        <div class="form-group flex-1">
          <label>當前價格 (TWD/USD)</label>
          <input v-model="newInv.current_price" type="number" placeholder="單價" step="0.01" />
        </div>
      </div>
      <div class="form-group">
        <label>平均成本 (可選)</label>
        <input v-model="newInv.average_cost" type="number" placeholder="0" step="0.01" />
      </div>
      
      <button @click="addInvestment" class="w-full">儲存</button>
    </div>

    <!-- List Wrapper -->
    <div class="list-wrapper">
      <div class="inv-list card">
        <div v-if="investments.length === 0" class="empty-state">
          沒有投資項目
        </div>
        <div v-for="inv in investments" :key="inv.id" class="inv-item">
          <div class="inv-info">
            <div class="inv-symbol">
              {{ inv.symbol }}
              <span class="inv-type">{{ inv.type === 'Stock' ? '股票' : '幣' }}</span>
            </div>
            <div class="inv-meta">
              {{ inv.quantity }} 股/顆 · 現價 {{ formatUSD(inv.current_price) }}
            </div>
          </div>
          <div class="inv-value">
            {{ formatCurrency(inv.quantity * inv.current_price) }}
            <button @click="deleteInvestment(inv.id)" class="delete-btn">×</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.investments-container {
  max-width: 600px;
  margin: 0 auto;
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 1rem;
  overflow: hidden;
}

.list-wrapper {
  flex: 1;
  overflow-y: auto;
  padding-bottom: 80px;
  -webkit-overflow-scrolling: touch;
  margin-top: 1rem;
}

.summary-card {
  text-align: center;
  margin-bottom: 0;
  flex-shrink: 0;
  padding: 1.5rem;
  border-radius: 16px;
}

.total-value {
  margin: 1rem 0;
}
.total-value span { color: var(--color-text-muted); font-size: 0.9rem; }
.total-value .amount { font-size: 2.5rem; font-weight: bold; color: var(--color-accent); margin-top: 0.5rem; }

.chart-container {
  height: 250px;
  margin: 1rem 0;
}

.add-btn {
  background: rgba(255,255,255,0.1);
  border: 1px solid rgba(255,255,255,0.2);
}

.add-form { margin-bottom: 1rem; }
.form-row { display: flex; gap: 1rem; }
.flex-1 { flex: 1; }

.form-group { margin-bottom: 1rem; }
.form-group label { display: block; margin-bottom: 0.4rem; color: var(--color-text-muted); font-size: 0.9rem; }

.inv-item {
  display: flex; justify-content: space-between; align-items: center;
  padding: 1rem; border-bottom: 1px solid rgba(255,255,255,0.1);
}
.inv-item:last-child { border-bottom: none; }

.inv-symbol { font-weight: bold; font-size: 1.1rem; }
.inv-type { font-size: 0.7rem; background: rgba(255,255,255,0.1); padding: 2px 6px; border-radius: 4px; margin-left: 0.5rem; font-weight: normal; color: var(--color-text-muted); }
.inv-meta { font-size: 0.85rem; color: var(--color-text-muted); margin-top: 0.2rem; }

.inv-value { font-weight: bold; display: flex; align-items: center; gap: 1rem; }

.delete-btn { background: transparent; color: var(--color-text-muted); border: 1px solid rgba(255,255,255,0.2); padding: 0.2rem 0.6rem; font-size: 1rem; }
.delete-btn:hover { border-color: var(--color-danger); color: var(--color-danger); }

.empty-state { text-align: center; color: var(--color-text-muted); padding: 2rem; }
</style>
