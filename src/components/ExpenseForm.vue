<script setup>
import { ref } from 'vue'

const emit = defineEmits(['add-expense'])

const title = ref('')
const amount = ref('')
const date = ref(new Date().toISOString().split('T')[0])
const category = ref('Food')

const handleSubmit = () => {
  if (!title.value || !amount.value || !date.value) return

  const newExpense = {
    id: crypto.randomUUID(),
    title: title.value,
    amount: parseFloat(amount.value),
    date: date.value,
    category: category.value
  }

  emit('add-expense', newExpense)

  // Reset form
  title.value = ''
  amount.value = ''
}
</script>

<template>
  <form @submit.prevent="handleSubmit">
    <div>
      <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">項目</label>
      <input 
        type="text" 
        v-model="title" 
        placeholder="例如：午餐" 
        required 
      />
    </div>
    
    <div style="display: flex; gap: 1rem;">
      <div style="flex: 1;">
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
      <div style="flex: 1;">
        <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">分類</label>
        <select v-model="category">
          <option value="Food">餐飲 🍔</option>
          <option value="Transport">交通 🚗</option>
          <option value="Utilities">水電 💡</option>
          <option value="Entertainment">娛樂 🎬</option>
          <option value="Health">醫療 🏥</option>
          <option value="Shopping">購物 🛍️</option>
          <option value="Other">其他 📦</option>
        </select>
      </div>
    </div>

    <div>
      <label style="display: block; margin-bottom: 0.5rem; color: var(--color-text-muted);">日期</label>
      <input 
        type="date" 
        v-model="date" 
        required 
      />
    </div>

    <button type="submit" class="w-full" style="margin-top: 1rem;">
      新增支出
    </button>
  </form>
</template>
