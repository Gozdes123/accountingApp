<script setup>
import { PhHouse, PhListDashes, PhCalendarCheck, PhTrendUp, PhWallet, PhBank } from '@phosphor-icons/vue'

defineProps({
  currentTab: {
    type: String,
    required: true
  }
})

const emit = defineEmits(['update:currentTab'])

const navItems = [
  { id: 'dashboard', label: '總覽', icon: PhHouse },
  { id: 'transactions', label: '帳務', icon: PhListDashes },
  { id: 'assets', label: '資產', icon: PhBank },
  { id: 'subscriptions', label: '訂閱', icon: PhCalendarCheck },
  { id: 'investments', label: '投資', icon: PhTrendUp },
]
</script>

<template>
  <nav class="bottom-nav">
    <button 
      v-for="item in navItems" 
      :key="item.id"
      :class="{ active: currentTab === item.id }"
      @click="emit('update:currentTab', item.id)"
      class="nav-item"
    >
      <component :is="item.icon" size="24" weight="fill" v-if="currentTab === item.id" />
      <component :is="item.icon" size="24" weight="regular" v-else />
      <span class="nav-label">{{ item.label }}</span>
    </button>
  </nav>
</template>

<style scoped>
.bottom-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  width: 100%;
  height: 60px; /* Standard mobile nav height */
  background: rgba(15, 23, 42, 0.95); /* Dark background */
  backdrop-filter: blur(12px);
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  display: flex;
  justify-content: space-around;
  align-items: center;
  z-index: 100;
  padding-bottom: env(safe-area-inset-bottom);
}

.nav-item {
  background: none;
  border: none;
  color: var(--color-text-muted);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4px;
  width: 100%;
  height: 100%;
  transition: color 0.2s;
}

.nav-item.active {
  color: var(--color-primary);
}

.nav-label {
  font-size: 0.7rem;
  margin-top: 2px;
}
</style>
