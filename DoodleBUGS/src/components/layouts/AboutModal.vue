<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>About DoodleBUGS</h3>
    </template>
    <template #body>
      <div class="about-content">
        <p>
          <strong>DoodleBUGS</strong> is a graphical modelling tool designed to simplify the creation
          of Bayesian models for analysis with the BUGS language using
          <a href="https://github.com/TuringLang/JuliaBUGS.jl" target="_blank" rel="noopener noreferrer">JuliaBUGS.jl</a>.
        </p>
        <p>
          Our goal is to provide an intuitive, visual interface for statisticians,
          researchers, and students to build, understand, and share complex probabilistic models.
        </p>
      </div>
    </template>
    <template #footer>
      <BaseButton @click="emit('close')" type="primary">Close</BaseButton>
    </template>
  </BaseModal>
</template>

<script setup lang="ts">
import BaseModal from '../common/BaseModal.vue';
import BaseButton from '../ui/BaseButton.vue';

defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits(['close']);
</script>

<style scoped>
.about-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
  color: var(--color-text);
  line-height: 1.6;
}

.about-content p {
  margin: 0;
}

.about-content a {
  color: var(--color-primary);
  text-decoration: none;
  font-weight: 500;
}
.about-content a:hover {
  text-decoration: underline;
}
hr {
  border: none;
  border-top: 1px solid var(--color-border-light);
  margin: 10px 0;
}
</style>
