<script setup lang="ts">
import InputText from 'primevue/inputtext';

defineProps<{
  modelValue: string | number | null | undefined;
  type?: string;
  placeholder?: string;
  disabled?: boolean;
  readonly?: boolean;
}>();

const emit = defineEmits(['update:modelValue', 'change', 'input', 'keyup.enter']);
</script>

<template>
  <InputText
    :type="type || 'text'"
    :model-value="modelValue"
    :placeholder="placeholder"
    :disabled="disabled"
    :readonly="readonly"
    @update:model-value="(val) => emit('update:modelValue', val)"
    @change="(e) => emit('change', e)"
    @input="(e) => emit('input', e)"
    @keyup.enter="(e) => emit('keyup.enter', e)"
    class="w-full"
  />
</template>
