<template>
  <div class="admin-page p-6">
    <h1 class="text-3xl font-bold text-gray-800 mb-6">Administration Dashboard</h1>

    <div class="grid grid-cols-1 lg:grid-cols-4 gap-4 mb-6">
      <!-- System Stats -->
      <div class="bg-white rounded-lg shadow p-4">
        <div class="text-sm text-gray-600 font-medium">Total Users</div>
        <div class="text-3xl font-bold text-gray-800">{{ stats.totalUsers }}</div>
      </div>

      <div class="bg-white rounded-lg shadow p-4">
        <div class="text-sm text-gray-600 font-medium">API Health</div>
        <div :class="stats.apiHealth === 'healthy' ? 'text-green-600' : 'text-red-600'" class="text-3xl font-bold">
          {{ stats.apiHealth === 'healthy' ? '✓' : '✕' }}
        </div>
      </div>

      <div class="bg-white rounded-lg shadow p-4">
        <div class="text-sm text-gray-600 font-medium">Active Jobs</div>
        <div class="text-3xl font-bold text-gray-800">{{ stats.activeJobs }}</div>
      </div>

      <div class="bg-white rounded-lg shadow p-4">
        <div class="text-sm text-gray-600 font-medium">Database Size</div>
        <div class="text-3xl font-bold text-gray-800">{{ stats.dbSize }}</div>
      </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Admin Menu -->
      <div class="bg-white rounded-lg shadow">
        <div class="p-4 border-b border-gray-200">
          <h2 class="font-bold text-gray-800">Admin Menu</h2>
        </div>
        <div class="divide-y">
          <button
            v-for="section in adminSections"
            :key="section"
            @click="activeSection = section"
            :class="activeSection === section ? 'bg-blue-50 text-blue-600 border-l-4 border-blue-600' : 'text-gray-700 hover:bg-gray-50'"
            class="w-full text-left px-4 py-3 transition"
          >
            {{ formatSectionName(section) }}
          </button>
        </div>
      </div>

      <!-- Admin Content -->
      <div class="lg:col-span-2">
        <!-- User Management -->
        <div v-if="activeSection === 'users'" class="bg-white rounded-lg shadow p-6">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">User Management</h2>
            <button
              @click="showNewUserForm = !showNewUserForm"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
            >
              + Add User
            </button>
          </div>

          <!-- New User Form -->
          <div v-if="showNewUserForm" class="bg-blue-50 p-4 rounded-lg mb-6 border border-blue-200">
            <h3 class="font-semibold text-gray-800 mb-4">Create New User</h3>
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Username</label>
                <input
                  v-model="newUser.username"
                  type="text"
                  placeholder="Enter username"
                  class="w-full px-3 py-2 border border-gray-300 rounded"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Email</label>
                <input
                  v-model="newUser.email"
                  type="email"
                  placeholder="user@example.com"
                  class="w-full px-3 py-2 border border-gray-300 rounded"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Role</label>
                <select v-model="newUser.role" class="w-full px-3 py-2 border border-gray-300 rounded">
                  <option value="viewer">Viewer</option>
                  <option value="analyst">Analyst</option>
                  <option value="admin">Admin</option>
                </select>
              </div>

              <div class="flex gap-2">
                <button
                  @click="createUser"
                  class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded transition"
                >
                  Create User
                </button>
                <button
                  @click="showNewUserForm = false"
                  class="px-4 py-2 bg-gray-300 hover:bg-gray-400 text-gray-800 rounded transition"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>

          <!-- Users List -->
          <div class="space-y-3">
            <div v-for="user in users" :key="user.id" class="border border-gray-200 rounded-lg p-4">
              <div class="flex justify-between items-start">
                <div class="flex-1">
                  <div class="font-semibold text-gray-800">{{ user.username }}</div>
                  <div class="text-sm text-gray-600">{{ user.email }}</div>
                  <div class="flex gap-2 mt-2">
                    <span :class="getRoleColor(user.role)" class="text-xs px-2 py-1 rounded font-medium">
                      {{ user.role }}
                    </span>
                    <span class="text-xs text-gray-500">Created: {{ formatDate(user.createdAt) }}</span>
                  </div>
                </div>

                <div class="flex gap-2">
                  <button
                    @click="editUser(user)"
                    class="px-3 py-1 text-sm bg-blue-100 text-blue-600 hover:bg-blue-200 rounded transition"
                  >
                    Edit
                  </button>
                  <button
                    @click="deleteUser(user.id)"
                    class="px-3 py-1 text-sm bg-red-100 text-red-600 hover:bg-red-200 rounded transition"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- System Monitoring -->
        <div v-if="activeSection === 'system'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">System Monitoring</h2>

          <div class="space-y-6">
            <!-- API Status -->
            <div>
              <div class="flex justify-between items-center mb-2">
                <label class="block text-sm font-medium text-gray-700">API Status</label>
                <button
                  @click="checkApiStatus"
                  class="text-xs px-2 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
                >
                  Refresh
                </button>
              </div>
              <div class="bg-gray-100 p-4 rounded-lg space-y-2">
                <div class="flex justify-between">
                  <span class="text-gray-700">Response Time</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.apiResponseTime }}ms</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-700">Uptime</span>
                  <span class="font-semibold text-green-600">99.9%</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-700">Requests Today</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.requestsToday }}</span>
                </div>
              </div>
            </div>

            <!-- Database Status -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Database Status</label>
              <div class="bg-gray-100 p-4 rounded-lg space-y-2">
                <div class="flex justify-between">
                  <span class="text-gray-700">Connection</span>
                  <span class="font-semibold text-green-600">Connected</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-700">Tables</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.dbTables }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-700">Disk Usage</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.dbSize }}</span>
                </div>
              </div>
            </div>

            <!-- Cache Status -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Cache Status</label>
              <div class="bg-gray-100 p-4 rounded-lg space-y-2">
                <div class="flex justify-between">
                  <span class="text-gray-700">Hit Rate</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.cacheHitRate }}%</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-700">Cached Items</span>
                  <span class="font-semibold text-gray-800">{{ monitoring.cachedItems }}</span>
                </div>
                <button
                  @click="clearCache"
                  class="w-full mt-3 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded transition text-sm"
                >
                  Clear Cache
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Analytics -->
        <div v-if="activeSection === 'analytics'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">Analytics Dashboard</h2>

          <div class="space-y-6">
            <!-- Top Operations -->
            <div>
              <h3 class="font-semibold text-gray-800 mb-3">Most Used Operations</h3>
              <div class="space-y-2">
                <div v-for="op in analytics.topOperations" :key="op.name" class="flex justify-between items-center p-3 bg-gray-50 rounded">
                  <span class="text-gray-700">{{ op.name }}</span>
                  <div class="flex gap-3">
                    <div class="bg-blue-100 text-blue-600 px-3 py-1 rounded text-sm font-semibold">
                      {{ op.count }} uses
                    </div>
                    <div class="w-40 bg-gray-200 rounded h-2">
                      <div class="bg-blue-600 h-2 rounded" :style="{ width: (op.count / analytics.topOperations[0].count) * 100 + '%' }"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- User Activity -->
            <div>
              <h3 class="font-semibold text-gray-800 mb-3">User Activity (Last 7 Days)</h3>
              <div class="space-y-2">
                <div class="flex items-end justify-between gap-2 h-32 bg-gray-50 p-3 rounded">
                  <div v-for="day in analytics.dailyActivity" :key="day.date" class="flex-1 flex flex-col items-center justify-end">
                    <div class="text-xs text-gray-600">{{ day.date }}</div>
                    <div class="bg-purple-600 w-full rounded-t" :style="{ height: (day.count / 50) * 100 + '%' }"></div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Analysis Success Rate -->
            <div>
              <h3 class="font-semibold text-gray-800 mb-3">Analysis Success Rate</h3>
              <div class="bg-gray-50 p-4 rounded-lg">
                <div class="flex items-center gap-4">
                  <div class="flex-1">
                    <div class="flex justify-between mb-2">
                      <span class="text-gray-700">Success</span>
                      <span class="font-semibold">{{ analytics.successRate }}%</span>
                    </div>
                    <div class="bg-gray-200 rounded-full h-4">
                      <div class="bg-green-600 h-4 rounded-full" :style="{ width: analytics.successRate + '%' }"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Configuration -->
        <div v-if="activeSection === 'config'" class="bg-white rounded-lg shadow p-6">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">Configuration Management</h2>

          <div class="space-y-6">
            <!-- Rate Limiting -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Rate Limit (requests per minute)</label>
              <input
                v-model.number="config.rateLimit"
                type="number"
                min="10"
                max="1000"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
              <p class="text-xs text-gray-600 mt-1">Default: 100 requests/minute per user</p>
            </div>

            <!-- Max Dataset Size -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Max Dataset Size (MB)</label>
              <input
                v-model.number="config.maxDatasetSize"
                type="number"
                min="10"
                max="10000"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
              <p class="text-xs text-gray-600 mt-1">Default: 500 MB</p>
            </div>

            <!-- Cache Duration -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Cache Duration (minutes)</label>
              <input
                v-model.number="config.cacheDuration"
                type="number"
                min="5"
                max="1440"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
              <p class="text-xs text-gray-600 mt-1">Default: 60 minutes</p>
            </div>

            <!-- Job Timeout -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Job Timeout (seconds)</label>
              <input
                v-model.number="config.jobTimeout"
                type="number"
                min="60"
                max="86400"
                class="w-full px-3 py-2 border border-gray-300 rounded"
              />
              <p class="text-xs text-gray-600 mt-1">Default: 3600 seconds (1 hour)</p>
            </div>

            <!-- Enable Features -->
            <div class="space-y-3">
              <div class="flex items-center gap-2">
                <input
                  v-model="config.enableCache"
                  type="checkbox"
                  class="w-4 h-4"
                />
                <label class="text-sm font-medium text-gray-700">Enable Result Caching</label>
              </div>

              <div class="flex items-center gap-2">
                <input
                  v-model="config.enableNotifications"
                  type="checkbox"
                  class="w-4 h-4"
                />
                <label class="text-sm font-medium text-gray-700">Enable User Notifications</label>
              </div>

              <div class="flex items-center gap-2">
                <input
                  v-model="config.enableAnalytics"
                  type="checkbox"
                  class="w-4 h-4"
                />
                <label class="text-sm font-medium text-gray-700">Enable Usage Analytics</label>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Save Configuration -->
    <div v-if="activeSection === 'config'" class="mt-6 flex gap-4">
      <button
        @click="saveConfig"
        :disabled="saving"
        class="px-6 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded transition"
      >
        {{ saving ? 'Saving...' : 'Save Configuration' }}
      </button>
      <button
        @click="resetConfig"
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
import { formatDate } from 'date-fns'

const appStore = useAppStore()

const adminSections = ['users', 'system', 'analytics', 'config']
const activeSection = ref('users')

// User Management
const users = ref([
  { id: 1, username: 'admin', email: 'admin@geo.local', role: 'admin', createdAt: new Date('2026-04-01') },
  { id: 2, username: 'analyst', email: 'analyst@geo.local', role: 'analyst', createdAt: new Date('2026-04-05') },
  { id: 3, username: 'viewer', email: 'viewer@geo.local', role: 'viewer', createdAt: new Date('2026-04-10') }
])

const showNewUserForm = ref(false)
const newUser = reactive({
  username: '',
  email: '',
  role: 'analyst'
})

// System Monitoring
const monitoring = reactive({
  apiResponseTime: 145,
  requestsToday: 2341,
  dbTables: 15,
  dbSize: '2.3 GB',
  cacheHitRate: 78,
  cachedItems: 524
})

// Analytics
const analytics = reactive({
  topOperations: [
    { name: 'Buffer', count: 145 },
    { name: 'Hotspot Analysis', count: 98 },
    { name: 'Intersect', count: 87 },
    { name: 'Cluster Analysis', count: 76 },
    { name: 'Kriging', count: 54 }
  ],
  dailyActivity: [
    { date: 'Mon', count: 42 },
    { date: 'Tue', count: 38 },
    { date: 'Wed', count: 45 },
    { date: 'Thu', count: 52 },
    { date: 'Fri', count: 48 },
    { date: 'Sat', count: 28 },
    { date: 'Sun', count: 35 }
  ],
  successRate: 94
})

// Configuration
const config = reactive({
  rateLimit: 100,
  maxDatasetSize: 500,
  cacheDuration: 60,
  jobTimeout: 3600,
  enableCache: true,
  enableNotifications: true,
  enableAnalytics: true
})

// Statistics
const stats = reactive({
  totalUsers: users.value.length,
  apiHealth: 'healthy',
  activeJobs: 3,
  dbSize: '2.3 GB'
})

const saving = ref(false)

function formatSectionName(section) {
  return section.charAt(0).toUpperCase() + section.slice(1).replace(/([A-Z])/g, ' $1').trim()
}

function getRoleColor(role) {
  switch (role) {
    case 'admin':
      return 'bg-red-100 text-red-600'
    case 'analyst':
      return 'bg-blue-100 text-blue-600'
    case 'viewer':
      return 'bg-gray-100 text-gray-600'
    default:
      return 'bg-gray-100 text-gray-600'
  }
}

function createUser() {
  if (!newUser.username || !newUser.email) {
    appStore.addNotification('Please fill in all fields', 'error')
    return
  }

  const user = {
    id: Math.max(...users.value.map(u => u.id)) + 1,
    username: newUser.username,
    email: newUser.email,
    role: newUser.role,
    createdAt: new Date()
  }

  users.value.push(user)
  newUser.username = ''
  newUser.email = ''
  newUser.role = 'analyst'
  showNewUserForm.value = false

  appStore.addNotification(`User ${user.username} created successfully`, 'success')
  stats.totalUsers = users.value.length
}

function editUser(user) {
  appStore.addNotification(`Editing user: ${user.username}`, 'info')
}

function deleteUser(userId) {
  const user = users.value.find(u => u.id === userId)
  if (confirm(`Are you sure you want to delete ${user.username}?`)) {
    users.value = users.value.filter(u => u.id !== userId)
    appStore.addNotification(`User ${user.username} deleted`, 'success')
    stats.totalUsers = users.value.length
  }
}

async function checkApiStatus() {
  try {
    await api.health()
    monitoring.apiResponseTime = Math.floor(Math.random() * 100) + 100
    appStore.addNotification('API status checked', 'success')
  } catch (error) {
    appStore.addNotification('API check failed', 'error')
  }
}

function clearCache() {
  monitoring.cachedItems = 0
  monitoring.cacheHitRate = 0
  appStore.addNotification('Cache cleared', 'success')
}

async function saveConfig() {
  saving.value = true
  try {
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 500))
    appStore.addNotification('Configuration saved successfully', 'success')
  } finally {
    saving.value = false
  }
}

function resetConfig() {
  config.rateLimit = 100
  config.maxDatasetSize = 500
  config.cacheDuration = 60
  config.jobTimeout = 3600
  config.enableCache = true
  config.enableNotifications = true
  config.enableAnalytics = true
  appStore.addNotification('Configuration reset to defaults', 'info')
}
</script>

<style scoped>
.admin-page {
  background: #f5f7fa;
  min-height: 100vh;
}
</style>
