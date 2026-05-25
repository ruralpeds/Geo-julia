/**
 * API Client for GeoSpatial Analysis Engine
 *
 * Handles all communication with the backend REST API,
 * including authentication, request formatting, and error handling.
 */

import axios from 'axios'

class APIClient {
  constructor(baseURL = 'http://localhost:8080') {
    this.baseURL = baseURL
    this.timeout = 30000 // 30 seconds default timeout
    this.retryAttempts = 3
    this.retryDelay = 1000 // Start with 1 second
    this.maxRetryDelay = 10000 // Cap at 10 seconds

    this.client = axios.create({
      baseURL,
      timeout: this.timeout,
      headers: {
        'Content-Type': 'application/json'
      }
    })

    // Add request interceptor for authentication
    this.client.interceptors.request.use((config) => {
      const token = localStorage.getItem('api_token')
      if (token) {
        config.headers.Authorization = `Bearer ${token}`
      }
      // Add request timeout
      config.timeout = this.timeout
      return config
    })

    // Add response interceptor for error handling
    this.client.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 401) {
          // Clear token and redirect to login
          localStorage.removeItem('api_token')
          window.location.href = '/login'
        }

        // Enhance error message
        const originalError = error.response?.data?.message || error.message
        error.userMessage = this.getUserMessage(error)

        return Promise.reject(error)
      }
    )
  }

  /**
   * Get user-friendly error message
   */
  getUserMessage(error) {
    if (error.code === 'ECONNABORTED') {
      return 'Request timeout - server is not responding. Please try again.'
    }
    if (error.code === 'ECONNREFUSED') {
      return 'Cannot connect to server. Please check if the API is running.'
    }
    if (error.response?.status === 400) {
      return error.response?.data?.message || 'Invalid request parameters'
    }
    if (error.response?.status === 401) {
      return 'Your session has expired. Please log in again.'
    }
    if (error.response?.status === 403) {
      return 'You do not have permission to perform this action'
    }
    if (error.response?.status === 404) {
      return 'Resource not found'
    }
    if (error.response?.status === 429) {
      return 'Too many requests. Please wait a moment and try again.'
    }
    if (error.response?.status >= 500) {
      return 'Server error. Please try again later.'
    }
    return error.message || 'An error occurred. Please try again.'
  }

  /**
   * Retry logic with exponential backoff
   */
  async retryRequest(fn, attempt = 0) {
    try {
      return await fn()
    } catch (error) {
      // Don't retry for 4xx errors (except timeout)
      const shouldRetry =
        attempt < this.retryAttempts &&
        (error.code === 'ECONNABORTED' || // Timeout
          error.code === 'ECONNREFUSED' || // Connection refused
          error.response?.status >= 500) // Server errors

      if (shouldRetry) {
        const delay = Math.min(
          this.retryDelay * Math.pow(2, attempt),
          this.maxRetryDelay
        )
        console.warn(
          `Request failed (attempt ${attempt + 1}/${this.retryAttempts}), retrying in ${delay}ms...`,
          error.message
        )
        await new Promise(resolve => setTimeout(resolve, delay))
        return this.retryRequest(fn, attempt + 1)
      }

      throw error
    }
  }

  /**
   * Health check endpoint
   */
  async health() {
    return this.retryRequest(async () => {
      try {
        const response = await this.client.get('/health')
        return response.data
      } catch (error) {
        throw new Error(`Health check failed: ${error.userMessage}`)
      }
    })
  }

  /**
   * Get server status
   */
  async getStatus() {
    return this.retryRequest(async () => {
      try {
        const response = await this.client.get('/status')
        return response.data.data
      } catch (error) {
        throw new Error(`Failed to fetch status: ${error.userMessage}`)
      }
    })
  }

  /**
   * User authentication
   */
  async login(username, password) {
    try {
      const response = await this.client.post('/auth/login', {
        username,
        password
      })
      const token = response.data.data.token
      localStorage.setItem('api_token', token)
      return response.data.data
    } catch (error) {
      throw new Error(`Login failed: ${error.response?.data?.message || error.userMessage}`)
    }
  }

  /**
   * Logout (client-side only)
   */
  logout() {
    localStorage.removeItem('api_token')
  }

  /**
   * Ingest data
   */
  async ingestData(source, format, data) {
    try {
      const response = await this.client.post('/ingest', {
        source,
        format,
        data
      })
      return response.data.data
    } catch (error) {
      throw new Error(`Data ingestion failed: ${error.response?.data?.message || error.message}`)
    }
  }

  /**
   * Perform synchronous analysis (with retry)
   */
  async analyze(operation, params) {
    return this.retryRequest(async () => {
      try {
        const response = await this.client.post('/analyze', {
          operation,
          params
        })
        return response.data.data
      } catch (error) {
        throw new Error(`Analysis failed: ${error.response?.data?.message || error.userMessage}`)
      }
    })
  }

  /**
   * Submit asynchronous analysis job
   */
  async analyzeAsync(operation, params) {
    try {
      const response = await this.client.post('/analyze/async', {
        operation,
        params
      })
      return response.data.data
    } catch (error) {
      throw new Error(
        `Job submission failed: ${error.response?.data?.message || error.userMessage}`
      )
    }
  }

  /**
   * Get job status and results (with retry for reliability)
   */
  async getJobStatus(jobId) {
    return this.retryRequest(async () => {
      try {
        const response = await this.client.get(`/jobs/${jobId}`)
        return response.data.data
      } catch (error) {
        throw new Error(`Failed to fetch job status: ${error.userMessage}`)
      }
    })
  }

  /**
   * Poll job until completion
   */
  async pollJob(jobId, intervalMs = 1000, maxAttempts = 3600) {
    let attempts = 0
    while (attempts < maxAttempts) {
      try {
        const job = await this.getJobStatus(jobId)
        if (job.status === 'completed' || job.status === 'failed') {
          return job
        }
      } catch (error) {
        console.error('Polling error:', error)
      }
      await new Promise(resolve => setTimeout(resolve, intervalMs))
      attempts++
    }
    throw new Error(`Job polling timeout after ${maxAttempts} attempts`)
  }

  /**
   * Generate predictions
   */
  async predict(modelId, features) {
    try {
      const response = await this.client.post('/predict', {
        model_id: modelId,
        features
      })
      return response.data.data
    } catch (error) {
      throw new Error(`Prediction failed: ${error.response?.data?.message || error.message}`)
    }
  }

  /**
   * Generate visualization
   */
  async visualize(type, variable, colormap = 'YlOrRd', title = '') {
    try {
      const response = await this.client.post('/visualize', {
        type,
        variable,
        colormap,
        title
      })
      return response.data.data
    } catch (error) {
      throw new Error(`Visualization failed: ${error.response?.data?.message || error.message}`)
    }
  }

  /**
   * Export data
   */
  async export(format, variable, filter = {}) {
    try {
      const response = await this.client.post('/export', {
        format,
        variable,
        filter
      })
      return response.data.data
    } catch (error) {
      throw new Error(`Export failed: ${error.response?.data?.message || error.message}`)
    }
  }

  /**
   * Download exported file
   */
  downloadFile(url, filename) {
    const link = document.createElement('a')
    link.href = this.baseURL + url
    link.download = filename
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  /**
   * Set authentication token
   */
  setToken(token) {
    localStorage.setItem('api_token', token)
  }

  /**
   * Get authentication token
   */
  getToken() {
    return localStorage.getItem('api_token')
  }

  /**
   * Check if authenticated
   */
  isAuthenticated() {
    return !!this.getToken()
  }

  /**
   * Handle WebSocket connection for real-time updates
   */
  connectWebSocket(jobId, onUpdate, onError) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/ws/jobs/${jobId}`

    try {
      const ws = new WebSocket(wsUrl)

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data)
        onUpdate(data)
      }

      ws.onerror = (error) => {
        onError(error)
      }

      return ws
    } catch (error) {
      onError(error)
      return null
    }
  }
}

// Export singleton instance
export default new APIClient()
