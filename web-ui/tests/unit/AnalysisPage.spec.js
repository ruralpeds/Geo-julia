import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import AnalysisPage from '@/views/AnalysisPage.vue'
import { createPinia } from 'pinia'
import { useAppStore } from '@/stores/app'

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
    },
    intersect: {
      id: 'intersect',
      name: 'Intersect',
      category: 'spatial',
      description: 'Find intersections',
      icon: '✂️',
      params: [
        {
          name: 'overlay_layer',
          label: 'Overlay Layer',
          type: 'select',
          default: ''
        }
      ]
    }
  },
  ML_OPERATIONS: {
    train: {
      id: 'train',
      name: 'Train Model',
      category: 'ml',
      description: 'Train ML model',
      icon: '🤖',
      params: [
        {
          name: 'model_type',
          label: 'Model Type',
          type: 'select',
          default: 'linear',
          options: ['linear', 'random_forest']
        }
      ]
    }
  },
  OPERATION_CATEGORIES: {
    spatial: {
      name: 'Spatial',
      description: 'Spatial operations',
      icon: '🗺️'
    },
    ml: {
      name: 'Machine Learning',
      description: 'ML operations',
      icon: '🤖'
    }
  }
}))

// Mock FormField component to have more control
vi.mock('@/components/FormField.vue', () => ({
  default: {
    name: 'FormField',
    props: ['field', 'modelValue'],
    emits: ['update:modelValue', 'validate'],
    template: '<div class="form-field-mock"></div>'
  }
}))

describe('AnalysisPage.vue', () => {
  let wrapper
  let pinia
  let appStore

  beforeEach(() => {
    pinia = createPinia()
    wrapper = mount(AnalysisPage, {
      global: {
        plugins: [pinia]
      }
    })
    appStore = useAppStore()
  })

  afterEach(() => {
    wrapper.unmount()
  })

  describe('Page Initialization', () => {
    it('renders analysis page header', () => {
      expect(wrapper.find('h1').text()).toContain('Spatial Analysis')
    })

    it('displays page description', () => {
      expect(wrapper.text()).toContain('Configure and execute spatial analysis operations')
    })

    it('initialization state is correct', () => {
      expect(wrapper.vm.selectedCategory).toBe('spatial')
      expect(wrapper.vm.selectedOperation).toBeNull()
      expect(wrapper.vm.executionMode).toBe('sync')
      expect(wrapper.vm.formValid).toBe(false)
      expect(wrapper.vm.analysisParams).toEqual({})
    })
  })

  describe('Dataset Warning', () => {
    it('shows warning when no dataset loaded', () => {
      const alert = wrapper.find('.alert-warning')
      expect(alert.exists()).toBe(true)
      expect(alert.text()).toContain('No Dataset Loaded')
    })

    it('shows ingest data instruction', () => {
      const warning = wrapper.find('.alert-warning')
      expect(warning.text()).toContain('📊 Ingest Data')
    })

    it('hides main content when no dataset', () => {
      const mainContent = wrapper.find('.lg\\:col-span-2')
      expect(mainContent.exists()).toBe(false)
    })

    it('hides content when dataset is loaded', async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      await wrapper.vm.$nextTick()

      const alert = wrapper.find('.alert-warning')
      expect(alert.exists()).toBe(false)
    })
  })

  describe('Operation Categories', () => {
    beforeEach(async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      await wrapper.vm.$nextTick()
    })

    it('displays operation categories', () => {
      const categorySection = wrapper.find('h2')
      expect(categorySection.text()).toContain('Select Operation Category')
    })

    it('can select operation category', async () => {
      const categoryButtons = wrapper.findAll('button')
      const spatialButton = categoryButtons.find(btn => btn.text().includes('Spatial'))

      expect(spatialButton).toBeDefined()
      expect(wrapper.vm.selectedCategory).toBe('spatial')
    })

    it('highlights selected category', async () => {
      wrapper.vm.selectedCategory = 'spatial'
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('button')
      const selectedBtn = buttons.find(btn => btn.classes().includes('border-blue-500'))
      expect(selectedBtn).toBeDefined()
    })

    it('filters operations by selected category', async () => {
      wrapper.vm.selectedCategory = 'spatial'
      await wrapper.vm.$nextTick()

      const operations = wrapper.vm.operationsByCategory
      expect(operations.length).toBeGreaterThan(0)
      expect(operations.every(op => op.category === 'spatial')).toBe(true)
    })

    it('shows different operations for ml category', async () => {
      wrapper.vm.selectedCategory = 'ml'
      await wrapper.vm.$nextTick()

      const operations = wrapper.vm.operationsByCategory
      expect(operations.length).toBeGreaterThan(0)
      expect(operations.some(op => op.id === 'train')).toBe(true)
    })
  })

  describe('Operation Selection', () => {
    beforeEach(async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      wrapper.vm.selectedCategory = 'spatial'
      await wrapper.vm.$nextTick()
    })

    it('can select an operation', async () => {
      const buffer = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        icon: '⭕',
        params: []
      }
      wrapper.vm.selectOperation(buffer)

      expect(wrapper.vm.selectedOperation).toEqual(buffer)
    })

    it('initializes form params with operation defaults', async () => {
      const operation = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        params: [
          { name: 'distance', label: 'Distance', default: 100 }
        ]
      }
      wrapper.vm.selectOperation(operation)

      expect(wrapper.vm.analysisParams.distance).toBe(100)
    })

    it('clears previous params on operation change', async () => {
      wrapper.vm.analysisParams = { oldParam: 'value' }
      const operation = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        params: [{ name: 'distance', label: 'Distance', default: 100 }]
      }

      wrapper.vm.selectOperation(operation)

      expect(wrapper.vm.analysisParams.oldParam).toBeUndefined()
      expect(wrapper.vm.analysisParams.distance).toBe(100)
    })

    it('resets form validation on operation change', async () => {
      wrapper.vm.formValid = true
      const operation = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        params: []
      }

      wrapper.vm.selectOperation(operation)

      expect(wrapper.vm.formValid).toBe(false)
    })
  })

  describe('Form Management', () => {
    beforeEach(async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      const operation = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        params: [
          { name: 'distance', label: 'Distance', default: 100 }
        ]
      }
      wrapper.vm.selectOperation(operation)
      await wrapper.vm.$nextTick()
    })

    it('displays form section when operation selected', async () => {
      const formHeading = wrapper.text()
      expect(formHeading).toContain('Parameters')
    })

    it('can reset form to defaults', async () => {
      wrapper.vm.analysisParams.distance = 500
      wrapper.vm.resetForm()

      expect(wrapper.vm.analysisParams.distance).toBe(100)
    })

    it('validates form', async () => {
      wrapper.vm.validateForm()
      expect(wrapper.vm.formValid).toBe(true)
    })

    it('shows execution mode options', async () => {
      const radioLabels = wrapper.findAll('label')
      const syncLabel = radioLabels.find(l => l.text().includes('Synchronous'))
      const asyncLabel = radioLabels.find(l => l.text().includes('Asynchronous'))

      expect(syncLabel).toBeDefined()
      expect(asyncLabel).toBeDefined()
    })
  })

  describe('Execution Modes', () => {
    beforeEach(async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      const operation = {
        id: 'buffer',
        name: 'Buffer',
        category: 'spatial',
        params: [{ name: 'distance', label: 'Distance', default: 100 }]
      }
      wrapper.vm.selectOperation(operation)
      wrapper.vm.formValid = true
      await wrapper.vm.$nextTick()
    })

    it('has sync mode selected by default', () => {
      expect(wrapper.vm.executionMode).toBe('sync')
    })

    it('can switch to async mode', async () => {
      wrapper.vm.executionMode = 'async'
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.executionMode).toBe('async')
    })

    it('button text changes based on execution mode', async () => {
      wrapper.vm.executionMode = 'sync'
      await wrapper.vm.$nextTick()
      let button = wrapper.find('button[type="submit"]')
      expect(button.text()).toContain('Run Analysis')

      wrapper.vm.executionMode = 'async'
      await wrapper.vm.$nextTick()
      button = wrapper.find('button[type="submit"]')
      expect(button.text()).toContain('Submit as Job')
    })
  })

  describe('Results Display', () => {
    beforeEach(async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      await wrapper.vm.$nextTick()
    })

    it('hides results when none available', () => {
      const resultsCard = wrapper.find('.bg-green-50')
      expect(resultsCard.exists()).toBe(false)
    })

    it('displays results when available', async () => {
      appStore.analysisResults = {
        features: 150,
        geometry_type: 'Polygon'
      }
      await wrapper.vm.$nextTick()

      const resultsCard = wrapper.find('.bg-green-50')
      expect(resultsCard.exists()).toBe(true)
      expect(resultsCard.text()).toContain('Analysis Completed')
    })

    it('shows download button for results', async () => {
      appStore.analysisResults = {
        features: 150,
        geometry_type: 'Polygon'
      }
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('button')
      const downloadBtn = buttons.find(b => b.text().includes('Download Results'))
      expect(downloadBtn || wrapper.text().includes('Download Results')).toBeTruthy()
    })
  })

  describe('Dataset Information', () => {
    it('displays dataset info when available', async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      await wrapper.vm.$nextTick()

      expect(wrapper.text()).toContain('test.geojson')
      expect(wrapper.text()).toContain('GeoJSON')
      expect(wrapper.text()).toContain('100')
    })
  })

  describe('Recent Jobs', () => {
    it('displays recent jobs when available', async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: ['id', 'name', 'value']
      }
      appStore.activeJobs = [
        {
          id: 'job1',
          operation: 'buffer',
          status: 'completed',
          progress: 100
        }
      ]
      await wrapper.vm.$nextTick()

      expect(wrapper.text()).toContain('Recent Jobs')
      expect(wrapper.text()).toContain('buffer')
    })

    it('limits recent jobs display to 5', async () => {
      appStore.currentDataset = {
        source: 'test.geojson',
        format: 'GeoJSON',
        rowsIngested: 100,
        columns: []
      }
      appStore.activeJobs = Array.from({ length: 10 }, (_, i) => ({
        id: `job${i}`,
        operation: 'buffer',
        status: 'pending',
        progress: 0
      }))
      await wrapper.vm.$nextTick()

      const jobElements = wrapper.findAll('[class*="p-3 bg-gray-50"]')
      expect(jobElements.length).toBeLessThanOrEqual(5)
    })
  })
})
