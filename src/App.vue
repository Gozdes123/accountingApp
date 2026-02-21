<script setup>
import { ref, onMounted, nextTick, watch } from 'vue'
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
const incomes = ref([]) // [New] Incomes state
const subscriptions = ref([]) // [New] Subscriptions state
const accounts = ref([]) // [New] Accounts state
const showEditModal = ref(false)
const editingExpense = ref({})
const transactionsRef = ref(null)
const pendingAction = ref(null) // Store action to perform after tab switch

// Toast System

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

const fetchIncomes = async () => {
  const { data, error } = await supabase
    .from('incomes')
    .select('*')
    .order('date', { ascending: false })
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Error fetching incomes:', error)
    // Optional: showToast('error', '無法載入收入資料')
  } else {
    incomes.value = data
  }
}

const fetchSubscriptions = async () => {
  const { data, error } = await supabase
    .from('subscriptions')
    .select('*')
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Error fetching subscriptions:', error)
  } else {
    subscriptions.value = data
  }
}

const fetchAccounts = async () => {
  const { data, error } = await supabase
    .from('accounts')
    .select('*')
    .order('created_at', { ascending: true })
  
  if (error) {
    console.error('Error fetching accounts:', error)
  } else {
    accounts.value = data
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
  const { data: subs, error: fetchError } = await supabase.from('subscriptions').select('*')
  if (fetchError || !subs) return

  const today = new Date()
  const todayStr = today.toISOString().split('T')[0]

  for (const sub of subs) {
    if (!sub.next_payment_date || sub.next_payment_date > todayStr) continue

    // Step 1: Insert expense record — if this fails, we stop and do NOT advance the date
    const expensePayload = {
      title: `[訂閱] ${sub.name}`,
      amount: sub.cost,
      category: 'Subscription',
      date: sub.next_payment_date
    }
    if (sub.account_id) expensePayload.account_id = sub.account_id

    const { data: newExpense, error: expenseError } = await supabase
      .from('expenses')
      .insert([expensePayload])
      .select()

    if (expenseError) {
      console.error(`訂閱 ${sub.name} 記帳失敗:`, expenseError)
      showToast('error', `訂閱「${sub.name}」自動記帳失敗，請手動新增`)
      continue // 跳過這筆，不更新下次扣款日
    }

    // Step 2: Deduct from account balance (only if account was specified)
    if (sub.account_id) {
      await updateAccountBalance(sub.account_id, -Math.abs(Number(sub.cost)))
    }

    // Step 3: Advance next_payment_date (only AFTER expense was confirmed)
    const nextDate = new Date(sub.next_payment_date)
    if (sub.billing_cycle === 'monthly') {
      nextDate.setMonth(nextDate.getMonth() + 1)
    } else {
      nextDate.setFullYear(nextDate.getFullYear() + 1)
    }
    const nextDateStr = nextDate.toISOString().split('T')[0]

    const { error: updateError } = await supabase
      .from('subscriptions')
      .update({ next_payment_date: nextDateStr })
      .eq('id', sub.id)

    if (updateError) {
      console.error(`更新 ${sub.name} 下次扣款日失敗:`, updateError)
    }

    // Step 4: Update local state
    expenses.value.unshift(newExpense[0])
    const localSub = subscriptions.value.find(s => s.id === sub.id)
    if (localSub) localSub.next_payment_date = nextDateStr

    showToast('success', `已自動記帳訂閱：${sub.name} ${formatCurrency(sub.cost)}`)
  }
}

const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', { style: 'currency', currency: 'TWD', minimumFractionDigits: 0 }).format(amount)
}

const isDataLoaded = ref(false)

onMounted(async () => {
  await Promise.all([
    fetchExpenses(),
    fetchIncomes(),
    fetchSubscriptions(),
    fetchAccounts()
  ])
  isDataLoaded.value = true
  await migrateLocalStorage()
  await checkSubscriptions()
})

const addExpense = async (expense) => {
  const { id, account_id, type, ...expenseData } = expense
  const payload = { ...expenseData }
  if (account_id) payload.account_id = account_id // Only send if selected

  const { data, error } = await supabase
    .from('expenses')
    .insert([payload])
    .select()

  if (error) {
    console.error('Error adding expense:', error)
    showToast('error', '新增失敗，請稍後再試')
  } else {
    expenses.value.unshift(data[0])
    showToast('success', `已新增支出：${expenseData.title} $${expenseData.amount}`)

    // Update Account Balance if account_id is provided
    if (account_id) {
       updateAccountBalance(account_id, -Math.abs(expenseData.amount))
    }
  }
}

// Helper: Update Account Balance
const updateAccountBalance = async (accountId, changeAmount) => {
  const account = accounts.value.find(a => a.id === accountId)
  if (!account) return

  const newBalance = Number(account.balance) + Number(changeAmount)
  
  const { error } = await supabase
    .from('accounts')
    .update({ balance: newBalance })
    .eq('id', accountId)

  if (error) {
    console.error('Error updating account balance:', error)
    showToast('error', '更新帳戶餘額失敗')
  } else {
    // Update local state
    account.balance = newBalance
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
  // Find expense before deleting to refund balance
  const expenseToDelete = expenses.value.find(e => e.id === id)
  
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
    
    // Refund Account Balance
    if (expenseToDelete && expenseToDelete.account_id) {
      updateAccountBalance(expenseToDelete.account_id, Math.abs(expenseToDelete.amount)) // Add back
    }
  }
}

const addIncome = async (income) => {
  const { id, account_id, type, ...incomeData } = income
  const payload = { ...incomeData }
  if (account_id) payload.account_id = account_id

  const { data, error } = await supabase
    .from('incomes')
    .insert([payload])
    .select()

  if (error) {
    console.error('Error adding income:', error)
    showToast('error', '新增收入失敗')
  } else {
    incomes.value.unshift(data[0])
    showToast('success', `已新增收入：${incomeData.title} $${incomeData.amount}`)
    
    // Update Account Balance
    if (account_id) {
      updateAccountBalance(account_id, Math.abs(incomeData.amount)) // Add
    }
  }
}

const deleteIncome = async (id) => {
  const incomeToDelete = incomes.value.find(i => i.id === id)

  const { error } = await supabase
    .from('incomes')
    .delete()
    .eq('id', id)
  
  if (error) {
    console.error('Error deleting income:', error)
    showToast('error', '刪除收入失敗')
  } else {
    incomes.value = incomes.value.filter(i => i.id !== id)
    showToast('success', '已刪除該筆收入')
    
    // Deduct Account Balance
    if (incomeToDelete && incomeToDelete.account_id) {
      updateAccountBalance(incomeToDelete.account_id, -Math.abs(incomeToDelete.amount)) // Deduct
    }
  }
}

const addSubscription = async (sub) => {
  const { data, error } = await supabase
    .from('subscriptions')
    .insert([sub])
    .select()

  if (error) {
    console.error('Error adding subscription:', error)
    showToast('error', '新增訂閱失敗')
    return
  }

  const newSub = data[0]
  subscriptions.value.unshift(newSub)
  showToast('success', `已新增訂閱：${newSub.name}`)

  // ── 立即記帳邏輯 ───────────────────────────────
  // 若扣款日已是今天或過去，立即建立支出、扣帳戶餘額、推進下次扣款日
  if (!newSub.next_payment_date) return

  const todayStr = new Date().toISOString().split('T')[0]
  if (newSub.next_payment_date > todayStr) return // 未來日期，不處理

  // Step 1: 建立支出紀錄
  const expensePayload = {
    title: `[訂閱] ${newSub.name}`,
    amount: newSub.cost,
    category: 'Subscription',
    date: newSub.next_payment_date
  }
  if (newSub.account_id) expensePayload.account_id = newSub.account_id

  const { data: newExpense, error: expenseError } = await supabase
    .from('expenses')
    .insert([expensePayload])
    .select()

  if (expenseError) {
    console.error(`訂閱 ${newSub.name} 立即記帳失敗:`, expenseError)
    showToast('error', `訂閱「${newSub.name}」自動記帳失敗，請手動新增支出`)
    return
  }

  // Step 2: 扣帳戶餘額（若有指定帳戶）
  if (newSub.account_id) {
    await updateAccountBalance(newSub.account_id, -Math.abs(Number(newSub.cost)))
  }

  // Step 3: 推進下次扣款日
  const nextDate = new Date(newSub.next_payment_date)
  if (newSub.billing_cycle === 'monthly') {
    nextDate.setMonth(nextDate.getMonth() + 1)
  } else {
    nextDate.setFullYear(nextDate.getFullYear() + 1)
  }
  const nextDateStr = nextDate.toISOString().split('T')[0]

  await supabase
    .from('subscriptions')
    .update({ next_payment_date: nextDateStr })
    .eq('id', newSub.id)

  // Step 4: 更新本地狀態
  expenses.value.unshift(newExpense[0])
  const localSub = subscriptions.value.find(s => s.id === newSub.id)
  if (localSub) localSub.next_payment_date = nextDateStr

  showToast('success', `已自動記帳：${newSub.name} ${formatCurrency(newSub.cost)}，下次扣款 ${nextDateStr}`)
}

const deleteSubscription = async (id) => {
  const { error } = await supabase
    .from('subscriptions')
    .delete()
    .eq('id', id)
  
  if (error) {
    console.error('Error deleting subscription:', error)
    showToast('error', '刪除訂閱失敗')
  } else {
    subscriptions.value = subscriptions.value.filter(s => s.id !== id)
    showToast('success', '已刪除該筆訂閱')
  }
}

// Pending actions watcher for delayed modal opening
watch(transactionsRef, (newRef) => {
  if (newRef && pendingAction.value) {
    if (pendingAction.value === 'add-expense') {
      newRef.openAddModal('expense')
    } else if (pendingAction.value === 'add-income') {
      newRef.openAddModal('income')
    } else if (pendingAction.value === 'open-favorites') {
      newRef.openFavorites()
    }
    pendingAction.value = null
  }
})

// FAB Actions
const handleOpenQuickAdd = () => {
  if (currentTab.value === 'transactions' && transactionsRef.value) {
    transactionsRef.value.openAddModal('expense')
  } else {
    pendingAction.value = 'add-expense'
    currentTab.value = 'transactions'
  }
}
const handleOpenIncomeAdd = () => {
  if (currentTab.value === 'transactions' && transactionsRef.value) {
    transactionsRef.value.openAddModal('income')
  } else {
    pendingAction.value = 'add-income'
    currentTab.value = 'transactions'
  }
}
const handleOpenFavAdd = () => {
  if (currentTab.value === 'transactions' && transactionsRef.value) {
    transactionsRef.value.openFavorites()
  } else {
    pendingAction.value = 'open-favorites'
    currentTab.value = 'transactions'
  }
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
    <div class="content-area" v-if="isDataLoaded">
      <Transition name="fade" mode="out-in">
        <KeepAlive>
          <Dashboard v-if="currentTab === 'dashboard'" key="dashboard"
            :expenses="expenses" 
            :incomes="incomes" 
            :accounts="accounts"
            @edit-expense="openEditModal" 
          />

          <Transactions v-else-if="currentTab === 'transactions'" key="transactions"
            ref="transactionsRef"
            :expenses="expenses" 
            :incomes="incomes"
            @add-expense="addExpense" 
            @add-income="addIncome"
            @delete-expense="deleteExpense" 
            @delete-income="deleteIncome"
            :subscriptions="subscriptions"
            :accounts="accounts"
            @add-subscription="addSubscription"
            @delete-subscription="deleteSubscription"
            @edit-expense="openEditModal" 
          />

          <Assets v-else-if="currentTab === 'assets'" key="assets"
            :accounts="accounts" @refresh="fetchAccounts" 
          />

          <Investments v-else-if="currentTab === 'investments'" key="investments" />
        </KeepAlive>
      </Transition>
    </div>
    <div class="content-area" v-else style="display: flex; align-items: center; justify-content: center; color: var(--color-text-muted);">
      載入中...
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
