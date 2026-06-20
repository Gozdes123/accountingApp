<script setup>
import { PhChartBar, PhChartLine, PhDotsThree } from '@phosphor-icons/vue'

defineProps({
  currentTab: {
    type: String,
    required: true
  }
})

const emit = defineEmits(['update:currentTab'])

const navItems = [
  { id: 'list', icon: PhChartBar },
  { id: 'trend', icon: PhChartLine },
  { id: 'settings', icon: PhDotsThree }
]
</script>

<template>
  <div class="bottom-nav-container">
    <nav class="bottom-nav">
      <button 
        v-for="item in navItems" 
        :key="item.id"
        :class="{ active: currentTab === item.id }"
        @click="emit('update:currentTab', item.id)"
        class="nav-item"
      >
        <component :is="item.icon" class="nav-icon" weight="bold" />
      </button>
    </nav>
  </div>
</template>

<style scoped>
.bottom-nav-container {
  position: fixed;
  bottom: 24px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 1000;
  width: auto;
}

.bottom-nav {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1.5rem;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 99px;
  padding: 8px 18px;
  box-shadow: 
    0 10px 30px rgba(0, 0, 0, 0.04),
    0 1px 2px rgba(0, 0, 0, 0.03);
}

.nav-item {
  background: none;
  border: none;
  color: #828e9e;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 6px;
  border-radius: 50%;
  cursor: pointer;
  transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: none !important; /* Remove global button shadow */
}

.nav-item:hover {
  color: #1a1e26;
  transform: scale(1.08);
}

.nav-item:active {
  transform: scale(0.95);
}

.nav-icon {
  font-size: 22px;
}

.nav-item.active {
  color: #1a1e26;
  transform: scale(1.1);
}
</style>
