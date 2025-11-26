<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';

interface LogEntry {
  timestamp: string;
  message: string;
  type: 'log' | 'error' | 'warn';
}

const logs = ref<LogEntry[]>([]);
const isVisible = ref(true);
const maxLogs = 100;
const copySuccess = ref(false);
const filterType = ref<'all' | 'log' | 'error' | 'warn'>('all');

const filteredLogs = computed(() => {
  if (filterType.value === 'all') return logs.value;
  return logs.value.filter(log => log.type === filterType.value);
});

const formatValue = (value: unknown): string => {
  if (value === null) return 'null';
  if (value === undefined) return 'undefined';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Error) {
    return `${value.name}: ${value.message}\n${value.stack || ''}`;
  }
  if (typeof value === 'object') {
    try {
      return JSON.stringify(value, (key, val) => {
        if (val instanceof Error) {
          return `Error: ${val.message}`;
        }
        return val;
      }, 2);
    } catch {
      return `[Object: ${Object.prototype.toString.call(value)}]`;
    }
  }
  return String(value);
};

const addLog = (message: string, type: 'log' | 'error' | 'warn' = 'log') => {
  const timestamp = new Date().toLocaleTimeString();
  logs.value.unshift({ timestamp, message, type });
  if (logs.value.length > maxLogs) {
    logs.value.pop();
  }
};

const getLogClass = (log: LogEntry) => {
  const classes: string[] = [];
  
  if (log.type === 'error') classes.push('log-error');
  if (log.type === 'warn') classes.push('log-warn');
  
  if (log.message.includes('[GraphEditor]') || 
      log.message.includes('[GraphCanvas]') || 
      log.message.includes('[MainLayout]')) {
    classes.push('log-important');
  }
  
  return classes.join(' ');
};

const clearLogs = () => {
  logs.value = [];
};

const toggleVisibility = () => {
  isVisible.value = !isVisible.value;
};

const copyLogs = async () => {
  const logsText = filteredLogs.value
    .map(log => `[${log.timestamp}] ${log.type.toUpperCase()}: ${log.message}`)
    .join('\n');
  
  try {
    await navigator.clipboard.writeText(logsText);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  } catch {
    const textarea = document.createElement('textarea');
    textarea.value = logsText;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      copySuccess.value = true;
      setTimeout(() => copySuccess.value = false, 2000);
    } catch {
      console.error('Clipboard not supported');
    }
    document.body.removeChild(textarea);
  }
};

const originalLog = console.log;
const originalError = console.error;
const originalWarn = console.warn;

onMounted(() => {
  console.log = (...args: unknown[]) => {
    originalLog(...args);
    addLog(args.map(formatValue).join(' '), 'log');
  };
  
  console.error = (...args: unknown[]) => {
    originalError(...args);
    addLog(args.map(formatValue).join(' '), 'error');
  };
  
  console.warn = (...args: unknown[]) => {
    originalWarn(...args);
    addLog(args.map(formatValue).join(' '), 'warn');
  };
  
  addLog('Debug panel initialized', 'log');
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
      <div class="debug-filters">
        <button 
          v-for="type in ['all', 'log', 'error', 'warn']" 
          :key="type"
          @click="filterType = type as typeof filterType"
          class="filter-btn"
          :class="{ active: filterType === type }"
        >
          {{ type === 'all' ? 'All' : type.charAt(0).toUpperCase() + type.slice(1) }}
          <span v-if="type !== 'all'" class="count">
            {{ logs.filter(l => l.type === type).length }}
          </span>
          <span v-else class="count">{{ logs.length }}</span>
        </button>
      </div>
      <div class="debug-logs">
        <div 
          v-for="(log, index) in filteredLogs" 
          :key="index" 
          class="debug-log-entry" 
          :class="getLogClass(log)"
        >
          <span class="log-time">[{{ log.timestamp }}]</span>
          <span class="log-type" :class="`type-${log.type}`">[{{ log.type.toUpperCase() }}]</span>
          <span class="log-message">{{ log.message }}</span>
        </div>
        <div v-if="filteredLogs.length === 0" class="debug-empty">
          {{ logs.length === 0 ? 'No logs yet. Waiting for activity...' : `No ${filterType} logs` }}
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

.debug-filters {
  display: flex;
  gap: 4px;
  padding: 6px 12px;
  background: rgba(0, 100, 0, 0.2);
  border-bottom: 1px solid rgba(0, 255, 0, 0.3);
}

.filter-btn {
  background: rgba(0, 255, 0, 0.1);
  border: 1px solid rgba(0, 255, 0, 0.3);
  color: #88ff88;
  padding: 3px 8px;
  border-radius: 3px;
  cursor: pointer;
  font-size: 10px;
  font-family: inherit;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  gap: 4px;
}

.filter-btn:hover {
  background: rgba(0, 255, 0, 0.2);
  border-color: #00ff00;
}

.filter-btn.active {
  background: rgba(0, 255, 0, 0.3);
  border-color: #00ff00;
  color: #00ff00;
  font-weight: bold;
}

.filter-btn .count {
  background: rgba(0, 255, 0, 0.2);
  padding: 1px 5px;
  border-radius: 10px;
  font-size: 9px;
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
  display: flex;
  gap: 6px;
}

.debug-log-entry:hover {
  background: rgba(0, 255, 0, 0.05);
}

.log-time {
  color: #666;
  flex-shrink: 0;
}

.log-type {
  flex-shrink: 0;
  font-weight: bold;
  min-width: 50px;
}

.log-type.type-log {
  color: #88ff88;
}

.log-type.type-error {
  color: #ff4444;
}

.log-type.type-warn {
  color: #ffaa00;
}

.log-message {
  flex: 1;
}

.debug-empty {
  text-align: center;
  padding: 20px;
  color: #666;
  font-style: italic;
}

.debug-log-entry.log-error .log-message {
  color: #ff4444;
}

.debug-log-entry.log-warn .log-message {
  color: #ffaa00;
}

.debug-log-entry.log-important {
  background: rgba(0, 100, 255, 0.1);
  border-left: 3px solid #4A90E2;
}
</style>
