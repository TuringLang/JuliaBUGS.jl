<!-- src/components/left-sidebar/ExecutionSettingsPanel.vue -->
<script setup lang="ts">
import { storeToRefs } from 'pinia';
import { useExecutionStore } from '../../stores/executionStore';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';

const executionStore = useExecutionStore();
const { dependencies, samplerSettings } = storeToRefs(executionStore);

const addDependency = () => {
  dependencies.value.push({ name: '', version: '' });
};

const removeDependency = (index: number) => {
  dependencies.value.splice(index, 1);
};
</script>

<template>
  <div class="execution-settings-panel">
    <div class="settings-section">
      <h4>Sampler Settings</h4>
      <div class="form-group">
        <label for="n_samples">Samples</label>
        <BaseInput id="n_samples" type="number" v-model.number="samplerSettings.n_samples" />
      </div>
      <div class="form-group">
        <label for="n_adapts">Adaptation Steps</label>
        <BaseInput id="n_adapts" type="number" v-model.number="samplerSettings.n_adapts" />
      </div>
      <div class="form-group">
        <label for="n_chains">Chains</label>
        <BaseInput id="n_chains" type="number" v-model.number="samplerSettings.n_chains" />
      </div>
    </div>

    <div class="settings-section">
      <h4>Dependencies</h4>
      <div v-for="(dep, index) in dependencies" :key="index" class="dependency-item">
        <BaseInput v-model="dep.name" placeholder="Package Name" class="dep-input" />
        <BaseInput v-model="dep.version" placeholder="Version (e.g., 1.0)" class="dep-input" />
        <BaseButton @click="removeDependency(index)" type="danger" size="small" class="remove-btn">-</BaseButton>
      </div>
      <BaseButton @click="addDependency" type="secondary" size="small" class="add-btn">
        Add Dependency
      </BaseButton>
    </div>
  </div>
</template>

<style scoped>
.execution-settings-panel {
  display: flex;
  flex-direction: column;
  gap: 20px;
  height: 100%;
}
.settings-section {
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
.form-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.form-group label {
  font-size: 0.9em;
  font-weight: 500;
}
.dependency-item {
  display: flex;
  gap: 10px;
  align-items: center;
}
.dep-input {
  flex-grow: 1;
}
.remove-btn {
  padding: 5px 10px;
}
.add-btn {
  align-self: flex-start;
  margin-top: 10px;
}
</style>
