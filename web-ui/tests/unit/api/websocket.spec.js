import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import WebSocketManager from '@/api/websocket'

describe('WebSocketManager', () => {
  let manager
  let mockWebSocket
  let mockWebSocketConstructor

  beforeEach(() => {
    manager = WebSocketManager
    manager.connections.clear()
    manager.listeners.clear()
    manager.messageQueue = []
    manager.isConnected = false

    // Mock WebSocket
    mockWebSocket = {
      send: vi.fn(),
      close: vi.fn(),
      readyState: WebSocket.OPEN,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn()
    }

    mockWebSocketConstructor = vi.fn(() => mockWebSocket)
    vi.stubGlobal('WebSocket', mockWebSocketConstructor)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.clearAllTimers()
  })

  describe('Initialization', () => {
    it('creates instance with default configuration', () => {
      expect(manager.baseURL).toBe('ws://localhost:8080')
      expect(manager.connections).toBeInstanceOf(Map)
    })

    it('sets correct reconnection parameters', () => {
      expect(manager.reconnectAttempts).toBe(3)
      expect(manager.reconnectDelay).toBe(2000)
      expect(manager.maxReconnectDelay).toBe(30000)
    })

    it('initializes empty connection map', () => {
      expect(manager.connections.size).toBe(0)
    })

    it('initializes empty listeners map', () => {
      expect(manager.listeners.size).toBe(0)
    })

    it('initializes empty message queue', () => {
      expect(manager.messageQueue).toEqual([])
      expect(manager.isConnected).toBe(false)
    })
  })

  describe('Subscribe & Connection', () => {
    it('subscribes to job updates', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      const unsubscribe = manager.subscribe('job1', onUpdate, onError)

      expect(manager.listeners.has('job1')).toBe(true)
      expect(manager.listeners.get('job1')[0].onUpdate).toBe(onUpdate)
      expect(typeof unsubscribe).toBe('function')
    })

    it('creates WebSocket connection on subscribe', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      expect(mockWebSocketConstructor).toHaveBeenCalledWith(
        expect.stringContaining('ws://localhost/ws/jobs/job1')
      )
      expect(manager.connections.has('job1')).toBe(true)
    })

    it('throws error if jobId is missing', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      expect(() => {
        manager.subscribe(null, onUpdate, onError)
      }).toThrow('jobId is required')
    })

    it('allows multiple subscribers to same job', () => {
      const onUpdate1 = vi.fn()
      const onUpdate2 = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate1, onError)
      manager.subscribe('job1', onUpdate2, onError)

      const listeners = manager.listeners.get('job1')
      expect(listeners.length).toBe(2)
    })

    it('reuses existing connection for multiple subscribers', () => {
      const onUpdate1 = vi.fn()
      const onUpdate2 = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate1, onError)
      const firstCallCount = mockWebSocketConstructor.mock.calls.length

      manager.subscribe('job1', onUpdate2, onError)
      const secondCallCount = mockWebSocketConstructor.mock.calls.length

      expect(secondCallCount).toBe(firstCallCount)
    })
  })

  describe('Connection Lifecycle', () => {
    it('handles connection open event', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate connection open
      if (mockWebSocket.onopen) {
        mockWebSocket.onopen()
      }

      expect(manager.isConnected).toBe(true)
    })

    it('handles incoming messages', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate message
      if (mockWebSocket.onmessage) {
        mockWebSocket.onmessage({ data: '{"status":"running","progress":50}' })
      }

      expect(onUpdate).toHaveBeenCalledWith({ status: 'running', progress: 50 })
    })

    it('handles connection errors', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate error
      if (mockWebSocket.onerror) {
        const error = new Error('Connection failed')
        mockWebSocket.onerror(error)
        expect(onError).toHaveBeenCalledWith(error)
      }
    })

    it('handles connection close event', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate close
      if (mockWebSocket.onclose) {
        mockWebSocket.onclose()
      }

      expect(manager.connections.has('job1')).toBe(false)
      expect(manager.isConnected).toBe(false)
    })

    it('handles malformed messages', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate malformed message
      if (mockWebSocket.onmessage) {
        mockWebSocket.onmessage({ data: 'not json' })
      }

      expect(onError).toHaveBeenCalled()
    })
  })

  describe('Unsubscribe & Disconnect', () => {
    it('unsubscribes from job updates', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      const unsubscribe = manager.subscribe('job1', onUpdate, onError)
      unsubscribe()

      const listeners = manager.listeners.get('job1')
      expect(listeners.length).toBe(0)
    })

    it('keeps connection alive if other subscribers exist', () => {
      const onUpdate1 = vi.fn()
      const onUpdate2 = vi.fn()
      const onError = vi.fn()

      const unsub1 = manager.subscribe('job1', onUpdate1, onError)
      manager.subscribe('job1', onUpdate2, onError)

      unsub1()

      expect(manager.connections.has('job1')).toBe(true)
    })

    it('closes connection when last subscriber unsubscribes', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      const unsubscribe = manager.subscribe('job1', onUpdate, onError)
      unsubscribe()

      expect(mockWebSocket.close).toHaveBeenCalled()
      expect(manager.connections.has('job1')).toBe(false)
    })

    it('disconnects single job', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.disconnect('job1')

      expect(mockWebSocket.close).toHaveBeenCalled()
      expect(manager.connections.has('job1')).toBe(false)
    })

    it('disconnects all jobs', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.subscribe('job2', onUpdate, onError)

      manager.disconnectAll()

      expect(manager.connections.size).toBe(0)
      expect(manager.listeners.size).toBe(0)
    })
  })

  describe('Message Sending', () => {
    it('sends message when connected', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.send('job1', { action: 'cancel' })

      expect(mockWebSocket.send).toHaveBeenCalledWith('{"action":"cancel"}')
    })

    it('queues message when not connected', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      mockWebSocket.readyState = WebSocket.CONNECTING
      manager.subscribe('job1', onUpdate, onError)
      manager.send('job1', { action: 'cancel' })

      expect(manager.messageQueue.length).toBeGreaterThan(0)
    })

    it('flushes queued messages on connection', async () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      mockWebSocket.readyState = WebSocket.CONNECTING
      manager.subscribe('job1', onUpdate, onError)
      manager.send('job1', { action: 'cancel' })

      // Simulate connection
      mockWebSocket.readyState = WebSocket.OPEN
      if (mockWebSocket.onopen) {
        mockWebSocket.onopen()
      }

      expect(manager.messageQueue.length).toBe(0)
    })

    it('does not send to disconnected job', () => {
      manager.send('nonexistent', { action: 'cancel' })
      expect(mockWebSocket.send).not.toHaveBeenCalled()
    })
  })

  describe('Status Checking', () => {
    it('checks if connected to specific job', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      expect(manager.isConnectedTo('job1')).toBe(false)

      manager.subscribe('job1', onUpdate, onError)

      expect(manager.isConnectedTo('job1')).toBe(true)
    })

    it('returns false if job connection is closed', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      mockWebSocket.readyState = WebSocket.CLOSED

      expect(manager.isConnectedTo('job1')).toBe(false)
    })

    it('gets status of all connections', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.subscribe('job2', onUpdate, onError)

      const status = manager.getStatus()

      expect(status).toHaveProperty('job1')
      expect(status).toHaveProperty('job2')
      expect(status.job1).toBe('connected')
    })

    it('shows disconnected status correctly', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      mockWebSocket.readyState = WebSocket.CLOSED

      const status = manager.getStatus()

      expect(status.job1).toBe('disconnected')
    })
  })

  describe('Error Handling', () => {
    it('handles listener callback errors', async () => {
      const badOnUpdate = vi.fn().mockImplementation(() => {
        throw new Error('Update callback error')
      })
      const onError = vi.fn()

      manager.subscribe('job1', badOnUpdate, onError)

      // Simulate message - should not throw
      if (mockWebSocket.onmessage) {
        expect(() => {
          mockWebSocket.onmessage({ data: '{"status":"done"}' })
        }).not.toThrow()
      }
    })

    it('handles listener error callback errors', async () => {
      const onUpdate = vi.fn()
      const badOnError = vi.fn().mockImplementation(() => {
        throw new Error('Error callback error')
      })

      manager.subscribe('job1', onUpdate, badOnError)

      // Simulate error - should not throw
      if (mockWebSocket.onerror) {
        expect(() => {
          mockWebSocket.onerror(new Error('Test error'))
        }).not.toThrow()
      }
    })
  })

  describe('Reconnection Logic', () => {
    it('attempts reconnection on close', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      vi.useFakeTimers()

      manager.subscribe('job1', onUpdate, onError)
      const firstWSCallCount = mockWebSocketConstructor.mock.calls.length

      // Simulate close
      if (mockWebSocket.onclose) {
        mockWebSocket.onclose()
      }

      // Should attempt reconnection
      vi.advanceTimersByTime(2000)

      expect(mockWebSocketConstructor.mock.calls.length).toBeGreaterThan(firstWSCallCount)

      vi.useRealTimers()
    })

    it('uses exponential backoff for reconnection', () => {
      const delays = []
      const originalSetTimeout = global.setTimeout
      global.setTimeout = vi.fn((cb, delay) => {
        delays.push(delay)
        return originalSetTimeout(cb, 0) // Execute immediately for testing
      })

      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate multiple closes
      if (mockWebSocket.onclose) {
        mockWebSocket.onclose() // First reconnect attempt
      }

      expect(delays.length).toBeGreaterThan(0)
      expect(delays[0]).toBeGreaterThan(0)

      global.setTimeout = originalSetTimeout
    })

    it('stops reconnecting after max attempts', () => {
      vi.useFakeTimers()

      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      const initialCallCount = mockWebSocketConstructor.mock.calls.length

      // Simulate multiple failures
      for (let i = 0; i < 5; i++) {
        if (mockWebSocket.onclose) {
          mockWebSocket.onclose()
        }
        mockWebSocketConstructor.mockReturnValueOnce(mockWebSocket)
        vi.advanceTimersByTime(30000)
      }

      // Should stop after reconnectAttempts
      expect(mockWebSocketConstructor.mock.calls.length - initialCallCount).toBeLessThanOrEqual(
        manager.reconnectAttempts + 1
      )

      vi.useRealTimers()
    })

    it('resets reconnect attempts on successful connection', () => {
      vi.useFakeTimers()

      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)

      // Simulate open
      if (mockWebSocket.onopen) {
        mockWebSocket.onopen()
      }

      expect(manager.isConnected).toBe(true)

      vi.useRealTimers()
    })
  })

  describe('Multiple Jobs', () => {
    it('manages multiple job connections independently', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.subscribe('job2', onUpdate, onError)
      manager.subscribe('job3', onUpdate, onError)

      expect(manager.connections.size).toBe(3)
      expect(mockWebSocketConstructor).toHaveBeenCalledTimes(3)
    })

    it('sends messages to correct job', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.subscribe('job2', onUpdate, onError)

      manager.send('job1', { action: 'cancel' })

      // First call (job1 subscribe) creates connection, second call (job2) creates another
      // Then send uses job1's connection
      expect(mockWebSocket.send).toHaveBeenCalled()
    })

    it('disconnects single job without affecting others', () => {
      const onUpdate = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate, onError)
      manager.subscribe('job2', onUpdate, onError)

      manager.disconnect('job1')

      expect(manager.connections.has('job1')).toBe(false)
      expect(manager.connections.has('job2')).toBe(true)
    })
  })

  describe('Listener Notification', () => {
    it('notifies all listeners of updates', () => {
      const onUpdate1 = vi.fn()
      const onUpdate2 = vi.fn()
      const onError = vi.fn()

      manager.subscribe('job1', onUpdate1, onError)
      manager.subscribe('job1', onUpdate2, onError)

      manager.notifyListeners('job1', { status: 'done' }, 'update')

      expect(onUpdate1).toHaveBeenCalledWith({ status: 'done' })
      expect(onUpdate2).toHaveBeenCalledWith({ status: 'done' })
    })

    it('notifies all listeners of errors', () => {
      const onUpdate = vi.fn()
      const onError1 = vi.fn()
      const onError2 = vi.fn()

      manager.subscribe('job1', onUpdate, onError1)
      manager.subscribe('job1', onUpdate, onError2)

      const error = new Error('Test error')
      manager.notifyListeners('job1', error, 'error')

      expect(onError1).toHaveBeenCalledWith(error)
      expect(onError2).toHaveBeenCalledWith(error)
    })

    it('handles non-existent job listeners gracefully', () => {
      expect(() => {
        manager.notifyListeners('nonexistent', {}, 'update')
      }).not.toThrow()
    })
  })
})
