<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  expense: {
    type: Object,
    required: true
  },
  show: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['close', 'save'])

const editedExpense = ref({ ...props.expense })

watch(() => props.expense, (newVal) => {
  editedExpense.value = { ...newVal }
})

const save = () => {
  emit('save', editedExpense.value)
}
</script>

<template>
  <div v-if="show" class="modal-overlay" @click.self="emit('close')">
    <div class="modal-content card-glass">
      <h3>✏️ 編輯帳目</h3>
      
      <div class="form-group">
        <label>項目名稱 (例如: 搭公車)</label>
        <input v-model="editedExpense.title" placeholder="項目名稱" />
      </div>
      
      <div class="form-group">
        <label>金額</label>
        <input v-model="editedExpense.amount" type="number" placeholder="金額" />
      </div>
      
      <div class="form-group">
        <label>分類</label>
        <select v-model="editedExpense.category">
          <option value="Food">餐飲</option>
          <option value="Transport">交通</option>
          <option value="Utilities">水電</option>
          <option value="Entertainment">娛樂</option>
          <option value="Health">醫療</option>
          <option value="Shopping">購物</option>
          <option value="Other">其他</option>
        </select>
      </div>
      
      <div class="form-group">
        <label>日期</label>
        <input v-model="editedExpense.date" type="date" />
      </div>

      <div class="actions">
        <button @click="emit('close')" class="cancel-btn">取消</button>
        <button @click="save" class="save-btn">儲存修改</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.7);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
  backdrop-filter: blur(4px);
}

.modal-content {
  background: #1e1e2e; /* Fallback */
  background: linear-gradient(135deg, rgba(30, 30, 46, 0.95), rgba(40, 40, 60, 0.95));
  padding: 1.25rem 1rem;
  border-radius: 16px;
  width: 95%;
  max-width: 400px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
  border: 1px solid rgba(255, 255, 255, 0.1);
}

h3 {
  text-align: center;
  margin-bottom: 1.5rem;
  color: var(--color-text);
}

.form-group {
  margin-bottom: 1.2rem;
}
.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  color: var(--color-text-muted);
  font-size: 0.9rem;
}

.actions {
  display: flex;
  justify-content: space-between;
  margin-top: 2rem;
  gap: 1rem;
}

button {
  flex: 1;
  padding: 0.8rem;
  font-size: 1rem;
}

.cancel-btn {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.2);
  color: var(--color-text-muted);
}
.cancel-btn:hover {
  background: rgba(255, 255, 255, 0.05);
  color: var(--color-text);
}

.save-btn {
  background: var(--color-primary);
  color: white;
  border: none;
}
</style>
