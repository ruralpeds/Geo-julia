<template>
  <div class="analysis-page p-6">
    <!-- Page Header -->
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-gray-800">Spatial Analysis</h1>
      <p class="text-gray-600 mt-1">Configure and execute spatial analysis operations</p>
    </div>

    <!-- No Dataset Warning -->
    <div v-if="!appStore.currentDataset" class="alert alert-warning mb-6">
      <span class="icon">⚠️</span>
      <div>
        <p class="font-semibold">No Dataset Loaded</p>
        <p class="text-sm mt-1">Please ingest data first using the "📊 Ingest Data" button in the sidebar.</p>
      </div>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Left Column: Operation Selection & Configuration -->
      <div class="lg:col-span-2">
        <!-- Category Selector -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-bold text-gray-800 mb-4">Select Operation Category</h2>
          <div class="grid grid-cols-2 gap-3">
            <button
              v-for="(category, key) in OPERATION_CATEGORIES"
              :key="key"
              @click="selectedCategory = key"
              :class="[
                'p-4 rounded-lg border-2 transition',
                selectedCategory === key
                  ? 'border-blue-500 bg-blue-50 text-blue-900'
                  : 'border-gray-200 bg-white text-gray-700 hover:border-blue-300'
              ]"
            >
              <div class="text-2xl mb-2">{{ category.icon }}</div>
              <div class="font-semibold text-sm">{{ category.name }}</div>
              <div class="text-xs text-gray-600 mt-1">{{ category.description }}</div>
            </button>
          </div>
        </div>

        <!-- Operation Selector -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-bold text-gray-800 mb-4">Select Operation</h2>
          <div class="space-y-2 max-h-48 overflow-y-auto">
            <button
              v-for="op in operationsByCategory"
              :key="op.id"
              @click="selectOperation(op)"
              :class="[
                'w-full p-4 rounded-lg border-2 text-left transition',
                selectedOperation?.id === op.id
                  ? 'border-blue-500 bg-blue-50'
                  : 'border-gray-200 bg-white hover:border-blue-300'
              ]"
            >
              <div class="flex items-start gap-3">
                <span class="text-2xl">{{ op.icon }}</span>
                <div>
                  <p class="font-semibold text-gray-900">{{ op.name }}</p>
                  <p class="text-sm text-gray-600">{{ op.description }}</p>
                </div>
              </div>
            </button>
          </div>
        </div>

        <!-- Parameters Form -->
        <div v-if="selectedOperation" class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-bold text-gray-800 mb-4">{{ selectedOperation.name }} Parameters</h2>
          <form @submit.prevent="handleExecuteAnalysis" class="space-y-4">
            <!-- Dynamic Form Fields -->
            <FormField
              v-for="param in selectedOperation.params"
              :key="param.name"
              :field="processedParam(param)"
              v-model="analysisParams[param.name]"
              @validate="validateForm"
            />

            <!-- Execution Options -->
            <div class="border-t pt-4 mt-6">
              <h3 class="font-semibold text-gray-800 mb-3">Execution Mode</h3>
              <div class="space-y-2">
                <label class="flex items-center">
                  <input
                    v-model="executionMode"
                    type="radio"
                    value="sync"
                    class="w-4 h-4 text-blue-600"
                  />
                  <span class="ml-3 text-sm text-gray-700">
                    <span class="font-medium">Synchronous</span> - Wait for results (for quick analyses)
                  </span>
                </label>
                <label class="flex items-center">
                  <input
                    v-model="executionMode"
                    type="radio"
                    value="async"
                    class="w-4 h-4 text-blue-600"
                  />
                  <span class="ml-3 text-sm text-gray-700">
                    <span class="font-medium">Asynchronous</span> - Submit as job (for long-running analyses)
                  </span>
                </label>
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="flex gap-3 pt-4 border-t">
              <button
                type="submit"
                :disabled="!formValid || appStore.analysisLoading || appStore.loadingData"
                class="flex-1 px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium rounded-lg transition"
              >
                <span v-if="appStore.analysisLoading" class="inline-block animate-spin mr-2">⏳</span>
                {{ executionMode === 'sync' ? 'Run Analysis' : 'Submit as Job' }}
              </button>
              <button
                type="button"
                @click="resetForm"
                class="px-4 py-2 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition"
              >
                Reset
              </button>
            </div>
          </form>
        </div>
      </div>

      <!-- Right Column: Dataset Info & Results -->
      <div>
        <!-- Dataset Information Card -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-lg font-bold text-gray-800 mb-4">Dataset Info</h2>
          <div class="space-y-3">
            <div>
              <p class="text-sm text-gray-600">Source</p>
              <p class="font-semibold text-gray-900">{{ appStore.currentDataset.source }}</p>
            </div>
            <div>
              <p class="text-sm text-gray-600">Format</p>
              <p class="font-semibold text-gray-900">{{ appStore.currentDataset.format }}</p>
            </div>
            <div>
              <p class="text-sm text-gray-600">Rows</p>
              <p class="font-semibold text-gray-900">{{ appStore.currentDataset.rowsIngested }}</p>
            </div>
            <div>
              <p class="text-sm text-gray-600">Columns</p>
              <div class="flex flex-wrap gap-1 mt-1">
                <span
                  v-for="col in appStore.currentDataset.columns?.slice(0, 5)"
                  :key="col"
                  class="px-2 py-1 bg-blue-100 text-blue-800 text-xs rounded"
                >
                  {{ col }}
                </span>
                <span
                  v-if="appStore.currentDataset.columns?.length > 5"
                  class="px-2 py-1 bg-gray-100 text-gray-800 text-xs rounded"
                >
                  +{{ appStore.currentDataset.columns.length - 5 }} more
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Analysis Results Card -->
        <div v-if="appStore.analysisResults" class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-lg font-bold text-gray-800 mb-4">Results</h2>
          <div class="bg-green-50 border border-green-200 rounded p-3 mb-3">
            <p class="text-sm font-medium text-green-800">✓ Analysis Completed</p>
          </div>

          <div class="space-y-3">
            <div v-if="appStore.analysisResults.features" class="text-sm">
              <p class="text-gray-600">Features</p>
              <p class="font-semibold text-gray-900">{{ appStore.analysisResults.features }}</p>
            </div>
            <div v-if="appStore.analysisResults.geometry_type" class="text-sm">
              <p class="text-gray-600">Geometry Type</p>
              <p class="font-semibold text-gray-900">{{ appStore.analysisResults.geometry_type }}</p>
            </div>

            <button
              @click="downloadResults"
              class="w-full mt-3 px-3 py-2 bg-green-600 hover:bg-green-700 text-white rounded text-sm font-medium transition"
            >
              📥 Download Results
            </button>

            <button
              @click="visualizeResults"
              class="w-full px-3 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded text-sm font-medium transition"
            >
              📈 Visualize
            </button>
          </div>
        </div>

        <!-- Recent Analyses -->
        <div v-if="appStore.activeJobs.length > 0" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-lg font-bold text-gray-800 mb-4">Recent Jobs</h2>
          <div class="space-y-2 max-h-48 overflow-y-auto">
            <div
              v-for="job in appStore.activeJobs.slice(0, 5)"
              :key="job.id"
              @click="selectJob(job.id)"
              class="p-3 bg-gray-50 rounded border border-gray-200 hover:bg-gray-100 cursor-pointer transition"
            >
              <p class="font-medium text-sm text-gray-900">{{ job.operation }}</p>
              <p class="text-xs text-gray-600">
                {{ job.status }} • {{ job.progress }}%
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useAppStore } from '@/stores/app'
import FormField from '@/components/FormField.vue'
import { OPERATIONS, OPERATION_CATEGORIES, ML_OPERATIONS } from '@/config/operations'

const appStore = useAppStore()

const selectedCategory = ref('spatial')
const selectedOperation = ref(null)
const analysisParams = ref({})
const executionMode = ref('sync')
const formValid = ref(false)

const operationsByCategory = computed(() => {
  const allOps = { ...OPERATIONS, ...ML_OPERATIONS }
  return Object.values(allOps).filter(op => op.category === selectedCategory.value)
})

// Process parameter with dynamic options from dataset
function processedParam(param) {
  const processed = { ...param }

  // Populate column options if available
  if (
    (processed.type === 'select' || processed.type === 'multi-select') &&
    (processed.name.includes('variable') ||
      processed.name.includes('column') ||
      processed.name.includes('features') ||
      processed.name === 'dissolve_by')
  ) {
    processed.options = appStore.currentDataset.columns || []
  }

  // Populate overlay layer options
  if (processed.name === 'overlay_layer' && appStore.datasets?.length) {
    processed.options = appStore.datasets.map((d) => d.source)
  }

  return processed
}

function selectOperation(operation) {
  selectedOperation.value = operation
  analysisParams.value = {}
  formValid.value = false

  // Initialize params with defaults
  operation.params.forEach((param) => {
    analysisParams.value[param.name] = param.default ?? ''
  })
}

function resetForm() {
  analysisParams.value = {}
  formValid.value = false
  if (selectedOperation.value) {
    selectedOperation.value.params.forEach((param) => {
      analysisParams.value[param.name] = param.default ?? ''
    })
  }
}

function validateForm() {
  // All fields are validated by FormField component
  formValid.value = true
}

async function handleExecuteAnalysis() {
  if (!selectedOperation.value || !formValid.value) {
    appStore.addNotification('Please fill all required fields', 'error')
    return
  }

  if (executionMode.value === 'sync') {
    const result = await appStore.runAnalysis(selectedOperation.value.id, analysisParams.value)
    if (result) {
      appStore.setCurrentPage('analysis')
    }
  } else {
    const job = await appStore.submitAsyncJob(selectedOperation.value.id, analysisParams.value)
    if (job) {
      appStore.setCurrentPage('jobs')
    }
  }
}

function downloadResults() {
  if (!appStore.analysisResults) return
  const data = JSON.stringify(appStore.analysisResults, null, 2)
  const blob = new Blob([data], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `analysis-${selectedOperation.value.id}-${Date.now()}.json`
  a.click()
  URL.revokeObjectURL(url)
  appStore.addNotification('Results downloaded', 'success')
}

function visualizeResults() {
  appStore.setCurrentPage('analysis')
  appStore.addNotification('Navigate to Visualize to create charts', 'info')
}

function selectJob(jobId) {
  appStore.selectedJobId = jobId
  appStore.setCurrentPage('jobs')
}
</script>

<style scoped>
.analysis-page {
  background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
  min-height: 100vh;
}

.alert {
  @apply px-4 py-3 rounded-lg flex items-start gap-3;
}

.alert-warning {
  @apply bg-yellow-50 border border-yellow-200 text-yellow-800;
}

.alert .icon {
  @apply text-xl flex-shrink-0;
}
</style>
