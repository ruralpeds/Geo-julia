<template>
  <div class="app" :class="{ 'sidebar-closed': !appStore.sidebarOpen }">
    <!-- Navigation -->
    <nav class="navbar bg-gradient-to-r from-blue-600 to-blue-800 text-white shadow-lg">
      <div class="navbar-content flex items-center justify-between px-6 py-4">
        <!-- Logo -->
        <div class="logo flex items-center gap-3">
          <svg class="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
          </svg>
          <h1 class="text-2xl font-bold">GeoSpatial Engine</h1>
        </div>

        <!-- Center nav items -->
        <div class="nav-items flex gap-6">
          <button
            @click="appStore.setCurrentPage('dashboard')"
            :class="appStore.currentPage === 'dashboard' ? 'border-b-2 border-white' : ''"
            class="nav-item hover:opacity-80 transition"
          >
            Dashboard
          </button>
          <button
            v-if="appStore.isAuthenticated"
            @click="appStore.setCurrentPage('analysis')"
            :class="appStore.currentPage === 'analysis' ? 'border-b-2 border-white' : ''"
            class="nav-item hover:opacity-80 transition"
          >
            Analysis
          </button>
          <button
            v-if="appStore.isAuthenticated"
            @click="appStore.setCurrentPage('jobs')"
            :class="appStore.currentPage === 'jobs' ? 'border-b-2 border-white' : ''"
            class="nav-item hover:opacity-80 transition"
          >
            Jobs ({{ appStore.activeJobs.length }})
          </button>
          <button
            v-if="appStore.isAuthenticated"
            @click="appStore.setCurrentPage('settings')"
            :class="appStore.currentPage === 'settings' ? 'border-b-2 border-white' : ''"
            class="nav-item hover:opacity-80 transition"
          >
            Settings
          </button>
          <button
            v-if="appStore.isAuthenticated && appStore.isAdmin"
            @click="appStore.setCurrentPage('admin')"
            :class="appStore.currentPage === 'admin' ? 'border-b-2 border-white' : ''"
            class="nav-item hover:opacity-80 transition"
          >
            Admin
          </button>
        </div>

        <!-- Right side: User & Status -->
        <div class="nav-right flex items-center gap-4">
          <!-- Server Status -->
          <div class="status-indicator flex items-center gap-2">
            <div :class="appStore.serverHealthy ? 'bg-green-400' : 'bg-red-400'" class="w-3 h-3 rounded-full"></div>
            <span class="text-sm">{{ appStore.serverHealthy ? 'Connected' : 'Disconnected' }}</span>
          </div>

          <!-- User Menu -->
          <div v-if="appStore.isAuthenticated" class="user-menu flex items-center gap-2">
            <span class="text-sm">{{ appStore.user?.username }}</span>
            <button
              @click="appStore.logout"
              class="px-3 py-1 bg-red-500 hover:bg-red-600 rounded text-sm transition"
            >
              Logout
            </button>
          </div>
        </div>
      </div>
    </nav>

    <div class="main-content flex">
      <!-- Sidebar (if authenticated) -->
      <aside v-if="appStore.isAuthenticated" class="sidebar bg-gray-100 border-r border-gray-300 w-64 transition-all duration-300">
        <div class="sidebar-content p-4">
          <h2 class="text-lg font-bold mb-4">Quick Actions</h2>

          <div class="space-y-3">
            <button
              @click="showIngestModal = true"
              class="w-full px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded transition"
            >
              📊 Ingest Data
            </button>

            <button
              @click="showAnalysisModal = true"
              class="w-full px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded transition"
            >
              🔍 New Analysis
            </button>

            <button
              @click="showVisualizationModal = true"
              class="w-full px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded transition"
            >
              📈 Visualize
            </button>
          </div>

          <hr class="my-4">

          <h3 class="font-semibold mb-2">Recent Jobs</h3>
          <div class="space-y-2 max-h-64 overflow-y-auto">
            <div
              v-for="job in appStore.activeJobs.slice(0, 5)"
              :key="job.id"
              @click="appStore.selectedJobId = job.id; appStore.setCurrentPage('jobs')"
              class="p-2 bg-white border border-gray-300 rounded cursor-pointer hover:bg-gray-50 transition"
            >
              <div class="text-sm font-medium truncate">{{ job.operation }}</div>
              <div class="text-xs text-gray-600">{{ job.status }} {{ job.progress }}%</div>
            </div>
          </div>
        </div>
      </aside>

      <!-- Main Content Area -->
      <main class="flex-1 overflow-auto">
        <!-- Login Page -->
        <LoginPage v-if="!appStore.isAuthenticated" />

        <!-- Dashboard Page -->
        <DashboardPage v-else-if="appStore.currentPage === 'dashboard'" />

        <!-- Analysis Page -->
        <AnalysisPage v-else-if="appStore.currentPage === 'analysis'" />

        <!-- Jobs Page -->
        <JobsPage v-else-if="appStore.currentPage === 'jobs'" />

        <!-- Settings Page -->
        <SettingsPage v-else-if="appStore.currentPage === 'settings'" />

        <!-- Admin Page -->
        <AdminPage v-else-if="appStore.currentPage === 'admin'" />
      </main>
    </div>

    <!-- Modals -->
    <IngestModal v-if="showIngestModal" @close="showIngestModal = false" />
    <AnalysisModal v-if="showAnalysisModal" @close="showAnalysisModal = false" />
    <VisualizationModal v-if="showVisualizationModal" @close="showVisualizationModal = false" />

    <!-- Notifications -->
    <div class="fixed bottom-4 right-4 space-y-2 z-50">
      <div
        v-for="notification in appStore.notifications"
        :key="notification.id"
        :class="[
          'px-4 py-3 rounded shadow-lg text-white',
          notification.type === 'success' ? 'bg-green-500' : '',
          notification.type === 'error' ? 'bg-red-500' : '',
          notification.type === 'info' ? 'bg-blue-500' : '',
          notification.type === 'warning' ? 'bg-yellow-500' : ''
        ]"
      >
        {{ notification.message }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAppStore } from '@/stores/app'
import LoginPage from '@/views/LoginPage.vue'
import DashboardPage from '@/views/DashboardPage.vue'
import AnalysisPage from '@/views/AnalysisPage.vue'
import JobsPage from '@/views/JobsPage.vue'
import SettingsPage from '@/views/SettingsPage.vue'
import AdminPage from '@/views/AdminPage.vue'
import IngestModal from '@/components/IngestModal.vue'
import AnalysisModal from '@/components/AnalysisModal.vue'
import VisualizationModal from '@/components/VisualizationModal.vue'

const appStore = useAppStore()

const showIngestModal = ref(false)
const showAnalysisModal = ref(false)
const showVisualizationModal = ref(false)
</script>

<style scoped>
.app {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background-color: #f5f5f5;
}

.navbar {
  flex-shrink: 0;
  z-index: 100;
}

.main-content {
  flex: 1;
  overflow: hidden;
}

.sidebar {
  flex-shrink: 0;
  overflow-y: auto;
  box-shadow: inset -1px 0 0 rgba(0, 0, 0, 0.1);
}

.sidebar-closed .sidebar {
  display: none;
}

main {
  flex: 1;
  background-color: #f5f5f5;
}

.nav-item {
  padding: 0.5rem 0;
  font-weight: 500;
  font-size: 0.95rem;
}
</style>
