<script setup lang="ts">
import { type StyleValue } from 'vue';
import { storeToRefs } from 'pinia';
import NodePropertiesPanel from '../right-sidebar/NodePropertiesPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import JsonEditorPanel from '../right-sidebar/JsonEditorPanel.vue';
import ExecutionPanel from '../right-sidebar/ExecutionPanel.vue';
import { useUiStore } from '../../stores/uiStore';
import { useExecutionStore } from '../../stores/executionStore';
import type { GraphElement, ValidationError } from '../../types';

const props = defineProps<{
  selectedElement: GraphElement | null;
  validationErrors: Map<string, ValidationError[]>;
  isModelValid: boolean;
}>();

const emit = defineEmits<{
  (e: 'toggle-right-sidebar'): void;
  (e: 'update-element', element: GraphElement): void;
  (e: 'delete-element', elementId: string): void;
  (e: 'show-validation-issues'): void;
}>();

const uiStore = useUiStore();
const executionStore = useExecutionStore();
const { isRightSidebarOpen, activeRightTab } = storeToRefs(uiStore);
const { isConnected } = storeToRefs(executionStore);

const sidebarStyle = (isOpen: boolean): StyleValue => {
    if (!isOpen) {
        return {
            transform: 'scale(0)',
            opacity: 0,
            pointerEvents: 'none',
            width: '320px',
            transformOrigin: 'top right'
        };
    }
    return {
        transform: 'scale(1)',
        opacity: 1,
        pointerEvents: 'auto',
        width: '320px',
        transformOrigin: 'top right'
    };
};
</script>

<template>
    <aside class="floating-sidebar right glass-panel" :style="sidebarStyle(isRightSidebarOpen)">
        <div class="sidebar-header" @click="$emit('toggle-right-sidebar')" style="cursor: pointer;">
            <span class="sidebar-title">Inspector</span>
            
            <div class="flex items-center gap-1 ml-auto" @click.stop>
                 <div class="status-indicator backend-status" 
                     :class="{ 'connected': isConnected, 'disconnected': !isConnected }">
                    <i class="fas fa-circle"></i>
                    <div class="instant-tooltip">{{ isConnected ? 'Backend Connected' : 'Backend Disconnected' }}</div>
                </div>
                <div class="status-indicator validation-status"
                    @click="$emit('show-validation-issues')"
                    :class="isModelValid ? 'valid' : 'invalid'">
                    <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
                    <div class="instant-tooltip">{{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}</div>
                </div>
            </div>

            <div class="cursor-pointer flex items-center ml-2">
                 <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
            </div>
        </div>
        
        <div class="sidebar-tabs text-tabs">
            <button :class="{ active: activeRightTab === 'properties' }" @click="uiStore.setActiveRightTab('properties')">Props</button>
            <button :class="{ active: activeRightTab === 'code' }" @click="uiStore.setActiveRightTab('code')">Code</button>
            <button :class="{ active: activeRightTab === 'json' }" @click="uiStore.setActiveRightTab('json')">JSON</button>
            <button :class="{ active: activeRightTab === 'connection' }" @click="uiStore.setActiveRightTab('connection')">Run</button>
        </div>

        <div class="sidebar-content">
            <NodePropertiesPanel v-show="activeRightTab === 'properties'" 
                :selected-element="selectedElement" 
                :validation-errors="validationErrors"
                @update-element="$emit('update-element', $event)" 
                @delete-element="$emit('delete-element', $event)" />
            <CodePreviewPanel v-show="activeRightTab === 'code'" :is-active="activeRightTab === 'code'" />
            <JsonEditorPanel v-show="activeRightTab === 'json'" :is-active="activeRightTab === 'json'" />
            <ExecutionPanel v-show="activeRightTab === 'connection'" />
        </div>
    </aside>
</template>

<style scoped>
.floating-sidebar {
  position: absolute;
  top: 16px;
  height: calc(100dvh - 32px); 
  bottom: auto;
  z-index: 50;
  display: flex;
  flex-direction: column;
  border-radius: var(--radius-lg);
  overflow: hidden;
  transition: transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1), opacity 0.3s ease;
  background: var(--theme-bg-panel);
  box-shadow: var(--shadow-floating);
}

.floating-sidebar.right {
  right: 16px;
  transform-origin: top right;
}

.sidebar-header {
  padding: 12px 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--theme-border);
  background: var(--theme-bg-panel-transparent);
  color: var(--theme-text-primary);
  flex-shrink: 0;
}

.sidebar-title {
  font-weight: 600;
  font-size: var(--font-size-md);
}

.toggle-icon {
    color: var(--theme-text-secondary);
}

.status-indicator {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    cursor: help;
}

.backend-status { margin-right: 0; }
.backend-status.connected { color: var(--theme-success); }
.backend-status.disconnected { color: var(--theme-danger); }

.validation-status { font-size: 1.1em; margin: 0 5px; }
.validation-status.valid { color: var(--theme-success); }
.validation-status.invalid { color: var(--theme-warning); }

.instant-tooltip {
    position: absolute;
    top: 100%;
    left: 50%;
    transform: translateX(-50%);
    background: var(--color-background-dark);
    color: var(--color-text-light);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 0.75rem;
    white-space: nowrap;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.1s;
    margin-top: 6px;
    z-index: 100;
    box-shadow: 0 2px 6px rgba(0,0,0,0.2);
}

.status-indicator:hover .instant-tooltip {
    opacity: 1;
}

.sidebar-tabs {
  display: flex;
  background: var(--theme-bg-hover);
  padding: 4px;
  gap: 4px;
  border-bottom: 1px solid var(--theme-border);
}

.sidebar-tabs button {
  flex: 1;
  background: transparent;
  border: none;
  padding: 8px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  color: var(--theme-text-secondary);
  transition: all 0.2s;
  font-weight: 500;
}

.sidebar-tabs button:hover {
  background: rgba(0,0,0,0.05);
  color: var(--theme-text-primary);
}

.sidebar-tabs button.active {
  background: var(--theme-bg-panel);
  color: var(--theme-primary);
  box-shadow: var(--shadow-sm);
}

.sidebar-content {
  flex: 1;
  overflow-y: auto;
  background: var(--theme-bg-panel);
}
</style>