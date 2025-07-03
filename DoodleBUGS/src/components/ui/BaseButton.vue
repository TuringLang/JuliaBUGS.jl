<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  type?: 'primary' | 'secondary' | 'danger' | 'ghost';
  size?: 'small' | 'medium' | 'large';
  disabled?: boolean;
}>();

const buttonClass = computed(() => {
  return {
    'base-button': true,
    [`button-${props.type || 'default'}`]: true,
    [`button-${props.size || 'medium'}`]: true,
    'button-disabled': props.disabled
  };
});
</script>

<template>
  <button :class="buttonClass" :disabled="disabled">
    <slot></slot>
  </button>
</template>

<style scoped>
.base-button {
  padding: 8px 15px;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  background-color: var(--color-background-mute);
  color: var(--color-text);
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: 500;
  white-space: nowrap;
}

.base-button:hover:not(.button-disabled) {
  background-color: var(--color-border-light);
}

.base-button:focus {
  outline: none;
  box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25);
}

.button-primary {
  background-color: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}

.button-primary:hover:not(.button-disabled) {
  background-color: var(--color-primary-hover);
  border-color: var(--color-primary-hover);
}

.button-secondary {
  background-color: var(--color-secondary);
  color: white;
  border-color: var(--color-secondary);
}

.button-secondary:hover:not(.button-disabled) {
  background-color: var(--color-secondary-hover);
  border-color: var(--color-secondary-hover);
}

.button-danger {
  background-color: var(--color-danger);
  color: white;
  border-color: var(--color-danger);
}

.button-danger:hover:not(.button-disabled) {
  background-color: #c82333;
  border-color: #bd2130;
}

.button-ghost {
  background-color: transparent;
  border-color: transparent;
  color: var(--color-text-light);
}

.button-ghost:hover:not(.button-disabled) {
  background-color: rgba(255, 255, 255, 0.1);
}

.button-small {
  padding: 6px 10px;
  font-size: 0.8em;
}

.button-medium {
  padding: 8px 15px;
  font-size: 0.9em;
}

.button-large {
  padding: 12px 20px;
  font-size: 1.1em;
}

.button-disabled {
  opacity: 0.6;
  cursor: not-allowed;
  background-color: var(--color-background-mute) !important;
  color: var(--color-secondary) !important;
  border-color: var(--color-border) !important;
}
</style>
