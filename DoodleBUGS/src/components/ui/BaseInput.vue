<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  modelValue: string | number;
  type?: string;
  placeholder?: string;
  disabled?: boolean;
  readonly?: boolean;
}>();

const emit = defineEmits(['update:modelValue', 'change', 'input', 'keyup.enter']);

const inputType = computed(() => props.type || 'text');

const handleInput = (event: Event) => {
  const target = event.target as HTMLInputElement;
  emit('update:modelValue', target.value);
  emit('input', event);
};

const handleChange = (event: Event) => {
  emit('change', event);
};

const handleKeyUpEnter = (event: KeyboardEvent) => {
  if (event.key === 'Enter') {
    emit('keyup.enter', event);
  }
};
</script>

<template>
  <input
    :type="inputType"
    :value="modelValue"
    :placeholder="placeholder"
    :disabled="disabled"
    :readonly="readonly"
    @input="handleInput"
    @change="handleChange"
    @keyup="handleKeyUpEnter"
    class="base-input"
  />
</template>

<style scoped>
.base-input {
  padding: 8px 12px;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  background-color: var(--color-background-soft);
  color: var(--color-text);
  box-sizing: border-box;
  font-size: 0.9em;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.base-input:focus {
  border-color: var(--color-primary);
  outline: none;
  box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25);
}

.base-input:disabled,
.base-input:readonly {
  background-color: var(--color-background-mute);
  cursor: not-allowed;
  opacity: 0.8;
}

.base-input[type="number"] {
  -moz-appearance: textfield;
  appearance: textfield;
}
.base-input[type="number"]::-webkit-outer-spin-button,
.base-input[type="number"]::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
</style>
