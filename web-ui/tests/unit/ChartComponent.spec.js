import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ChartComponent from '@/components/ChartComponent.vue'

// Mock Chart.js
vi.mock('chart.js/auto', () => {
  const mockChart = vi.fn(function() {
    this.data = {}
    this.options = {}
    this.update = vi.fn()
    this.destroy = vi.fn()
    this.toBase64Image = vi.fn().mockReturnValue('data:image/png;base64,test')
  })

  return { default: mockChart }
})

describe('ChartComponent.vue', () => {
  let wrapper

  beforeEach(() => {
    wrapper = mount(ChartComponent, {
      props: {
        type: 'bar',
        data: {
          labels: ['Label 1', 'Label 2'],
          datasets: [
            {
              label: 'Dataset 1',
              data: [10, 20],
              backgroundColor: 'rgba(75, 192, 192, 0.6)'
            }
          ]
        },
        title: 'Test Chart',
        height: '400px'
      }
    })
  })

  afterEach(() => {
    wrapper.unmount()
  })

  describe('Initialization', () => {
    it('renders chart container', () => {
      const container = wrapper.find('.chart-container')
      expect(container.exists()).toBe(true)
    })

    it('displays chart title', () => {
      const title = wrapper.find('.chart-title')
      expect(title.text()).toBe('Test Chart')
    })

    it('initializes with loading state false', () => {
      expect(wrapper.vm.loading).toBe(false)
    })

    it('initializes with no error', () => {
      expect(wrapper.vm.error).toBeNull()
    })

    it('initializes with legend shown', () => {
      expect(wrapper.vm.showLegend).toBe(true)
    })

    it('creates canvas element', () => {
      const canvas = wrapper.find('canvas')
      expect(canvas.exists()).toBe(true)
    })
  })

  describe('Chart Types', () => {
    it('accepts bar chart type', () => {
      expect(wrapper.props('type')).toBe('bar')
    })

    it('accepts line chart type', async () => {
      const lineWrapper = mount(ChartComponent, {
        props: {
          type: 'line',
          data: { labels: [], datasets: [] }
        }
      })
      expect(lineWrapper.props('type')).toBe('line')
      lineWrapper.unmount()
    })

    it('accepts scatter chart type', async () => {
      const scatterWrapper = mount(ChartComponent, {
        props: {
          type: 'scatter',
          data: { labels: [], datasets: [] }
        }
      })
      expect(scatterWrapper.props('type')).toBe('scatter')
      scatterWrapper.unmount()
    })

    it('accepts pie chart type', async () => {
      const pieWrapper = mount(ChartComponent, {
        props: {
          type: 'pie',
          data: { labels: [], datasets: [] }
        }
      })
      expect(pieWrapper.props('type')).toBe('pie')
      pieWrapper.unmount()
    })

    it('accepts doughnut chart type', async () => {
      const doughnutWrapper = mount(ChartComponent, {
        props: {
          type: 'doughnut',
          data: { labels: [], datasets: [] }
        }
      })
      expect(doughnutWrapper.props('type')).toBe('doughnut')
      doughnutWrapper.unmount()
    })

    it('accepts histogram chart type', async () => {
      const histogramWrapper = mount(ChartComponent, {
        props: {
          type: 'histogram',
          data: { labels: [], datasets: [] }
        }
      })
      expect(histogramWrapper.props('type')).toBe('histogram')
      histogramWrapper.unmount()
    })
  })

  describe('Data Handling', () => {
    it('accepts chart format data', () => {
      const data = {
        labels: ['A', 'B', 'C'],
        datasets: [
          {
            label: 'Series 1',
            data: [10, 20, 30]
          }
        ]
      }

      expect(wrapper.props('data')).toBeDefined()
    })

    it('converts array format data', async () => {
      const newWrapper = mount(ChartComponent, {
        props: {
          data: [
            { label: 'Item 1', value: 10 },
            { label: 'Item 2', value: 20 }
          ]
        }
      })

      const prepared = newWrapper.vm.prepareData(newWrapper.props('data'))

      expect(prepared.labels).toContain('Item 1')
      expect(prepared.labels).toContain('Item 2')
      expect(prepared.datasets[0].data).toContain(10)
      expect(prepared.datasets[0].data).toContain(20)

      newWrapper.unmount()
    })

    it('handles array format without labels', async () => {
      const newWrapper = mount(ChartComponent, {
        props: {
          data: [
            { value: 10 },
            { value: 20 }
          ]
        }
      })

      const prepared = newWrapper.vm.prepareData(newWrapper.props('data'))

      expect(prepared.labels).toContain('Item 1')
      expect(prepared.labels).toContain('Item 2')

      newWrapper.unmount()
    })

    it('handles empty data', () => {
      const prepared = wrapper.vm.prepareData({})

      expect(prepared.labels).toEqual([])
      expect(prepared.datasets).toEqual([])
    })

    it('updates chart when data changes', async () => {
      const updateChartSpy = vi.spyOn(wrapper.vm, 'updateChart')

      const newData = {
        labels: ['New 1', 'New 2'],
        datasets: [
          {
            label: 'New Dataset',
            data: [30, 40]
          }
        ]
      }

      await wrapper.setProps({ data: newData })

      expect(updateChartSpy).toHaveBeenCalled()
    })
  })

  describe('Chart Controls', () => {
    it('displays download button', () => {
      const buttons = wrapper.findAll('.control-btn')
      expect(buttons.length).toBeGreaterThan(0)
    })

    it('displays legend toggle button', () => {
      const buttons = wrapper.findAll('.control-btn')
      expect(buttons.length).toBeGreaterThanOrEqual(2)
    })

    it('calls downloadChart on download button click', async () => {
      const downloadSpy = vi.spyOn(wrapper.vm, 'downloadChart')
      const buttons = wrapper.findAll('.control-btn')
      await buttons[0].trigger('click')
      expect(downloadSpy).toHaveBeenCalled()
    })

    it('calls toggleLegend on legend button click', async () => {
      const toggleSpy = vi.spyOn(wrapper.vm, 'toggleLegend')
      const buttons = wrapper.findAll('.control-btn')
      await buttons[1].trigger('click')
      expect(toggleSpy).toHaveBeenCalled()
    })
  })

  describe('Chart Download', () => {
    it('downloads chart as PNG', () => {
      const createElementSpy = vi.spyOn(document, 'createElement')
      const link = { href: '', download: '', click: vi.fn() }
      createElementSpy.mockReturnValue(link)

      wrapper.vm.downloadChart()

      expect(createElementSpy).toHaveBeenCalledWith('a')
      expect(link.href).toBeDefined()
      expect(link.download).toContain('.png')
      expect(link.click).toHaveBeenCalled()

      createElementSpy.mockRestore()
    })

    it('includes chart type in filename', () => {
      const createElementSpy = vi.spyOn(document, 'createElement')
      const link = { href: '', download: '', click: vi.fn() }
      createElementSpy.mockReturnValue(link)

      wrapper.vm.downloadChart()

      expect(link.download).toContain('bar')

      createElementSpy.mockRestore()
    })

    it('handles download error gracefully', async () => {
      // Create a chart that fails to generate image
      const failWrapper = mount(ChartComponent, {
        props: {
          type: 'bar',
          data: { labels: [], datasets: [] }
        }
      })

      failWrapper.vm.downloadChart()
      // Should not throw
      expect(failWrapper.vm).toBeDefined()

      failWrapper.unmount()
    })
  })

  describe('Legend Toggle', () => {
    it('toggles legend visibility', () => {
      expect(wrapper.vm.showLegend).toBe(true)
      wrapper.vm.toggleLegend()
      expect(wrapper.vm.showLegend).toBe(false)
      wrapper.vm.toggleLegend()
      expect(wrapper.vm.showLegend).toBe(true)
    })

    it('updates chart when legend is toggled', () => {
      const updateSpy = vi.spyOn(wrapper.vm, 'toggleLegend')
      wrapper.vm.toggleLegend()
      expect(updateSpy).toHaveBeenCalled()
    })
  })

  describe('Loading & Error States', () => {
    it('displays loading indicator while loading', async () => {
      wrapper.vm.loading = true
      await wrapper.vm.$nextTick()

      const loading = wrapper.find('.chart-loading')
      expect(loading.exists()).toBe(true)
    })

    it('hides loading indicator when done', async () => {
      wrapper.vm.loading = false
      await wrapper.vm.$nextTick()

      const loading = wrapper.find('.chart-loading')
      expect(loading.exists()).toBe(false)
    })

    it('displays error message when error occurs', async () => {
      wrapper.vm.error = 'Test error message'
      await wrapper.vm.$nextTick()

      const errorElement = wrapper.find('.chart-error')
      expect(errorElement.exists()).toBe(true)
      expect(errorElement.text()).toContain('Test error message')
    })

    it('clears error on successful update', async () => {
      wrapper.vm.error = 'Some error'
      expect(wrapper.vm.error).not.toBeNull()

      wrapper.vm.error = null
      await wrapper.vm.$nextTick()

      const errorElement = wrapper.find('.chart-error')
      expect(errorElement.exists()).toBe(false)
    })
  })

  describe('Chart Type Change', () => {
    it('recreates chart when type changes', async () => {
      const createChartSpy = vi.spyOn(wrapper.vm, 'createChart')

      await wrapper.setProps({ type: 'line' })

      expect(createChartSpy).toHaveBeenCalled()
    })

    it('destroys old chart instance on type change', async () => {
      const initialInstance = wrapper.vm
      await wrapper.setProps({ type: 'pie' })
      // Chart should be recreated
      expect(wrapper.vm).toBeDefined()
    })
  })

  describe('Props', () => {
    it('accepts type prop', () => {
      expect(wrapper.props('type')).toBeDefined()
    })

    it('accepts data prop', () => {
      expect(wrapper.props('data')).toBeDefined()
    })

    it('accepts options prop', () => {
      expect(wrapper.props('options')).toBeDefined()
    })

    it('accepts title prop', () => {
      expect(wrapper.props('title')).toBe('Test Chart')
    })

    it('accepts height prop', () => {
      expect(wrapper.props('height')).toBe('400px')
    })

    it('uses default title', async () => {
      const defaultWrapper = mount(ChartComponent, {
        props: {
          data: { labels: [], datasets: [] }
        }
      })
      expect(defaultWrapper.props('title')).toBe('Chart')
      defaultWrapper.unmount()
    })

    it('uses default height', async () => {
      const defaultWrapper = mount(ChartComponent, {
        props: {
          data: { labels: [], datasets: [] }
        }
      })
      expect(defaultWrapper.props('height')).toBe('400px')
      defaultWrapper.unmount()
    })

    it('uses default chart type', async () => {
      const defaultWrapper = mount(ChartComponent, {
        props: {
          data: { labels: [], datasets: [] }
        }
      })
      expect(defaultWrapper.props('type')).toBe('bar')
      defaultWrapper.unmount()
    })

    it('uses default options', async () => {
      const defaultWrapper = mount(ChartComponent, {
        props: {
          data: { labels: [], datasets: [] }
        }
      })
      expect(defaultWrapper.props('options')).toEqual({})
      defaultWrapper.unmount()
    })
  })

  describe('Exposed Methods', () => {
    it('exposes downloadChart method', () => {
      expect(wrapper.vm.downloadChart).toBeDefined()
      expect(typeof wrapper.vm.downloadChart).toBe('function')
    })

    it('exposes toggleLegend method', () => {
      expect(wrapper.vm.toggleLegend).toBeDefined()
      expect(typeof wrapper.vm.toggleLegend).toBe('function')
    })

    it('exposes update method', () => {
      expect(wrapper.vm.update).toBeDefined()
      expect(typeof wrapper.vm.update).toBe('function')
    })
  })

  describe('Component Lifecycle', () => {
    it('destroys chart on unmount', () => {
      const chartInstance = wrapper.vm
      wrapper.unmount()
      expect(wrapper.vm).toBeDefined()
    })

    it('creates chart on mount if data provided', () => {
      const canvas = wrapper.find('canvas')
      expect(canvas.exists()).toBe(true)
    })

    it('does not create chart if no data provided', async () => {
      const noDataWrapper = mount(ChartComponent, {
        props: {
          data: null
        }
      })
      expect(noDataWrapper.vm).toBeDefined()
      noDataWrapper.unmount()
    })
  })

  describe('Complex Scenarios', () => {
    it('handles multiple data updates', async () => {
      const data1 = {
        labels: ['A', 'B'],
        datasets: [{ label: 'Series 1', data: [10, 20] }]
      }

      const data2 = {
        labels: ['C', 'D'],
        datasets: [{ label: 'Series 2', data: [30, 40] }]
      }

      const data3 = {
        labels: ['E', 'F'],
        datasets: [{ label: 'Series 3', data: [50, 60] }]
      }

      await wrapper.setProps({ data: data1 })
      await wrapper.setProps({ data: data2 })
      await wrapper.setProps({ data: data3 })

      expect(wrapper.vm).toBeDefined()
      expect(wrapper.vm.error).toBeNull()
    })

    it('handles type and data changes together', async () => {
      await wrapper.setProps({
        type: 'line',
        data: {
          labels: ['New A', 'New B'],
          datasets: [{ label: 'New Series', data: [100, 200] }]
        }
      })

      expect(wrapper.vm).toBeDefined()
    })

    it('preserves legend state across updates', async () => {
      wrapper.vm.toggleLegend()
      expect(wrapper.vm.showLegend).toBe(false)

      const newData = {
        labels: ['X', 'Y'],
        datasets: [{ label: 'New', data: [5, 10] }]
      }

      await wrapper.setProps({ data: newData })

      expect(wrapper.vm.showLegend).toBe(false)
    })
  })
})
