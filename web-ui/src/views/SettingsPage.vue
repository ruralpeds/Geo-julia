<template>
  <div class="settings-page p-6">
    <h1 class="text-3xl font-bold text-gray-800 mb-6">Settings</h1>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Settings Menu -->
      <div class="bg-white rounded-lg shadow">
        <div class="p-4 border-b border-gray-200">
          <h2 class="font-bold text-gray-800">Settings</h2>
        </div>
        <div class="divide-y">
          <button
            v-for="section in settingsSections"
            :key="section"
            @click="activeSection = section"
            :class="activeSection === section ? 'bg-blue-50 text-blue-600 border-l-4 border-blue-600' : 'text-gray-700 hover:bg-gray-50'"
            class="w-full text-left px-4 py-3 transition"
          >
            {{ formatSectionName(section) }}
          </button>
        </div>
      </div>

      <!-- Settings Content -->
      <div class="lg:col-span-2">
        <!-- Appearance Settings -->
        <div v-if="activeSection === 'appearance'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">Appearance</h2>

          <div class="space-y-6">
            <!-- Theme Selection -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-3">Theme</label>
              <div class="flex gap-4">
                <button
                  @click="settings.theme = 'light'"
                  :class="settings.theme === 'light' ? 'ring-2 ring-blue-500' : 'ring-1 ring-gray-300'"
                  class="flex items-center gap-2 px-4 py-3 rounded-lg transition"
                >
                  <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 18a6 6 0 100-12 6 6 0 000 12zM12 2v4m0 12v4M2 12h4m12 0h4M4.22 4.22l2.83 2.83m8.9 0l2.83-2.83M4.22 19.78l2.83-2.83m8.9 0l2.83 2.83"/>
                  </svg>
                  Light
                </button>
                <button
                  @click="settings.theme = 'dark'"
                  :class="settings.theme === 'dark' ? 'ring-2 ring-blue-500' : 'ring-1 ring-gray-300'"
                  class="flex items-center gap-2 px-4 py-3 rounded-lg transition"
                >
                  <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
                  </svg>
                  Dark
                </button>
              </div>
            </div>

            <!-- Font Size -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Font Size</label>
              <select v-model="settings.fontSize" class="w-full px-3 py-2 border border-gray-300 rounded">
                <option value="small">Small</option>
                <option value="normal">Normal</option>
                <option value="large">Large</option>
              </select>
            </div>

            <!-- Notifications -->
            <div>
              <label class="flex items-center gap-2">
                <input v-model="settings.enableNotifications" type="checkbox" class="w-4 h-4" />
                <span class="text-sm font-medium text-gray-700">Enable Notifications</span>
              </label>
            </div>
          </div>
        </div>

        <!-- API Settings -->
        <div v-if="activeSection === 'api'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">API Configuration</h2>

          <div class="space-y-4">
            <!-- API URL -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">API Base URL</label>
              <input
                v-model="settings.apiUrl"
                type="url"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
              <p class="text-xs text-gray-600 mt-1">Default: http://localhost:8080</p>
            </div>

            <!-- API Timeout -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Request Timeout (seconds)</label>
              <input
                v-model.number="settings.apiTimeout"
                type="number"
                min="5"
                max="300"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>

            <!-- Auto-refresh -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Auto-refresh Interval (seconds)</label>
              <input
                v-model.number="settings.autoRefreshInterval"
                type="number"
                min="5"
                max="300"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>

            <!-- Test Connection -->
            <button
              @click="testConnection"
              :disabled="testing"
              class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white rounded transition"
            >
              {{ testing ? 'Testing...' : 'Test Connection' }}
            </button>
          </div>
        </div>

        <!-- Data Settings -->
        <div v-if="activeSection === 'data'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">Data Settings</h2>

          <div class="space-y-4">
            <!-- Max Dataset Size -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Max Dataset Size (MB)</label>
              <input
                v-model.number="settings.maxDatasetSize"
                type="number"
                min="1"
                max="1000"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>

            <!-- Auto Cache -->
            <div>
              <label class="flex items-center gap-2">
                <input v-model="settings.enableCache" type="checkbox" class="w-4 h-4" />
                <span class="text-sm font-medium text-gray-700">Enable Result Caching</span>
              </label>
            </div>

            <!-- Cache Duration -->
            <div v-if="settings.enableCache">
              <label class="block text-sm font-medium text-gray-700 mb-2">Cache Duration (minutes)</label>
              <input
                v-model.number="settings.cacheDuration"
                type="number"
                min="1"
                max="1440"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
            </div>

            <!-- Clear Cache -->
            <button
              @click="clearCache"
              class="w-full px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded transition"
            >
              Clear Cache
            </button>
          </div>
        </div>

        <!-- About Section -->
        <div v-if="activeSection === 'about'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">About</h2>

          <div class="space-y-4 text-gray-700">
            <div>
              <p class="font-semibold">GeoSpatial Analysis Engine</p>
              <p class="text-sm text-gray-600">Version 1.0.0</p>
            </div>

            <div>
              <p class="font-semibold mb-2">Features</p>
              <ul class="text-sm space-y-1 list-disc list-inside">
                <li>4+ data source integrations</li>
                <li>6 spatial operations</li>
                <li>4 statistical methods</li>
                <li>5 ML algorithms</li>
                <li>10+ visualizations</li>
              </ul>
            </div>

            <div>
              <p class="font-semibold mb-2">Technology</p>
              <ul class="text-sm space-y-1 list-disc list-inside">
                <li>Frontend: Vue.js 3 + Vite</li>
                <li>Backend: Julia with HTTP.jl</li>
                <li>Database: PostgreSQL + PostGIS</li>
                <li>Caching: Redis</li>
              </ul>
            </div>

            <div>
              <p class="font-semibold mb-2">Links</p>
              <ul class="text-sm space-y-1">
                <li><a href="#" class="text-blue-600 hover:underline">GitHub Repository</a></li>
                <li><a href="#" class="text-blue-600 hover:underline">Documentation</a></li>
                <li><a href="#" class="text-blue-600 hover:underline">Report Issues</a></li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Save Button -->
    <div class="mt-6 flex gap-4">
      <button
        @click="saveSettings"
        :disabled="saving"
        class="px-6 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded transition"
      >
        {{ saving ? 'Saving...' : 'Save Settings' }}
      </button>
      <button
        @click="resetSettings"
        class="px-6 py-2 bg-gray-600 hover:bg-gray-700 text-white rounded transition"
      >
        Reset to Defaults
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive } from 'vue'
import { useAppStore } from '@/stores/app'
import api from '@/api/client'

const appStore = useAppStore()

const settingsSections = ['appearance', 'api', 'data', 'about']
const activeSection = ref('appearance')
const saving = ref(false)
const testing = ref(false)

const settings = reactive({
  // Appearance
  theme: localStorage.getItem('theme') || 'light',
  fontSize: localStorage.getItem('fontSize') || 'normal',
  enableNotifications: localStorage.getItem('enableNotifications') !== 'false',

  // API
  apiUrl: localStorage.getItem('apiUrl') || 'http://localhost:8080',
  apiTimeout: parseInt(localStorage.getItem('apiTimeout') || '30'),
  autoRefreshInterval: parseInt(localStorage.getItem('autoRefreshInterval') || '30'),

  // Data
  maxDatasetSize: parseInt(localStorage.getItem('maxDatasetSize') || '100'),
  enableCache: localStorage.getItem('enableCache') !== 'false',
  cacheDuration: parseInt(localStorage.getItem('cacheDuration') || '60')
})

function formatSectionName(section) {
  return section.charAt(0).toUpperCase() + section.slice(1)
}

async function testConnection() {
  testing.value = true
  try {
    await api.health()
    appStore.addNotification('API connection successful', 'success')
  } catch (error) {
    appStore.addNotification('API connection failed: ' + error.message, 'error')
  } finally {
    testing.value = false
  }
}

function clearCache() {
  localStorage.removeItem('cache')
  appStore.addNotification('Cache cleared', 'success')
}

async function saveSettings() {
  saving.value = true
  try {
    // Save to localStorage
    localStorage.setItem('theme', settings.theme)
    localStorage.setItem('fontSize', settings.fontSize)
    localStorage.setItem('enableNotifications', settings.enableNotifications)
    localStorage.setItem('apiUrl', settings.apiUrl)
    localStorage.setItem('apiTimeout', settings.apiTimeout)
    localStorage.setItem('autoRefreshInterval', settings.autoRefreshInterval)
    localStorage.setItem('maxDatasetSize', settings.maxDatasetSize)
    localStorage.setItem('enableCache', settings.enableCache)
    localStorage.setItem('cacheDuration', settings.cacheDuration)

    // Apply theme
    if (settings.theme === 'dark') {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }

    appStore.addNotification('Settings saved successfully', 'success')
  } finally {
    saving.value = false
  }
}

function resetSettings() {
  settings.theme = 'light'
  settings.fontSize = 'normal'
  settings.enableNotifications = true
  settings.apiUrl = 'http://localhost:8080'
  settings.apiTimeout = 30
  settings.autoRefreshInterval = 30
  settings.maxDatasetSize = 100
  settings.enableCache = true
  settings.cacheDuration = 60

  appStore.addNotification('Settings reset to defaults', 'info')
}
</script>

<style scoped>
.settings-page {
  background: #f5f7fa;
  min-height: 100vh;
}
</style>
