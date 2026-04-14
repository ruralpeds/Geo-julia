import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import AnalysisPage from '@/views/AnalysisPage.vue'
import { createPinia } from 'pinia'

// Mock the operation config
vi.mock('@/config/operations', () => ({
  OPERATIONS: {
    buffer: {
      id: 'buffer',
      name: 'Buffer',
      category: 'spatial',
      description: 'Create buffer zones',
      icon: '⭕',
      params: [
        {
          name: 'distance',
          label: 'Distance',
          type: 'number',
          default: 100,
          min: 0,
          max: 10000
        }
      ]
    }
  },
  ML_OPERATIONS: {},
  OPERATION_CATEGORIES: {
    spatial: {
      name: 'Spatial',
      description: 'Spatial operations',
      icon: '🗺️'
    }
  }
}))

describe('AnalysisPage.vue', () => {
  let wrapper
  const pinia = createPinia()

  beforeEach(() => {
    wrapper = mount(AnalysisPage, {
      global: {
        plugins: [pinia],
        stubs: {
          FormField: true
        }
      }
    })
  })

  it('renders analysis page', () => {
    expect(wrapper.find('h1').text()).toContain('Spatial Analysis')
  })

  it('displays operation categories', () => {
    const buttons = wrapper.findAll('button')
    expect(buttons.length).toBeGreaterThan(0)
  })

  it('shows warning when no dataset loaded', () => {
    const alert = wrapper.find('.alert-warning')
    expect(alert.exists()).toBe(true)
  })

  it('can select an operation category', async () => {
    const categoryButtons = wrapper.findAll('button')
    if (categoryButtons.length > 0) {
      await categoryButtons[0].trigger('click')
      // Selected state should be updated
    }
  })

  it('initialization state is correct', () => {
    expect(wrapper.vm.selectedCategory).toBe('spatial')
    expect(wrapper.vm.selectedOperation).toBeNull()
    expect(wrapper.vm.executionMode).toBe('sync')
  })

  it('has correct form validation state', () => {
    expect(wrapper.vm.formValid).toBe(false)
  })

  it('can reset form', async () => {
    wrapper.vm.analysisParams = { test: 'value' }
    await wrapper.vm.resetForm()
    expect(wrapper.vm.analysisParams).toEqual({})
  })
})
