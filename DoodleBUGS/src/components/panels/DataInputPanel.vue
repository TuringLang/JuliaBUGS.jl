<script setup lang="ts">
</script>

<template>
  <div class="data-input-panel">
    <h4>BUGS Model Data</h4>
    <div class="data-section">
      <p>Manage input data for your BUGS model here.</p>
      <p>
        Currently, this section is a placeholder for defining observed variables
        and uploading/entering their values.
      </p>
      <div class="data-placeholder">
        <i class="icon-data">📊</i>
        <span>Data definitions and values will appear here.</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.data-input-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

h4 {
  margin: 0 0 10px 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.data-section {
  display: flex;
  flex-direction: column;
  gap: 15px;
  background-color: var(--color-background-mute);
  border: 1px solid var(--color-border-light);
  border-radius: 8px;
  padding: 15px;
  text-align: center;
}

.data-section p {
  margin: 0;
  font-size: 0.9em;
  color: var(--color-text);
  line-height: 1.5;
}

.data-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 15px;
  padding: 20px;
  background-color: var(--color-background-soft);
  border: 1px dashed var(--color-border);
  border-radius: 5px;
  margin-top: 10px;
}

.icon-data {
  font-size: 3em;
  color: var(--color-secondary);
}

.data-placeholder span {
  font-style: italic;
  color: var(--color-secondary);
  font-size: 0.9em;
}

.data-placeholder button {
  width: 80%;
  max-width: 250px;
}
</style>
