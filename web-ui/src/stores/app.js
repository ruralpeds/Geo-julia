/**
 * Application State Management (Pinia Store)
 *
 * Manages:
 * - Authentication state
 * - Current dataset and analysis
 * - Job queue and results
 * - UI state (modals, notifications, etc.)
 */

import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/api/client'

export const useAppStore = defineStore('app', () => {
  // Authentication state
  const user = ref(null)
  const isAuthenticated = computed(() => !!user.value)
  const isAdmin = computed(() => user.value?.role === 'admin')
  const token = ref(localStorage.getItem('api_token') || '')

  // Dataset state
  const currentDataset = ref(null)
  const datasets = ref([])
  const loadingData = ref(false)

  // Analysis state
  const selectedOperation = ref('buffer')
  const analysisParams = ref({})
  const analysisResults = ref(null)
  const analysisLoading = ref(false)

  // Job management
  const activeJobs = ref([])
  const jobResults = ref({})
  const selectedJobId = ref(null)

  // UI state
  const notifications = ref([])
  const sidebarOpen = ref(true)
  const currentPage = ref('dashboard')

  // Server status
  const serverStatus = ref(null)
  const serverHealthy = computed(() => serverStatus.value?.status === 'healthy')

  // Actions
  async function login(username, password) {
    try {
      loadingData.value = true
      const result = await api.login(username, password)

      // Assign role based on username for demo purposes
      if (!result.role) {
        result.role = username === 'admin' ? 'admin' : 'analyst'
      }

      user.value = result
      token.value = result.token
      addNotification('Login successful', 'success')
      return true
    } catch (error) {
      addNotification(error.message, 'error')
      return false
    } finally {
      loadingData.value = false
    }
  }

  function logout() {
    api.logout()
    user.value = null
    token.value = ''
    currentDataset.value = null
    activeJobs.value = []
    addNotification('Logged out', 'success')
  }

  async function fetchServerStatus() {
    try {
      serverStatus.value = await api.getStatus()
    } catch (error) {
      addNotification(`Status check failed: ${error.message}`, 'error')
    }
  }

  async function ingestData(source, format, data) {
    try {
      loadingData.value = true
      const result = await api.ingestData(source, format, data)
      currentDataset.value = {
        source,
        format,
        rowsIngested: result.rows_ingested,
        columns: result.columns
      }
      addNotification(`Data ingested: ${result.rows_ingested} rows`, 'success')
      return result
    } catch (error) {
      addNotification(error.message, 'error')
      return null
    } finally {
      loadingData.value = false
    }
  }

  async function runAnalysis(operation, params) {
    try {
      analysisLoading.value = true
      selectedOperation.value = operation
      analysisParams.value = params

      const result = await api.analyze(operation, params)
      analysisResults.value = result

      addNotification(`Analysis completed: ${operation}`, 'success')
      return result
    } catch (error) {
      addNotification(error.message, 'error')
      return null
    } finally {
      analysisLoading.value = false
    }
  }

  async function submitAsyncJob(operation, params) {
    try {
      loadingData.value = true
      const jobData = await api.analyzeAsync(operation, params)

      const job = {
        id: jobData.job_id,
        operation: jobData.operation,
        status: jobData.status,
        progress: 0,
        createdAt: new Date(),
        results: null,
        error: null
      }

      activeJobs.value.push(job)
      selectedJobId.value = job.id

      addNotification(`Job submitted: ${jobData.job_id.substring(0, 8)}...`, 'success')

      // Start polling
      pollJobStatus(job.id)

      return job
    } catch (error) {
      addNotification(error.message, 'error')
      return null
    } finally {
      loadingData.value = false
    }
  }

  async function pollJobStatus(jobId) {
    const maxAttempts = 3600 // 1 hour with 1 second intervals
    let attempts = 0

    const poll = async () => {
      try {
        const jobStatus = await api.getJobStatus(jobId)
        const jobIndex = activeJobs.value.findIndex(j => j.id === jobId)

        if (jobIndex !== -1) {
          activeJobs.value[jobIndex] = {
            ...activeJobs.value[jobIndex],
            status: jobStatus.status,
            progress: jobStatus.progress,
            results: jobStatus.result,
            error: jobStatus.error
          }

          jobResults.value[jobId] = jobStatus

          if (jobStatus.status === 'completed') {
            addNotification(`Job completed: ${jobId.substring(0, 8)}...`, 'success')
            return
          } else if (jobStatus.status === 'failed') {
            addNotification(`Job failed: ${jobStatus.error}`, 'error')
            return
          }
        }

        if (attempts < maxAttempts) {
          attempts++
          setTimeout(poll, 1000)
        }
      } catch (error) {
        console.error('Job polling error:', error)
      }
    }

    poll()
  }

  function addNotification(message, type = 'info', duration = 5000) {
    const id = Date.now()
    const notification = { id, message, type }
    notifications.value.push(notification)

    if (duration > 0) {
      setTimeout(() => {
        notifications.value = notifications.value.filter(n => n.id !== id)
      }, duration)
    }

    return id
  }

  function removeNotification(id) {
    notifications.value = notifications.value.filter(n => n.id !== id)
  }

  function clearNotifications() {
    notifications.value = []
  }

  function setCurrentPage(page) {
    currentPage.value = page
  }

  function toggleSidebar() {
    sidebarOpen.value = !sidebarOpen.value
  }

  // Initialize app status
  fetchServerStatus()
  const statusInterval = setInterval(fetchServerStatus, 30000) // Every 30 seconds

  return {
    // State
    user,
    isAuthenticated,
    isAdmin,
    token,
    currentDataset,
    datasets,
    loadingData,
    selectedOperation,
    analysisParams,
    analysisResults,
    analysisLoading,
    activeJobs,
    jobResults,
    selectedJobId,
    notifications,
    sidebarOpen,
    currentPage,
    serverStatus,
    serverHealthy,

    // Actions
    login,
    logout,
    fetchServerStatus,
    ingestData,
    runAnalysis,
    submitAsyncJob,
    pollJobStatus,
    addNotification,
    removeNotification,
    clearNotifications,
    setCurrentPage,
    toggleSidebar
  }
})
