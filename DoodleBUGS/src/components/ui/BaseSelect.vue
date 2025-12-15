<script setup lang="ts">
import Select from 'primevue/select'

// Relaxed interface to allow any object shape since we map with optionLabel/optionValue
export interface SelectOption {
  [key: string]: unknown
}

defineProps<{
  modelValue: string | number | null | undefined
  options: SelectOption[] | unknown[]
  disabled?: boolean
  placeholder?: string
  optionLabel?: string
  optionValue?: string
}>()

const emit = defineEmits(['update:modelValue', 'change'])
</script>

<template>
  <Select
    :model-value="modelValue"
    :options="options"
    :optionLabel="optionLabel || 'label'"
    :optionValue="optionValue || 'value'"
    :disabled="disabled"
    :placeholder="placeholder"
    @update:model-value="(val) => emit('update:modelValue', val)"
    @change="(e) => emit('change', e)"
    class="w-auto db-select-field"
  >
    <template #value="slotProps">
      <div v-if="slotProps.value" class="flex items-center">
        <slot name="value" :value="slotProps.value" :placeholder="slotProps.placeholder">
          {{
            // eslint-disable-next-line @typescript-eslint/ban-ts-comment
            // @ts-ignore - Dynamic access based on props
            options.find((o) => o[optionValue || 'value'] === slotProps.value)?.[
              optionLabel || 'label'
            ] || slotProps.value
          }}
        </slot>
      </div>
      <span v-else>
        {{ slotProps.placeholder || placeholder || 'Select...' }}
      </span>
    </template>

    <template #option="slotProps">
      <slot name="option" :option="slotProps.option">
        {{ slotProps.option[optionLabel || 'label'] }}
      </slot>
    </template>
  </Select>
</template>

<style scoped>
.db-select-field {
  font-size: 12px;
}
:deep(.p-select-label) {
  padding: 0.4rem 0.5rem;
}
</style>
