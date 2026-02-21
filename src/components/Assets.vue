<script setup>
import { ref, onMounted, onActivated, computed } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { PhBank, PhCoins, PhCreditCard, PhPlus, PhTrash, PhTrendUp, PhWallet, PhEye, PhEyeSlash } from '@phosphor-icons/vue'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { Doughnut } from 'vue-chartjs'

ChartJS.register(ArcElement, Tooltip, Legend)

const accounts = ref([])
const showAddModal = ref(false)
const isHidden = ref(true)
const togglePrivacy = () => { isHidden.value = !isHidden.value }

const isInitialDataLoaded = ref(false)

const newAccount = ref({
  name: '',
  balance: 0,
  type: 'Bank'
})
const accountTypes = ['Bank', 'Cash', 'Credit Card', 'Investment', 'Other']

// Computed: Total Assets
const totalAssets = computed(() => {
  return accounts.value.reduce((sum, acc) => sum + Number(acc.balance), 0)
})

// Computed: Grouped Accounts
const groupedAccounts = computed(() => {
  const groups = {}
  accountTypes.forEach(type => groups[type] = [])
  
  accounts.value.forEach(acc => {
    if (!groups[acc.type]) groups[acc.type] = []
    groups[acc.type].push(acc)
  })
  
  // Filter out empty groups and return array
  return Object.keys(groups)
    .filter(type => groups[type].length > 0)
    .map(type => ({
      type,
      total: groups[type].reduce((sum, acc) => sum + Number(acc.balance), 0),
      accounts: groups[type]
    }))
    .sort((a, b) => b.total - a.total) // Sort by highest value group
})

// Computed: Chart Data
const chartData = computed(() => {
  const labels = groupedAccounts.value.map(g => g.type)
  const data = groupedAccounts.value.map(g => g.total)
  
  const colors = [
    '#3b82f6', // Blue (Bank)
    '#10b981', // Emerald (Cash)
    '#f59e0b', // Amber (Credit)
    '#8b5cf6', // Violet (Invest)
    '#64748b'  // Slate (Other)
  ]

  return {
    labels,
    datasets: [{
      backgroundColor: colors,
      borderWidth: 0,
      data
    }]
  }
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '75%',
  plugins: {
    legend: { display: false }
  }
}

const fetchAccounts = async () => {
  const { data, error } = await supabase
    .from('accounts')
    .select('*')
    .order('created_at', { ascending: true })
  
  if (error) console.error('Error fetching accounts:', error)
  else accounts.value = data
  isInitialDataLoaded.value = true
}

const addAccount = async () => {
  const { data, error } = await supabase
    .from('accounts')
    .insert([newAccount.value])
    .select()

  if (error) {
    console.error('Error adding account:', error)
  } else {
    accounts.value.push(data[0])
    showAddModal.value = false
    newAccount.value = { name: '', balance: 0, type: 'Bank' }
  }
}

const deleteAccount = async (id) => {
  if (!confirm('確定要刪除此帳戶？')) return

  const { error } = await supabase
    .from('accounts')
    .delete()
    .eq('id', id)

  if (error) {
    console.error('Error deleting account:', error)
  } else {
    accounts.value = accounts.value.filter(a => a.id !== id)
  }
}

const getIcon = (type) => {
  switch (type) {
    case 'Bank': return PhBank
    case 'Cash': return PhCoins
    case 'Credit Card': return PhCreditCard
    case 'Investment': return PhTrendUp
    default: return PhWallet
  }
}

const getGroupColor = (type) => {
   switch (type) {
    case 'Bank': return '#3b82f6'
    case 'Cash': return '#10b981'
    case 'Credit Card': return '#f59e0b'
    case 'Investment': return '#8b5cf6'
    default: return '#64748b'
  }
}

onMounted(() => {
  fetchAccounts()
})

onActivated(() => {
  fetchAccounts()
})
</script>

<template>
  <div class="assets-container" v-if="isInitialDataLoaded">
    <!-- Header: Chart & Focus -->
    <div class="fixed-top">
      <div class="portfolio-card">
         <div class="card-header">
           <button class="privacy-icon-btn" @click="togglePrivacy" :title="isHidden ? '顯示金額' : '隱藏金額'">
             <component :is="isHidden ? PhEyeSlash : PhEye" size="18" />
           </button>
         </div>
         <div class="chart-wrapper">
            <Doughnut :data="chartData" :options="chartOptions" />
            <div class="chart-center-text">
              <span class="label">總資產</span>
              <span class="value" v-if="isHidden">****</span>
              <span class="value" v-else>${{ (totalAssets / 10000).toFixed(1) }}萬</span>
            </div>
         </div>

         <!-- Quick Legend -->
         <div class="legend-row">
            <div v-for="group in groupedAccounts.slice(0, 3)" :key="group.type" class="legend-item">
               <span class="dot" :style="{ background: getGroupColor(group.type) }"></span>
               <span class="l-name">{{ group.type }}</span>
               <span class="l-pct">{{ totalAssets > 0 ? Math.round((group.total / totalAssets) * 100) : 0 }}%</span>
            </div>
         </div>
      </div>

      <div class="add-asset-wrapper">
        <button class="add-asset-btn" @click="showAddModal = true">
           <PhPlus weight="bold" /> 新增資產
        </button>
      </div>
    </div>

    <!-- Scrollable List -->
    <div class="scrollable-content">
       <div class="grouped-list">
          <div v-for="group in groupedAccounts" :key="group.type" class="account-group">
             <div class="group-header">
                <span class="g-title" :style="{ color: getGroupColor(group.type) }">{{ group.type }}</span>
                <span class="g-total">{{ isHidden ? '****' : '$' + group.total.toLocaleString() }}</span>
             </div>
             
             <div class="account-cards">
                <div v-for="acc in group.accounts" :key="acc.id" class="account-card">
                   <div class="ac-icon" :style="{ background: getGroupColor(acc.type) + '20', color: getGroupColor(acc.type) }">
                      <component :is="getIcon(acc.type)" size="20" weight="duotone" />
                   </div>
                   <div class="ac-info">
                      <div class="ac-name">{{ acc.name }}</div>
                      <div class="ac-bal">{{ isHidden ? '****' : '$' + Number(acc.balance).toLocaleString() }}</div>
                   </div>
                   <button class="del-btn-mini" @click="deleteAccount(acc.id)">
                      <PhTrash size="14" />
                   </button>
                </div>
             </div>
          </div>
       </div>
    </div>

    <!-- Add Modal -->
    <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
      <div class="modal-content">
        <h3>新增帳戶</h3>
        <input v-model="newAccount.name" placeholder="名稱 (e.g. 玉山銀行)" />
        <select v-model="newAccount.type">
          <option v-for="t in accountTypes" :key="t" :value="t">{{ t }}</option>
        </select>
        <input v-model.number="newAccount.balance" type="number" placeholder="金額" />
        <div class="actions">
          <button @click="showAddModal = false">取消</button>
          <button class="primary" @click="addAccount">建立</button>
        </div>
      </div>
    </div>
  </div>
  <div class="assets-container" v-else style="display: flex; align-items: center; justify-content: center; color: var(--color-text-muted);">
    <div class="loading-spinner"></div>
    <span style="margin-left: 10px;">資料同步中...</span>
  </div>
</template>

<style scoped>
.assets-container {
  max-width: 800px;
  margin: 0 auto;
  height: 100%;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--color-bg);
}

.fixed-top {
  flex-shrink: 0;
  padding: 1rem 1rem 0.5rem 1rem;
  background: var(--color-bg);
  z-index: 10;
}

.top-actions {
  display: flex;
  justify-content: flex-start;
  margin-bottom: -1rem; /* Pull up to avoid adding extra height */
  position: relative;
  z-index: 2;
}

.privacy-icon-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s, color 0.2s;
  -webkit-tap-highlight-color: transparent;
  padding: 0 !important;
  flex: 0 0 auto;
}
.privacy-icon-btn:hover { color: var(--color-text); background: rgba(255,255,255,0.05); }
.privacy-icon-btn:active { background: rgba(255,255,255,0.1); }

/* Portfolio Circular Card */
.portfolio-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-bottom: 1.5rem;
  background: linear-gradient(135deg, rgba(59, 130, 246, 0.1) 0%, rgba(16, 185, 129, 0.05) 100%);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 18px;
  padding: 1rem 1.2rem;
  position: relative;
}

.card-header {
  width: 100%;
  display: flex;
  justify-content: flex-start;
  margin-bottom: -1rem; /* Prevent pushing the chart down */
  z-index: 2;
}

.chart-wrapper {
  position: relative;
  width: 160px;
  height: 160px;
  margin-bottom: 1rem;
}

.chart-center-text {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  pointer-events: none;
}
.chart-center-text .label {
  display: block;
  font-size: 0.8rem;
  color: var(--color-text-muted);
}
.chart-center-text .value {
  display: block;
  font-size: 1.4rem;
  font-weight: 700;
  color: var(--color-text);
  white-space: nowrap;
}

.legend-row {
  display: flex;
  gap: 1.5rem;
  justify-content: center;
}
.legend-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 0.85rem;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.l-name { color: var(--color-text-muted); }
.l-pct { font-weight: 600; color: var(--color-text); }


/* Add Asset Button */
.add-asset-wrapper {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 0.6rem;
  margin-bottom: 0.8rem;
}

.add-asset-btn {
  background: transparent;
  color: var(--color-primary);
  border: 1px solid var(--color-primary);
  border-radius: 20px;
  padding: 6px 20px;
  font-size: 0.9rem;
  font-weight: 500;
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  transition: all 0.2s;
}
.add-asset-btn:hover {
  background: rgba(59, 130, 246, 0.1);
}
.add-asset-btn:active { 
  transform: scale(0.95);
}

/* Scrollable Content */
.scrollable-content {
  flex: 1;
  overflow-y: auto;
  padding: 0 1rem 140px 1rem;
  -webkit-overflow-scrolling: touch;
}

/* Grouped List Styles */
.grouped-list {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.account-group {
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
}

.group-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.9rem;
  padding-bottom: 0.2rem;
  border-bottom: 1px solid rgba(255,255,255,0.05);
}
.g-title { font-weight: 600; }
.g-total { color: var(--color-text); opacity: 0.8; }

.account-cards {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.8rem;
}

.account-card {
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.05);
  border-radius: 16px;
  padding: 1rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  transition: transform 0.2s;
}
.account-card:active { transform: scale(0.98); }

.ac-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.ac-info {
  flex: 1;
  min-width: 0;
}
.ac-name { font-size: 0.95rem; font-weight: 500; margin-bottom: 2px; }
.ac-bal { font-size: 1.1rem; font-weight: 700; }

.del-btn-mini {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  opacity: 0.3;
  padding: 8px;
  cursor: pointer;
}
.del-btn-mini:hover { opacity: 1; color: var(--color-danger); }

/* Modal */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0,0,0,0.8);
  backdrop-filter: blur(4px);
  z-index: 2000;
  display: flex;
  align-items: center;
  justify-content: center;
}
.modal-content {
  background: #1e293b;
  width: 85%;
  max-width: 320px;
  padding: 1.5rem;
  border-radius: 20px;
  border: 1px solid rgba(255,255,255,0.1);
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
h3 { margin: 0; font-size: 1.2rem; text-align: center; }
input, select {
  padding: 12px;
  background: rgba(0,0,0,0.3);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 10px;
  color: white;
  font-size: 1rem;
}
.actions { display: flex; gap: 0.8rem; }
button {
  flex: 1;
  padding: 12px;
  border-radius: 10px;
  border: none;
  font-weight: 600;
  cursor: pointer;
}
button.primary { background: var(--color-primary); color: white; }

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
