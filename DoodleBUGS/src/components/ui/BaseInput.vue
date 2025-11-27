<script setup lang="ts">
import InputText from 'primevue/inputtext'
import { computed } from 'vue'

const props = defineProps<{
  modelValue: string | number | null | undefined
  type?: string
  placeholder?: string
  disabled?: boolean
  readonly?: boolean
}>()

const emit = defineEmits(['update:modelValue', 'change', 'input', 'keyup.enter'])

const stringValue = computed(() => {
  if (props.modelValue === null || props.modelValue === undefined) return ''
  return String(props.modelValue)
})

const handleUpdate = (val: string | null | undefined) => {
  if (props.type === 'number' && val !== null && val !== undefined && val !== '') {
    const num = Number(val)
    emit('update:modelValue', isNaN(num) ? val : num)
  } else {
    emit('update:modelValue', val)
  }
}
</script>

<template>
  <InputText
    :type="type || 'text'"
    :model-value="stringValue"
    :placeholder="placeholder"
    :disabled="disabled"
    :readonly="readonly"
    @update:model-value="handleUpdate"
    @change="(e) => emit('change', e)"
    @input="(e) => emit('input', e)"
    @keyup.enter="(e) => emit('keyup.enter', e)"
    class="w-full base-input-field"
  />
</template>
