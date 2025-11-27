<script setup lang="ts">
import { ref, computed } from 'vue'
import BaseModal from '../common/BaseModal.vue'

defineProps<{
  isOpen: boolean
}>()

const emit = defineEmits(['close'])

interface FaqItem {
  q: string
  a: string
  open: boolean
}

const faqs = ref<FaqItem[]>([
  {
    q: 'How do I create a loop (Plate)?',
    a: 'Drag a "Plate" node from the left sidebar onto the canvas. You can then drop other nodes inside the plate to nest them, or drag existing nodes into it.',
    open: false,
  },
  {
    q: 'How do I run the model locally?',
    a: 'Use the "Script for Local Run" option in the bottom toolbar (under the Code menu). This generates a standalone Julia script that includes your model definition, data, and initial values. You can run this script using your local Julia installation.',
    open: false,
  },
  {
    q: 'Does this work on tablets/iPads?',
    a: 'Yes! DoodleBUGS supports touch interactions. However, for building complex models, we recommend using a desktop device with a mouse and keyboard for the best experience.',
    open: false,
  },
  {
    q: 'How do I delete a node or edge?',
    a: 'Select the element by tapping or clicking it (it will be highlighted), then open the "Inspector" panel (right sidebar). Click the red "Delete Element" button.',
    open: false,
  },
  {
    q: 'What are Stochastic vs Deterministic edges?',
    a: '<strong>Stochastic edges</strong> (dashed) represent probabilistic dependencies (e.g., parameters of a distribution). <strong>Deterministic edges</strong> (solid) represent functional relationships (e.g., variables in an equation).',
    open: false,
  },
  {
    q: 'How do I enter data?',
    a: 'Use the "Data & Inits" panel (accessible from the bottom toolbar). You can enter data in either JSON format or Julia syntax. The system will automatically parse it for the model.',
    open: false,
  },
  {
    q: 'Is my work saved?',
    a: "Yes, your projects and graphs are automatically saved to your browser's local storage. You can also export your graph as a JSON file to backup or share it.",
    open: false,
  },
])

const allExpanded = computed(() => faqs.value.every((item) => item.open))

const toggleAll = () => {
  const targetState = !allExpanded.value
  faqs.value.forEach((item) => (item.open = targetState))
}

const toggleItem = (index: number) => {
  faqs.value[index].open = !faqs.value[index].open
}
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <div class="header-row">
        <h3>Frequently Asked Questions</h3>
        <button
          class="toggle-all-btn"
          @click="toggleAll"
          :title="allExpanded ? 'Collapse All' : 'Expand All'"
        >
          <i :class="allExpanded ? 'fas fa-compress-alt' : 'fas fa-expand-alt'"></i>
        </button>
      </div>
    </template>
    <template #body>
      <div class="faq-layout">
        <div class="faq-list">
          <div
            v-for="(item, index) in faqs"
            :key="index"
            class="faq-item"
            :class="{ 'is-open': item.open }"
          >
            <div class="question" @click="toggleItem(index)">
              <div class="q-content">
                <span class="q-text">{{ item.q }}</span>
              </div>
              <i class="fas fa-chevron-down toggle-icon"></i>
            </div>
            <div class="answer-wrapper" :class="{ open: item.open }">
              <div class="answer" v-html="item.a"></div>
            </div>
          </div>
        </div>

        <div class="faq-footer">
          <p>Can't find your answer?</p>
          <a
            href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md"
            target="_blank"
            class="support-link"
          >
            Ask here <i class="fas fa-external-link-alt"></i>
          </a>
        </div>
      </div>
    </template>
  </BaseModal>
</template>

<style scoped>
.header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  padding-right: 20px;
}

.header-row h3 {
  margin: 0;
}

.toggle-all-btn {
  background: transparent;
  border: 1px solid var(--theme-border);
  border-radius: 4px;
  cursor: pointer;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--theme-text-secondary);
  transition: all 0.2s;
}

.toggle-all-btn:hover {
  background: var(--theme-bg-hover);
  color: var(--theme-primary);
  border-color: var(--theme-primary);
}

.faq-layout {
  display: flex;
  flex-direction: column;
  max-height: 60vh;
  padding-top: 10px;
}

.faq-list {
  flex-grow: 1;
  overflow-y: auto;
  padding-right: 6px;
  display: flex;
  flex-direction: column;
  gap: 0; /* Removed gap */
}

.faq-item {
  border-bottom: 1px solid var(--theme-border);
  /* Removed border, radius, background, overflow */
}

.faq-item:last-child {
  border-bottom: none;
}

.question {
  font-weight: 600;
  color: var(--theme-text-primary);
  font-size: 0.95em;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 0; /* Reduced padding, no side padding */
  cursor: pointer;
  background-color: transparent;
  transition: color 0.2s;
  user-select: none;
}

.question:hover {
  color: var(--theme-primary);
}

.q-content {
  display: flex;
  align-items: center;
  gap: 10px;
}

.q-content::before {
  content: 'Q';
  color: var(--theme-primary);
  font-weight: 800;
  font-size: 0.85em;
  opacity: 0.8;
  /* Removed background block styling for simple look */
}

.toggle-icon {
  transition: transform 0.3s ease;
  font-size: 0.85em;
  color: var(--theme-text-muted);
  margin-left: 10px;
}

.faq-item.is-open .toggle-icon {
  transform: rotate(180deg);
  color: var(--theme-primary);
}

.answer-wrapper {
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.4s cubic-bezier(0.4, 0, 0.2, 1);
}

.answer-wrapper.open {
  max-height: 1000px;
  transition: max-height 0.6s ease-in-out;
}

.answer {
  color: var(--theme-text-secondary);
  font-size: 0.9em;
  line-height: 1.6;
  padding: 0 0 15px 20px; /* Reduced padding, indented slightly */
}

.faq-footer {
  margin-top: 15px;
  padding: 15px;
  background-color: var(--theme-bg-hover);
  border-radius: var(--radius-md);
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 5px;
  flex-shrink: 0;
  border-top: 1px solid var(--theme-border);
}

.faq-footer p {
  margin: 0;
  font-weight: 500;
  color: var(--theme-text-primary);
}

.support-link {
  color: var(--theme-primary);
  font-weight: 600;
  text-decoration: none;
  display: flex;
  align-items: center;
  gap: 5px;
}

.support-link:hover {
  text-decoration: underline;
}
</style>
