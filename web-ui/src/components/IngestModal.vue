<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="text-2xl font-bold text-gray-800">Ingest Data</h2>
        <button @click="$emit('close')" class="text-gray-600 hover:text-gray-800">✕</button>
      </div>

      <div class="modal-body space-y-4">
        <!-- Source Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Data Source</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="src in sources"
              :key="src"
              @click="selectedSource = src"
              :class="selectedSource === src ? 'bg-blue-500 text-white border-blue-500' : 'bg-gray-100 text-gray-800 border-gray-300'"
              class="px-4 py-2 border-2 rounded font-medium transition"
            >
              {{ src }}
            </button>
          </div>
        </div>

        <!-- File Upload or URL -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Upload Data</label>
          <input
            type="file"
            @change="handleFileUpload"
            accept=".json,.csv,.geojson"
            class="block w-full px-3 py-2 border border-gray-300 rounded"
          />
          <p class="text-xs text-gray-600 mt-1">Supported: JSON, CSV, GeoJSON</p>
        </div>

        <!-- Or URL Input -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Or Paste URL</label>
          <input
            v-model="dataUrl"
            type="url"
            placeholder="https://..."
            class="w-full px-3 py-2 border border-gray-300 rounded"
          />
        </div>

        <!-- Data Preview -->
        <div v-if="dataPreview" class="bg-gray-50 p-3 rounded">
          <p class="text-sm font-medium text-gray-700 mb-2">Preview</p>
          <pre class="text-xs overflow-auto max-h-32 bg-white p-2 rounded border border-gray-300">{{ dataPreview }}</pre>
        </div>
      </div>

      <div class="modal-footer">
        <button
          @click="$emit('close')"
          class="px-4 py-2 text-gray-700 border border-gray-300 rounded hover:bg-gray-50 transition"
        >
          Cancel
        </button>
        <button
          @click="handleIngest"
          :disabled="!selectedSource || !uploadedData"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white rounded transition"
        >
          {{ ingesting ? 'Ingesting...' : 'Ingest Data' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAppStore } from '@/stores/app'

const emit = defineEmits(['close'])
const appStore = useAppStore()

const sources = ['NOAA', 'USGS', 'OpenStreetMap', 'Copernicus']
const selectedSource = ref('NOAA')
const dataUrl = ref('')
const uploadedData = ref(null)
const dataPreview = ref('')
const ingesting = ref(false)

function handleFileUpload(event) {
  const file = event.target.files[0]
  if (file) {
    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        uploadedData.value = JSON.parse(e.target.result)
        dataPreview.value = JSON.stringify(uploadedData.value, null, 2).substring(0, 200) + '...'
      } catch (error) {
        appStore.addNotification('Invalid JSON file', 'error')
      }
    }
    reader.readAsText(file)
  }
}

async function handleIngest() {
  if (!uploadedData.value || !selectedSource.value) {
    appStore.addNotification('Please select source and upload data', 'error')
    return
  }

  ingesting.value = true
  try {
    await appStore.ingestData(selectedSource.value, 'JSON', uploadedData.value)
    emit('close')
  } finally {
    ingesting.value = false
  }
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 50;
}

.modal-content {
  background: white;
  border-radius: 0.5rem;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  width: 90%;
  max-width: 500px;
  max-height: 90vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.5rem;
  border-bottom: 1px solid #e5e7eb;
}

.modal-body {
  flex: 1;
  padding: 1.5rem;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 1.5rem;
  border-top: 1px solid #e5e7eb;
}
</style>
