<script setup lang="ts">
import { computed, ref } from 'vue'
import BaseModal from '../common/BaseModal.vue'
import BaseButton from '../ui/BaseButton.vue'
import type { GraphElement, GraphNode, ValidationError } from '../../types'

const props = defineProps<{
  isOpen: boolean
  validationErrors: Map<string, ValidationError[]>
  elements: GraphElement[]
}>()

const emit = defineEmits(['close', 'select-node'])

const copySuccess = ref(false)

const nodeMap = computed(() => {
  const map = new Map<string, GraphNode>()
  for (const el of props.elements) {
    if (el.type === 'node') {
      map.set(el.id, el as GraphNode)
    }
  }
  return map
})

const errorsWithNodeNames = computed(() => {
  const allErrors: { nodeId: string; nodeName: string; errors: ValidationError[] }[] = []
  for (const [nodeId, errors] of props.validationErrors.entries()) {
    const node = nodeMap.value.get(nodeId)
    if (node) {
      allErrors.push({
        nodeId,
        nodeName: node.name,
        errors,
      })
    }
  }
  // Sort by node name for consistent order
  allErrors.sort((a, b) => a.nodeName.localeCompare(b.nodeName))
  return allErrors
})

const handleSelectNode = (nodeId: string) => {
  emit('select-node', nodeId)
  emit('close')
}

const copyLogs = () => {
  const logText = errorsWithNodeNames.value
    .map((item) => {
      const errorLines = item.errors.map((err) => `- ${err.message}`).join('\n')
      return `Node: ${item.nodeName}\n${errorLines}`
    })
    .join('\n\n')

  navigator.clipboard
    .writeText(logText)
    .then(() => {
      copySuccess.value = true
      setTimeout(() => {
        copySuccess.value = false
      }, 2000)
    })
    .catch((err) => {
      console.error('Failed to copy validation logs: ', err)
      alert('Could not copy logs to clipboard.')
    })
}
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>Model Validation Issues</h3>
    </template>
    <template #body>
      <div v-if="errorsWithNodeNames.length === 0" class="no-issues">
        <i class="fas fa-check-circle"></i>
        <p>No validation issues found. The model appears to be valid!</p>
      </div>
      <div v-else class="issues-list">
        <div v-for="item in errorsWithNodeNames" :key="item.nodeId" class="issue-item">
          <div
            class="issue-header"
            @click="handleSelectNode(item.nodeId)"
            title="Click to select node"
          >
            <strong>Node: {{ item.nodeName }}</strong>
            <i class="fas fa-crosshairs"></i>
          </div>
          <ul class="error-details">
            <li v-for="(error, index) in item.errors" :key="index">
              {{ error.message }}
            </li>
          </ul>
        </div>
      </div>
    </template>
    <template #footer>
      <div class="w-full flex justify-end">
        <BaseButton @click="copyLogs" type="secondary" v-if="errorsWithNodeNames.length > 0">
          <i v-if="copySuccess" class="fas fa-check"></i>
          <span v-else>Copy Logs</span>
        </BaseButton>
      </div>
    </template>
  </BaseModal>
</template>

<style scoped>
.no-issues {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 20px;
  color: var(--color-success);
}
.no-issues i {
  font-size: 3em;
  margin-bottom: 15px;
}
.no-issues p {
  font-size: 1.1em;
  font-weight: 500;
  margin: 0;
}
.issues-list {
  display: flex;
  flex-direction: column;
  gap: 15px;
}
.issue-item {
  background-color: var(--color-background-mute);
  border: 1px solid var(--color-border-light);
  border-left: 4px solid var(--color-danger);
  border-radius: 4px;
  padding: 10px 15px;
}
.issue-header {
  font-weight: 600;
  color: var(--color-heading);
  cursor: pointer;
  display: flex;
  justify-content: space-between;
  align-items: center;
  transition: color 0.2s ease;
}
.issue-header:hover {
  color: var(--color-primary);
}
.issue-header i {
  opacity: 0.6;
}
.error-details {
  margin: 8px 0 0 0;
  padding-left: 20px;
  font-size: 0.9em;
  color: var(--color-text);
}
</style>
