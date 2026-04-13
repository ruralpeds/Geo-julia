<template>
  <div class="login-container">
    <div class="login-card">
      <div class="text-center mb-8">
        <svg class="w-16 h-16 mx-auto text-blue-600 mb-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
        </svg>
        <h1 class="text-3xl font-bold text-gray-800">GeoSpatial Engine</h1>
        <p class="text-gray-600 mt-2">Advanced Spatial Analysis Platform</p>
      </div>

      <form @submit.prevent="handleLogin" class="space-y-4">
        <!-- Username -->
        <div>
          <label for="username" class="block text-sm font-medium text-gray-700">Username</label>
          <input
            id="username"
            v-model="username"
            type="text"
            placeholder="admin"
            class="mt-1 w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            :disabled="loading"
          />
        </div>

        <!-- Password -->
        <div>
          <label for="password" class="block text-sm font-medium text-gray-700">Password</label>
          <input
            id="password"
            v-model="password"
            type="password"
            placeholder="changeme"
            class="mt-1 w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            :disabled="loading"
          />
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="loading || !username || !password"
          class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium rounded-lg transition duration-200"
        >
          {{ loading ? 'Logging in...' : 'Login' }}
        </button>
      </form>

      <!-- Demo Credentials -->
      <div class="mt-6 pt-4 border-t border-gray-200">
        <p class="text-sm text-gray-600 mb-2">Demo Credentials:</p>
        <code class="text-xs bg-gray-100 p-2 rounded block">
          Username: admin<br />
          Password: changeme
        </code>
      </div>

      <!-- Features -->
      <div class="mt-8 pt-6 border-t border-gray-200">
        <h3 class="font-semibold text-gray-800 mb-3">Features</h3>
        <ul class="space-y-2 text-sm text-gray-600">
          <li class="flex items-start gap-2">
            <span class="text-blue-600">✓</span>
            <span>Ingest data from 4+ sources (NOAA, USGS, OSM, Copernicus)</span>
          </li>
          <li class="flex items-start gap-2">
            <span class="text-blue-600">✓</span>
            <span>Spatial analysis (buffer, clip, hotspots, clustering)</span>
          </li>
          <li class="flex items-start gap-2">
            <span class="text-blue-600">✓</span>
            <span>Machine learning (5 algorithms with cross-validation)</span>
          </li>
          <li class="flex items-start gap-2">
            <span class="text-blue-600">✓</span>
            <span>Interactive visualizations (maps, heatmaps, 3D plots)</span>
          </li>
          <li class="flex items-start gap-2">
            <span class="text-blue-600">✓</span>
            <span>Async job queue with real-time progress tracking</span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()

const username = ref('admin')
const password = ref('changeme')
const loading = ref(false)

const handleLogin = async () => {
  loading.value = true
  try {
    const success = await appStore.login(username.value, password.value)
    if (success) {
      appStore.setCurrentPage('dashboard')
    }
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-container {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 2rem;
}

.login-card {
  width: 100%;
  max-width: 400px;
  background: white;
  border-radius: 1rem;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  padding: 2rem;
}

code {
  font-family: 'Courier New', monospace;
}
</style>
