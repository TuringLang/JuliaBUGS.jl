<template>
  <transition name="modal-fade">
    <div v-if="isOpen" class="modal-overlay" @click.self="emit('close')">
      <div class="modal-content" role="dialog" aria-modal="true">
        <header v-if="$slots.header" class="modal-header">
          <slot name="header"></slot>
        </header>
        <section v-if="$slots.body" class="modal-body">
          <slot name="body"></slot>
        </section>
        <footer v-if="$slots.footer" class="modal-footer">
          <slot name="footer"></slot>
        </footer>
      </div>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue';

defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits(['close']);

const handleKeydown = (e: KeyboardEvent) => {
  if (e.key === 'Escape') {
    emit('close');
  }
};

onMounted(() => {
  document.addEventListener('keydown', handleKeydown);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleKeydown);
});
</script>

<style>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.6);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1050;
  padding: 1rem;
}

.modal-content {
  background-color: var(--color-background-soft, white);
  padding: 25px;
  border-radius: 8px;
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
  box-sizing: border-box;
  min-width: 320px;
  max-width: min(50vw, 500px);
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  position: relative;
}

.modal-content > * {
  max-width: 100%;
  box-sizing: border-box;
  word-break: break-word;
  overflow-wrap: break-word;
  white-space: normal;
}

.modal-content .flex-container,
.modal-content .grid-container {
  word-break: normal;
}

.modal-content pre,
.modal-content code,
.modal-content img,
.modal-content table {
  max-width: 100%;
  overflow-x: auto;
  display: block;
}

.modal-header {
  padding-bottom: 15px;
  margin-bottom: 15px;
  border-bottom: 1px solid var(--color-border-light, #e9ecef);
  flex-shrink: 0;
}

.modal-header h3 {
  margin: 0;
  font-size: 1.25em;
  color: var(--color-heading, #212529);
}

.modal-body {
  overflow-y: auto;
  flex-grow: 1;
  width: 100%;
  overflow-x: hidden;
  padding-right: 2px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.modal-footer {
  padding-top: 15px;
  margin-top: 15px;
  border-top: 1px solid var(--color-border-light, #e9ecef);
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  flex-shrink: 0;
}

.modal-fade-enter-active {
  animation: fadeIn 0.2s ease-out;
}

.modal-fade-leave-active {
  animation: fadeOut 0.2s ease-in forwards;
}

.modal-fade-enter-active .modal-content {
  animation: slideIn 0.3s cubic-bezier(0.25, 0.8, 0.25, 1);
}

.modal-fade-leave-active .modal-content {
  animation: slideOut 0.2s ease-in forwards;
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes fadeOut {
  from { opacity: 1; }
  to { opacity: 0; }
}

@keyframes slideIn {
  from { transform: translateY(-30px); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}

@keyframes slideOut {
  from { transform: translateY(0); opacity: 1; }
  to { transform: translateY(-30px); opacity: 0; }
}
</style>
