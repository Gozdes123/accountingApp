<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  expenses: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['delete-expense', 'edit-expense'])

const selectedDate = ref('')

const filteredExpenses = computed(() => {
  if (!selectedDate.value) return props.expenses
  return props.expenses.filter(expense => expense.date === selectedDate.value)
})

const totalAmount = computed(() => {
  return filteredExpenses.value.reduce((sum, item) => sum + Number(item.amount), 0)
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

// Map categories to Chinese for display
const categoryMap = {
  'Food': '餐飲 🍔',
  'Transport': '交通 🚗',
  'Utilities': '水電 💡',
  'Entertainment': '娛樂 🎬',
  'Health': '醫療 🏥',
  'Shopping': '購物 🛍️',
  'Other': '其他 📦'
}

const getCategoryLabel = (cat) => categoryMap[cat] || cat
</script>

<template>
  <div class="filter-section">
    <label>📅</label>
    <input type="date" v-model="selectedDate" class="date-filter" />
    <button v-if="selectedDate" @click="selectedDate = ''" class="clear-btn">顯示全部</button>
  </div>

  <p v-if="filteredExpenses.length === 0" class="text-center empty-state">
    {{ selectedDate ? '這一天沒有支出紀錄' : '目前沒有支出紀錄，開始記帳吧！' }}
  </p>
  
  <div v-else class="list-wrapper">
    <ul style="list-style: none; padding: 0; margin: 0;">
      <li v-for="expense in filteredExpenses" :key="expense.id" 
          class="expense-item"
      >
        <div style="flex: 1;">
          <div style="font-weight: 500; font-size: 1rem;">{{ expense.title }}</div>
          <div style="font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.2rem;">
            <span style="display: inline-block; background-color: rgba(255,255,255,0.1); padding: 0.1rem 0.4rem; border-radius: 4px; margin-right: 0.5rem;">
              {{ getCategoryLabel(expense.category) }}
            </span>
            {{ formatDate(expense.date) }}
          </div>
        </div>
        
        <div style="display: flex; align-items: center; gap: 0.5rem;">
          <div style="font-weight: bold; font-size: 1.1rem; color: var(--color-success);">
            {{ formatCurrency(expense.amount) }}
          </div>
          
          <button 
            @click="emit('edit-expense', expense)"
            class="icon-btn edit"
            aria-label="Edit expense"
          >
            ✎
          </button>

          <button 
            @click="emit('delete-expense', expense.id)"
            class="icon-btn delete"
            aria-label="Delete expense"
          >
            ✕
          </button>
        </div>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.filter-section {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
  background: rgba(255,255,255,0.05);
  padding: 0.5rem;
  border-radius: 8px;
  flex-shrink: 0; /* Keep filter fixed at top if needed, or let it scroll with list? User wants NO scroll, so keep fixed */
}

.date-filter {
  margin-bottom: 0;
  width: auto;
  padding: 0.3rem;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.1);
  color: white;
  border-radius: 4px;
}

.clear-btn {
  padding: 0.3rem 0.6rem;
  font-size: 0.8rem;
  background-color: var(--color-text-muted);
  border: none;
  border-radius: 4px;
  color: #1e293b;
  cursor: pointer;
}

.empty-state {
  color: var(--color-text-muted);
  padding: 2rem;
  text-align: center;
}

.list-wrapper {
  flex: 1; /* Take remaining height */
  overflow-y: auto; /* Scroll internally */
  padding-bottom: 80px; /* Space for FAB/Nav */
}

.expense-item {
  display: flex; 
  justify-content: space-between; 
  align-items: center; 
  padding: 0.8rem 0.5rem; 
  border-bottom: 1px solid rgba(255,255,255,0.05);
  transition: background-color 0.2s;
}

.expense-item:hover {
  background-color: rgba(255, 255, 255, 0.05);
}

.icon-btn {
  background-color: transparent; 
  padding: 0.3rem; 
  border-radius: 4px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid transparent;
}

.icon-btn.edit {
  color: var(--color-text-muted);
  border-color: rgba(255, 255, 255, 0.1);
}

.icon-btn.delete {
  color: var(--color-danger);
  border-color: rgba(239, 68, 68, 0.2);
}
</style>
