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
    this.client = axios.create({
      baseURL,
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
        return Promise.reject(error)
      }
    )
  }

  /**
   * Health check endpoint
   */
  async health() {
    try {
      const response = await this.client.get('/health')
      return response.data
    } catch (error) {
      throw new Error(`Health check failed: ${error.message}`)
    }
  }

  /**
   * Get server status
   */
  async getStatus() {
    try {
      const response = await this.client.get('/status')
      return response.data.data
    } catch (error) {
      throw new Error(`Failed to fetch status: ${error.message}`)
    }
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
      throw new Error(`Login failed: ${error.response?.data?.message || error.message}`)
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
   * Perform synchronous analysis
   */
  async analyze(operation, params) {
    try {
      const response = await this.client.post('/analyze', {
        operation,
        params
      })
      return response.data.data
    } catch (error) {
      throw new Error(`Analysis failed: ${error.response?.data?.message || error.message}`)
    }
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
      throw new Error(`Job submission failed: ${error.response?.data?.message || error.message}`)
    }
  }

  /**
   * Get job status and results
   */
  async getJobStatus(jobId) {
    try {
      const response = await this.client.get(`/jobs/${jobId}`)
      return response.data.data
    } catch (error) {
      throw new Error(`Failed to fetch job status: ${error.message}`)
    }
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
