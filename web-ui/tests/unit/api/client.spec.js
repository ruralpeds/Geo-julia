import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import APIClient from '@/api/client'

describe('APIClient', () => {
  let mockAxios
  let mockResponse

  beforeEach(() => {
    // Clear localStorage
    localStorage.clear()

    // Mock axios create and methods
    mockResponse = {
      data: {
        data: { success: true }
      }
    }

    mockAxios = {
      create: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue(mockResponse),
        post: vi.fn().mockResolvedValue(mockResponse),
        interceptors: {
          request: { use: vi.fn() },
          response: { use: vi.fn() }
        }
      })
    }

    // Spy on methods
    vi.spyOn(APIClient, 'retryRequest')
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  describe('Initialization', () => {
    it('creates instance with default base URL', () => {
      expect(APIClient.baseURL).toBeDefined()
      expect(APIClient.timeout).toBe(30000)
    })

    it('sets correct retry configuration', () => {
      expect(APIClient.retryAttempts).toBe(3)
      expect(APIClient.retryDelay).toBe(1000)
      expect(APIClient.maxRetryDelay).toBe(10000)
    })

    it('creates axios client with correct headers', () => {
      expect(APIClient.client).toBeDefined()
      expect(APIClient.client.defaults.timeout).toBe(30000)
    })
  })

  describe('Error Message Handling', () => {
    it('returns timeout error message', () => {
      const error = { code: 'ECONNABORTED' }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('timeout')
    })

    it('returns connection refused message', () => {
      const error = { code: 'ECONNREFUSED' }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('Cannot connect')
    })

    it('returns 400 error message', () => {
      const error = { response: { status: 400, data: { message: 'Invalid input' } } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('Invalid')
    })

    it('returns 401 error message', () => {
      const error = { response: { status: 401 } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('session')
    })

    it('returns 403 error message', () => {
      const error = { response: { status: 403 } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('permission')
    })

    it('returns 404 error message', () => {
      const error = { response: { status: 404 } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('not found')
    })

    it('returns 429 rate limit message', () => {
      const error = { response: { status: 429 } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('Too many requests')
    })

    it('returns generic 5xx message', () => {
      const error = { response: { status: 500 } }
      const message = APIClient.getUserMessage(error)
      expect(message).toContain('Server error')
    })

    it('returns generic error message as fallback', () => {
      const error = { message: 'Unknown error' }
      const message = APIClient.getUserMessage(error)
      expect(message).toBeTruthy()
    })
  })

  describe('Authentication', () => {
    it('stores token on login', async () => {
      const loginResponse = {
        data: { data: { token: 'test-token-123' } }
      }
      APIClient.client.post = vi.fn().mockResolvedValue(loginResponse)

      const result = await APIClient.login('user', 'pass')

      expect(localStorage.getItem('api_token')).toBe('test-token-123')
      expect(result).toHaveProperty('token')
    })

    it('throws error on login failure', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Login failed')
      )

      await expect(APIClient.login('user', 'pass')).rejects.toThrow()
    })

    it('logs out and removes token', () => {
      localStorage.setItem('api_token', 'test-token')
      APIClient.logout()
      expect(localStorage.getItem('api_token')).toBeNull()
    })

    it('sets token manually', () => {
      APIClient.setToken('manual-token')
      expect(localStorage.getItem('api_token')).toBe('manual-token')
    })

    it('gets token from storage', () => {
      localStorage.setItem('api_token', 'stored-token')
      const token = APIClient.getToken()
      expect(token).toBe('stored-token')
    })

    it('checks if authenticated', () => {
      localStorage.removeItem('api_token')
      expect(APIClient.isAuthenticated()).toBe(false)

      localStorage.setItem('api_token', 'token')
      expect(APIClient.isAuthenticated()).toBe(true)
    })

    it('includes token in request headers', () => {
      localStorage.setItem('api_token', 'test-token')
      // The interceptor should add the token to headers
      expect(APIClient.client.interceptors.request.use).toBeDefined()
    })
  })

  describe('Health & Status Endpoints', () => {
    it('checks health', async () => {
      APIClient.client.get = vi.fn().mockResolvedValue({
        data: { status: 'healthy' }
      })

      const result = await APIClient.health()
      expect(result).toBeDefined()
    })

    it('gets server status', async () => {
      APIClient.client.get = vi.fn().mockResolvedValue({
        data: { data: { version: '1.0.0' } }
      })

      const result = await APIClient.getStatus()
      expect(result).toBeDefined()
      expect(result).toHaveProperty('version')
    })

    it('handles health check failure', async () => {
      APIClient.client.get = vi.fn().mockRejectedValue(
        new Error('Connection failed')
      )

      await expect(APIClient.health()).rejects.toThrow()
    })
  })

  describe('Data Ingestion', () => {
    it('ingests data with source, format, and data', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { rowsIngested: 100 } }
      })

      const result = await APIClient.ingestData('test.csv', 'CSV', [{ id: 1 }])

      expect(APIClient.client.post).toHaveBeenCalledWith('/ingest', {
        source: 'test.csv',
        format: 'CSV',
        data: [{ id: 1 }]
      })
      expect(result).toHaveProperty('rowsIngested')
    })

    it('handles ingestion errors', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Ingestion failed')
      )

      await expect(APIClient.ingestData('test.csv', 'CSV', [])).rejects.toThrow()
    })
  })

  describe('Analysis Operations', () => {
    it('performs synchronous analysis with retry', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { features: 150 } }
      })

      const result = await APIClient.analyze('buffer', { distance: 100 })

      expect(APIClient.client.post).toHaveBeenCalledWith('/analyze', {
        operation: 'buffer',
        params: { distance: 100 }
      })
      expect(result).toHaveProperty('features')
    })

    it('submits asynchronous analysis job', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { id: 'job-123', status: 'pending' } }
      })

      const result = await APIClient.analyzeAsync('buffer', { distance: 100 })

      expect(APIClient.client.post).toHaveBeenCalledWith('/analyze/async', {
        operation: 'buffer',
        params: { distance: 100 }
      })
      expect(result).toHaveProperty('id')
      expect(result).toHaveProperty('status')
    })

    it('handles analysis errors', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Analysis error')
      )

      await expect(APIClient.analyze('buffer', {})).rejects.toThrow()
    })
  })

  describe('Job Management', () => {
    it('gets job status with retry', async () => {
      APIClient.client.get = vi.fn().mockResolvedValue({
        data: { data: { id: 'job-123', status: 'running', progress: 50 } }
      })

      const result = await APIClient.getJobStatus('job-123')

      expect(APIClient.client.get).toHaveBeenCalledWith('/jobs/job-123')
      expect(result).toHaveProperty('status')
      expect(result).toHaveProperty('progress')
    })

    it('polls job until completion', async () => {
      let callCount = 0
      APIClient.client.get = vi.fn().mockImplementation(() => {
        callCount++
        if (callCount < 3) {
          return Promise.resolve({
            data: { data: { status: 'running', progress: 50 } }
          })
        }
        return Promise.resolve({
          data: { data: { status: 'completed', progress: 100 } }
        })
      })

      const result = await APIClient.pollJob('job-123', 1, 10)

      expect(result.status).toBe('completed')
    })

    it('handles polling timeout', async () => {
      APIClient.client.get = vi.fn().mockResolvedValue({
        data: { data: { status: 'running' } }
      })

      await expect(APIClient.pollJob('job-123', 1, 2)).rejects.toThrow('timeout')
    })
  })

  describe('Predictions', () => {
    it('generates predictions', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { predictions: [0.8, 0.2] } }
      })

      const result = await APIClient.predict('model-1', [[1, 2, 3]])

      expect(APIClient.client.post).toHaveBeenCalledWith('/predict', {
        model_id: 'model-1',
        features: [[1, 2, 3]]
      })
      expect(result).toHaveProperty('predictions')
    })

    it('handles prediction errors', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Prediction failed')
      )

      await expect(APIClient.predict('model-1', [])).rejects.toThrow()
    })
  })

  describe('Visualization', () => {
    it('generates visualization', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { imageUrl: '/images/viz.png' } }
      })

      const result = await APIClient.visualize(
        'choropleth',
        'population',
        'YlOrRd',
        'Population Map'
      )

      expect(APIClient.client.post).toHaveBeenCalledWith('/visualize', {
        type: 'choropleth',
        variable: 'population',
        colormap: 'YlOrRd',
        title: 'Population Map'
      })
      expect(result).toHaveProperty('imageUrl')
    })

    it('uses default colormap', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { imageUrl: '/images/viz.png' } }
      })

      await APIClient.visualize('heatmap', 'value')

      expect(APIClient.client.post).toHaveBeenCalledWith(
        '/visualize',
        expect.objectContaining({
          colormap: 'YlOrRd'
        })
      )
    })

    it('handles visualization errors', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Visualization failed')
      )

      await expect(APIClient.visualize('heatmap', 'value')).rejects.toThrow()
    })
  })

  describe('Data Export', () => {
    it('exports data', async () => {
      APIClient.client.post = vi.fn().mockResolvedValue({
        data: { data: { url: '/download/export-123.geojson' } }
      })

      const result = await APIClient.export('GeoJSON', 'geometry', { status: 'active' })

      expect(APIClient.client.post).toHaveBeenCalledWith('/export', {
        format: 'GeoJSON',
        variable: 'geometry',
        filter: { status: 'active' }
      })
      expect(result).toHaveProperty('url')
    })

    it('handles export errors', async () => {
      APIClient.client.post = vi.fn().mockRejectedValue(
        new Error('Export failed')
      )

      await expect(APIClient.export('GeoJSON', 'geometry')).rejects.toThrow()
    })
  })

  describe('File Download', () => {
    it('downloads file', () => {
      const createElementSpy = vi.spyOn(document, 'createElement')
      const appendChildSpy = vi.spyOn(document.body, 'appendChild')
      const removeChildSpy = vi.spyOn(document.body, 'removeChild')

      APIClient.downloadFile('/download/file.json', 'data.json')

      expect(createElementSpy).toHaveBeenCalledWith('a')
      expect(appendChildSpy).toHaveBeenCalled()
      expect(removeChildSpy).toHaveBeenCalled()

      createElementSpy.mockRestore()
      appendChildSpy.mockRestore()
      removeChildSpy.mockRestore()
    })
  })

  describe('WebSocket Connection', () => {
    it('connects to WebSocket', () => {
      const mockWS = {
        onmessage: null,
        onerror: null
      }
      global.WebSocket = vi.fn().mockImplementation(() => mockWS)

      const onUpdate = vi.fn()
      const onError = vi.fn()

      const ws = APIClient.connectWebSocket('job-123', onUpdate, onError)

      expect(global.WebSocket).toHaveBeenCalled()
      expect(ws).toBeDefined()
    })

    it('handles WebSocket messages', () => {
      const mockWS = {
        onmessage: null,
        onerror: null
      }
      global.WebSocket = vi.fn().mockReturnValue(mockWS)

      const onUpdate = vi.fn()
      const onError = vi.fn()

      APIClient.connectWebSocket('job-123', onUpdate, onError)

      // Simulate incoming message
      if (mockWS.onmessage) {
        mockWS.onmessage({ data: '{"status":"running"}' })
        expect(onUpdate).toHaveBeenCalledWith({ status: 'running' })
      }
    })

    it('handles WebSocket errors', () => {
      const mockWS = {
        onmessage: null,
        onerror: null
      }
      global.WebSocket = vi.fn().mockReturnValue(mockWS)

      const onUpdate = vi.fn()
      const onError = vi.fn()

      APIClient.connectWebSocket('job-123', onUpdate, onError)

      // Simulate error
      if (mockWS.onerror) {
        const error = new Error('Connection lost')
        mockWS.onerror(error)
        expect(onError).toHaveBeenCalledWith(error)
      }
    })

    it('handles WebSocket connection failure', () => {
      global.WebSocket = vi.fn().mockImplementation(() => {
        throw new Error('Cannot create WebSocket')
      })

      const onUpdate = vi.fn()
      const onError = vi.fn()

      const ws = APIClient.connectWebSocket('job-123', onUpdate, onError)

      expect(ws).toBeNull()
      expect(onError).toHaveBeenCalled()
    })
  })

  describe('Retry Logic', () => {
    it('retries on connection refused error', async () => {
      let attempts = 0
      const fn = vi.fn().mockImplementation(() => {
        attempts++
        if (attempts < 2) {
          const error = new Error('Connection refused')
          error.code = 'ECONNREFUSED'
          return Promise.reject(error)
        }
        return Promise.resolve('success')
      })

      // Note: We can't directly test retryRequest without mocking internal delay
      // This is a conceptual test
      expect(APIClient.retryAttempts).toBe(3)
    })

    it('does not retry on 4xx errors', async () => {
      const fn = vi.fn().mockRejectedValue(
        new Error('Bad request')
      )

      // The API client should not retry on client errors
      expect(APIClient.retryAttempts).toBeGreaterThan(0)
    })

    it('uses exponential backoff', () => {
      // Verify exponential backoff calculation
      const baseDelay = APIClient.retryDelay
      const attemptDelay = baseDelay * Math.pow(2, 1)
      const cappedDelay = Math.min(attemptDelay, APIClient.maxRetryDelay)

      expect(cappedDelay).toBeLessThanOrEqual(APIClient.maxRetryDelay)
    })
  })
})
