<script setup>
import { ref } from 'vue'
import ExpenseForm from './ExpenseForm.vue'
import ExpenseList from './ExpenseList.vue'
import Incomes from './Incomes.vue'
import { PhPlus, PhX } from '@phosphor-icons/vue'

const props = defineProps({
  expenses: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['add-expense', 'delete-expense', 'edit-expense'])

const activeTab = ref('expenses') // 'expenses' or 'incomes'
const showAddModal = ref(false)

const handleAddExpense = (expense) => {
  emit('add-expense', expense)
  showAddModal.value = false
}
</script>

<template>
  <div class="transactions-view">
    <!-- Header / Tabs -->
    <div class="header-actions">
      <div class="tabs">
        <button 
          :class="{ active: activeTab === 'expenses' }" 
          @click="activeTab = 'expenses'"
        >
          日常記帳
        </button>
        <button 
          :class="{ active: activeTab === 'incomes' }" 
          @click="activeTab = 'incomes'"
        >
          收入管理
        </button>
      </div>
      
      <!-- Add Button (Top Right) -->
       <button v-if="activeTab === 'expenses'" class="icon-add-btn" @click="showAddModal = true">
        <PhPlus size="20" weight="bold" />
      </button>
    </div>

    <!-- Expenses Content -->
    <div v-if="activeTab === 'expenses'" class="tab-content">
        <!-- List only, maximize space -->
        <div class="list-container">
          <ExpenseList :expenses="expenses" @delete-expense="emit('delete-expense', $event)" @edit-expense="emit('edit-expense', $event)" />
        </div>

        <!-- Add Expense Modal -->
        <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
          <div class="modal-content">
            <div class="modal-header">
              <h3>新增支出</h3>
              <button class="close-btn" @click="showAddModal = false"><PhX size="20" /></button>
            </div>
            <ExpenseForm @add-expense="handleAddExpense" />
          </div>
        </div>
    </div>

    <!-- Incomes Content -->
    <div v-else class="tab-content">
      <Incomes />
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
  justify-content: center;
  align-items: center;
  position: relative;
  margin-bottom: 1rem;
  padding: 0 1rem;
}

.tabs {
  display: flex;
  justify-content: center;
  gap: 0.5rem;
  background: rgba(0, 0, 0, 0.2);
  padding: 4px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.05);
}

.tabs button {
  background: none;
  border: none;
  padding: 6px 16px;
  border-radius: 8px;
  color: var(--color-text-muted);
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
  font-size: 0.9rem;
}

.tabs button.active {
  background: var(--color-primary);
  color: white;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
  font-weight: 600;
}

.icon-add-btn {
  position: absolute;
  right: 1rem;
  background: rgba(255,255,255,0.1);
  border: none;
  border-radius: 50%;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-primary);
  cursor: pointer;
}

.tab-content {
  flex: 1;
  overflow: hidden; /* Manage scroll internally */
  display: flex;
  flex-direction: column;
}

.list-container {
  flex: 1;
  overflow-y: auto;
  padding: 0 1rem;
  -webkit-overflow-scrolling: touch;
}

/* Modal Styles */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0,0,0,0.8);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
}

.modal-content {
  background: #1e293b;
  padding: 1.5rem;
  border-radius: 16px;
  width: 90%;
  max-width: 400px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  border: 1px solid rgba(255,255,255,0.1);
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
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
}

.close-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 4px;
}
</style>
