<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabaseClient'

const incomes = ref([])
const showAddModal = ref(false)
const newIncome = ref({ 
  title: '', 
  amount: '', 
  date: new Date().toISOString().split('T')[0] 
})

const fetchIncomes = async () => {
  const { data, error } = await supabase
    .from('incomes')
    .select('*')
    .order('date', { ascending: false })
    .order('created_at', { ascending: false })
  
  if (error) console.error('Error fetching incomes:', error)
  else incomes.value = data
}

const addIncome = async () => {
  if (!newIncome.value.title || !newIncome.value.amount) return
  
  const { data, error } = await supabase
    .from('incomes')
    .insert([newIncome.value])
    .select()

  if (error) {
    console.error('Error adding income:', error)
  } else {
    incomes.value.unshift(data[0])
    showAddModal.value = false
    newIncome.value.title = ''
    newIncome.value.amount = ''
    // Keep date as is or reset
  }
}

const deleteIncome = async (id) => {
  const { error } = await supabase
    .from('incomes')
    .delete()
    .eq('id', id)
  
  if (!error) {
    incomes.value = incomes.value.filter(i => i.id !== id)
  }
}

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

onMounted(() => {
  fetchIncomes()
})
</script>

<template>
  <div class="incomes-container">
    <div class="summary-card card">
      <h2>💵 收入管理</h2>
      <button @click="showAddModal = !showAddModal" class="add-btn">
        {{ showAddModal ? '取消' : '+ 新增收入' }}
      </button>
    </div>

    <!-- Add Form -->
    <div v-if="showAddModal" class="add-form card">
      <div class="form-group">
        <label>項目名稱</label>
        <input v-model="newIncome.title" placeholder="例如: 薪資、獎金" />
      </div>
      <div class="form-group">
        <label>金額</label>
        <input v-model="newIncome.amount" type="number" placeholder="0" />
      </div>
      <div class="form-group">
        <label>日期</label>
        <input v-model="newIncome.date" type="date" />
      </div>
      <button @click="addIncome" class="w-full">儲存</button>
    </div>

    <!-- List -->
    <div class="list card">
      <div v-if="incomes.length === 0" class="empty-state">
        沒有收入紀錄
      </div>
      <div v-for="inc in incomes" :key="inc.id" class="item">
        <div class="info">
          <div class="name">{{ inc.title }}</div>
          <div class="meta">{{ formatDate(inc.date) }}</div>
        </div>
        <div class="amount">
          <span style="color: var(--color-success)">+{{ formatCurrency(inc.amount) }}</span>
          <button @click="deleteIncome(inc.id)" class="delete-btn">×</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.incomes-container {
  max-width: 600px;
  margin: 0 auto;
}

.summary-card {
  text-align: center;
  margin-bottom: 1rem;
  padding: 1.5rem;
}

.add-btn {
  background: rgba(255,255,255,0.1);
  border: 1px solid rgba(255,255,255,0.2);
  margin-top: 1rem;
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

.item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem;
  border-bottom: 1px solid rgba(255,255,255,0.1);
}
.item:last-child {
  border-bottom: none;
}

.name {
  font-weight: 500;
  font-size: 1.1rem;
}

.meta {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-top: 0.2rem;
}

.amount {
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
