<template>
  <div v-if="hasError" class="error-boundary">
    <!-- Error UI -->
    <div class="error-container">
      <div class="error-icon">⚠️</div>
      <div class="error-content">
        <h2 class="error-title">Something went wrong</h2>
        <p class="error-message">{{ errorMessage }}</p>

        <div v-if="showDetails" class="error-details">
          <p class="error-component">
            <span class="label">Component:</span>
            <span class="value">{{ componentName }}</span>
          </p>
          <pre class="error-stack">{{ errorStack }}</pre>
        </div>

        <div class="error-actions">
          <button @click="resetError" class="btn btn-primary">
            Try Again
          </button>
          <button @click="toggleDetails" class="btn btn-secondary">
            {{ showDetails ? 'Hide Details' : 'Show Details' }}
          </button>
          <button @click="reportError" class="btn btn-secondary">
            📧 Report Error
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Normal slot content -->
  <template v-else>
    <slot />
  </template>
</template>

<script setup>
import { ref, onErrorCaptured, getCurrentInstance } from 'vue'
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()
const instance = getCurrentInstance()

const hasError = ref(false)
const errorMessage = ref('An unexpected error occurred')
const errorStack = ref('')
const componentName = ref('')
const showDetails = ref(false)

onErrorCaptured((error, componentInstance, info) => {
  hasError.value = true
  errorMessage.value = error.message || 'An unexpected error occurred'
  errorStack.value = error.stack || 'No stack trace available'
  componentName.value = componentInstance?.$options.name || 'Unknown Component'

  // Log to console for debugging
  console.error('Error Boundary Caught:', {
    error,
    component: componentName.value,
    info
  })

  // Add notification
  appStore.addNotification(
    `Error in ${componentName.value}: ${errorMessage.value}`,
    'error',
    0 // Don't auto-dismiss error notifications
  )

  // Return false to prevent propagation to parent error handlers
  return false
})

function resetError() {
  hasError.value = false
  errorMessage.value = ''
  errorStack.value = ''
  componentName.value = ''
  showDetails.value = false
}

function toggleDetails() {
  showDetails.value = !showDetails.value
}

function reportError() {
  const reportData = {
    timestamp: new Date().toISOString(),
    component: componentName.value,
    error: errorMessage.value,
    stack: errorStack.value,
    userAgent: navigator.userAgent,
    url: window.location.href
  }

  // Copy to clipboard
  const text = JSON.stringify(reportData, null, 2)
  navigator.clipboard.writeText(text).then(() => {
    appStore.addNotification('Error details copied to clipboard. Please email to support.', 'success')
  }).catch(() => {
    appStore.addNotification('Failed to copy error details', 'error')
  })
}

defineExpose({
  hasError,
  resetError
})
</script>

<style scoped>
.error-boundary {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 400px;
  padding: 2rem;
  background: linear-gradient(135deg, #fee5e5 0%, #ffd6d6 100%);
}

.error-container {
  background: white;
  border: 2px solid #f87171;
  border-radius: 0.75rem;
  padding: 2rem;
  max-width: 600px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
}

.error-icon {
  font-size: 3rem;
  margin-bottom: 1rem;
}

.error-content {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.error-title {
  font-size: 1.5rem;
  font-weight: bold;
  color: #991b1b;
  margin: 0;
}

.error-message {
  color: #7f1d1d;
  margin: 0;
  line-height: 1.5;
}

.error-details {
  background-color: #fef2f2;
  border: 1px solid #fed7d7;
  border-radius: 0.5rem;
  padding: 1rem;
  display: none;
}

.error-details.show {
  display: block;
}

.error-component {
  display: flex;
  gap: 0.5rem;
  margin: 0 0 0.5rem 0;
  font-size: 0.875rem;
}

.error-component .label {
  font-weight: 600;
  color: #991b1b;
}

.error-component .value {
  color: #7f1d1d;
  font-family: 'Courier New', monospace;
}

.error-stack {
  background-color: white;
  border: 1px solid #fed7d7;
  border-radius: 0.375rem;
  padding: 0.75rem;
  font-size: 0.75rem;
  max-height: 200px;
  overflow-y: auto;
  color: #7f1d1d;
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
}

.error-actions {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.btn {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 0.375rem;
  cursor: pointer;
  font-size: 0.875rem;
  font-weight: 500;
  transition: all 0.2s;
}

.btn-primary {
  background-color: #dc2626;
  color: white;
}

.btn-primary:hover {
  background-color: #991b1b;
}

.btn-secondary {
  background-color: #fed7d7;
  color: #991b1b;
}

.btn-secondary:hover {
  background-color: #fecaca;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
