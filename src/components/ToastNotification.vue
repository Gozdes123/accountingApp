<script setup>
import { PhCheckCircle, PhWarning, PhInfo } from '@phosphor-icons/vue'
import { ref } from 'vue'

const props = defineProps({
  notifications: {
    type: Array, // [{ id, type: 'success'|'error', message }]
    required: true
  }
})

const getIcon = (type) => {
  if (type === 'success') return PhCheckCircle
  if (type === 'error') return PhWarning
  return PhInfo
}
</script>

<template>
  <div class="toast-container">
    <TransitionGroup name="toast">
      <div v-for="note in notifications" :key="note.id" class="toast" :class="note.type">
        <component :is="getIcon(note.type)" size="24" weight="fill" />
        <span class="message">{{ note.message }}</span>
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toast-container {
  position: fixed;
  top: 20px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 1000;
  display: flex;
  flex-direction: column;
  gap: 10px;
  pointer-events: none;
}

.toast {
  background: rgba(30, 41, 59, 0.95);
  backdrop-filter: blur(8px);
  color: white;
  padding: 12px 20px;
  border-radius: 50px;
  display: flex;
  align-items: center;
  gap: 10px;
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.3);
  border: 1px solid rgba(255,255,255,0.1);
  min-width: 300px;
  justify-content: center;
}

.toast.success { border-color: var(--color-success); }
.toast.success svg { color: var(--color-success); }

.toast.error { border-color: var(--color-danger); }
.toast.error svg { color: var(--color-danger); }

/* Animation */
.toast-enter-active,
.toast-leave-active {
  transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

.toast-enter-from {
  opacity: 0;
  transform: translateY(-20px) scale(0.9);
}
.toast-leave-to {
  opacity: 0;
  transform: translateY(-20px);
}
</style>
