<script setup lang="ts">
import MainLayout from './components/layouts/MainLayout.vue'
import Toast from 'primevue/toast'
</script>

<template>
  <MainLayout />
  <Toast position="top-center" />
</template>

<style>
body {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  background-color: var(--theme-bg-canvas);
  color: var(--theme-text-primary);
  font-family: var(--font-family-sans);
  font-size: var(--font-size-sm);
  -webkit-font-smoothing: antialiased;
}

#app {
  display: flex;
  flex-direction: column;
  height: 100vh;
  width: 100vw;
  overflow: hidden;
}
</style>
