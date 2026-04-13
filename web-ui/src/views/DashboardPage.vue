<template>
  <div class="dashboard-page p-6">
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-gray-800">Dashboard</h1>
      <p class="text-gray-600 mt-1">Welcome to GeoSpatial Analysis Engine</p>
    </div>

    <!-- Statistics Cards -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
      <!-- Active Jobs Card -->
      <div class="stat-card bg-white rounded-lg shadow p-6 border-l-4 border-blue-500">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-gray-600 text-sm font-medium">Active Jobs</p>
            <p class="text-3xl font-bold text-blue-600 mt-2">{{ appStore.activeJobs.length }}</p>
          </div>
          <svg class="w-12 h-12 text-blue-200" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
          </svg>
        </div>
      </div>

      <!-- Data Rows Card -->
      <div class="stat-card bg-white rounded-lg shadow p-6 border-l-4 border-green-500">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-gray-600 text-sm font-medium">Data Rows</p>
            <p class="text-3xl font-bold text-green-600 mt-2">{{ appStore.currentDataset?.rowsIngested || 0 }}</p>
          </div>
          <svg class="w-12 h-12 text-green-200" fill="currentColor" viewBox="0 0 24 24">
            <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
          </svg>
        </div>
      </div>

      <!-- Server Status Card -->
      <div class="stat-card bg-white rounded-lg shadow p-6 border-l-4" :class="appStore.serverHealthy ? 'border-green-500' : 'border-red-500'">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-gray-600 text-sm font-medium">Server Status</p>
            <p :class="appStore.serverHealthy ? 'text-green-600' : 'text-red-600'" class="text-lg font-bold mt-2">
              {{ appStore.serverHealthy ? 'Healthy' : 'Offline' }}
            </p>
          </div>
          <div :class="appStore.serverHealthy ? 'bg-green-100' : 'bg-red-100'" class="w-12 h-12 rounded-full flex items-center justify-center">
            <div :class="appStore.serverHealthy ? 'bg-green-500' : 'bg-red-500'" class="w-4 h-4 rounded-full"></div>
          </div>
        </div>
      </div>

      <!-- Completed Analyses Card -->
      <div class="stat-card bg-white rounded-lg shadow p-6 border-l-4 border-purple-500">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-gray-600 text-sm font-medium">Completed</p>
            <p class="text-3xl font-bold text-purple-600 mt-2">{{ completedJobsCount }}</p>
          </div>
          <svg class="w-12 h-12 text-purple-200" fill="currentColor" viewBox="0 0 24 24">
            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/>
          </svg>
        </div>
      </div>
    </div>

    <!-- Quick Start Guide -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
      <!-- Getting Started -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">🚀 Getting Started</h2>
        <ol class="space-y-3 text-gray-700">
          <li class="flex gap-3">
            <span class="font-bold text-blue-600 min-w-6">1</span>
            <span><strong>Ingest Data:</strong> Load data from NOAA, USGS, OSM, or Copernicus</span>
          </li>
          <li class="flex gap-3">
            <span class="font-bold text-blue-600 min-w-6">2</span>
            <span><strong>Analyze:</strong> Run spatial analysis (buffer, clip, hotspots)</span>
          </li>
          <li class="flex gap-3">
            <span class="font-bold text-blue-600 min-w-6">3</span>
            <span><strong>Model:</strong> Train ML models on extracted features</span>
          </li>
          <li class="flex gap-3">
            <span class="font-bold text-blue-600 min-w-6">4</span>
            <span><strong>Visualize:</strong> Create interactive maps and charts</span>
          </li>
          <li class="flex gap-3">
            <span class="font-bold text-blue-600 min-w-6">5</span>
            <span><strong>Export:</strong> Download results as GeoJSON/GeoTIFF</span>
          </li>
        </ol>
      </div>

      <!-- Supported Operations -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-bold text-gray-800 mb-4">📊 Operations</h2>
        <div class="space-y-2 text-gray-700">
          <div class="flex items-center gap-2">
            <span class="text-green-600">✓</span>
            <span><strong>Spatial:</strong> Buffer, Clip, Dissolve, Intersect, Union, Reproject</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-green-600">✓</span>
            <span><strong>Statistics:</strong> Autocorrelation, Hotspots, Clustering, Kriging</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-green-600">✓</span>
            <span><strong>ML Models:</strong> Linear, Ridge, Lasso, Forest, Boost</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-green-600">✓</span>
            <span><strong>Visualization:</strong> Maps, Heatmaps, 3D, Animation</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Recent Jobs -->
    <div class="bg-white rounded-lg shadow p-6">
      <h2 class="text-xl font-bold text-gray-800 mb-4">📋 Recent Jobs</h2>
      <div v-if="appStore.activeJobs.length === 0" class="text-center py-8 text-gray-600">
        <p>No jobs yet. Start by creating a new analysis!</p>
      </div>
      <div v-else class="space-y-3">
        <div
          v-for="job in appStore.activeJobs.slice(0, 5)"
          :key="job.id"
          class="flex items-center gap-4 p-3 bg-gray-50 rounded border border-gray-200 hover:bg-gray-100 transition"
        >
          <div class="flex-1">
            <p class="font-medium text-gray-800">{{ job.operation }}</p>
            <p class="text-sm text-gray-600">{{ formatDate(job.createdAt) }}</p>
          </div>
          <div class="text-right">
            <div class="text-sm font-medium" :class="statusColor(job.status)">{{ job.status }}</div>
            <div class="text-xs text-gray-600">{{ job.progress }}%</div>
          </div>
          <div class="w-20 bg-gray-200 rounded-full h-2">
            <div
              class="bg-blue-600 h-2 rounded-full transition-all duration-300"
              :style="{ width: job.progress + '%' }"
            ></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useAppStore } from '@/stores/app'
import { formatDistanceToNow } from 'date-fns'

const appStore = useAppStore()

const completedJobsCount = computed(() => {
  return appStore.activeJobs.filter(j => j.status === 'completed').length
})

function formatDate(date) {
  return formatDistanceToNow(new Date(date), { addSuffix: true })
}

function statusColor(status) {
  const colors = {
    pending: 'text-yellow-600',
    running: 'text-blue-600',
    completed: 'text-green-600',
    failed: 'text-red-600'
  }
  return colors[status] || 'text-gray-600'
}
</script>

<style scoped>
.dashboard-page {
  background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
  min-height: 100vh;
}

.stat-card {
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.stat-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 12px 24px rgba(0, 0, 0, 0.15);
}
</style>
