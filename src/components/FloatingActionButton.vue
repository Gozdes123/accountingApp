<script setup>
import { ref } from 'vue'
import { PhPlus, PhX, PhReceipt, PhWallet, PhStar } from '@phosphor-icons/vue'

const emit = defineEmits(['open-quick-add', 'open-income-add', 'open-fav-add'])
const isOpen = ref(false)

const toggleMenu = () => {
  isOpen.value = !isOpen.value
}

const handleAction = (action) => {
  if (action === 'expense') emit('open-quick-add')
  if (action === 'income') emit('open-income-add')
  if (action === 'fav') emit('open-fav-add')
  isOpen.value = false
}
</script>

<template>
  <div class="fab-container">
    <!-- Overlay -->
    <div v-if="isOpen" class="overlay" @click="isOpen = false"></div>

    <!-- Action Buttons -->
    <div class="actions" :class="{ open: isOpen }">
      <button @click="handleAction('fav')" class="action-btn" style="transition-delay: 0ms;">
        <span class="label">常用</span>
        <div class="icon-circle sec"><PhStar size="20" weight="fill" /></div>
      </button>
      <button @click="handleAction('income')" class="action-btn" style="transition-delay: 50ms;">
        <span class="label">收入</span>
        <div class="icon-circle sec"><PhWallet size="20" weight="fill" /></div>
      </button>
      <button @click="handleAction('expense')" class="action-btn" style="transition-delay: 100ms;">
        <span class="label">支出</span>
        <div class="icon-circle prim"><PhReceipt size="20" weight="fill" /></div>
      </button>
    </div>

    <!-- Main FAB -->
    <button class="main-fab" @click="toggleMenu" :class="{ active: isOpen }">
      <PhPlus size="28" weight="bold" v-if="!isOpen" />
      <PhX size="28" weight="bold" v-else />
    </button>
  </div>
</template>

<style scoped>
.fab-container {
  position: fixed;
  bottom: 80px; /* Above bottom nav */
  right: 20px;
  z-index: 200;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0,0,0,0.6);
  backdrop-filter: blur(2px);
  z-index: 199; /* Below FAB but above everything else */
}

.main-fab {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: var(--color-primary);
  color: white;
  border: none;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.3s, background-color 0.3s;
  z-index: 200;
}

.main-fab:active {
  transform: scale(0.95);
}

.main-fab.active {
  background: var(--color-text-muted);
  transform: rotate(90deg);
}

.actions {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-bottom: 12px;
  align-items: flex-end;
  pointer-events: none;
  z-index: 201; /* Ensure above overlay (199) and main fab (200) if needed, or just above overlay */
}

.actions.open {
  pointer-events: auto;
}

.action-btn {
  display: flex;
  align-items: center;
  gap: 12px;
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  opacity: 0;
  transform: translateY(20px) scale(0.8);
  transition: opacity 0.2s, transform 0.2s;
}

.actions.open .action-btn {
  opacity: 1;
  transform: translateY(0) scale(1);
}

.icon-circle {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 8px rgba(0,0,0,0.3);
  color: white;
}

.prim { background: var(--color-danger); } /* Expense is red/danger usually, or primary */
.sec { background: var(--color-card-bg); border: 1px solid rgba(255,255,255,0.1); }

.label {
  background: rgba(255,255,255,0.9);
  color: #0f172a;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 0.85rem;
  font-weight: 500;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
</style>
