<template>
  <div class="analysis-page p-6">
    <h1 class="text-3xl font-bold text-gray-800 mb-6">Spatial Analysis</h1>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Operation Selection -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">Available Operations</h2>

        <!-- Spatial Operations -->
        <div class="mb-6">
          <h3 class="font-semibold text-gray-700 mb-2">Spatial Operations</h3>
          <div class="space-y-2">
            <button
              v-for="op in spatialOps"
              :key="op"
              @click="selectOperation(op)"
              :class="appStore.selectedOperation === op ? 'bg-blue-500 text-white' : 'bg-gray-100 text-gray-800'"
              class="w-full px-3 py-2 rounded text-left hover:opacity-80 transition"
            >
              {{ formatOpName(op) }}
            </button>
          </div>
        </div>

        <!-- Statistical Methods -->
        <div class="mb-6">
          <h3 class="font-semibold text-gray-700 mb-2">Statistical Methods</h3>
          <div class="space-y-2">
            <button
              v-for="op in statisticalOps"
              :key="op"
              @click="selectOperation(op)"
              :class="appStore.selectedOperation === op ? 'bg-blue-500 text-white' : 'bg-gray-100 text-gray-800'"
              class="w-full px-3 py-2 rounded text-left hover:opacity-80 transition"
            >
              {{ formatOpName(op) }}
            </button>
          </div>
        </div>
      </div>

      <!-- Parameters -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">Parameters</h2>

        <div class="space-y-4">
          <!-- Operation-specific parameters -->
          <div v-if="appStore.selectedOperation === 'buffer'" class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-gray-700">Distance</label>
              <input
                v-model.number="params.distance"
                type="number"
                min="0"
                class="mt-1 w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Units</label>
              <select v-model="params.units" class="mt-1 w-full px-3 py-2 border border-gray-300 rounded">
                <option value="meters">Meters</option>
                <option value="kilometers">Kilometers</option>
                <option value="degrees">Degrees</option>
              </select>
            </div>
          </div>

          <div v-if="appStore.selectedOperation === 'clip'" class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-gray-700">Min Latitude</label>
              <input
                v-model.number="params.minLat"
                type="number"
                class="mt-1 w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Max Latitude</label>
              <input
                v-model.number="params.maxLat"
                type="number"
                class="mt-1 w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>
          </div>

          <div v-if="appStore.selectedOperation === 'hotspot_analysis'" class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-gray-700">Variable</label>
              <input
                v-model="params.variable"
                type="text"
                placeholder="e.g., temperature"
                class="mt-1 w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>
          </div>

          <div v-if="appStore.selectedOperation === 'cluster_analysis'" class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-gray-700">Number of Clusters</label>
              <input
                v-model.number="params.nClusters"
                type="number"
                min="2"
                max="20"
                class="mt-1 w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>
          </div>

          <!-- Run Button -->
          <button
            @click="runAnalysis"
            :disabled="!appStore.currentDataset || analysisLoading"
            class="w-full px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white font-medium rounded transition"
          >
            {{ analysisLoading ? 'Running...' : 'Run Analysis' }}
          </button>

          <!-- Async Job Button -->
          <button
            @click="submitAsyncJob"
            :disabled="!appStore.currentDataset || analysisLoading"
            class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium rounded transition"
          >
            {{ analysisLoading ? 'Submitting...' : 'Submit as Job' }}
          </button>
        </div>
      </div>

      <!-- Results -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">Results</h2>

        <div v-if="!appStore.analysisResults" class="text-center py-8 text-gray-600">
          <p>Run an analysis to see results</p>
        </div>
        <div v-else class="space-y-3">
          <div class="bg-gray-50 p-3 rounded">
            <p class="text-sm text-gray-600">Operation</p>
            <p class="font-semibold text-gray-800">{{ appStore.selectedOperation }}</p>
          </div>

          <div class="bg-gray-50 p-3 rounded">
            <p class="text-sm text-gray-600">Status</p>
            <p class="font-semibold text-green-600">{{ appStore.analysisResults.status }}</p>
          </div>

          <div class="bg-gray-50 p-3 rounded">
            <p class="text-sm text-gray-600">Result</p>
            <pre class="text-xs overflow-auto bg-white p-2 rounded border border-gray-300 mt-1">{{ JSON.stringify(appStore.analysisResults.result, null, 2) }}</pre>
          </div>

          <button
            @click="downloadResults"
            class="w-full px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white font-medium rounded transition"
          >
            Download Results
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive } from 'vue'
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()

const spatialOps = ['buffer', 'clip', 'dissolve', 'intersect', 'union', 'reproject']
const statisticalOps = ['hotspot_analysis', 'cluster_analysis', 'spatial_autocorrelation', 'kriging']

const analysisLoading = ref(false)
const params = reactive({
  distance: 100,
  units: 'meters',
  minLat: -90,
  maxLat: 90,
  variable: 'value',
  nClusters: 3
})

function selectOperation(op) {
  appStore.selectedOperation = op
}

function formatOpName(op) {
  return op
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
}

async function runAnalysis() {
  analysisLoading.value = true
  try {
    await appStore.runAnalysis(appStore.selectedOperation, params)
  } finally {
    analysisLoading.value = false
  }
}

async function submitAsyncJob() {
  analysisLoading.value = true
  try {
    await appStore.submitAsyncJob(appStore.selectedOperation, params)
    appStore.setCurrentPage('jobs')
  } finally {
    analysisLoading.value = false
  }
}

function downloadResults() {
  const dataStr = JSON.stringify(appStore.analysisResults, null, 2)
  const dataBlob = new Blob([dataStr], { type: 'application/json' })
  const url = URL.createObjectURL(dataBlob)
  const link = document.createElement('a')
  link.href = url
  link.download = `analysis-${Date.now()}.json`
  link.click()
  URL.revokeObjectURL(url)
}
</script>

<style scoped>
.analysis-page {
  background: #f5f7fa;
  min-height: 100vh;
}
</style>
