<script setup>
import { ref } from 'vue'
import QuickAdd from './QuickAdd.vue'
import ExpenseForm from './ExpenseForm.vue'
import ExpenseList from './ExpenseList.vue'
import SubscriptionsPanel from './Subscriptions.vue'
import { PhPlus, PhX, PhArrowsLeftRight, PhCalendarCheck } from '@phosphor-icons/vue'
import { computed } from 'vue'

const props = defineProps({
  expenses: {
    type: Array,
    required: true
  },
  incomes: {
    type: Array,
    required: true
  },
  subscriptions: {
    type: Array,
    required: true
  },
  accounts: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['add-expense', 'add-income', 'delete-expense', 'delete-income', 'edit-expense', 'add-subscription', 'delete-subscription'])

const showAddModal = ref(false)
const showFavModal = ref(false)
const showSubModal = ref(false)
const initialFormType = ref('expense')
const currentView = ref('transactions') // 'transactions' or 'subscriptions'

// Subscription Form
const newSub = ref({
  name: '',
  cost: '',
  billing_cycle: 'monthly',
  next_payment_date: ''
})

const handleAddSubscription = () => {
  if (!newSub.value.name || !newSub.value.cost) return
  emit('add-subscription', newSub.value)
  showSubModal.value = false
  newSub.value = { name: '', cost: '', billing_cycle: 'monthly', next_payment_date: '' }
}

const totalMonthlySubCost = computed(() => {
  return props.subscriptions.reduce((sum, sub) => {
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

const openAddModal = (type = 'expense') => {
  initialFormType.value = type
  showAddModal.value = true
}

const openFavorites = () => {
  showFavModal.value = true
}

defineExpose({
  openAddModal,
  openFavorites
})

const handleAddTransaction = (transaction) => {
  if (transaction.type === 'income') {
    emit('add-income', transaction)
  } else {
    emit('add-expense', transaction) // Default to expense
  }
  showAddModal.value = false
  showFavModal.value = false
}
</script>

<template>
  <div class="transactions-view">
    <!-- Header -->
    <!-- Header -->
    <div class="view-toggle">
      <button @click="currentView = 'transactions'" :class="{ active: currentView === 'transactions' }">
        <PhArrowsLeftRight size="18" weight="bold" />
        帳務紀錄
      </button>
      <button @click="currentView = 'subscriptions'" :class="{ active: currentView === 'subscriptions' }">
        <PhCalendarCheck size="18" weight="bold" />
        訂閱服務
      </button>
    </div>

    <!-- Transactions View Actions -->
    <div class="header-actions" v-if="currentView === 'transactions'">
      <button class="add-btn" @click="openAddModal('expense')">
        <PhPlus size="18" weight="bold" />
        <span>新增帳目</span>
      </button>
    </div>

    <!-- Subscriptions View Actions -->
    <div class="header-actions" v-if="currentView === 'subscriptions'">
      <div class="sub-summary">
        <span style="font-size: 0.85rem; opacity: 0.7">訂閱服務</span>
      </div>
    </div>

    <!-- Unified Content -->
    <div class="tab-content" v-if="currentView === 'transactions'">
      <!-- List only, maximize space -->
      <div class="list-container">
        <ExpenseList :expenses="expenses" :incomes="incomes" @delete-expense="emit('delete-expense', $event)"
          @delete-income="emit('delete-income', $event)" @edit-expense="emit('edit-expense', $event)" />
      </div>

      <!-- Add Transaction Modal -->
      <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
        <div class="modal-content">
          <div class="modal-header">
            <h3>{{ initialFormType === 'income' ? '新增收入' : '新增支出' }}</h3>
            <button class="close-btn" @click="showAddModal = false">
              <PhX size="20" />
            </button>
          </div>
          <ExpenseForm :initial-type="initialFormType" :accounts="accounts" @add-expense="handleAddTransaction"
            @update:type="initialFormType = $event" />
        </div>
      </div>

      <!-- Favorites Modal -->
      <div v-if="showFavModal" class="modal-overlay" @click.self="showFavModal = false">
        <div class="modal-content" style="max-width: 500px;">
          <div class="modal-header">
            <h3>⭐ 常用消費</h3>
            <button class="close-btn" @click="showFavModal = false">
              <PhX size="20" />
            </button>
          </div>
          <QuickAdd @add-expense="handleAddTransaction" />
        </div>
      </div>
    </div>

    <!-- Subscriptions Content - delegated to Subscriptions component -->
    <div class="tab-content" v-if="currentView === 'subscriptions'">
      <SubscriptionsPanel :subscriptions="subscriptions" :accounts="accounts"
        @add-subscription="emit('add-subscription', $event)"
        @delete-subscription="emit('delete-subscription', $event)" />
    </div>
  </div>
</template>

<style scoped>
.transactions-view {
  padding-bottom: 2rem;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.header-actions {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  margin-bottom: 1rem;
  padding: 0 1rem;
}

.view-toggle {
  display: flex;
  margin: 0 1rem 1rem 1rem;
  background: rgba(0, 0, 0, 0.04);
  padding: 4px;
  border-radius: 12px;
}

.view-toggle button {
  flex: 1;
  border: none;
  background: transparent;
  color: var(--color-text-muted);
  padding: 8px;
  border-radius: 8px;
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  transition: all 0.2s;
}

.view-toggle button.active {
  background: #ffffff;
  color: var(--color-text);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
}

.sub-summary {
  margin-right: auto;
  background: var(--color-primary-bg);
  padding: 4px 12px;
  border-radius: 20px;
  border: 1px solid rgba(92, 103, 245, 0.15);
}

.empty-state {
  text-align: center;
  color: var(--color-text-muted);
  padding: 2rem;
  font-size: 0.9rem;
}

.sub-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem;
  background: var(--color-card-bg);
  margin-bottom: 0.5rem;
  border-radius: 12px;
  border: 1px solid var(--color-card-border);
}

.sub-name {
  font-weight: 500;
  font-size: 1rem;
}

.sub-meta {
  font-size: 0.8rem;
  color: var(--color-text-muted);
  margin-top: 2px;
}

.sub-cost {
  font-weight: bold;
  display: flex;
  align-items: center;
  gap: 1rem;
  font-size: 1rem;
}

.icon-btn {
  background: transparent;
  border: 1px solid rgba(0, 0, 0, 0.08);
  color: var(--color-text-muted);
  width: 40px;
  height: 40px;
  font-size: 1.1rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  cursor: pointer;
}

.icon-btn.delete:hover {
  border-color: var(--color-danger);
  color: var(--color-danger);
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

.form-group input,
.form-group select {
  width: 100%;
  padding: 0.6rem;
  background: #f1f5f9;
  border: 1px solid rgba(0, 0, 0, 0.08);
  color: var(--color-text);
  border-radius: 8px;
}

/* Removed tabs styles */

.add-btn {
  background: var(--color-primary);
  border: none;
  border-radius: 20px;
  padding: 8px 16px;
  display: flex;
  align-items: center;
  gap: 6px;
  color: white;
  cursor: pointer;
  box-shadow: 0 4px 12px rgba(92, 103, 245, 0.2);
  font-size: 0.9rem;
  font-weight: 500;
  transition: transform 0.2s, box-shadow 0.2s;
}

.add-btn:active {
  transform: scale(0.95);
}

.tab-content {
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  display: flex;
  flex-direction: column;
}

.list-container {
  flex: 1;
  overflow-y: auto;
  padding: 0 1rem 140px 1rem;
  -webkit-overflow-scrolling: touch;
}

/* Modal Styles */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
}

.modal-content {
  background: var(--color-card-bg);
  padding: 1.25rem 1rem;
  /* reduced from 1.5rem */
  border-radius: 16px;
  width: 90%;
  /* wider than 90% */
  max-width: 400px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  border: 1px solid var(--color-card-border);
  box-shadow: var(--shadow-lg);
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.modal-header h3 {
  margin: 0;
  font-size: 1.2rem;
  color: var(--color-text);
}

.close-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 4px;
}
</style>
