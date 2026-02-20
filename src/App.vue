<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from './lib/supabaseClient'
import Subscriptions from './components/Subscriptions.vue'
import Investments from './components/Investments.vue'
import Dashboard from './components/Dashboard.vue'
import ExpenseEditModal from './components/ExpenseEditModal.vue'

// New UX Components
import BottomNav from './components/BottomNav.vue'
import FloatingActionButton from './components/FloatingActionButton.vue'
import ToastNotification from './components/ToastNotification.vue'
import Transactions from './components/Transactions.vue'
import Assets from './components/Assets.vue'

const currentTab = ref('dashboard') // dashboard, transactions, assets, subscriptions, investments
const expenses = ref([])
const showEditModal = ref(false)
const editingExpense = ref({})

// Toast System
const toasts = ref([])
const showToast = (type, message) => {
  const id = Date.now()
  toasts.value.push({ id, type, message })
  setTimeout(() => {
    toasts.value = toasts.value.filter(t => t.id !== id)
  }, 3000)
}

const fetchExpenses = async () => {
  const { data, error } = await supabase
    .from('expenses')
    .select('*')
    .order('date', { ascending: false })
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Error fetching expenses:', error)
    showToast('error', '無法載入帳目資料')
  } else {
    expenses.value = data
  }
}

const migrateLocalStorage = async () => {
  const saved = localStorage.getItem('expenses')
  if (saved) {
    const localExpenses = JSON.parse(saved)
    if (localExpenses.length > 0) {
      const expensesToInsert = localExpenses.map(({ id, ...rest }) => rest)
      
      const { error } = await supabase.from('expenses').insert(expensesToInsert)
      if (!error) {
        localStorage.removeItem('expenses')
        console.log('Migrated local expenses to Supabase')
        await fetchExpenses()
      } else {
        console.error('Migration failed:', error)
      }
    }
  }
}

const checkSubscriptions = async () => {
  const { data: subs } = await supabase.from('subscriptions').select('*')
  if (!subs) return

  const today = new Date()
  const todayStr = today.toISOString().split('T')[0]

  for (const sub of subs) {
    if (sub.next_payment_date && sub.next_payment_date <= todayStr) {
      // 1. Create Expense
      const expense = {
        title: `[訂閱] ${sub.name}`,
        amount: sub.cost,
        category: 'Utilities', // Default category for subs
        date: sub.next_payment_date // Use the due date as expense date
      }
      await supabase.from('expenses').insert([expense])

      // 2. Calculate Next Date
      const nextDate = new Date(sub.next_payment_date)
      if (sub.billing_cycle === 'monthly') {
        nextDate.setMonth(nextDate.getMonth() + 1)
      } else {
        nextDate.setFullYear(nextDate.getFullYear() + 1)
      }
      const nextDateStr = nextDate.toISOString().split('T')[0]

      // 3. Update Subscription
      await supabase
        .from('subscriptions')
        .update({ next_payment_date: nextDateStr })
        .eq('id', sub.id)

      // 4. Notify
      showToast('success', `已自動扣款訂閱：${sub.name} $${sub.cost}`)
    }
  }
}

onMounted(async () => {
  await fetchExpenses()
  await migrateLocalStorage()
  await checkSubscriptions()
})

const addExpense = async (expense) => {
  const { id, ...expenseData } = expense
  
  const { data, error } = await supabase
    .from('expenses')
    .insert([expenseData])
    .select()

  if (error) {
    console.error('Error adding expense:', error)
    showToast('error', '新增失敗，請稍後再試')
  } else {
    expenses.value.unshift(data[0])
    showToast('success', `已新增支出：${expenseData.title} $${expenseData.amount}`)
  }
}

const openEditModal = (expense) => {
  editingExpense.value = expense
  showEditModal.value = true
}

const updateExpense = async (updatedExpense) => {
  const { data, error } = await supabase
    .from('expenses')
    .update({
      title: updatedExpense.title,
      amount: updatedExpense.amount,
      category: updatedExpense.category,
      date: updatedExpense.date
    })
    .eq('id', updatedExpense.id)
    .select()

  if (error) {
    console.error('Error updating expense:', error)
    showToast('error', '更新失敗')
  } else {
    // Update local state
    const index = expenses.value.findIndex(e => e.id === updatedExpense.id)
    if (index !== -1) {
      expenses.value[index] = data[0]
      fetchExpenses()
    }
    showEditModal.value = false
    showToast('success', '更正成功')
  }
}

const deleteExpense = async (id) => {
  const { error } = await supabase
    .from('expenses')
    .delete()
    .eq('id', id)

  if (error) {
    console.error('Error deleting expense:', error)
    showToast('error', '刪除失敗')
  } else {
    expenses.value = expenses.value.filter(exp => exp.id !== id)
    showToast('success', '已刪除該筆帳目')
  }
}

// FAB Actions
const handleOpenQuickAdd = () => {
  currentTab.value = 'transactions'
  // Trigger expense add mode if needed, for now just go to tab
}
const handleOpenIncomeAdd = () => {
  currentTab.value = 'transactions'
  // Trigger income add mode if needed
}
const handleOpenFavAdd = () => {
  currentTab.value = 'transactions' 
}
</script>

<template>
  <div class="container">
    <ToastNotification :notifications="toasts" />
    
    <!-- Header -->
    <header class="app-header">
      <h1>
        <span v-if="currentTab === 'dashboard'">總覽</span>
        <span v-else-if="currentTab === 'transactions'">帳務管理</span>
        <span v-else-if="currentTab === 'assets'">資產總覽</span>
        <span v-else-if="currentTab === 'subscriptions'">訂閱服務</span>
        <span v-else-if="currentTab === 'investments'">投資組合</span>
      </h1>
    </header>

    <!-- Main Content Area with Transition -->
    <div class="content-area">
      <Transition name="fade" mode="out-in">
        <!-- Dashboard View -->
        <div v-if="currentTab === 'dashboard'" key="dashboard">
          <Dashboard :expenses="expenses" @edit-expense="openEditModal" />
        </div>

        <!-- Transactions View (Incomes + Expenses) -->
        <div v-else-if="currentTab === 'transactions'" key="transactions">
          <Transactions 
            :expenses="expenses" 
            @add-expense="addExpense" 
            @delete-expense="deleteExpense" 
            @edit-expense="openEditModal" 
          />
        </div>

        <!-- Assets View -->
        <div v-else-if="currentTab === 'assets'" key="assets">
          <Assets />
        </div>

        <!-- Subscriptions View -->
        <div v-else-if="currentTab === 'subscriptions'" key="subscriptions">
          <Subscriptions />
        </div>

        <!-- Investments View -->
        <div v-else-if="currentTab === 'investments'" key="investments">
          <Investments />
        </div>
      </Transition>
    </div>

    <!-- Global Components -->
    <FloatingActionButton 
      @open-quick-add="handleOpenQuickAdd" 
      @open-income-add="handleOpenIncomeAdd"
      @open-fav-add="handleOpenFavAdd"
    />
    
    <BottomNav v-model:currentTab="currentTab" />

    <!-- Edit Modal -->
    <ExpenseEditModal 
      :show="showEditModal" 
      :expense="editingExpense" 
      @close="showEditModal = false" 
      @save="updateExpense" 
    />
  </div>
</template>

/* Global Page Layout */
:global(body) {
  margin: 0;
  padding: 0;
  overflow: hidden; /* Prevent global scroll */
  height: 100vh;
  width: 100vw;
  background-color: var(--color-bg);
  color: var(--color-text);
  font-family: 'Inter', sans-serif;
}

.container {
  width: 100%;
  height: 100vh;
  display: flex;
  flex-direction: column;
  padding-bottom: 0; /* Nav handled by fixed positioning or flex */
  padding-top: 10px;
  overflow: hidden;
}

.app-header {
  flex-shrink: 0;
  padding: 0 1rem;
}

.app-header h1 {
  font-size: 1.5rem;
  margin-bottom: 0.5rem;
  text-align: center;
  background: linear-gradient(to right, var(--color-primary), var(--color-accent));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  margin-top: 0.5rem;
}

.content-area {
  flex: 1;
  overflow: hidden; /* Internal components handle scrolling */
  position: relative;
  display: flex;
  flex-direction: column;
}

/* Page Transitions */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.fade-enter-from {
  opacity: 0;
  transform: translateY(10px);
}
.fade-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

/* Ensure direct children of content-area take full height if needed */
.content-area > div {
  height: 100%;
  display: flex;
  flex-direction: column;
}

<style scoped>
.container {
  width: 100%;
}
</style>
