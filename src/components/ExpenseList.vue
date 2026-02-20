<script setup>
import { ref, computed } from 'vue'
import { PhCaretDown, PhCaretUp, PhCaretLeft, PhCaretRight, PhCalendarBlank } from '@phosphor-icons/vue'

const props = defineProps({
  expenses: {
    type: Array,
    required: true
  },
  incomes: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['delete-expense', 'delete-income', 'edit-expense'])

const selectedDate = ref(new Date().toISOString().split('T')[0])
const isCalendarExpanded = ref(false)
const currentMonth = ref(new Date())

// --- Filter Modes ---
const filterMode = ref('calendar') // 'calendar' or 'range'
const startDate = ref('')
const endDate = ref('')

// --- Calendar State & Logic ---

const daysOfWeek = ['日', '一', '二', '三', '四', '五', '六']

const getDaysInMonth = (year, month) => {
  return new Date(year, month + 1, 0).getDate()
}

const getFirstDayOfMonth = (year, month) => {
  return new Date(year, month, 1).getDay()
}

// Check if a specific date string has any transactions
const hasTransactionsOnDate = (dateStr) => {
  const hasExp = props.expenses.some(e => e.date === dateStr)
  const hasInc = props.incomes.some(i => i.date === dateStr)
  return { hasExp, hasInc }
}

const calendarDays = computed(() => {
  const year = currentMonth.value.getFullYear()
  const month = currentMonth.value.getMonth()
  const daysInMonth = getDaysInMonth(year, month)
  const firstDayIndex = getFirstDayOfMonth(year, month)
  
  const days = []
  
  // Padding for previous month
  for (let i = 0; i < firstDayIndex; i++) {
    days.push({ class: 'empty' })
  }
  
  // Actual days
  const todayStr = new Date().toISOString().split('T')[0]
  
  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    const isToday = dateStr === todayStr
    const isSelected = dateStr === selectedDate.value
    const { hasExp, hasInc } = hasTransactionsOnDate(dateStr)
    
    days.push({
      dateStr,
      dayNumber: d,
      isToday,
      isSelected,
      hasExp,
      hasInc,
      class: 'active-day'
    })
  }
  return days
})

// Only show the row (week) that contains the selected date, or the current week if nothing selected
const collapsedCalendarDays = computed(() => {
  const fullCal = calendarDays.value
  const targetDateStr = selectedDate.value || new Date().toISOString().split('T')[0]
  
  // Find index of the target day
  let targetIndex = fullCal.findIndex(d => d.dateStr === targetDateStr)
  
  // If target day not in current displayed month, show first week
  if (targetIndex === -1) {
    if(!selectedDate.value) {
        // trying to show today
        return fullCal.slice(0, 7) // fallback to first week if today not in month
    }
    return fullCal.slice(0, 7)
  }
  
  // Calculate start of the week (assuming Sunday start)
  const rowStart = Math.floor(targetIndex / 7) * 7
  return fullCal.slice(rowStart, rowStart + 7)
})

const prevMonth = () => {
  currentMonth.value = new Date(currentMonth.value.getFullYear(), currentMonth.value.getMonth() - 1, 1)
}

const nextMonth = () => {
  currentMonth.value = new Date(currentMonth.value.getFullYear(), currentMonth.value.getMonth() + 1, 1)
}

const selectDate = (dateStr) => {
  if (!dateStr) return
  selectedDate.value = dateStr
}

const toggleCalendar = () => {
  isCalendarExpanded.value = !isCalendarExpanded.value
}

// --- List Logic ---

const filterByDateRange = (list) => {
  if (filterMode.value === 'calendar') {
    if (selectedDate.value) return list.filter(item => item.date === selectedDate.value)
    return list
  } else {
    // Range mode
    if (!startDate.value && !endDate.value) return list
    if (startDate.value && !endDate.value) return list.filter(item => item.date >= startDate.value)
    if (!startDate.value && endDate.value) return list.filter(item => item.date <= endDate.value)
    return list.filter(item => item.date >= startDate.value && item.date <= endDate.value)
  }
}

const filteredIncomes = computed(() => {
  let list = props.incomes.map(i => ({ ...i, type: 'income' }))
  list = filterByDateRange(list)
  return list.sort((a, b) => new Date(b.date) - new Date(a.date) || new Date(b.created_at) - new Date(a.created_at))
})

const filteredExpenses = computed(() => {
  let list = props.expenses.map(e => ({ ...e, type: 'expense' }))
  list = filterByDateRange(list)
  return list.sort((a, b) => new Date(b.date) - new Date(a.date) || new Date(b.created_at) - new Date(a.created_at))
})

const totalIncome = computed(() => {
  return filteredIncomes.value.reduce((sum, item) => sum + Number(item.amount), 0)
})

const totalExpense = computed(() => {
  return filteredExpenses.value.reduce((sum, item) => sum + Number(item.amount), 0)
})

const netBalance = computed(() => totalIncome.value - totalExpense.value)

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
  'Other': '其他 📦',
  'Salary': '薪水 💰',
  'Bonus': '獎金 🧧',
  'Investment': '投資 📈',
  'Gift': '紅包/禮金 🎁'
}

const getCategoryLabel = (cat) => categoryMap[cat] || cat
</script>

<template>
  <!-- Mode Toggle -->
  <div class="filter-controls">
    <div class="segmented-control">
      <button @click="filterMode = 'calendar'" :class="{ active: filterMode === 'calendar' }">單月日曆</button>
      <button @click="filterMode = 'range'" :class="{ active: filterMode === 'range' }">日期區間</button>
    </div>
  </div>

  <!-- Collapsible Calendar Widget -->
  <div class="calendar-widget" v-if="filterMode === 'calendar'">
    <div class="calendar-header">
      <div class="month-selector">
        <button @click="prevMonth" class="nav-btn"><PhCaretLeft size="18" weight="bold" /></button>
        <span class="current-month" @click="toggleCalendar">
          {{ currentMonth.getFullYear() }} 年 {{ currentMonth.getMonth() + 1 }} 月
          <PhCalendarBlank size="16" weight="bold" style="margin-left: 4px; opacity: 0.7;"/>
        </span>
        <button @click="nextMonth" class="nav-btn"><PhCaretRight size="18" weight="bold" /></button>
      </div>
      <button @click="toggleCalendar" class="expand-btn">
        <component :is="isCalendarExpanded ? PhCaretUp : PhCaretDown" size="18" weight="bold"/>
      </button>
    </div>

    <div class="calendar-body" :class="{ 'expanded': isCalendarExpanded }">
      <!-- Days of week -->
      <div class="weekdays">
        <div v-for="day in daysOfWeek" :key="day" class="weekday">{{ day }}</div>
      </div>
      
      <!-- Grid -->
      <div class="days-grid">
        <template v-if="isCalendarExpanded">
          <div 
            v-for="(day, index) in calendarDays" 
            :key="'full-'+index"
            class="day-cell"
            :class="[day.class, { 'today': day.isToday, 'selected': day.isSelected }]"
            @click="day.dateStr && selectDate(day.dateStr)"
          >
            <span v-if="day.dayNumber">{{ day.dayNumber }}</span>
            <div class="dots-container" v-if="day.dayNumber">
              <span v-if="day.hasInc" class="dot income-dot"></span>
              <span v-if="day.hasExp" class="dot expense-dot"></span>
            </div>
          </div>
        </template>
        <template v-else>
           <div 
            v-for="(day, index) in collapsedCalendarDays" 
            :key="'col-'+index"
            class="day-cell"
            :class="[day.class, { 'today': day.isToday, 'selected': day.isSelected }]"
            @click="day.dateStr && selectDate(day.dateStr)"
          >
            <span v-if="day.dayNumber">{{ day.dayNumber }}</span>
             <div class="dots-container" v-if="day.dayNumber">
              <span v-if="day.hasInc" class="dot income-dot"></span>
              <span v-if="day.hasExp" class="dot expense-dot"></span>
            </div>
          </div>
        </template>
      </div>
    </div>
    

  </div>

  <!-- Date Range Widget -->
  <div class="date-range-widget" v-if="filterMode === 'range'">
    <div class="date-range-picker">
      <div class="date-field">
        <label class="date-label">開始日</label>
        <input type="date" v-model="startDate" class="date-input" />
      </div>
      <div class="range-arrow">→</div>
      <div class="date-field">
        <label class="date-label">結束日</label>
        <input type="date" v-model="endDate" class="date-input" />
      </div>
      <button v-if="startDate || endDate" @click="startDate = ''; endDate = ''" class="clear-btn-small" title="清除">✕</button>
    </div>
  </div>

  <div v-if="filteredIncomes.length === 0 && filteredExpenses.length === 0" class="text-center empty-state">
    {{ filterMode === 'calendar' && selectedDate ? '這一天沒有帳目紀錄' : '目前沒有帳目紀錄，開始記帳吧！' }}
  </div>
  
  <div v-else class="list-wrapper">
    <!-- Net Balance Summary -->
    <div class="balance-summary" v-if="(filterMode === 'calendar' && selectedDate) || filterMode === 'range'">
      <span style="color: var(--color-text-muted)">{{ filterMode === 'calendar' ? '當日結餘:' : '範圍結餘:' }} </span>
      <span :style="{ color: netBalance >= 0 ? 'var(--color-success)' : 'var(--color-danger)', fontWeight: 'bold' }">
        {{ formatCurrency(netBalance) }}
      </span>
    </div>

    <!-- Income Section -->
    <div v-if="filteredIncomes.length > 0" class="section">
      <h3 class="section-title income-title">
        <span>💰 收入</span>
        <span class="section-total">+{{ formatCurrency(totalIncome) }}</span>
      </h3>
      <ul class="list">
        <li v-for="item in filteredIncomes" :key="item.id" class="expense-item">
           <div style="flex: 1;">
            <div style="font-weight: 500; font-size: 1rem;">{{ item.title }}</div>
            <div style="font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.2rem;">
              {{ formatDate(item.date) }}
            </div>
          </div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <div style="font-weight: bold; font-size: 1.1rem; color: var(--color-success);">
              +{{ formatCurrency(item.amount) }}
            </div>
             <button @click="emit('delete-income', item.id)" class="icon-btn delete">✕</button>
          </div>
        </li>
      </ul>
    </div>

     <!-- Expense Section -->
    <div v-if="filteredExpenses.length > 0" class="section">
      <h3 class="section-title expense-title">
        <span>💸 支出</span>
        <span class="section-total">-{{ formatCurrency(totalExpense) }}</span>
      </h3>
      <ul class="list">
        <li v-for="item in filteredExpenses" :key="item.id" class="expense-item">
          <div style="flex: 1;">
            <div style="font-weight: 500; font-size: 1rem;">{{ item.title }}</div>
            <div style="font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.2rem;">
              <span v-if="item.category" style="display: inline-block; background-color: rgba(255,255,255,0.1); padding: 0.1rem 0.4rem; border-radius: 4px; margin-right: 0.5rem;">
                {{ getCategoryLabel(item.category) }}
              </span>
              {{ formatDate(item.date) }}
            </div>
          </div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <div style="font-weight: bold; font-size: 1.1rem; color: white;">
              {{ formatCurrency(item.amount) }}
            </div>
             <button @click="emit('edit-expense', item)" class="icon-btn edit">✎</button>
             <button @click="emit('delete-expense', item.id)" class="icon-btn delete">✕</button>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
/* --- Calendar Widget Styles --- */
.calendar-widget {
  background: var(--color-bg);
  border-radius: 12px;
  margin-bottom: 1rem;
  overflow: hidden;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
  border: 1px solid rgba(255,255,255,0.05);
  flex-shrink: 0;
}

.calendar-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 1rem;
  background: rgba(255,255,255,0.02);
  border-bottom: 1px solid rgba(255,255,255,0.05);
}

.month-selector {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.current-month {
  font-weight: bold;
  font-size: 1rem;
  color: var(--color-text);
  cursor: pointer;
  display: flex;
  align-items: center;
}

.nav-btn, .expand-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  transition: background 0.2s;
}

.nav-btn:hover, .expand-btn:hover {
  background: rgba(255,255,255,0.1);
  color: white;
}

.calendar-body {
  padding: 0.5rem 1rem 1rem 1rem;
}

.weekdays {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  text-align: center;
  font-size: 0.75rem;
  color: var(--color-text-muted);
  margin-bottom: 0.5rem;
}

.days-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 2px;
}

.day-cell {
  aspect-ratio: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  font-size: 0.9rem;
  cursor: pointer;
  position: relative;
  transition: all 0.2s;
}

.day-cell.empty {
  visibility: hidden;
}

.day-cell.active-day {
  color: var(--color-text);
}

.day-cell.active-day:hover {
  background: rgba(255,255,255,0.05);
}

.day-cell.today {
  color: var(--color-accent);
  font-weight: bold;
}

.day-cell.selected {
  background: var(--color-primary);
  color: white;
  font-weight: bold;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.4);
}

.dots-container {
  display: flex;
  gap: 2px;
  position: absolute;
  bottom: 4px;
}

.dot {
  width: 4px;
  height: 4px;
  border-radius: 50%;
}

.income-dot { background-color: var(--color-success); }
.expense-dot { background-color: var(--color-text-muted); }

.day-cell.selected .expense-dot { background-color: rgba(255,255,255,0.8); }



/* --- List Styles --- */

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

.balance-summary {
  padding: 0 1rem 1rem;
  text-align: right;
  font-size: 0.95rem;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  margin-bottom: 1rem;
}

.section {
  margin-bottom: 1.5rem;
}

.section-title {
  padding: 0.5rem 1rem;
  margin: 0;
  font-size: 0.9rem;
  font-weight: 600;
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(255,255,255,0.02);
}

.income-title {
  color: var(--color-success);
}

.expense-title {
  color: white; /* or a specific expense color */
}

.section-total {
  font-family: monospace;
  font-size: 1rem;
}

.list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.icon-btn.delete {
  color: var(--color-danger);
  border-color: rgba(239, 68, 68, 0.2);
}

/* --- Filter Mode & Date Range Styles --- */
.filter-controls {
  margin-bottom: 0.5rem;
}

.segmented-control {
  display: flex;
  background: rgba(255, 255, 255, 0.05);
  padding: 4px;
  border-radius: 12px;
}

.segmented-control button {
  flex: 1;
  padding: 6px 0;
  font-size: 0.85rem;
  background: transparent;
  border: none;
  border-radius: 8px;
  color: var(--color-text-muted);
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: 500;
}

.segmented-control button.active {
  background: rgba(255, 255, 255, 0.1);
  color: var(--color-text);
  box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}

.date-range-widget {
  margin-bottom: 1rem;
}

.date-range-picker {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  background: rgba(255,255,255,0.04);
  padding: 0.6rem 0.75rem;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.08);
}

.date-field {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.date-label {
  font-size: 0.68rem;
  color: var(--color-text-muted);
  font-weight: 500;
  letter-spacing: 0.3px;
}

.date-input {
  width: 100%;
  background: transparent;
  border: none;
  color: var(--color-text);
  font-size: 0.85rem;
  outline: none;
  padding: 0;
  min-width: 0;
}
.date-input::-webkit-calendar-picker-indicator {
  filter: invert(1);
  opacity: 0.4;
  cursor: pointer;
  padding: 0;
  margin: 0;
  flex-shrink: 0;
}

.range-arrow {
  color: var(--color-text-muted);
  font-size: 0.9rem;
  flex-shrink: 0;
  padding: 0 2px;
}

.clear-btn-small {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  font-size: 0.75rem;
  padding: 2px 4px;
  border-radius: 4px;
  cursor: pointer;
  flex-shrink: 0;
  line-height: 1;
}
.clear-btn-small:hover {
  color: var(--color-danger);
}
</style>
