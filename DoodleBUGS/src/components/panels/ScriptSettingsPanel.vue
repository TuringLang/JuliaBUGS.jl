<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { useScriptStore } from '../../stores/scriptStore'
import BaseInput from '../ui/BaseInput.vue'

const scriptStore = useScriptStore()
const { samplerSettings } = storeToRefs(scriptStore)
</script>

<template>
  <div class="db-settings-panel">
    <div class="db-settings-section">
      <h4>Sampler Settings</h4>
      <div class="db-form-group">
        <label for="n_samples">Samples</label>
        <BaseInput id="n_samples" type="number" v-model.number="samplerSettings.n_samples" />
      </div>
      <div class="db-form-group">
        <label for="n_adapts">Adaptation Steps</label>
        <BaseInput id="n_adapts" type="number" v-model.number="samplerSettings.n_adapts" />
      </div>
      <div class="db-form-group">
        <label for="n_chains">Chains</label>
        <BaseInput id="n_chains" type="number" v-model.number="samplerSettings.n_chains" />
      </div>
      <div class="db-form-group">
        <label for="seed">Seed (optional)</label>
        <BaseInput
          id="seed"
          type="number"
          v-model.number="samplerSettings.seed"
          placeholder="Leave blank for random"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.db-settings-panel {
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.db-settings-section {
  display: flex;
  flex-direction: column;
  gap: 15px;
  border: 1px solid var(--color-border-light);
  padding: 15px;
  border-radius: 8px;
}
h4 {
  margin: 0;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--color-border-light);
  color: var(--color-heading);
  font-weight: 600;
}
.db-form-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.db-form-group label {
  font-size: 0.9em;
  font-weight: 500;
}
</style>
