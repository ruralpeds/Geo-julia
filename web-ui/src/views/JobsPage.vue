<template>
  <div class="jobs-page p-6">
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-3xl font-bold text-gray-800">Job Queue</h1>
      <div class="text-gray-600">
        {{ appStore.activeJobs.filter(j => j.status === 'completed').length }} /
        {{ appStore.activeJobs.length }} completed
      </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Job List -->
      <div class="lg:col-span-2">
        <div class="bg-white rounded-lg shadow">
          <div v-if="appStore.activeJobs.length === 0" class="p-6 text-center text-gray-600">
            <p>No jobs submitted yet</p>
          </div>

          <div v-else class="divide-y">
            <div
              v-for="job in appStore.activeJobs"
              :key="job.id"
              @click="appStore.selectedJobId = job.id"
              :class="appStore.selectedJobId === job.id ? 'bg-blue-50 border-l-4 border-blue-500' : ''"
              class="p-4 hover:bg-gray-50 cursor-pointer transition"
            >
              <div class="flex items-start justify-between mb-2">
                <div>
                  <h3 class="font-semibold text-gray-800">{{ job.operation }}</h3>
                  <p class="text-xs text-gray-600">{{ formatDate(job.createdAt) }}</p>
                </div>
                <span
                  :class="getStatusClass(job.status)"
                  class="px-3 py-1 rounded-full text-sm font-medium"
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
import { computed } from 'vue'
import { useAppStore } from '@/stores/app'
import { formatDistanceToNow, format } from 'date-fns'

const appStore = useAppStore()

const selectedJob = computed(() => {
  return appStore.activeJobs.find(j => j.id === appStore.selectedJobId)
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
  }
}

function downloadResults(job) {
  const dataStr = JSON.stringify(job.results, null, 2)
  const dataBlob = new Blob([dataStr], { type: 'application/json' })
  const url = URL.createObjectURL(dataBlob)
  const link = document.createElement('a')
  link.href = url
  link.download = `results-${job.id.substring(0, 8)}.json`
  link.click()
  URL.revokeObjectURL(url)
}
</script>

<style scoped>
.jobs-page {
  background: #f5f7fa;
  min-height: 100vh;
}
</style>
