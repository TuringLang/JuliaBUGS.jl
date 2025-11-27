<script setup lang="ts">
import Dialog from 'primevue/dialog';
import { computed } from 'vue';

const props = defineProps<{
  isOpen: boolean;
  header?: string;
}>();

const emit = defineEmits(['close']);

const visible = computed({
  get: () => props.isOpen,
  set: (value) => {
    if (!value) emit('close');
  }
});
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="header" :style="{ width: '50vw' }" dismissableMask>
    <template #header v-if="$slots.header">
      <slot name="header"></slot>
    </template>
    
    <slot name="body"></slot>
    <slot></slot>

    <template #footer v-if="$slots.footer">
      <slot name="footer"></slot>
    </template>
  </Dialog>
</template>
