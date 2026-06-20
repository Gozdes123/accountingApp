<script setup>
import { ref, onMounted, onActivated, computed } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { PhBank, PhCoins, PhCreditCard, PhPlus, PhTrash, PhTrendUp, PhWallet, PhEye, PhEyeSlash, PhShieldWarning } from '@phosphor-icons/vue'
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
  balance: '',
  type: 'Bank'
})

const accountTypes = ['Bank', 'Cash', 'Credit Card', 'Investment', 'Liability', 'Other']

const translateType = (type) => {
  switch (type) {
    case 'Bank': return '銀行存款'
    case 'Cash': return '現金'
    case 'Credit Card': return '信用卡'
    case 'Investment': return '證券帳戶'
    case 'Liability': return '借款負債'
    default: return '其他資產'
  }
}

// 分類資產與負債
const assetAccounts = computed(() => accounts.value.filter(a => a.type !== 'Credit Card' && a.type !== 'Liability'))
const liabilityAccounts = computed(() => accounts.value.filter(a => a.type === 'Credit Card' || a.type === 'Liability'))

// 淨帳戶資產 = 資產小計 - 負債小計
const totalNetAssets = computed(() => {
  const assetsSum = assetAccounts.value.reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
  const liabsSum = liabilityAccounts.value.reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
  return assetsSum - liabsSum
})

// Doughnut chart showing allocation grouped by types
const chartData = computed(() => {
  const typesMap = {}
  accounts.value.forEach(acc => {
    // 儲存為正值以利圓環圖渲染
    typesMap[acc.type] = (typesMap[acc.type] || 0) + Math.abs(Number(acc.balance))
  })
  
  const entries = Object.entries(typesMap).filter(([, v]) => v > 0)
  const labels = entries.map(([k]) => translateType(k))
  const data = entries.map(([, v]) => v)
  const colors = entries.map(([k]) => getGroupColor(k))

  if (labels.length === 0) {
    return {
      labels: ['無資料'],
      datasets: [{ backgroundColor: ['#1e293b'], data: [1], borderWidth: 0 }]
    }
  }

  return {
    labels,
    datasets: [{
      backgroundColor: colors,
      borderWidth: 2,
      borderColor: '#070913',
      data
    }]
  }
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '80%',
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
  if (!newAccount.value.name) return
  const balanceVal = Math.abs(Number(newAccount.value.balance || 0))
  
  const { data, error } = await supabase
    .from('accounts')
    .insert([{
      name: newAccount.value.name,
      type: newAccount.value.type,
      balance: balanceVal
    }])
    .select()

  if (error) {
    console.error('Error adding account:', error)
  } else {
    accounts.value.push(data[0])
    showAddModal.value = false
    newAccount.value = { name: '', balance: '', type: 'Bank' }
  }
}

const deleteAccount = async (id) => {
  if (!confirm('確定要刪除此項目？')) return

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
    case 'Liability': return PhShieldWarning
    default: return PhWallet
  }
}

const getGroupColor = (type) => {
   switch (type) {
    case 'Bank': return '#3b82f6'         // Blue
    case 'Cash': return '#10b981'         // Emerald
    case 'Credit Card': return '#f43f5e'  // Crimson Red
    case 'Investment': return '#8b5cf6'   // Purple
    case 'Liability': return '#e11d48'    // Deep Red
    default: return '#64748b'            // Slate
  }
}

const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', {
    style: 'currency',
    currency: 'TWD',
    minimumFractionDigits: 0
  }).format(amount)
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
      <div class="portfolio-card card-gradient">
         <div class="card-header">
           <button class="privacy-icon-btn" @click="togglePrivacy" :title="isHidden ? '顯示金額' : '隱藏金額'">
             <component :is="isHidden ? PhEyeSlash : PhEye" size="16" />
           </button>
         </div>
         <div class="chart-wrapper">
            <Doughnut :data="chartData" :options="chartOptions" />
            <div class="chart-center-text">
              <span class="label">帳戶淨資產</span>
              <span class="value" :class="{ 'value-hidden': isHidden }">
                {{ isHidden ? '••••••' : formatCurrency(totalNetAssets) }}
              </span>
            </div>
         </div>

         <!-- Quick Legend -->
         <div class="legend-row" v-if="accounts.length > 0">
            <div v-for="type in [...new Set(accounts.map(a => a.type))]" :key="type" class="legend-item">
               <span class="dot" :style="{ background: getGroupColor(type) }"></span>
               <span class="l-name">{{ translateType(type) }}</span>
            </div>
         </div>
      </div>

      <div class="add-asset-wrapper">
        <button class="add-asset-btn" @click="showAddModal = true">
           <PhPlus weight="bold" /> 新增帳目
        </button>
      </div>
    </div>

    <!-- Scrollable List -->
    <div class="scrollable-content">
       <div class="grouped-list">
          
          <!-- Assets Section -->
          <div class="account-group" v-if="assetAccounts.length > 0">
             <div class="group-header text-green">
                <span class="g-title">💰 資產帳戶</span>
                <span class="g-total">{{ isHidden ? '••••••' : formatCurrency(assetAccounts.reduce((s, a) => s + Number(a.balance), 0)) }}</span>
             </div>
             
             <div class="account-cards">
                <div v-for="acc in assetAccounts" :key="acc.id" class="account-card">
                   <div class="ac-icon" :style="{ background: getGroupColor(acc.type) + '12', color: getGroupColor(acc.type) }">
                      <component :is="getIcon(acc.type)" size="20" weight="duotone" />
                   </div>
                   <div class="ac-info">
                      <div class="ac-name">{{ acc.name }}</div>
                      <div class="ac-type">{{ translateType(acc.type) }}</div>
                   </div>
                   <div class="ac-bal-wrap">
                      <div class="ac-bal">{{ isHidden ? '••••••' : formatCurrency(acc.balance) }}</div>
                   </div>
                   <button class="del-btn-mini" @click="deleteAccount(acc.id)">
                      <PhTrash size="14" />
                   </button>
                </div>
             </div>
          </div>

          <!-- Liabilities Section -->
          <div class="account-group" v-if="liabilityAccounts.length > 0">
             <div class="group-header text-red">
                <span class="g-title">💳 負債項目</span>
                <span class="g-total">{{ isHidden ? '••••••' : formatCurrency(liabilityAccounts.reduce((s, a) => s + Number(a.balance), 0)) }}</span>
             </div>
             
             <div class="account-cards">
                <div v-for="acc in liabilityAccounts" :key="acc.id" class="account-card liability-border">
                   <div class="ac-icon" :style="{ background: getGroupColor(acc.type) + '12', color: getGroupColor(acc.type) }">
                      <component :is="getIcon(acc.type)" size="20" weight="duotone" />
                   </div>
                   <div class="ac-info">
                      <div class="ac-name">{{ acc.name }}</div>
                      <div class="ac-type">{{ translateType(acc.type) }}</div>
                   </div>
                   <div class="ac-bal-wrap">
                      <div class="ac-bal text-red">{{ isHidden ? '••••••' : formatCurrency(acc.balance) }}</div>
                   </div>
                   <button class="del-btn-mini" @click="deleteAccount(acc.id)">
                      <PhTrash size="14" />
                   </button>
                </div>
             </div>
          </div>
          
          <div v-if="accounts.length === 0" class="empty-state">
             <div style="font-size: 2rem; margin-bottom: 0.5rem;">🏦</div>
             <div>目前尚無任何帳戶資料</div>
             <div style="font-size: 0.8rem; margin-top: 0.3rem; opacity: 0.6;">點擊「新增帳目」建立您的資產或債務</div>
          </div>
       </div>
    </div>

    <!-- Add Modal -->
    <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
      <div class="modal-content card">
        <h3>新增帳目</h3>
        <div class="form-group">
          <label>帳目名稱</label>
          <input v-model="newAccount.name" placeholder="例: 富邦銀行、Line Pay 信用卡" />
        </div>
        <div class="form-group">
          <label>帳目類型</label>
          <select v-model="newAccount.type">
            <option v-for="t in accountTypes" :key="t" :value="t">{{ translateType(t) }}</option>
          </select>
        </div>
        <div class="form-group">
          <label>金額</label>
          <input v-model.number="newAccount.balance" type="number" placeholder="金額 (非負數)" />
        </div>
        <div class="actions">
          <button @click="showAddModal = false">取消</button>
          <button class="primary" @click="addAccount">建立帳目</button>
        </div>
      </div>
    </div>
  </div>
  
  <div class="assets-container loader-container" v-else>
    <div class="loading-spinner"></div>
    <span class="loader-text">同步資料中...</span>
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

.loader-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--color-text-muted);
  gap: 12px;
}

.loader-text {
  font-size: 0.9rem;
  font-weight: 500;
  letter-spacing: 0.05em;
}

.fixed-top {
  flex-shrink: 0;
  padding: 1rem 1rem 0.5rem 1rem;
  background: var(--color-bg);
  z-index: 10;
}

.privacy-icon-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
  padding: 0 !important;
  flex: 0 0 auto;
  box-shadow: none;
}
.privacy-icon-btn:hover { color: #ffffff; background: rgba(255,255,255,0.06); }
.privacy-icon-btn:active { transform: scale(0.95); }

/* Portfolio Circular Card */
.portfolio-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-bottom: 1.2rem;
  border-radius: var(--radius-lg);
  padding: 1.2rem;
  position: relative;
}

.card-gradient {
  background: linear-gradient(135deg, rgba(59, 130, 246, 0.08) 0%, rgba(16, 185, 129, 0.04) 100%);
  border: 1px solid var(--color-card-border);
  box-shadow: 
    inset 0 1px 0 rgba(255, 255, 255, 0.05),
    0 10px 25px rgba(0, 0, 0, 0.35);
}

.card-header {
  width: 100%;
  display: flex;
  justify-content: flex-start;
  margin-bottom: -1.2rem;
  z-index: 2;
}

.chart-wrapper {
  position: relative;
  width: 170px;
  height: 170px;
  margin-bottom: 0.8rem;
  display: flex;
  align-items: center;
  justify-content: center;
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
  font-size: 0.7rem;
  color: var(--color-text-muted);
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}
.chart-center-text .value {
  display: block;
  font-family: var(--font-display);
  font-size: 1.4rem;
  font-weight: 800;
  color: var(--color-text);
  margin-top: 2px;
}

.chart-center-text .value.value-hidden {
  letter-spacing: 0.15em;
  font-size: 1.15rem;
}

.legend-row {
  display: flex;
  gap: 1rem;
  justify-content: center;
  flex-wrap: wrap;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  width: 100%;
  padding-top: 0.8rem;
}
.legend-item {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 0.72rem;
}
.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
}
.l-name { color: var(--color-text-muted); font-weight: 500; }

/* Add Asset Button */
.add-asset-wrapper {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-bottom: 0.5rem;
}

.add-asset-btn {
  background: transparent;
  color: var(--color-primary-hover);
  border: 1px solid rgba(99, 102, 241, 0.35);
  border-radius: 20px;
  padding: 6px 20px;
  font-size: 0.85rem;
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: none;
}
.add-asset-btn:hover {
  background: rgba(99, 102, 241, 0.1);
  border-color: var(--color-primary-hover);
}
.add-asset-btn:active { 
  transform: scale(0.96);
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
  font-size: 0.85rem;
  padding-bottom: 0.4rem;
  border-bottom: 1px solid rgba(255,255,255,0.05);
}
.text-green { color: var(--color-success); }
.text-red { color: var(--color-danger); }

.g-title { font-weight: 700; letter-spacing: 0.05em; }
.g-total { font-family: var(--font-display); font-weight: 700; opacity: 0.9; }

.account-cards {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.6rem;
}

.account-card {
  background: var(--color-card-bg);
  border: 1px solid var(--color-card-border);
  border-radius: var(--radius-md);
  padding: 0.75rem 1rem;
  display: flex;
  align-items: center;
  gap: 0.85rem;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.account-card:hover {
  border-color: rgba(255, 255, 255, 0.1);
  transform: translateY(-1px);
}

.liability-border {
  border-left: 3px solid var(--color-danger);
}

.ac-icon {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.ac-info {
  flex: 1;
  min-width: 0;
  text-align: left;
}
.ac-name { font-size: 0.9rem; font-weight: 600; color: #ffffff; margin-bottom: 1px; }
.ac-type { font-size: 0.72rem; color: var(--color-text-muted); font-weight: 500; }

.ac-bal-wrap {
  text-align: right;
}
.ac-bal { font-family: var(--font-display); font-size: 1.05rem; font-weight: 700; color: #ffffff; }
.ac-bal.text-red { color: var(--color-danger); }

.del-btn-mini {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  opacity: 0.2;
  padding: 6px;
  cursor: pointer;
  box-shadow: none;
  transition: all 0.2s ease;
}
.account-card:hover .del-btn-mini { opacity: 0.6; }
.del-btn-mini:hover { opacity: 1 !important; color: var(--color-danger); }

/* Modal */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(4, 5, 10, 0.8);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  z-index: 2000;
  display: flex;
  align-items: center;
  justify-content: center;
}
.modal-content {
  width: 85%;
  max-width: 340px;
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
h3 { margin: 0; font-size: 1.15rem; text-align: center; font-weight: 700; }

.form-group {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  text-align: left;
}
.form-group label {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--color-text-muted);
}
input, select {
  margin-bottom: 0 !important;
}

.actions { display: flex; gap: 0.75rem; margin-top: 0.5rem; }
.actions button {
  flex: 1;
  padding: 10px;
  font-size: 0.9rem;
  font-weight: 600;
}
button.primary { background: linear-gradient(135deg, var(--color-primary), var(--color-primary-hover)); color: white; }

.empty-state {
  height: 160px; 
  display: flex; 
  flex-direction: column;
  align-items: center; 
  justify-content: center;
  color: var(--color-text-muted);
  font-size: 0.85rem;
  border: 1px dashed rgba(255, 255, 255, 0.08);
  border-radius: var(--radius-md);
  background: rgba(255, 255, 255, 0.01);
  padding: 1.5rem;
}

.loading-spinner {
  width: 24px;
  height: 24px;
  border: 2px solid rgba(255, 255, 255, 0.08);
  border-top: 2px solid var(--color-accent);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
</style>
