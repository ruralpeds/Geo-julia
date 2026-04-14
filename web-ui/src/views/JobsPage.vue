<template>
  <div class="jobs-page p-6">
    <!-- Page Header -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-3xl font-bold text-gray-800">Job Queue</h1>
        <p class="text-gray-600 mt-1">
          {{ filteredJobs.length }} job{{ filteredJobs.length !== 1 ? 's' : '' }} •
          {{ appStore.activeJobs.filter(j => j.status === 'completed').length }} completed
        </p>
      </div>
      <div class="flex gap-2">
        <button
          @click="refreshAllJobs"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition"
        >
          🔄 Refresh All
        </button>
        <button
          @click="exportJobs"
          :disabled="filteredJobs.length === 0"
          class="px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded-lg font-medium transition"
        >
          📥 Export
        </button>
      </div>
    </div>

    <!-- Filters & Sorting -->
    <div class="bg-white rounded-lg shadow p-4 mb-6">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <!-- Search -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Search</label>
          <input
            v-model="searchQuery"
            type="text"
            placeholder="Search by operation or ID"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <!-- Status Filter -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
          <select
            v-model="filterStatus"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          >
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="running">Running</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
          </select>
        </div>

        <!-- Operation Filter -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Operation</label>
          <select
            v-model="filterOperation"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          >
            <option value="">All Operations</option>
            <option v-for="op in uniqueOperations" :key="op" :value="op">
              {{ op }}
            </option>
          </select>
        </div>

        <!-- Sort -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Sort By</label>
          <select
            v-model="sortBy"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          >
            <option value="created_desc">Newest First</option>
            <option value="created_asc">Oldest First</option>
            <option value="progress_desc">Progress (High to Low)</option>
            <option value="progress_asc">Progress (Low to High)</option>
            <option value="status">Status (A-Z)</option>
          </select>
        </div>
      </div>
    </div>

    <!-- Summary Cards -->
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <div class="bg-white rounded-lg shadow p-4">
        <p class="text-gray-600 text-sm">Total Jobs</p>
        <p class="text-2xl font-bold text-gray-900">{{ appStore.activeJobs.length }}</p>
      </div>
      <div class="bg-white rounded-lg shadow p-4">
        <p class="text-gray-600 text-sm">Completed</p>
        <p class="text-2xl font-bold text-green-600">
          {{ appStore.activeJobs.filter(j => j.status === 'completed').length }}
        </p>
      </div>
      <div class="bg-white rounded-lg shadow p-4">
        <p class="text-gray-600 text-sm">Running</p>
        <p class="text-2xl font-bold text-blue-600">
          {{ appStore.activeJobs.filter(j => j.status === 'running').length }}
        </p>
      </div>
      <div class="bg-white rounded-lg shadow p-4">
        <p class="text-gray-600 text-sm">Failed</p>
        <p class="text-2xl font-bold text-red-600">
          {{ appStore.activeJobs.filter(j => j.status === 'failed').length }}
        </p>
      </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Job List -->
      <div class="lg:col-span-2">
        <div class="bg-white rounded-lg shadow">
          <div v-if="filteredJobs.length === 0" class="p-6 text-center text-gray-600">
            <p v-if="appStore.activeJobs.length === 0">No jobs submitted yet</p>
            <p v-else>No jobs match the current filters</p>
          </div>

          <div v-else class="divide-y max-h-96 overflow-y-auto">
            <div
              v-for="job in filteredJobs"
              :key="job.id"
              @click="appStore.selectedJobId = job.id"
              :class="appStore.selectedJobId === job.id ? 'bg-blue-50 border-l-4 border-blue-500' : ''"
              class="p-4 hover:bg-gray-50 cursor-pointer transition"
            >
              <div class="flex items-start justify-between mb-2">
                <div>
                  <h3 class="font-semibold text-gray-800">{{ job.operation }}</h3>
                  <p class="text-xs text-gray-600">{{ formatDate(job.createdAt) }}</p>
                  <p class="text-xs text-gray-500 font-mono mt-1">{{ job.id.substring(0, 12) }}...</p>
                </div>
                <span
                  :class="getStatusClass(job.status)"
                  class="px-3 py-1 rounded-full text-sm font-medium whitespace-nowrap"
                >
                  {{ job.status }}
                </span>
              </div>

              <!-- Progress Bar -->
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-blue-600 h-2 rounded-full transition-all duration-300"
                  :style="{ width: job.progress + '%' }"
                ></div>
              </div>

              <div class="text-xs text-gray-600 mt-2">{{ job.progress }}% complete</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Job Details -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">Details</h2>

        <div v-if="selectedJob">
          <div class="space-y-4">
            <!-- Operation -->
            <div>
              <p class="text-sm text-gray-600 mb-1">Operation</p>
              <p class="font-semibold text-gray-800">{{ selectedJob.operation }}</p>
            </div>

            <!-- Status -->
            <div>
              <p class="text-sm text-gray-600 mb-1">Status</p>
              <p :class="getStatusClass(selectedJob.status)" class="font-semibold">
                {{ selectedJob.status }}
              </p>
            </div>

            <!-- Progress -->
            <div>
              <p class="text-sm text-gray-600 mb-1">Progress</p>
              <div class="w-full bg-gray-200 rounded-full h-3">
                <div
                  class="bg-blue-600 h-3 rounded-full"
                  :style="{ width: selectedJob.progress + '%' }"
                ></div>
              </div>
              <p class="text-xs text-gray-600 mt-1">{{ selectedJob.progress }}%</p>
            </div>

            <!-- Created At -->
            <div>
              <p class="text-sm text-gray-600 mb-1">Created</p>
              <p class="text-sm text-gray-800">{{ formatDateTime(selectedJob.createdAt) }}</p>
            </div>

            <!-- Started At -->
            <div v-if="selectedJob.startedAt">
              <p class="text-sm text-gray-600 mb-1">Started</p>
              <p class="text-sm text-gray-800">{{ formatDateTime(selectedJob.startedAt) }}</p>
            </div>

            <!-- Completed At -->
            <div v-if="selectedJob.completedAt">
              <p class="text-sm text-gray-600 mb-1">Completed</p>
              <p class="text-sm text-gray-800">{{ formatDateTime(selectedJob.completedAt) }}</p>
            </div>

            <!-- Error -->
            <div v-if="selectedJob.error">
              <p class="text-sm text-gray-600 mb-1">Error</p>
              <p class="text-sm text-red-600 bg-red-50 p-2 rounded">{{ selectedJob.error }}</p>
            </div>

            <!-- Download Results -->
            <button
              v-if="selectedJob.status === 'completed' && selectedJob.results"
              @click="downloadResults(selectedJob)"
              class="w-full px-4 py-2 bg-green-600 hover:bg-green-700 text-white font-medium rounded transition"
            >
              Download Results
            </button>

            <!-- Refresh -->
            <button
              @click="refreshJob"
              class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded transition"
            >
              Refresh Status
            </button>
          </div>
        </div>

        <div v-else class="text-center py-8 text-gray-600">
          <p>Select a job to view details</p>
        </div>
      </div>
    </div>

    <!-- Results Preview -->
    <div v-if="selectedJob?.results" class="mt-6 bg-white rounded-lg shadow p-6">
      <h2 class="text-xl font-bold text-gray-800 mb-4">Results Preview</h2>
      <pre class="bg-gray-50 p-4 rounded border border-gray-300 overflow-auto max-h-96 text-sm">{{ JSON.stringify(selectedJob.results, null, 2) }}</pre>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useAppStore } from '@/stores/app'
import { formatDistanceToNow, format } from 'date-fns'

const appStore = useAppStore()

// Filters & Sorting
const searchQuery = ref('')
const filterStatus = ref('')
const filterOperation = ref('')
const sortBy = ref('created_desc')

const selectedJob = computed(() => {
  return appStore.activeJobs.find(j => j.id === appStore.selectedJobId)
})

const uniqueOperations = computed(() => {
  return [...new Set(appStore.activeJobs.map(job => job.operation))]
})

// Apply filters and sorting
const filteredJobs = computed(() => {
  let jobs = [...appStore.activeJobs]

  // Search filter
  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase()
    jobs = jobs.filter(
      job =>
        job.operation.toLowerCase().includes(query) ||
        job.id.toLowerCase().includes(query)
    )
  }

  // Status filter
  if (filterStatus.value) {
    jobs = jobs.filter(job => job.status === filterStatus.value)
  }

  // Operation filter
  if (filterOperation.value) {
    jobs = jobs.filter(job => job.operation === filterOperation.value)
  }

  // Sort
  switch (sortBy.value) {
    case 'created_asc':
      jobs.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))
      break
    case 'progress_desc':
      jobs.sort((a, b) => b.progress - a.progress)
      break
    case 'progress_asc':
      jobs.sort((a, b) => a.progress - b.progress)
      break
    case 'status':
      jobs.sort((a, b) => a.status.localeCompare(b.status))
      break
    case 'created_desc':
    default:
      jobs.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      break
  }

  return jobs
})

function formatDate(date) {
  return formatDistanceToNow(new Date(date), { addSuffix: true })
}

function formatDateTime(date) {
  return format(new Date(date), 'PPpp')
}

function getStatusClass(status) {
  const classes = {
    pending: 'bg-yellow-100 text-yellow-800',
    running: 'bg-blue-100 text-blue-800',
    completed: 'bg-green-100 text-green-800',
    failed: 'bg-red-100 text-red-800'
  }
  return classes[status] || 'bg-gray-100 text-gray-800'
}

async function refreshJob() {
  if (selectedJob.value) {
    await appStore.pollJobStatus(selectedJob.value.id)
    appStore.addNotification('Job status refreshed', 'success')
  }
}

async function refreshAllJobs() {
  for (const job of appStore.activeJobs) {
    if (job.status === 'pending' || job.status === 'running') {
      await appStore.pollJobStatus(job.id)
    }
  }
  appStore.addNotification(`Refreshed ${appStore.activeJobs.length} jobs`, 'success')
}

function downloadResults(job) {
  if (!job.results) {
    appStore.addNotification('No results available', 'error')
    return
  }

  const dataStr = JSON.stringify(job.results, null, 2)
  const dataBlob = new Blob([dataStr], { type: 'application/json' })
  const url = URL.createObjectURL(dataBlob)
  const link = document.createElement('a')
  link.href = url
  link.download = `results-${job.operation}-${job.id.substring(0, 8)}.json`
  link.click()
  URL.revokeObjectURL(url)
  appStore.addNotification('Results downloaded', 'success')
}

function exportJobs() {
  if (filteredJobs.value.length === 0) {
    appStore.addNotification('No jobs to export', 'warning')
    return
  }

  const exportData = {
    exportedAt: new Date().toISOString(),
    jobCount: filteredJobs.value.length,
    jobs: filteredJobs.value.map(job => ({
      id: job.id,
      operation: job.operation,
      status: job.status,
      progress: job.progress,
      createdAt: job.createdAt,
      completedAt: job.completedAt || null,
      error: job.error || null,
      hasResults: !!job.results
    }))
  }

  const dataStr = JSON.stringify(exportData, null, 2)
  const dataBlob = new Blob([dataStr], { type: 'application/json' })
  const url = URL.createObjectURL(dataBlob)
  const link = document.createElement('a')
  link.href = url
  link.download = `jobs-export-${format(new Date(), 'yyyy-MM-dd-HHmmss')}.json`
  link.click()
  URL.revokeObjectURL(url)
  appStore.addNotification(`Exported ${filteredJobs.value.length} jobs`, 'success')
}
</script>

<style scoped>
.jobs-page {
  background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
  min-height: 100vh;
}
</style>
