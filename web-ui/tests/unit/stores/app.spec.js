import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useAppStore } from '@/stores/app'

// Mock API client
vi.mock('@/api/client', () => ({
  default: {
    login: vi.fn(),
    logout: vi.fn(),
    getStatus: vi.fn(),
    ingestData: vi.fn(),
    analyze: vi.fn(),
    analyzeAsync: vi.fn(),
    getJobStatus: vi.fn()
  }
}))

// Mock WebSocket Manager
vi.mock('@/api/websocket', () => ({
  default: {
    subscribe: vi.fn(),
    unsubscribe: vi.fn(),
    disconnectAll: vi.fn()
  }
}))

import api from '@/api/client'
import wsManager from '@/api/websocket'

describe('App Store (Pinia)', () => {
  let store

  beforeEach(() => {
    setActivePinia(createPinia())
    store = useAppStore()
    vi.clearAllMocks()
    localStorage.clear()
  })

  afterEach(() => {
    vi.clearAllTimers()
  })

  describe('Initial State', () => {
    it('initializes with correct default values', () => {
      expect(store.user).toBeNull()
      expect(store.token).toBe('')
      expect(store.currentDataset).toBeNull()
      expect(store.datasets).toEqual([])
      expect(store.loadingData).toBe(false)
      expect(store.analysisResults).toBeNull()
      expect(store.analysisLoading).toBe(false)
      expect(store.activeJobs).toEqual([])
      expect(store.selectedJobId).toBeNull()
      expect(store.notifications).toEqual([])
      expect(store.currentPage).toBe('dashboard')
    })

    it('initializes with sidebar open', () => {
      expect(store.sidebarOpen).toBe(true)
    })

    it('loads token from localStorage if available', () => {
      localStorage.setItem('api_token', 'test-token')
      const newStore = useAppStore()
      expect(newStore.token).toBe('test-token')
    })

    it('fetches server status on initialization', () => {
      expect(api.getStatus).toHaveBeenCalled()
    })
  })

  describe('Computed Properties', () => {
    it('isAuthenticated is false when user is null', () => {
      expect(store.isAuthenticated).toBe(false)
    })

    it('isAuthenticated is true when user exists', async () => {
      store.user = { username: 'test', role: 'analyst' }
      expect(store.isAuthenticated).toBe(true)
    })

    it('isAdmin returns true for admin role', async () => {
      store.user = { username: 'admin', role: 'admin' }
      expect(store.isAdmin).toBe(true)
    })

    it('isAdmin returns false for non-admin role', () => {
      store.user = { username: 'analyst', role: 'analyst' }
      expect(store.isAdmin).toBe(false)
    })

    it('serverHealthy is true when status is healthy', () => {
      store.serverStatus = { status: 'healthy', version: '1.0.0' }
      expect(store.serverHealthy).toBe(true)
    })

    it('serverHealthy is false when status is not healthy', () => {
      store.serverStatus = { status: 'degraded' }
      expect(store.serverHealthy).toBe(false)
    })
  })

  describe('Authentication', () => {
    it('logs in successfully', async () => {
      api.login.mockResolvedValue({
        token: 'test-token',
        username: 'testuser'
      })

      const result = await store.login('testuser', 'password')

      expect(result).toBe(true)
      expect(store.user).toBeDefined()
      expect(store.token).toBe('test-token')
      expect(store.loadingData).toBe(false)
    })

    it('assigns analyst role for non-admin users', async () => {
      api.login.mockResolvedValue({
        token: 'test-token',
        username: 'analyst'
      })

      await store.login('analyst', 'password')

      expect(store.user.role).toBe('analyst')
    })

    it('assigns admin role for admin user', async () => {
      api.login.mockResolvedValue({
        token: 'test-token',
        username: 'admin'
      })

      await store.login('admin', 'password')

      expect(store.user.role).toBe('admin')
    })

    it('handles login failure', async () => {
      api.login.mockRejectedValue(new Error('Invalid credentials'))

      const result = await store.login('user', 'wrong')

      expect(result).toBe(false)
      expect(store.user).toBeNull()
      expect(store.loadingData).toBe(false)
    })

    it('adds success notification on login', async () => {
      api.login.mockResolvedValue({
        token: 'test-token',
        username: 'testuser'
      })

      await store.login('testuser', 'password')

      const successNotif = store.notifications.find(n => n.type === 'success')
      expect(successNotif).toBeDefined()
      expect(successNotif.message).toContain('Login successful')
    })

    it('adds error notification on login failure', async () => {
      api.login.mockRejectedValue(new Error('Login failed'))

      await store.login('user', 'wrong')

      const errorNotif = store.notifications.find(n => n.type === 'error')
      expect(errorNotif).toBeDefined()
    })

    it('logs out successfully', () => {
      store.user = { username: 'test', role: 'analyst' }
      store.token = 'test-token'
      store.currentDataset = { source: 'test.csv' }
      store.activeJobs = [{ id: 'job1', status: 'running' }]

      store.logout()

      expect(store.user).toBeNull()
      expect(store.token).toBe('')
      expect(store.currentDataset).toBeNull()
      expect(store.activeJobs).toEqual([])
      expect(api.logout).toHaveBeenCalled()
    })
  })

  describe('Server Status', () => {
    it('fetches server status', async () => {
      api.getStatus.mockResolvedValue({
        status: 'healthy',
        version: '1.0.0'
      })

      await store.fetchServerStatus()

      expect(api.getStatus).toHaveBeenCalled()
      expect(store.serverStatus).toBeDefined()
      expect(store.serverStatus.status).toBe('healthy')
    })

    it('handles server status fetch error', async () => {
      api.getStatus.mockRejectedValue(new Error('Connection failed'))

      await store.fetchServerStatus()

      const errorNotif = store.notifications.find(n => n.type === 'error')
      expect(errorNotif).toBeDefined()
    })
  })

  describe('Data Ingestion', () => {
    it('ingests data successfully', async () => {
      api.ingestData.mockResolvedValue({
        rows_ingested: 100,
        columns: ['id', 'name', 'value']
      })

      const result = await store.ingestData('test.csv', 'CSV', [])

      expect(store.currentDataset).toBeDefined()
      expect(store.currentDataset.source).toBe('test.csv')
      expect(store.currentDataset.format).toBe('CSV')
      expect(store.currentDataset.rowsIngested).toBe(100)
      expect(store.currentDataset.columns).toEqual(['id', 'name', 'value'])
      expect(store.loadingData).toBe(false)
    })

    it('adds success notification on data ingestion', async () => {
      api.ingestData.mockResolvedValue({
        rows_ingested: 100,
        columns: ['id']
      })

      await store.ingestData('test.csv', 'CSV', [])

      const successNotif = store.notifications.find(n => n.type === 'success')
      expect(successNotif).toBeDefined()
      expect(successNotif.message).toContain('Data ingested')
    })

    it('handles data ingestion error', async () => {
      api.ingestData.mockRejectedValue(new Error('Invalid format'))

      const result = await store.ingestData('test.csv', 'CSV', [])

      expect(result).toBeNull()
      expect(store.currentDataset).toBeNull()
      expect(store.loadingData).toBe(false)
    })
  })

  describe('Analysis Operations', () => {
    it('runs synchronous analysis successfully', async () => {
      api.analyze.mockResolvedValue({
        features: 150,
        geometry_type: 'Polygon'
      })

      const result = await store.runAnalysis('buffer', { distance: 100 })

      expect(store.selectedOperation).toBe('buffer')
      expect(store.analysisParams).toEqual({ distance: 100 })
      expect(store.analysisResults).toBeDefined()
      expect(store.analysisResults.features).toBe(150)
      expect(store.analysisLoading).toBe(false)
    })

    it('adds success notification on analysis completion', async () => {
      api.analyze.mockResolvedValue({ features: 150 })

      await store.runAnalysis('buffer', { distance: 100 })

      const successNotif = store.notifications.find(n => n.type === 'success')
      expect(successNotif).toBeDefined()
      expect(successNotif.message).toContain('Analysis completed')
    })

    it('handles analysis error', async () => {
      api.analyze.mockRejectedValue(new Error('Analysis failed'))

      const result = await store.runAnalysis('buffer', {})

      expect(result).toBeNull()
      expect(store.analysisResults).toBeNull()
      expect(store.analysisLoading).toBe(false)
    })
  })

  describe('Async Job Submission', () => {
    it('submits async job successfully', async () => {
      api.analyzeAsync.mockResolvedValue({
        job_id: 'job-123',
        operation: 'buffer',
        status: 'pending'
      })

      const result = await store.submitAsyncJob('buffer', { distance: 100 })

      expect(result).toBeDefined()
      expect(result.id).toBe('job-123')
      expect(result.operation).toBe('buffer')
      expect(result.status).toBe('pending')
      expect(store.activeJobs.length).toBe(1)
      expect(store.selectedJobId).toBe('job-123')
    })

    it('adds success notification on job submission', async () => {
      api.analyzeAsync.mockResolvedValue({
        job_id: 'job-123',
        operation: 'buffer',
        status: 'pending'
      })

      await store.submitAsyncJob('buffer', {})

      const successNotif = store.notifications.find(n => n.type === 'success')
      expect(successNotif).toBeDefined()
      expect(successNotif.message).toContain('Job submitted')
    })

    it('starts polling on job submission', async () => {
      api.analyzeAsync.mockResolvedValue({
        job_id: 'job-123',
        operation: 'buffer',
        status: 'pending'
      })

      await store.submitAsyncJob('buffer', {})

      expect(wsManager.subscribe).toHaveBeenCalledWith(
        'job-123',
        expect.any(Function),
        expect.any(Function)
      )
    })

    it('handles async job submission error', async () => {
      api.analyzeAsync.mockRejectedValue(new Error('Submission failed'))

      const result = await store.submitAsyncJob('buffer', {})

      expect(result).toBeNull()
      expect(store.activeJobs.length).toBe(0)
      expect(store.loadingData).toBe(false)
    })
  })

  describe('Job Status Updates', () => {
    it('updates job status', () => {
      store.activeJobs = [
        {
          id: 'job-123',
          operation: 'buffer',
          status: 'pending',
          progress: 0
        }
      ]

      store.updateJobStatus('job-123', {
        status: 'running',
        progress: 50
      })

      const job = store.activeJobs[0]
      expect(job.status).toBe('running')
      expect(job.progress).toBe(50)
    })

    it('stores job results', () => {
      store.activeJobs = [
        {
          id: 'job-123',
          operation: 'buffer',
          status: 'pending',
          progress: 0
        }
      ]

      const results = { features: 150 }
      store.updateJobStatus('job-123', {
        status: 'running',
        progress: 50,
        result: results
      })

      expect(store.jobResults['job-123']).toBeDefined()
    })

    it('adds notification when job completes', () => {
      store.activeJobs = [
        {
          id: 'job-123',
          operation: 'buffer',
          status: 'running',
          progress: 100
        }
      ]

      store.updateJobStatus('job-123', {
        status: 'completed',
        progress: 100
      })

      const successNotif = store.notifications.find(n => n.type === 'success')
      expect(successNotif).toBeDefined()
      expect(successNotif.message).toContain('Job completed')
      expect(wsManager.unsubscribe).toHaveBeenCalled()
    })

    it('adds error notification when job fails', () => {
      store.activeJobs = [
        {
          id: 'job-123',
          operation: 'buffer',
          status: 'running',
          progress: 25
        }
      ]

      store.updateJobStatus('job-123', {
        status: 'failed',
        error: 'Invalid parameters'
      })

      const errorNotif = store.notifications.find(n => n.type === 'error')
      expect(errorNotif).toBeDefined()
      expect(errorNotif.message).toContain('Job failed')
    })

    it('ignores updates for non-existent jobs', () => {
      store.activeJobs = []

      expect(() => {
        store.updateJobStatus('nonexistent', { status: 'running' })
      }).not.toThrow()

      expect(store.activeJobs.length).toBe(0)
    })
  })

  describe('Job Polling', () => {
    it('subscribes to WebSocket updates on poll', async () => {
      wsManager.subscribe.mockImplementation(() => {})

      store.pollJobStatus('job-123')

      expect(wsManager.subscribe).toHaveBeenCalledWith(
        'job-123',
        expect.any(Function),
        expect.any(Function)
      )
    })

    it('falls back to HTTP polling on WebSocket error', async () => {
      let errorCallback

      wsManager.subscribe.mockImplementation((jobId, onUpdate, onError) => {
        errorCallback = onError
      })

      api.getJobStatus.mockResolvedValue({
        status: 'running',
        progress: 50
      })

      store.pollJobStatus('job-123')

      // Simulate WebSocket error
      expect(errorCallback).toBeDefined()
    })

    it('handles polling exception with HTTP fallback', () => {
      wsManager.subscribe.mockImplementation(() => {
        throw new Error('WebSocket unavailable')
      })

      expect(() => {
        store.pollJobStatus('job-123')
      }).not.toThrow()
    })
  })

  describe('Notifications', () => {
    it('adds notification', () => {
      const id = store.addNotification('Test message', 'info')

      expect(id).toBeDefined()
      expect(store.notifications.length).toBe(1)
      expect(store.notifications[0].message).toBe('Test message')
      expect(store.notifications[0].type).toBe('info')
    })

    it('removes notification by id', () => {
      const id = store.addNotification('Test', 'info', 0)
      store.removeNotification(id)

      expect(store.notifications.length).toBe(0)
    })

    it('auto-removes notification after duration', async () => {
      vi.useFakeTimers()

      store.addNotification('Test', 'info', 3000)
      expect(store.notifications.length).toBe(1)

      vi.advanceTimersByTime(3000)
      await Promise.resolve()

      expect(store.notifications.length).toBe(0)

      vi.useRealTimers()
    })

    it('does not auto-remove notification with zero duration', () => {
      vi.useFakeTimers()

      store.addNotification('Persistent', 'info', 0)
      vi.advanceTimersByTime(5000)

      expect(store.notifications.length).toBe(1)

      vi.useRealTimers()
    })

    it('clears all notifications', () => {
      store.addNotification('Test 1', 'info', 0)
      store.addNotification('Test 2', 'info', 0)
      store.addNotification('Test 3', 'info', 0)

      store.clearNotifications()

      expect(store.notifications.length).toBe(0)
    })
  })

  describe('UI Navigation', () => {
    it('sets current page', () => {
      store.setCurrentPage('analysis')
      expect(store.currentPage).toBe('analysis')

      store.setCurrentPage('jobs')
      expect(store.currentPage).toBe('jobs')
    })

    it('toggles sidebar', () => {
      expect(store.sidebarOpen).toBe(true)

      store.toggleSidebar()
      expect(store.sidebarOpen).toBe(false)

      store.toggleSidebar()
      expect(store.sidebarOpen).toBe(true)
    })
  })

  describe('WebSocket Cleanup', () => {
    it('disconnects all WebSockets on cleanup', () => {
      store.cleanupWebSocket()

      expect(wsManager.disconnectAll).toHaveBeenCalled()
    })
  })

  describe('Complex Workflows', () => {
    it('completes full analysis workflow', async () => {
      // Login
      api.login.mockResolvedValue({ token: 'token', username: 'user' })
      await store.login('user', 'pass')

      // Ingest data
      api.ingestData.mockResolvedValue({
        rows_ingested: 100,
        columns: ['id', 'value']
      })
      await store.ingestData('test.csv', 'CSV', [])

      // Run analysis
      api.analyze.mockResolvedValue({ features: 150 })
      await store.runAnalysis('buffer', { distance: 100 })

      expect(store.isAuthenticated).toBe(true)
      expect(store.currentDataset).toBeDefined()
      expect(store.analysisResults).toBeDefined()
      expect(store.notifications.length).toBeGreaterThan(0)
    })

    it('completes async job workflow', async () => {
      // Setup
      api.analyzeAsync.mockResolvedValue({
        job_id: 'job-123',
        operation: 'buffer',
        status: 'pending'
      })
      wsManager.subscribe.mockImplementation(() => {})

      // Submit async job
      const job = await store.submitAsyncJob('buffer', { distance: 100 })
      expect(job).toBeDefined()

      // Simulate job status update
      store.updateJobStatus('job-123', {
        status: 'completed',
        progress: 100,
        result: { features: 150 }
      })

      expect(store.activeJobs[0].status).toBe('completed')
      expect(store.jobResults['job-123']).toBeDefined()
    })
  })
})
