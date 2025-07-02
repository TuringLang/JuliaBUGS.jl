<script setup lang="ts">
import BaseButton from '../ui/BaseButton.vue';
</script>

<template>
  <div class="code-preview-panel">
    <h4>Generated BUGS Code</h4>
    <div class="code-output">
      <p>BUGS model code will be generated and displayed here.</p>
      <pre class="code-block">
        <code>
model {
  # Example: Define a normal distribution
  # mu ~ dnorm(0, 1.0E-6)
  # tau ~ dgamma(0.01, 0.01)

  # Example: A simple deterministic relationship
  # theta <- exp(mu) / (1 + exp(mu))

  # Example: A loop for indexed variables (Plate)
  # for (i in 1:N) {
  #   y[i] ~ dbin(theta[i], n[i])
  # }

  # Add your nodes and connections visually to generate code!
}
        </code>
      </pre>
      <BaseButton class="copy-button" type="secondary">Copy Code</BaseButton>
    </div>
  </div>
</template>

<style scoped>
.code-preview-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
}

h4 {
  margin: 0 0 10px 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.code-output {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  background-color: #282c34;
  color: #abb2bf;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
}

.code-output p {
  padding: 15px;
  margin: 0;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.9em;
  color: #61afef;
}

.code-block {
  flex-grow: 1;
  padding: 15px;
  margin: 0;
  overflow: auto;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.85em;
  line-height: 1.4;
  white-space: pre-wrap;
  word-break: break-all;
}

.copy-button {
  position: sticky;
  bottom: 0;
  align-self: flex-end;
  margin: 10px;
  padding: 8px 15px;
  background-color: var(--color-secondary);
  color: white;
  border: none;
  border-radius: 5px;
  cursor: pointer;
  z-index: 10;
  opacity: 0.9;
}

.copy-button:hover {
  opacity: 1;
  background-color: var(--color-secondary-hover);
}
</style>
