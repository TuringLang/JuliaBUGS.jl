<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import BaseModal from '../common/BaseModal.vue'
import BaseButton from '../ui/BaseButton.vue'
import BaseInput from '../ui/BaseInput.vue'

export type ExportType = 'png' | 'jpg' | 'svg'

interface ExportOptions {
  bg: string
  full: boolean
  scale: number
  quality?: number
  maxWidth?: number
  maxHeight?: number
}

const props = defineProps<{
  isOpen: boolean
  exportType: ExportType | null
}>()

const emit = defineEmits(['close', 'confirm-export'])

const options = ref({
  bg: '#ffffff',
  full: true,
  scale: 2,
  quality: 0.92,
  maxWidth: '' as string,
  maxHeight: '' as string,
})

watch(
  () => props.isOpen,
  (newVal) => {
    if (newVal) {
      options.value = {
        bg: props.exportType === 'png' || props.exportType === 'svg' ? 'transparent' : '#ffffff',
        full: true,
        scale: 2,
        quality: 0.92,
        maxWidth: '',
        maxHeight: '',
      }
    }
  }
)

const title = computed(() => {
  if (!props.exportType) return 'Export'
  return `Export as ${props.exportType.toUpperCase()}`
})

const handleConfirm = () => {
  const exportOptions: ExportOptions = {
    bg: options.value.bg,
    full: options.value.full,
    scale: options.value.scale,
  }

  if (props.exportType === 'jpg') {
    exportOptions.quality = options.value.quality
  }

  if (options.value.maxWidth) {
    exportOptions.maxWidth = Number(options.value.maxWidth)
  }
  if (options.value.maxHeight) {
    exportOptions.maxHeight = Number(options.value.maxHeight)
  }

  emit('confirm-export', exportOptions)
  emit('close')
}
</script>

<template>
  <BaseModal :is-open="isOpen" @close="$emit('close')">
    <template #header>
      <h3>{{ title }}</h3>
    </template>
    <template #body>
      <div class="db-export-options-form">
        <div class="db-form-group">
          <label for="export-bg">Background Color:</label>
          <BaseInput id="export-bg" type="color" v-model="options.bg" />
        </div>

        <div class="db-form-group checkbox-group">
          <label for="export-full">Export Full Graph:</label>
          <input id="export-full" type="checkbox" v-model="options.full" />
          <small class="db-help-text">(Uncheck to export current view only)</small>
        </div>

        <div class="db-form-group">
          <label for="export-scale">Scale:</label>
          <BaseInput
            id="export-scale"
            type="number"
            v-model.number="options.scale"
            min="0.1"
            step="0.1"
          />
        </div>

        <template v-if="exportType === 'png' || exportType === 'jpg'">
          <div class="db-form-group">
            <label for="export-maxWidth">Max Width (optional):</label>
            <BaseInput
              id="export-maxWidth"
              type="number"
              v-model="options.maxWidth"
              placeholder="e.g., 1920"
            />
          </div>
          <div class="db-form-group">
            <label for="export-maxHeight">Max Height (optional):</label>
            <BaseInput
              id="export-maxHeight"
              type="number"
              v-model="options.maxHeight"
              placeholder="e.g., 1080"
            />
          </div>
        </template>

        <template v-if="exportType === 'jpg'">
          <div class="db-form-group">
            <label for="export-quality">JPG Quality (0 to 1):</label>
            <input
              id="export-quality"
              type="range"
              v-model.number="options.quality"
              min="0"
              max="1"
              step="0.01"
            />
            <span>{{ options.quality.toFixed(2) }}</span>
          </div>
        </template>
      </div>
    </template>
    <template #footer>
      <BaseButton @click="handleConfirm" type="primary">Export</BaseButton>
    </template>
  </BaseModal>
</template>

<style scoped>
.db-export-options-form {
  display: flex;
  flex-direction: column;
  gap: 15px;
}
.db-form-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.db-form-group.checkbox-group {
  flex-direction: row;
  align-items: center;
}
.db-form-group label {
  font-weight: 500;
  color: var(--color-text);
  font-size: 0.9em;
}
.db-form-group input[type='range'] {
  flex-grow: 1;
}
.db-form-group span {
  font-size: 0.9em;
  font-variant-numeric: tabular-nums;
}
.db-help-text {
  font-size: 0.8em;
  color: var(--color-secondary);
  font-style: italic;
}
</style>
