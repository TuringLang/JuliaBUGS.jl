<script setup lang="ts">
import Button from 'primevue/button';
import { computed } from 'vue';

const props = defineProps<{
  type?: 'primary' | 'secondary' | 'danger' | 'ghost';
  size?: 'small' | 'medium' | 'large';
  disabled?: boolean;
  icon?: string;
}>();

const severity = computed(() => {
  switch (props.type) {
    case 'primary': return 'primary';
    case 'secondary': return 'secondary';
    case 'danger': return 'danger';
    case 'ghost': return 'secondary';
    default: return 'secondary';
  }
});

const variant = computed(() => {
  if (props.type === 'ghost') return 'text';
  return undefined;
});

const primeSize = computed(() => {
  if (props.size === 'small') return 'small';
  if (props.size === 'large') return 'large';
  return undefined;
});
</script>

<template>
  <Button 
    :severity="severity" 
    :variant="variant" 
    :size="primeSize" 
    :disabled="disabled" 
    :icon="icon"
  >
    <slot></slot>
  </Button>
</template>
