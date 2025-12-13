<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>About DoodleBUGS</h3>
    </template>
    <template #body>
      <div class="db-about-content">
        <p>
          <strong>DoodleBUGS</strong> is a graphical modelling tool designed to simplify the
          creation of Bayesian models for analysis with the BUGS language using
          <a
            href="https://github.com/TuringLang/JuliaBUGS.jl"
            target="_blank"
            rel="noopener noreferrer"
            >JuliaBUGS.jl</a
          >.
        </p>
        <p>
          Our goal is to provide an intuitive, visual interface for statisticians, researchers, and
          students to build, understand, and share complex probabilistic models.
        </p>

        <div class="db-resources-section">
          <h4>Resources</h4>
          <div class="db-links-list">
            <a
              href="https://github.com/TuringLang/JuliaBUGS.jl"
              target="_blank"
              rel="noopener noreferrer"
              class="db-resource-link"
            >
              <i class="fab fa-github"></i> Codebase
            </a>
            <a
              href="https://github.com/TuringLang/JuliaBUGS.jl/issues?q=is%3Aissue%20state%3Aopen%20label%3ADoodleBUGS"
              target="_blank"
              rel="noopener noreferrer"
              class="db-resource-link"
            >
              <i class="fas fa-list"></i> Issue Tracker
            </a>
            <a
              href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md"
              target="_blank"
              rel="noopener noreferrer"
              class="db-resource-link"
            >
              <i class="fas fa-bug"></i> Report Issue
            </a>
          </div>
        </div>
      </div>
    </template>
  </BaseModal>
</template>

<script setup lang="ts">
import BaseModal from '../common/BaseModal.vue'

defineProps<{
  isOpen: boolean
}>()

const emit = defineEmits(['close'])
</script>

<style scoped>
.db-about-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
  color: var(--color-text);
  line-height: 1.6;
}

.db-about-content p {
  margin: 0;
}

.db-about-content a {
  color: var(--color-primary);
  text-decoration: none;
  font-weight: 500;
}
.db-about-content a:hover {
  text-decoration: underline;
}

.db-resources-section {
  margin-top: 15px;
  padding-top: 15px;
  border-top: 1px solid var(--theme-border);
}

.db-resources-section h4 {
  margin: 0 0 10px 0;
  color: var(--theme-text-primary);
  font-size: 0.95rem;
}

.db-links-list {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 12px;
}

.db-resource-link {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  background-color: var(--theme-bg-hover);
  border-radius: var(--radius-sm);
  color: var(--theme-text-primary) !important;
  font-weight: 500;
  transition: background-color 0.2s;
  border: 1px solid transparent;
  flex: 1;
  justify-content: center;
  min-width: 120px;
}

.db-resource-link:hover {
  background-color: var(--theme-bg-active);
  text-decoration: none !important;
  border-color: var(--theme-border);
}

.db-resource-link i {
  width: 20px;
  text-align: center;
  color: var(--theme-text-secondary);
}
</style>
