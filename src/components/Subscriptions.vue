<script setup>
import { ref, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabaseClient'

const subscriptions = ref([])
const showAddModal = ref(false)
const newSub = ref({ 
  name: '', 
  cost: '', 
  billing_cycle: 'monthly',
  next_payment_date: '' 
})

const fetchSubscriptions = async () => {
  const { data, error } = await supabase
    .from('subscriptions')
    .select('*')
    .order('created_at', { ascending: false })
  
  if (error) console.error('Error fetching subscriptions:', error)
  else subscriptions.value = data
}

const addSubscription = async () => {
  if (!newSub.value.name || !newSub.value.cost) return
  
  const { data, error } = await supabase
    .from('subscriptions')
    .insert([newSub.value])
    .select()

  if (error) {
    console.error('Error adding subscription:', error)
  } else {
    subscriptions.value.unshift(data[0])
    showAddModal.value = false
    newSub.value = { name: '', cost: '', billing_cycle: 'monthly', next_payment_date: '' }
  }
}

const deleteSubscription = async (id) => {
  const { error } = await supabase
    .from('subscriptions')
    .delete()
    .eq('id', id)
  
  if (!error) {
    subscriptions.value = subscriptions.value.filter(s => s.id !== id)
  }
}

const totalMonthlyCost = computed(() => {
  return subscriptions.value.reduce((sum, sub) => {
    let monthlyAmount = parseFloat(sub.cost)
    if (sub.billing_cycle === 'yearly') {
      monthlyAmount = monthlyAmount / 12
    }
    return sum + monthlyAmount
  }, 0)
})

const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', {
    style: 'currency',
    currency: 'TWD',
    minimumFractionDigits: 0
  }).format(amount)
}

onMounted(() => {
  fetchSubscriptions()
})
</script>

<template>
  <div class="subscriptions-container">
    <div class="summary-card card">
      <h2>📅 訂閱管理</h2>
      <div class="total-cost">
        <span>每月平均支出</span>
        <div class="amount">{{ formatCurrency(totalMonthlyCost) }}</div>
      </div>
      <button @click="showAddModal = !showAddModal" class="add-btn">
        {{ showAddModal ? '取消' : '+ 新增訂閱' }}
      </button>
    </div>

    <!-- Add Form -->
    <div v-if="showAddModal" class="add-form card">
      <div class="form-group">
        <label>名稱</label>
        <input v-model="newSub.name" placeholder="例如: Netflix" />
      </div>
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
      <div class="form-group">
        <label>下次扣款日 (選填)</label>
        <input v-model="newSub.next_payment_date" type="date" />
      </div>
      <button @click="addSubscription" class="w-full">儲存</button>
    </div>

    <!-- List Wrapper -->
    <div class="list-wrapper">
      <div class="sub-list card">
        <div v-if="subscriptions.length === 0" class="empty-state">
          沒有訂閱項目
        </div>
        <div v-for="sub in subscriptions" :key="sub.id" class="sub-item">
          <div class="sub-info">
            <div class="sub-name">{{ sub.name }}</div>
            <div class="sub-meta">
              {{ sub.billing_cycle === 'monthly' ? '月繳' : '年繳' }} 
              <span v-if="sub.next_payment_date"> · 下次: {{ sub.next_payment_date }}</span>
            </div>
          </div>
          <div class="sub-cost">
            {{ formatCurrency(sub.cost) }}
            <button @click="deleteSubscription(sub.id)" class="delete-btn">×</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.subscriptions-container {
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

.total-cost {
  margin: 1.5rem 0;
}

.total-cost span {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}

.total-cost .amount {
  font-size: 2.5rem;
  font-weight: bold;
  color: var(--color-primary);
  margin-top: 0.5rem;
}

.add-btn {
  background: rgba(255,255,255,0.1);
  border: 1px solid rgba(255,255,255,0.2);
}

.add-form {
  margin-bottom: 1rem;
}

.form-group {
  margin-bottom: 1rem;
}
.form-group label {
  display: block;
  margin-bottom: 0.4rem;
  color: var(--color-text-muted);
  font-size: 0.9rem;
}

.sub-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem;
  border-bottom: 1px solid rgba(255,255,255,0.1);
}
.sub-item:last-child {
  border-bottom: none;
}

.sub-name {
  font-weight: 500;
  font-size: 1.1rem;
}

.sub-meta {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-top: 0.2rem;
}

.sub-cost {
  font-weight: bold;
  display: flex;
  align-items: center;
  gap: 1rem;
}

.delete-btn {
  background: transparent;
  color: var(--color-text-muted);
  border: 1px solid rgba(255,255,255,0.2);
  padding: 0.2rem 0.6rem;
  font-size: 1rem;
}
.delete-btn:hover {
  border-color: var(--color-danger);
  color: var(--color-danger);
}

.empty-state {
  text-align: center;
  color: var(--color-text-muted);
  padding: 2rem;
}
</style>
