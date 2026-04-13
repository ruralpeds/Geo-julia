<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="text-2xl font-bold text-gray-800">Create Visualization</h2>
        <button @click="$emit('close')" class="text-gray-600 hover:text-gray-800">✕</button>
      </div>

      <div class="modal-body space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Visualization Type</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="type in vizTypes"
              :key="type"
              @click="selectedType = type"
              :class="selectedType === type ? 'bg-blue-500 text-white' : 'bg-gray-100 text-gray-800'"
              class="px-3 py-2 rounded font-medium transition"
            >
              {{ type }}
            </button>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Variable</label>
          <input
            v-model="variable"
            type="text"
            placeholder="e.g., temperature"
            class="w-full px-3 py-2 border border-gray-300 rounded"
          />
        </div>

        <div v-if="selectedType !== '3d'">
          <label class="block text-sm font-medium text-gray-700 mb-2">Colormap</label>
          <select v-model="colormap" class="w-full px-3 py-2 border border-gray-300 rounded">
            <option value="YlOrRd">Yellow-Orange-Red</option>
            <option value="viridis">Viridis</option>
            <option value="plasma">Plasma</option>
            <option value="RdYlBu">Red-Yellow-Blue</option>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Visualization title"
            class="w-full px-3 py-2 border border-gray-300 rounded"
          />
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
          @click="handleGenerate"
          :disabled="!variable"
          class="px-4 py-2 bg-purple-600 hover:bg-purple-700 disabled:bg-gray-400 text-white rounded transition"
        >
          {{ generating ? 'Generating...' : 'Generate' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAppStore } from '@/stores/app'
import api from '@/api/client'

const emit = defineEmits(['close'])
const appStore = useAppStore()

const vizTypes = ['map', 'heatmap', '3d', 'animation']
const selectedType = ref('map')
const variable = ref('')
const colormap = ref('YlOrRd')
const title = ref('')
const generating = ref(false)

async function handleGenerate() {
  if (!variable.value) {
    appStore.addNotification('Please select a variable', 'error')
    return
  }

  generating.value = true
  try {
    const result = await api.visualize(selectedType.value, variable.value, colormap.value, title.value)
    appStore.addNotification('Visualization generated', 'success')

    // Open visualization URL if available
    if (result.url) {
      window.open(result.url, '_blank')
    }

    emit('close')
  } finally {
    generating.value = false
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
  max-width: 450px;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.5rem;
  border-bottom: 1px solid #e5e7eb;
}

.modal-body {
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
