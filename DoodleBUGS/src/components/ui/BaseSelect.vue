<script setup lang="ts">
import Select from 'primevue/select'

interface SelectOption {
  value: string
  label: string
}

defineProps<{
  modelValue: string
  options: SelectOption[]
  disabled?: boolean
}>()

const emit = defineEmits(['update:modelValue', 'change'])
</script>

<template>
  <Select
    :model-value="modelValue"
    :options="options"
    optionLabel="label"
    optionValue="value"
    :disabled="disabled"
    @update:model-value="(val) => emit('update:modelValue', val)"
    @change="(e) => emit('change', e)"
    class="w-auto"
  />
</template>
