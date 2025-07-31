<template>
  <div class="menu-item-wrapper" ref="dropdownRef">
    <div @click="toggle" class="menu-toggle">
      <slot name="trigger"></slot>
    </div>
    <transition name="dropdown-animation">
      <div v-if="isOpen" class="dropdown-content" @click="close">
        <slot name="content"></slot>
      </div>
    </transition>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

const isOpen = ref(false);
const dropdownRef = ref<HTMLElement | null>(null);

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};

const handleClickOutside = (event: MouseEvent) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
    close();
  }
};

onMounted(() => {
  document.addEventListener('click', handleClickOutside, true);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside, true);
});
</script>

<style scoped>
.menu-item-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.menu-toggle {
  cursor: pointer;
}

.dropdown-content {
  position: absolute;
  top: calc(100% + 5px);
  left: 0;
  background-color: var(--color-background-soft);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  border-radius: 6px;
  min-width: 220px;
  z-index: 60;
  display: flex;
  flex-direction: column;
  padding: 8px 0;
  border: 1px solid var(--color-border-light);
}

.dropdown-animation-enter-active {
  animation: fadeInDown 0.2s ease-out;
}
.dropdown-animation-leave-active {
  animation: fadeInDown 0.15s ease-in reverse;
}

@keyframes fadeInDown {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
