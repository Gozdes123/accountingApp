<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabaseClient'

const emit = defineEmits(['add-expense'])

const getLocalDateStr = () => {
  const d = new Date()
  const year = d.getFullYear()
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

const favorites = ref([])
const showAddModal = ref(false)
const newFav = ref({ title: '', amount: '', category: 'Food' })
const selectedDate = ref(getLocalDateStr())

const fetchFavorites = async () => {
  const { data, error } = await supabase
    .from('favorites')
    .select('*')
    .order('created_at', { ascending: false })

  if (error) console.error('Error fetching favorites:', error)
  else favorites.value = data
}

const addFavorite = async () => {
  if (!newFav.value.title || !newFav.value.amount) return

  const { data, error } = await supabase
    .from('favorites')
    .insert([{
      title: newFav.value.title,
      amount: newFav.value.amount,
      category: newFav.value.category
    }])
    .select()

  if (error) {
    console.error('Error adding favorite:', error)
  } else {
    favorites.value.unshift(data[0])
    showAddModal.value = false
    newFav.value = { title: '', amount: '', category: 'Food' }
  }
}

const useFavorite = (fav) => {
  // Emit event to parent to add expense immediately
  const expense = {
    title: fav.title,
    amount: fav.amount,
    category: fav.category,
    date: selectedDate.value
  }
  emit('add-expense', expense)
}

const deleteFavorite = async (id) => {
  const { error } = await supabase
    .from('favorites')
    .delete()
    .eq('id', id)

  if (!error) {
    favorites.value = favorites.value.filter(f => f.id !== id)
  }
}

onMounted(() => {
  fetchFavorites()
})
</script>

<template>
  <div class="favorites-section">
    <div class="header">
      <div class="fav-date-selector">
        <label>日期:</label>
        <input type="date" v-model="selectedDate" />
      </div>
      <button @click="showAddModal = !showAddModal" class="add-btn" :class="{ 'cancel': showAddModal }">
        {{ showAddModal ? '取消' : '+ 新增常用' }}
      </button>
    </div>

    <!-- Quick Add Form -->
    <div v-if="showAddModal" class="add-form card-glass">
      <div class="form-row">
        <input v-model="newFav.title" placeholder="項目名稱 (例如: 捷運)" />
        <input v-model="newFav.amount" type="number" placeholder="金額" />
        <select v-model="newFav.category">
          <option value="Food">餐飲</option>
          <option value="Transport">交通</option>
          <option value="Utilities">水電</option>
          <option value="Entertainment">娛樂</option>
          <option value="Health">醫療</option>
          <option value="Shopping">購物</option>
          <option value="Other">其他</option>
        </select>
        <button @click="addFavorite">儲存</button>
      </div>
    </div>

    <!-- Favorites List (Horizontal Scroll or Grid) -->
    <div class="favorites-grid">
      <div v-for="fav in favorites" :key="fav.id" class="fav-card" @click="useFavorite(fav)">
        <div class="fav-icon">{{ fav.category === 'Food' ? '🍔' : fav.category === 'Transport' ? '🚗' : '📦' }}</div>
        <div class="fav-info">
          <div class="fav-title">{{ fav.title }}</div>
          <div class="fav-amount">${{ fav.amount }}</div>
        </div>
        <div class="fav-actions">
          <button @click.stop="deleteFavorite(fav.id)" class="delete-btn">×</button>
        </div>
      </div>
      <div v-if="favorites.length === 0" class="no-favs">
        尚未設定常用消費
      </div>
    </div>
  </div>
</template>

<style scoped>
.favorites-section {
  margin-bottom: 2rem;
  width: 100%;
  max-width: 800px;
  margin-left: auto;
  margin-right: auto;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.fav-date-selector {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.fav-date-selector label {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}

.fav-date-selector input {
  padding: 0.3rem 0.5rem;
  font-size: 0.9rem;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  color: white;
  border-radius: 6px;
}

.header h3 {
  margin: 0;
  font-size: 1.2rem;
  color: var(--color-text);
}

.add-btn {
  padding: 0.3rem 0.8rem;
  font-size: 0.9rem;
}

.add-btn.cancel {
  background-color: transparent;
  border: 1px solid var(--color-text-muted);
}

.card-glass {
  background: rgba(255, 255, 255, 0.05);
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
}

.form-row {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.form-row input,
.form-row select {
  flex: 1;
  min-width: 100px;
  margin-bottom: 0;
  padding: 0.5rem;
  font-size: 0.9rem;
}

.favorites-grid {
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
  max-height: 60vh;
  overflow-y: auto;
  overflow-x: hidden;
  padding-bottom: 0.5rem;
  padding-top: 0.5rem;
}

.fav-card {
  width: 100%;
  box-sizing: border-box;
  background: var(--color-card-bg);
  border: 1px solid rgba(255, 255, 255, 0.1);
  padding: 0.8rem 1rem;
  border-radius: 12px;
  cursor: pointer;
  transition: transform 0.2s, background-color 0.2s;
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 1rem;
}

.fav-card:hover {
  transform: translateY(-2px);
  background-color: rgba(59, 130, 246, 0.2);
  /* primary color tint */
  border-color: var(--color-primary);
}

.fav-card:active {
  transform: scale(0.98);
}

.fav-icon {
  font-size: 1.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 50%;
  flex-shrink: 0;
}

.fav-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
  text-align: left;
}

.fav-title {
  font-weight: 500;
  font-size: 1rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--color-text);
  width: 100%;
}

.fav-amount {
  color: var(--color-success);
  font-weight: bold;
  font-size: 0.95rem;
}

.fav-actions {
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.delete-btn {
  background: transparent;
  color: var(--color-text-muted);
  border: none;
  font-size: 1.5rem;
  line-height: 1;
  padding: 8px;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  transition: all 0.2s;
}

.delete-btn:hover {
  background: rgba(239, 68, 68, 0.1);
  color: var(--color-danger);
  transform: none;
  box-shadow: none;
}

.no-favs {
  color: var(--color-text-muted);
  font-size: 0.9rem;
  font-style: italic;
  padding: 1rem;
  width: 100%;
  text-align: center;
  background: rgba(255, 255, 255, 0.03);
  border-radius: 8px;
}
</style>
