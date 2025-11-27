<script setup lang="ts">
import { ref, watch } from 'vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';

const props = defineProps<{
  isOpen: boolean;
  url: string;
}>();

const emit = defineEmits(['close']);

const copySuccess = ref(false);
const shortUrl = ref<string | null>(null);
const isLoadingShort = ref(false);
const shortError = ref<string | null>(null);

watch(() => props.isOpen, (val) => {
    if (val) {
        copySuccess.value = false;
        shortUrl.value = null;
        shortError.value = null;
        isLoadingShort.value = false;
    }
});

const copyToClipboard = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  } catch (err) {
    // Fallback
    const input = document.createElement("textarea");
    input.value = text;
    document.body.appendChild(input);
    input.select();
    document.execCommand('copy');
    document.body.removeChild(input);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  }
};

const shortenUrl = async () => {
    if (shortUrl.value) return; // Already done
    
    isLoadingShort.value = true;
    shortError.value = null;
    
    try {
        // Use allorigins.win proxy to bypass is.gd CORS restrictions
        const target = `https://is.gd/create.php?format=json&url=${encodeURIComponent(props.url)}`;
        const proxy = `https://api.allorigins.win/get?url=${encodeURIComponent(target)}`;
        
        const response = await fetch(proxy);
        if (!response.ok) {
            throw new Error(`HTTP Error ${response.status}`);
        }
        
        const proxyData = await response.json();
        
        if (proxyData.contents) {
            const data = JSON.parse(proxyData.contents);
            if (data.errorcode) {
                throw new Error(data.errormessage || 'Unknown is.gd error');
            }
            if (data.shorturl) {
                shortUrl.value = data.shorturl;
            } else {
                throw new Error('Invalid response from is.gd');
            }
        } else {
             throw new Error('Empty response from proxy');
        }

    } catch (e: unknown) {
        console.error("Shortening failed:", e);
        shortError.value = e instanceof Error ? e.message : String(e);
        if (shortError.value?.includes("Rate limit")) {
            shortError.value = "Rate limit exceeded. Please try again later.";
        }
    } finally {
        isLoadingShort.value = false;
    }
};
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>Share Model</h3>
    </template>
    <template #body>
      <div class="share-content">
        <p class="description">
          Share this URL to let others view and edit a copy of your model. 
          <br>
          <small class="note">Note: The entire model is encoded in the link. No data is stored on a server.</small>
        </p>
        
        <div class="url-section">
            <label>Long URL (Base64)</label>
            <div class="url-container">
                <BaseInput 
                    :model-value="url" 
                    readonly 
                    class="url-input"
                    @focus="(e: FocusEvent) => (e.target as HTMLInputElement).select()"
                />
                <BaseButton @click="copyToClipboard(url)" type="primary" class="copy-btn">
                    <i class="fas fa-copy"></i> Copy
                </BaseButton>
            </div>
        </div>

        <div class="divider"></div>

        <div class="shorten-section">
            <label>Shortened URL (is.gd)</label>
            
            <div v-if="!shortUrl && !shortError" class="action-row">
                <BaseButton @click="shortenUrl" type="secondary" :disabled="isLoadingShort" class="w-full">
                    <i v-if="isLoadingShort" class="fas fa-spinner fa-spin"></i>
                    <span v-else>Generate Short Link</span>
                </BaseButton>
            </div>

            <div v-if="shortError" class="error-box">
                <i class="fas fa-exclamation-circle"></i>
                <span>{{ shortError }}</span>
            </div>

            <div v-if="shortUrl" class="url-container">
                <BaseInput 
                    :model-value="shortUrl" 
                    readonly 
                    class="url-input highlight"
                    @focus="(e: FocusEvent) => (e.target as HTMLInputElement).select()"
                />
                <BaseButton @click="copyToClipboard(shortUrl)" type="primary" class="copy-btn">
                    <i class="fas fa-copy"></i> Copy
                </BaseButton>
            </div>
            
            <div class="disclaimer-box">
                <i class="fas fa-info-circle"></i>
                <small>
                    <strong>Note:</strong> is.gd is a third-party service. Please avoid generating short links excessively to prevent rate limiting. 
                    If generation fails, use the Long URL above.
                </small>
            </div>
        </div>
        
        <div v-if="copySuccess" class="toast-success">
            Link copied to clipboard!
        </div>
      </div>
    </template>
    <template #footer>
      <BaseButton @click="emit('close')" type="secondary">Close</BaseButton>
    </template>
  </BaseModal>
</template>

<style scoped>
.share-content {
    display: flex;
    flex-direction: column;
    gap: 15px;
}

.description {
    margin: 0;
    color: var(--theme-text-primary);
    line-height: 1.5;
}

.note {
    color: var(--theme-text-secondary);
    font-style: italic;
}

.url-section label, .shorten-section label {
    display: block;
    font-size: 0.85em;
    font-weight: 600;
    margin-bottom: 5px;
    color: var(--theme-text-secondary);
}

.url-container {
    display: flex;
    gap: 8px;
    align-items: center;
}

.url-input {
    flex-grow: 1;
    font-family: monospace;
    font-size: 0.85em;
    background-color: var(--theme-bg-hover);
}

.url-input.highlight {
    background-color: rgba(16, 185, 129, 0.1);
    border-color: var(--theme-primary);
    color: var(--theme-primary);
}

.copy-btn {
    min-width: 80px;
    justify-content: center;
}

.divider {
    height: 1px;
    background: var(--theme-border);
    margin: 5px 0;
}

.action-row {
    display: flex;
}

.error-box {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--theme-danger);
    font-size: 0.9em;
    padding: 8px;
    background-color: rgba(239, 68, 68, 0.1);
    border-radius: var(--radius-sm);
}

.disclaimer-box {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    font-size: 0.8em;
    color: var(--theme-text-muted);
    background-color: var(--theme-bg-hover);
    padding: 8px;
    border-radius: var(--radius-sm);
    margin-top: 5px;
}

.toast-success {
    position: absolute;
    top: 10px;
    left: 50%;
    transform: translateX(-50%);
    background-color: var(--theme-primary);
    color: white;
    padding: 6px 12px;
    border-radius: 20px;
    font-size: 0.85em;
    font-weight: 600;
    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    animation: fadeInOut 2s ease-in-out;
}

@keyframes fadeInOut {
    0% { opacity: 0; transform: translate(-50%, -10px); }
    10% { opacity: 1; transform: translate(-50%, 0); }
    90% { opacity: 1; transform: translate(-50%, 0); }
    100% { opacity: 0; transform: translate(-50%, -10px); }
}
</style>
