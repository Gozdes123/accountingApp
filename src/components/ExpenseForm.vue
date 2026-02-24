<script setup>
import { ref } from 'vue'
import { PhReceipt, PhWallet, PhCheckCircle } from '@phosphor-icons/vue'

const props = defineProps({
  initialType: {
    type: String,
    default: 'expense'
  },
  accounts: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['add-expense', 'update:type'])

const getLocalDateStr = () => {
  const d = new Date()
  const year = d.getFullYear()
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

const title = ref('')
const amount = ref('')
const date = ref(getLocalDateStr())
const type = ref(props.initialType) // 'expense' or 'income'
const category = ref(props.initialType === 'income' ? 'Salary' : 'Food')
const accountId = ref('') // Selected Account ID

import { watch, onMounted } from 'vue'

onMounted(() => {
  if (props.accounts.length > 0) {
    accountId.value = props.accounts[0].id
  }
})

watch(() => props.accounts, (newVal) => {
  if (newVal.length > 0 && !accountId.value) {
    accountId.value = newVal[0].id
  }
}, { immediate: true })
watch(type, (newType) => {
  if (newType === 'income') {
    category.value = 'Salary'
  } else {
    category.value = 'Food'
  }
})

const handleSubmit = () => {
  if (!title.value || !amount.value || !date.value) return

  const newExpense = {
    id: crypto.randomUUID(),
    title: title.value,
    amount: parseFloat(amount.value),
    date: date.value,
    type: type.value,
    category: category.value,
    account_id: accountId.value
  }

  emit('add-expense', newExpense)

  // Reset form
  title.value = ''
  amount.value = ''
  // keep date and type as is for convenience
}
</script>

<template>
  <form @submit.prevent="handleSubmit">
    <!-- Type Selector -->
    <!-- Type Selector -->
    <div class="type-selector">
      <button 
        type="button"
        @click="type = 'expense'; $emit('update:type', 'expense')"
        class="type-btn"
        :class="{ active: type === 'expense', 'expense-active': type === 'expense' }"
      >
        <div class="icon-wrapper">
          <PhReceipt size="24" weight="fill" v-if="type === 'expense'" />
          <PhReceipt size="24" weight="regular" v-else />
        </div>
        <span>支出</span>
        <PhCheckCircle v-if="type === 'expense'" size="16" weight="fill" class="check-icon" />
      </button>

      <button 
        type="button"
        @click="type = 'income'; $emit('update:type', 'income')"
        class="type-btn"
        :class="{ active: type === 'income', 'income-active': type === 'income' }"
      >
        <div class="icon-wrapper">
          <PhWallet size="24" weight="fill" v-if="type === 'income'" />
          <PhWallet size="24" weight="regular" v-else />
        </div>
        <span>收入</span>
        <PhCheckCircle v-if="type === 'income'" size="16" weight="fill" class="check-icon" />
      </button>
    </div>

    <div>
      <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">項目</label>
      <input 
        type="text" 
        v-model="title" 
        placeholder="例如：午餐" 
        required 
      />
    </div>
    
    <div style="display: flex; gap: 0.75rem; flex-wrap: wrap;">
      <div style="flex: 1; min-width: 120px;">
        <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">金額</label>
        <input 
          type="number" 
          v-model="amount" 
          placeholder="0" 
          min="0" 
          step="1" 
          required 
        />
      </div>
      <div style="flex: 1; min-width: 120px;">
        <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">分類</label>
        <select v-model="category" :disabled="false">
          <template v-if="type === 'expense'">
            <option value="Food">餐飲 🍔</option>
            <option value="Transport">交通 🚗</option>
            <option value="Utilities">水電 💡</option>
            <option value="Entertainment">娛樂 🎬</option>
            <option value="Health">醫療 🏥</option>
            <option value="Shopping">購物 🛍️</option>
            <option value="Other">其他 📦</option>
          </template>
          <template v-else>
            <option value="Salary">薪水 💰</option>
            <option value="Bonus">獎金 🧧</option>
            <option value="Investment">投資 📈</option>
            <option value="Gift">紅包/禮金 🎁</option>
            <option value="Other">其他 📦</option>
          </template>
        </select>
      </div>
    </div>

    <div v-if="accounts.length > 0">
      <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">扣款/入帳帳戶</label>
      <div class="account-scroll">
        <div 
          v-for="acc in accounts" 
          :key="acc.id"
          @click="accountId = acc.id"
          class="account-chip"
          :class="{ active: accountId === acc.id }"
        >
          {{ acc.name }}
        </div>
      </div>
    </div>

    <div>
      <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">日期</label>
      <input 
        type="date" 
        v-model="date" 
        style="width: 100%; min-width: 0;"
        required 
      />
    </div>

    <button 
      type="submit" 
      class="w-full" 
      style="margin-top: 1rem;"
      :style="{ background: type === 'income' ? 'var(--color-success)' : '' }"
    >
      {{ type === 'income' ? '新增收入' : '新增支出' }}
    </button>
  </form>
</template>

<style scoped>
.type-selector {
  display: flex;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.type-btn {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 1rem;
  border-radius: 12px;
  border: 2px solid rgba(255,255,255,0.05);
  background: rgba(255,255,255,0.02);
  color: var(--color-text-muted);
  cursor: pointer;
  position: relative;
  transition: all 0.2s;
}

.type-btn:hover {
  background: rgba(255,255,255,0.05);
}

.type-btn.active {
  border-color: transparent;
  color: white;
}

.expense-active {
  background: linear-gradient(135deg, var(--color-primary), #2563eb);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.income-active {
  background: linear-gradient(135deg, var(--color-success), #059669);
  box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
}

.icon-wrapper {
  margin-bottom: 2px;
}

.check-icon {
  position: absolute;
  top: 8px;
  right: 8px;
  opacity: 0.8;
}

.account-scroll {
  display: flex;
  gap: 0.6rem;
  overflow-x: auto;
  padding-bottom: 4px;
}

.account-chip {
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.1);
  padding: 6px 12px;
  border-radius: 20px;
  color: var(--color-text-muted);
  white-space: nowrap;
  font-size: 0.9rem;
  cursor: pointer;
  transition: all 0.2s;
}

.account-chip.active {
  background: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}
</style>
