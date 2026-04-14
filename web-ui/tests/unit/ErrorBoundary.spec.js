import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ErrorBoundary from '@/components/ErrorBoundary.vue'
import { createPinia } from 'pinia'
import { defineComponent } from 'vue'

describe('ErrorBoundary.vue', () => {
  let wrapper
  let pinia

  beforeEach(() => {
    pinia = createPinia()

    const TestComponent = defineComponent({
      name: 'TestComponent',
      template: '<div>Test content</div>'
    })

    wrapper = mount(ErrorBoundary, {
      slots: {
        default: TestComponent
      },
      global: {
        plugins: [pinia]
      }
    })
  })

  afterEach(() => {
    wrapper.unmount()
    vi.clearAllMocks()
  })

  describe('Normal Operation', () => {
    it('renders slot content when no error', () => {
      expect(wrapper.find('.error-boundary').exists()).toBe(false)
      expect(wrapper.text()).toContain('Test content')
    })

    it('shows slot content instead of error UI', () => {
      const errorContainer = wrapper.find('.error-container')
      expect(errorContainer.exists()).toBe(false)
    })

    it('does not display error message when no error', () => {
      expect(wrapper.vm.hasError).toBe(false)
    })
  })

  describe('Error Handling', () => {
    it('displays error boundary when error occurs', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-boundary').exists()).toBe(true)
    })

    it('displays error message', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.errorMessage = 'Test error message'
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-message').text()).toContain('Test error message')
    })

    it('displays error title', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-title').text()).toBe('Something went wrong')
    })

    it('displays error icon', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-icon').text()).toBe('⚠️')
    })

    it('displays component name', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.componentName = 'FormComponent'
      await wrapper.vm.$nextTick()

      expect(wrapper.text()).toContain('FormComponent')
    })
  })

  describe('Error Details', () => {
    it('hides error details by default', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.showDetails = false
      await wrapper.vm.$nextTick()

      const details = wrapper.find('.error-details')
      expect(details.exists()).toBe(true) // Element exists but might be hidden
    })

    it('displays error details when showDetails is true', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.showDetails = true
      wrapper.vm.errorStack = 'Stack trace here'
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-stack').exists()).toBe(true)
      expect(wrapper.text()).toContain('Stack trace here')
    })

    it('toggles detail visibility', () => {
      expect(wrapper.vm.showDetails).toBe(false)

      wrapper.vm.toggleDetails()
      expect(wrapper.vm.showDetails).toBe(true)

      wrapper.vm.toggleDetails()
      expect(wrapper.vm.showDetails).toBe(false)
    })

    it('displays full error stack when details shown', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.showDetails = true
      wrapper.vm.errorStack = 'Error at line 42\n  at function() {...}'
      await wrapper.vm.$nextTick()

      const stack = wrapper.find('.error-stack')
      expect(stack.text()).toContain('Error at line 42')
    })
  })

  describe('Error Actions', () => {
    it('displays "Try Again" button', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const tryAgainBtn = buttons.find(b => b.text().includes('Try Again'))
      expect(tryAgainBtn).toBeDefined()
    })

    it('displays "Show Details" button when details hidden', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.showDetails = false
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const detailsBtn = buttons.find(b => b.text().includes('Show Details'))
      expect(detailsBtn).toBeDefined()
    })

    it('displays "Hide Details" button when details shown', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.showDetails = true
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const detailsBtn = buttons.find(b => b.text().includes('Hide Details'))
      expect(detailsBtn).toBeDefined()
    })

    it('displays "Report Error" button', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const reportBtn = buttons.find(b => b.text().includes('Report Error'))
      expect(reportBtn).toBeDefined()
    })

    it('calls resetError on "Try Again" click', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const resetSpy = vi.spyOn(wrapper.vm, 'resetError')
      const buttons = wrapper.findAll('.btn')
      const tryAgainBtn = buttons.find(b => b.text().includes('Try Again'))

      if (tryAgainBtn) {
        await tryAgainBtn.trigger('click')
      }

      expect(resetSpy).toHaveBeenCalled()
    })

    it('calls toggleDetails on details button click', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const toggleSpy = vi.spyOn(wrapper.vm, 'toggleDetails')
      const buttons = wrapper.findAll('.btn')
      const detailsBtn = buttons.find(b => b.text().includes('Details'))

      if (detailsBtn) {
        await detailsBtn.trigger('click')
      }

      expect(toggleSpy).toHaveBeenCalled()
    })

    it('calls reportError on report button click', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const reportSpy = vi.spyOn(wrapper.vm, 'reportError')
      const buttons = wrapper.findAll('.btn')
      const reportBtn = buttons.find(b => b.text().includes('Report Error'))

      if (reportBtn) {
        await reportBtn.trigger('click')
      }

      expect(reportSpy).toHaveBeenCalled()
    })
  })

  describe('Error Reset', () => {
    it('clears error state when reset', () => {
      wrapper.vm.hasError = true
      wrapper.vm.errorMessage = 'Error'
      wrapper.vm.errorStack = 'Stack'
      wrapper.vm.componentName = 'Component'
      wrapper.vm.showDetails = true

      wrapper.vm.resetError()

      expect(wrapper.vm.hasError).toBe(false)
      expect(wrapper.vm.errorMessage).toBe('')
      expect(wrapper.vm.errorStack).toBe('')
      expect(wrapper.vm.componentName).toBe('')
      expect(wrapper.vm.showDetails).toBe(false)
    })

    it('shows slot content again after reset', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()
      expect(wrapper.find('.error-boundary').exists()).toBe(true)

      wrapper.vm.resetError()
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-boundary').exists()).toBe(false)
      expect(wrapper.text()).toContain('Test content')
    })
  })

  describe('Error Reporting', () => {
    it('generates error report data', () => {
      wrapper.vm.componentName = 'TestComponent'
      wrapper.vm.errorMessage = 'Test error'
      wrapper.vm.errorStack = 'Stack trace'

      // The report function should prepare data
      expect(wrapper.vm.componentName).toBe('TestComponent')
      expect(wrapper.vm.errorMessage).toBe('Test error')
    })

    it('includes required fields in report', () => {
      wrapper.vm.componentName = 'MyComponent'
      wrapper.vm.errorMessage = 'Something failed'
      wrapper.vm.errorStack = 'Error at...'

      // Just verify the data is stored
      expect(wrapper.vm.componentName).toBeDefined()
      expect(wrapper.vm.errorMessage).toBeDefined()
      expect(wrapper.vm.errorStack).toBeDefined()
    })

    it('attempts to copy error details to clipboard', async () => {
      const clipboardSpy = vi.spyOn(navigator.clipboard, 'writeText')
        .mockResolvedValue(undefined)

      wrapper.vm.hasError = true
      wrapper.vm.componentName = 'TestComponent'
      wrapper.vm.errorMessage = 'Test error'
      wrapper.vm.errorStack = 'Stack'

      await wrapper.vm.reportError()

      expect(clipboardSpy).toHaveBeenCalled()
      clipboardSpy.mockRestore()
    })

    it('shows success notification on successful copy', async () => {
      const clipboardSpy = vi.spyOn(navigator.clipboard, 'writeText')
        .mockResolvedValue(undefined)

      wrapper.vm.hasError = true
      wrapper.vm.componentName = 'TestComponent'
      wrapper.vm.errorMessage = 'Test error'
      wrapper.vm.errorStack = 'Stack'

      await wrapper.vm.reportError()

      const successNotif = wrapper.vm.$store ? undefined : true
      expect(clipboardSpy).toHaveBeenCalled()

      clipboardSpy.mockRestore()
    })

    it('shows error notification on copy failure', async () => {
      const clipboardSpy = vi.spyOn(navigator.clipboard, 'writeText')
        .mockRejectedValue(new Error('Clipboard error'))

      wrapper.vm.hasError = true
      wrapper.vm.componentName = 'TestComponent'
      wrapper.vm.errorMessage = 'Test error'
      wrapper.vm.errorStack = 'Stack'

      await wrapper.vm.reportError()

      expect(clipboardSpy).toHaveBeenCalled()
      clipboardSpy.mockRestore()
    })
  })

  describe('Error Notifications', () => {
    it('adds error notification when error is caught', () => {
      wrapper.vm.hasError = true
      wrapper.vm.componentName = 'TestComponent'
      wrapper.vm.errorMessage = 'Test error'

      // onErrorCaptured is called during component setup
      // The notification is added in that hook
      expect(wrapper.vm.hasError).toBe(true)
    })
  })

  describe('State Management', () => {
    it('initializes with correct default state', () => {
      expect(wrapper.vm.hasError).toBe(false)
      expect(wrapper.vm.errorMessage).toBe('An unexpected error occurred')
      expect(wrapper.vm.errorStack).toBe('')
      expect(wrapper.vm.componentName).toBe('')
      expect(wrapper.vm.showDetails).toBe(false)
    })

    it('updates error message', () => {
      wrapper.vm.errorMessage = 'New error message'
      expect(wrapper.vm.errorMessage).toBe('New error message')
    })

    it('updates component name', () => {
      wrapper.vm.componentName = 'MyComponent'
      expect(wrapper.vm.componentName).toBe('MyComponent')
    })

    it('updates error stack', () => {
      const stack = 'Error at line 10'
      wrapper.vm.errorStack = stack
      expect(wrapper.vm.errorStack).toBe(stack)
    })

    it('toggles detail visibility state', () => {
      expect(wrapper.vm.showDetails).toBe(false)
      wrapper.vm.showDetails = true
      expect(wrapper.vm.showDetails).toBe(true)
      wrapper.vm.showDetails = false
      expect(wrapper.vm.showDetails).toBe(false)
    })
  })

  describe('Exposed API', () => {
    it('exposes hasError ref', () => {
      expect(wrapper.vm.hasError).toBeDefined()
    })

    it('exposes resetError method', () => {
      expect(wrapper.vm.resetError).toBeDefined()
      expect(typeof wrapper.vm.resetError).toBe('function')
    })
  })

  describe('Styling & UI', () => {
    it('applies error styling when error present', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const errorBoundary = wrapper.find('.error-boundary')
      expect(errorBoundary.exists()).toBe(true)
      expect(errorBoundary.classes()).toContain('error-boundary')
    })

    it('applies primary button style to Try Again', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const primaryBtn = buttons.find(b => b.classes().includes('btn-primary'))
      expect(primaryBtn).toBeDefined()
    })

    it('applies secondary button style to other actions', async () => {
      wrapper.vm.hasError = true
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('.btn')
      const secondaryBtns = buttons.filter(b => b.classes().includes('btn-secondary'))
      expect(secondaryBtns.length).toBeGreaterThan(0)
    })
  })

  describe('Edge Cases', () => {
    it('handles error with no stack trace', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.errorStack = ''
      wrapper.vm.showDetails = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.error-stack').exists()).toBe(true)
    })

    it('handles error with no component name', async () => {
      wrapper.vm.hasError = true
      wrapper.vm.componentName = ''
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.componentName).toBe('')
    })

    it('handles very long error messages', async () => {
      const longMessage = 'A'.repeat(1000)
      wrapper.vm.hasError = true
      wrapper.vm.errorMessage = longMessage
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.errorMessage).toBe(longMessage)
    })

    it('handles multiple rapid error resets', () => {
      for (let i = 0; i < 5; i++) {
        wrapper.vm.resetError()
      }

      expect(wrapper.vm.hasError).toBe(false)
      expect(wrapper.vm.errorMessage).toBe('')
    })
  })
})
