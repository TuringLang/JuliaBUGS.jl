<!-- This file is AI generated using Claude Sonnet 4.5 -->
<!-- TODO(shravanngoswamii): Review this file properly -->
<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

const logs = ref<string[]>([]);
const isVisible = ref(true);
const maxLogs = 50;
const copySuccess = ref(false);

const formatValue = (value: any): string => {
  if (value === null) return 'null';
  if (value === undefined) return 'undefined';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Error) {
    return `${value.name}: ${value.message}\n${value.stack || ''}`;
  }
  if (typeof value === 'object') {
    try {
      // Try to stringify, but handle circular references and errors
      return JSON.stringify(value, (key, val) => {
        // Handle Error objects specially
        if (val instanceof Error) {
          return `Error: ${val.message}`;
        }
        return val;
      }, 2);
    } catch (e) {
      return `[Object: ${Object.prototype.toString.call(value)}]`;
    }
  }
  return String(value);
};

const addLog = (message: string) => {
  const timestamp = new Date().toLocaleTimeString();
  logs.value.unshift(`[${timestamp}] ${message}`);
  if (logs.value.length > maxLogs) {
    logs.value = logs.value.slice(0, maxLogs);
  }
};

const clearLogs = () => {
  logs.value = [];
};

const toggleVisibility = () => {
  isVisible.value = !isVisible.value;
};

const copyLogs = async () => {
  try {
    const logsText = logs.value.join('\n');
    await navigator.clipboard.writeText(logsText);
    copySuccess.value = true;
    setTimeout(() => {
      copySuccess.value = false;
    }, 2000);
  } catch (err) {
    // Fallback for older browsers or if clipboard API fails
    const textarea = document.createElement('textarea');
    textarea.value = logs.value.join('\n');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      copySuccess.value = true;
      setTimeout(() => {
        copySuccess.value = false;
      }, 2000);
    } catch (e) {
      console.error('Failed to copy logs:', e);
    }
    document.body.removeChild(textarea);
  }
};

// Override console.log to capture logs
const originalLog = console.log;
const originalError = console.error;
const originalWarn = console.warn;

onMounted(() => {
  console.log = (...args: any[]) => {
    originalLog(...args);
    addLog(args.map(formatValue).join(' '));
  };
  
  console.error = (...args: any[]) => {
    originalError(...args);
    addLog('ERROR: ' + args.map(formatValue).join(' '));
  };
  
  console.warn = (...args: any[]) => {
    originalWarn(...args);
    addLog('WARN: ' + args.map(formatValue).join(' '));
  };
  
  addLog('Debug panel initialized');
});

onUnmounted(() => {
  console.log = originalLog;
  console.error = originalError;
  console.warn = originalWarn;
});
</script>

<template>
  <div class="debug-panel" :class="{ collapsed: !isVisible }">
    <div class="debug-header">
      <span>🐛 Debug Console</span>
      <div class="debug-controls">
        <button @click="copyLogs" class="debug-btn" :title="copySuccess ? 'Copied!' : 'Copy logs'">
          <span v-if="copySuccess">✓</span>
          <i v-else class="fas fa-copy"></i>
        </button>
        <button @click="clearLogs" class="debug-btn" title="Clear logs">
          <i class="fas fa-trash"></i>
        </button>
        <button @click="toggleVisibility" class="debug-btn" title="Toggle visibility">
          <i :class="isVisible ? 'fas fa-chevron-down' : 'fas fa-chevron-up'"></i>
        </button>
      </div>
    </div>
    <div v-if="isVisible" class="debug-content">
      <div class="log-count">{{ logs.length }} logs (max {{ maxLogs }})</div>
      <div class="debug-logs">
        <div v-for="(log, index) in logs" :key="index" class="debug-log-entry">
          {{ log }}
        </div>
        <div v-if="logs.length === 0" class="debug-empty">
          No logs yet. Waiting for activity...
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.debug-panel {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: rgba(0, 0, 0, 0.95);
  color: #00ff00;
  font-family: 'Courier New', monospace;
  font-size: 11px;
  z-index: 99999;
  border-top: 2px solid #00ff00;
  max-height: 40vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 -4px 20px rgba(0, 255, 0, 0.3);
}

.debug-panel.collapsed {
  max-height: 40px;
}

.debug-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  background: rgba(0, 100, 0, 0.3);
  border-bottom: 1px solid #00ff00;
  font-weight: bold;
  font-size: 12px;
  cursor: pointer;
  user-select: none;
  -webkit-user-select: none;
}

.debug-controls {
  display: flex;
  gap: 8px;
}

.debug-btn {
  background: rgba(0, 255, 0, 0.2);
  border: 1px solid #00ff00;
  color: #00ff00;
  padding: 4px 8px;
  border-radius: 3px;
  cursor: pointer;
  font-size: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 30px;
  transition: all 0.2s;
}

.debug-btn:active {
  background: rgba(0, 255, 0, 0.4);
  transform: scale(0.95);
}

.debug-btn span {
  font-size: 14px;
  color: #00ff00;
  font-weight: bold;
}

.debug-content {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  flex: 1;
  min-height: 0;
}

.log-count {
  padding: 4px 12px;
  background: rgba(0, 100, 0, 0.2);
  border-bottom: 1px solid rgba(0, 255, 0, 0.3);
  font-size: 10px;
  color: #88ff88;
}

.debug-logs {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
  -webkit-overflow-scrolling: touch;
}

.debug-log-entry {
  padding: 4px 8px;
  border-bottom: 1px solid rgba(0, 255, 0, 0.1);
  word-break: break-word;
  line-height: 1.4;
}

.debug-log-entry:hover {
  background: rgba(0, 255, 0, 0.05);
}

.debug-empty {
  text-align: center;
  padding: 20px;
  color: #666;
  font-style: italic;
}

/* Highlight error messages */
.debug-log-entry:has-text("ERROR") {
  color: #ff4444;
}

/* Highlight important events */
.debug-log-entry:has-text("[GraphEditor]"),
.debug-log-entry:has-text("[GraphCanvas]"),
.debug-log-entry:has-text("[MainLayout]") {
  background: rgba(0, 100, 255, 0.1);
}
</style>
