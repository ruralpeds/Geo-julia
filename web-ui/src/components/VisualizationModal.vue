<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="text-2xl font-bold text-gray-800">Create Visualization</h2>
        <button @click="$emit('close')" class="text-gray-600 hover:text-gray-800">✕</button>
      </div>

      <div class="modal-body space-y-4">
        <!-- Visualization Type Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Visualization Type</label>
          <div class="grid grid-cols-3 gap-2">
            <button
              v-for="(viz, key) in visualizationTypes"
              :key="key"
              @click="selectedType = key"
              :class="[
                'p-3 rounded-lg border-2 text-center transition',
                selectedType === key
                  ? 'border-purple-500 bg-purple-50 text-purple-900'
                  : 'border-gray-200 bg-white text-gray-700 hover:border-purple-300'
              ]"
            >
              <div class="text-xl mb-1">{{ viz.icon }}</div>
              <div class="text-xs font-medium">{{ viz.name }}</div>
            </button>
          </div>
          <p class="text-xs text-gray-600 mt-2">{{ visualizationTypes[selectedType]?.description }}</p>
        </div>

        <!-- Variable Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Variable</label>
          <select
            v-model="variable"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          >
            <option value="">-- Select a variable --</option>
            <option v-for="col in appStore.currentDataset.columns" :key="col" :value="col">
              {{ col }}
            </option>
          </select>
          <p class="text-xs text-gray-600 mt-1">Select the numeric column to visualize</p>
        </div>

        <!-- Type-specific parameters -->
        <div v-if="selectedType === 'map' || selectedType === 'heatmap'">
          <label class="block text-sm font-medium text-gray-700 mb-2">Colormap</label>
          <select
            v-model="colormap"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          >
            <option value="viridis">Viridis</option>
            <option value="plasma">Plasma</option>
            <option value="YlOrRd">Yellow-Orange-Red</option>
            <option value="YlGn">Yellow-Green</option>
            <option value="Blues">Blues</option>
            <option value="Greens">Greens</option>
            <option value="RdYlBu">Red-Yellow-Blue</option>
          </select>
        </div>

        <div v-if="selectedType === 'heatmap'">
          <label class="block text-sm font-medium text-gray-700 mb-2">Radius (pixels)</label>
          <input
            v-model.number="heatmapRadius"
            type="number"
            min="5"
            max="100"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          />
        </div>

        <div v-if="selectedType === 'chart'">
          <label class="block text-sm font-medium text-gray-700 mb-2">Chart Type</label>
          <select
            v-model="chartType"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          >
            <option value="bar">Bar Chart</option>
            <option value="line">Line Chart</option>
            <option value="scatter">Scatter Plot</option>
            <option value="histogram">Histogram</option>
          </select>
        </div>

        <div v-if="selectedType === 'animation'">
          <label class="block text-sm font-medium text-gray-700 mb-2">Animation Speed</label>
          <select
            v-model="animationSpeed"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          >
            <option value="slow">Slow (1 frame/second)</option>
            <option value="normal">Normal (2 frames/second)</option>
            <option value="fast">Fast (4 frames/second)</option>
          </select>
        </div>

        <!-- Title -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Enter visualization title"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
          />
        </div>

        <!-- Preview info -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
          <p class="text-xs text-blue-800">
            <span class="font-semibold">Preview:</span> Visualization will be generated and displayed in a new window
          </p>
        </div>
      </div>

      <div class="modal-footer">
        <button
          @click="$emit('close')"
          class="px-4 py-2 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition"
        >
          Cancel
        </button>
        <button
          @click="handleGenerate"
          :disabled="!variable || generating"
          class="px-4 py-2 bg-purple-600 hover:bg-purple-700 disabled:bg-gray-400 text-white rounded-lg font-medium transition"
        >
          <span v-if="generating" class="inline-block animate-spin mr-2">⏳</span>
          {{ generating ? 'Generating...' : 'Generate Visualization' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useAppStore } from '@/stores/app'
import { VISUALIZATION_TYPES } from '@/config/operations'
import api from '@/api/client'

const emit = defineEmits(['close'])
const appStore = useAppStore()

const selectedType = ref('map')
const variable = ref('')
const colormap = ref('viridis')
const title = ref('')
const generating = ref(false)
const heatmapRadius = ref(25)
const chartType = ref('bar')
const animationSpeed = ref('normal')

const visualizationTypes = computed(() => VISUALIZATION_TYPES)

async function handleGenerate() {
  if (!variable.value) {
    appStore.addNotification('Please select a variable', 'error')
    return
  }

  if (!title.value) {
    appStore.addNotification('Please enter a visualization title', 'error')
    return
  }

  generating.value = true
  try {
    const params = {
      type: selectedType.value,
      variable: variable.value,
      title: title.value
    }

    // Add type-specific parameters
    if (selectedType.value === 'map' || selectedType.value === 'heatmap') {
      params.colormap = colormap.value
    }
    if (selectedType.value === 'heatmap') {
      params.radius = heatmapRadius.value
    }
    if (selectedType.value === 'chart') {
      params.chart_type = chartType.value
    }
    if (selectedType.value === 'animation') {
      params.speed = animationSpeed.value
    }

    const result = await api.visualize(
      selectedType.value,
      variable.value,
      colormap.value,
      title.value
    )

    appStore.addNotification('Visualization generated successfully!', 'success')

    // Open visualization in new window if URL provided
    if (result.url) {
      window.open(result.url, '_blank')
    }

    emit('close')
  } catch (error) {
    appStore.addNotification(`Visualization error: ${error.message}`, 'error')
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
