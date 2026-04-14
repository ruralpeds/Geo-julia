/**
 * WebSocket Manager for Real-time Job Updates
 *
 * Handles WebSocket connections for real-time progress tracking,
 * reducing server load compared to constant HTTP polling.
 */

class WebSocketManager {
  constructor(baseURL = 'ws://localhost:8080') {
    this.baseURL = baseURL
    this.connections = new Map() // Map of jobId -> WebSocket
    this.listeners = new Map() // Map of jobId -> callback functions
    this.reconnectAttempts = 3
    this.reconnectDelay = 2000 // Start with 2 seconds
    this.maxReconnectDelay = 30000 // Max 30 seconds
    this.messageQueue = [] // Queue messages while reconnecting
    this.isConnected = false
  }

  /**
   * Subscribe to job updates
   * @param {string} jobId - Job ID to monitor
   * @param {Function} onUpdate - Callback for updates: (data) => {}
   * @param {Function} onError - Callback for errors: (error) => {}
   * @returns {Function} Unsubscribe function
   */
  subscribe(jobId, onUpdate, onError) {
    if (!jobId) {
      throw new Error('jobId is required')
    }

    // Store listener
    if (!this.listeners.has(jobId)) {
      this.listeners.set(jobId, [])
    }
    this.listeners.get(jobId).push({ onUpdate, onError })

    // Connect if not already
    if (!this.connections.has(jobId)) {
      this.connect(jobId, onError)
    }

    // Return unsubscribe function
    return () => {
      this.unsubscribe(jobId, onUpdate)
    }
  }

  /**
   * Connect to job updates via WebSocket
   */
  connect(jobId, onError, attempt = 0) {
    try {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      const wsUrl = `${protocol}//${window.location.host}/ws/jobs/${jobId}`

      const ws = new WebSocket(wsUrl)

      // Connection opened
      ws.onopen = () => {
        console.log(`✅ WebSocket connected for job ${jobId}`)
        this.isConnected = true
        attempt = 0 // Reset reconnect attempts

        // Process any queued messages
        while (this.messageQueue.length > 0) {
          const msg = this.messageQueue.shift()
          ws.send(msg)
        }
      }

      // Message received
      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          this.notifyListeners(jobId, data, 'update')
        } catch (err) {
          console.error('Failed to parse WebSocket message:', err)
          this.notifyListeners(jobId, err, 'error')
        }
      }

      // Connection error
      ws.onerror = (error) => {
        console.error(`❌ WebSocket error for job ${jobId}:`, error)
        this.notifyListeners(jobId, error, 'error')
      }

      // Connection closed
      ws.onclose = () => {
        console.log(`🔌 WebSocket closed for job ${jobId}`)
        this.connections.delete(jobId)
        this.isConnected = false

        // Attempt reconnection with exponential backoff
        if (attempt < this.reconnectAttempts) {
          const delay = Math.min(
            this.reconnectDelay * Math.pow(2, attempt),
            this.maxReconnectDelay
          )
          console.log(`🔄 Reconnecting in ${delay}ms... (attempt ${attempt + 1}/${this.reconnectAttempts})`)

          setTimeout(() => {
            this.connect(jobId, onError, attempt + 1)
          }, delay)
        }
      }

      this.connections.set(jobId, ws)
    } catch (err) {
      console.error(`Failed to create WebSocket for job ${jobId}:`, err)
      this.notifyListeners(jobId, err, 'error')
    }
  }

  /**
   * Send message to job WebSocket
   */
  send(jobId, message) {
    const ws = this.connections.get(jobId)

    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message))
    } else {
      // Queue message for later
      this.messageQueue.push(JSON.stringify(message))
    }
  }

  /**
   * Unsubscribe from job updates
   */
  unsubscribe(jobId, onUpdate) {
    const listeners = this.listeners.get(jobId)
    if (listeners) {
      const index = listeners.findIndex((l) => l.onUpdate === onUpdate)
      if (index !== -1) {
        listeners.splice(index, 1)
      }

      // Close connection if no more listeners
      if (listeners.length === 0) {
        this.disconnect(jobId)
        this.listeners.delete(jobId)
      }
    }
  }

  /**
   * Disconnect from job updates
   */
  disconnect(jobId) {
    const ws = this.connections.get(jobId)
    if (ws) {
      ws.close(1000, 'Client closing connection')
      this.connections.delete(jobId)
    }
  }

  /**
   * Disconnect from all jobs
   */
  disconnectAll() {
    for (const [jobId, ws] of this.connections) {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close(1000, 'Client closing all connections')
      }
    }
    this.connections.clear()
    this.listeners.clear()
  }

  /**
   * Notify all listeners of an update
   */
  notifyListeners(jobId, data, type = 'update') {
    const listeners = this.listeners.get(jobId)
    if (listeners) {
      listeners.forEach((listener) => {
        try {
          if (type === 'update') {
            listener.onUpdate(data)
          } else if (type === 'error') {
            listener.onError(data)
          }
        } catch (err) {
          console.error('Error in listener callback:', err)
        }
      })
    }
  }

  /**
   * Check if connected to specific job
   */
  isConnectedTo(jobId) {
    const ws = this.connections.get(jobId)
    return ws && ws.readyState === WebSocket.OPEN
  }

  /**
   * Get connection status for all jobs
   */
  getStatus() {
    const status = {}
    for (const [jobId, ws] of this.connections) {
      status[jobId] = ws.readyState === WebSocket.OPEN ? 'connected' : 'disconnected'
    }
    return status
  }
}

// Export singleton
export default new WebSocketManager()
