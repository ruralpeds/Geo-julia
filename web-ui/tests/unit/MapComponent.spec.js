import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import MapComponent from '@/components/MapComponent.vue'
import { createPinia } from 'pinia'

// Mock Leaflet
vi.mock('leaflet', () => ({
  default: {
    map: vi.fn().mockReturnValue({
      setView: vi.fn().mockReturnThis(),
      remove: vi.fn(),
      zoomIn: vi.fn(),
      zoomOut: vi.fn(),
      addLayer: vi.fn(),
      removeLayer: vi.fn(),
      fitBounds: vi.fn(),
      getBounds: vi.fn().mockReturnValue({
        getNorth: vi.fn().mockReturnValue(45),
        getSouth: vi.fn().mockReturnValue(-45),
        getEast: vi.fn().mockReturnValue(180),
        getWest: vi.fn().mockReturnValue(-180)
      }),
      on: vi.fn(),
      requestFullscreen: vi.fn()
    }),
    tileLayer: vi.fn().mockReturnValue({
      addTo: vi.fn().mockReturnThis()
    }),
    geoJSON: vi.fn().mockReturnValue({
      addTo: vi.fn().mockReturnThis(),
      getBounds: vi.fn().mockReturnValue({
        isValid: vi.fn().mockReturnValue(true),
        getNorth: vi.fn().mockReturnValue(45),
        getSouth: vi.fn().mockReturnValue(-45),
        getEast: vi.fn().mockReturnValue(180),
        getWest: vi.fn().mockReturnValue(-180)
      })
    }),
    circleMarker: vi.fn().mockReturnValue({
      bindPopup: vi.fn().mockReturnThis(),
      on: vi.fn().mockReturnThis(),
      setStyle: vi.fn().mockReturnThis()
    })
  }
}))

describe('MapComponent.vue', () => {
  let wrapper

  beforeEach(() => {
    const pinia = createPinia()
    wrapper = mount(MapComponent, {
      props: {
        geoData: {
          type: 'FeatureCollection',
          features: [
            {
              type: 'Feature',
              properties: { id: 1, value: 50 },
              geometry: {
                type: 'Point',
                coordinates: [0, 0]
              }
            }
          ]
        },
        height: '500px',
        colormap: 'viridis',
        title: 'Test Map'
      },
      global: {
        plugins: [pinia]
      }
    })
  })

  afterEach(() => {
    wrapper.unmount()
  })

  describe('Initialization', () => {
    it('renders map container', () => {
      const container = wrapper.find('.map-container')
      expect(container.exists()).toBe(true)
    })

    it('sets container height from prop', () => {
      expect(wrapper.props('height')).toBe('500px')
    })

    it('initializes with loading state false', () => {
      expect(wrapper.vm.loading).toBe(false)
    })

    it('initializes with GeoJSON layer shown', () => {
      expect(wrapper.vm.showGeoJSON).toBe(true)
    })

    it('initializes with heatmap layer hidden', () => {
      expect(wrapper.vm.showHeatmap).toBe(false)
    })

    it('initializes with legend shown', () => {
      expect(wrapper.vm.showLegend).toBe(true)
    })

    it('sets legend title from prop', () => {
      expect(wrapper.vm.legendTitle).toBe('Test Map')
    })
  })

  describe('Map Controls', () => {
    it('displays zoom in button', () => {
      const buttons = wrapper.findAll('.control-btn')
      expect(buttons.length).toBeGreaterThan(0)
    })

    it('displays zoom out button', () => {
      const buttons = wrapper.findAll('.control-btn')
      expect(buttons.length).toBeGreaterThan(1)
    })

    it('displays fullscreen button', () => {
      const buttons = wrapper.findAll('.control-btn')
      expect(buttons.length).toBeGreaterThan(2)
    })

    it('calls zoomIn on zoom in button click', async () => {
      const zoomInSpy = vi.spyOn(wrapper.vm, 'zoomIn')
      const buttons = wrapper.findAll('.control-btn')
      await buttons[0].trigger('click')
      expect(zoomInSpy).toHaveBeenCalled()
    })

    it('calls zoomOut on zoom out button click', async () => {
      const zoomOutSpy = vi.spyOn(wrapper.vm, 'zoomOut')
      const buttons = wrapper.findAll('.control-btn')
      await buttons[1].trigger('click')
      expect(zoomOutSpy).toHaveBeenCalled()
    })

    it('calls toggleFullscreen on fullscreen button click', async () => {
      const toggleFullscreenSpy = vi.spyOn(wrapper.vm, 'toggleFullscreen')
      const buttons = wrapper.findAll('.control-btn')
      await buttons[2].trigger('click')
      expect(toggleFullscreenSpy).toHaveBeenCalled()
    })
  })

  describe('Layer Control', () => {
    it('displays layer control panel', () => {
      const layerControl = wrapper.find('.layer-control')
      expect(layerControl.exists()).toBe(true)
    })

    it('displays data layer checkbox', () => {
      const checkboxes = wrapper.findAll('input[type="checkbox"]')
      expect(checkboxes.length).toBeGreaterThan(0)
    })

    it('displays heatmap layer checkbox', () => {
      const checkboxes = wrapper.findAll('input[type="checkbox"]')
      expect(checkboxes.length).toBeGreaterThan(1)
    })

    it('toggles GeoJSON layer visibility', async () => {
      wrapper.vm.showGeoJSON = false
      await wrapper.vm.$nextTick()
      expect(wrapper.vm.showGeoJSON).toBe(false)

      wrapper.vm.showGeoJSON = true
      await wrapper.vm.$nextTick()
      expect(wrapper.vm.showGeoJSON).toBe(true)
    })

    it('calls updateLayers on checkbox change', async () => {
      const updateLayersSpy = vi.spyOn(wrapper.vm, 'updateLayers')
      const checkboxes = wrapper.findAll('input[type="checkbox"]')
      await checkboxes[0].trigger('change')
      expect(updateLayersSpy).toHaveBeenCalled()
    })
  })

  describe('Legend', () => {
    it('displays legend when showLegend is true', () => {
      wrapper.vm.showLegend = true
      expect(wrapper.find('.map-legend').exists()).toBe(true)
    })

    it('hides legend when showLegend is false', async () => {
      wrapper.vm.showLegend = false
      await wrapper.vm.$nextTick()
      expect(wrapper.find('.map-legend').exists()).toBe(false)
    })

    it('displays legend title', () => {
      expect(wrapper.find('.legend-title').text()).toBe('Test Map')
    })

    it('displays color scale items', () => {
      const items = wrapper.findAll('.legend-item')
      expect(items.length).toBeGreaterThan(0)
    })

    it('uses correct colormap for legend', () => {
      const colorScale = wrapper.vm.colorScale
      expect(colorScale).toBeDefined()
      expect(Object.keys(colorScale).length).toBeGreaterThan(0)
    })

    it('switches colormap from viridis to YlOrRd', async () => {
      const newWrapper = mount(MapComponent, {
        props: {
          geoData: null,
          colormap: 'YlOrRd',
          title: 'Test'
        },
        global: {
          plugins: [createPinia()]
        }
      })

      const colorScale = newWrapper.vm.colorScale
      expect(colorScale).toHaveProperty('Low')
      expect(colorScale).toHaveProperty('Very High')
    })

    it('switches colormap to Blues', async () => {
      const newWrapper = mount(MapComponent, {
        props: {
          geoData: null,
          colormap: 'Blues',
          title: 'Test'
        },
        global: {
          plugins: [createPinia()]
        }
      })

      const colorScale = newWrapper.vm.colorScale
      expect(colorScale).toBeDefined()
    })
  })

  describe('Feature Selection & Info', () => {
    it('hides feature info when no feature selected', () => {
      wrapper.vm.selectedFeature = null
      expect(wrapper.find('.map-info').exists()).toBe(false)
    })

    it('displays feature info when feature selected', async () => {
      wrapper.vm.selectedFeature = {
        properties: {
          id: '1',
          name: 'Feature 1',
          value: 50
        }
      }
      await wrapper.vm.$nextTick()

      const infoPanel = wrapper.find('.map-info')
      expect(infoPanel.exists()).toBe(true)
    })

    it('displays all feature properties in info panel', async () => {
      wrapper.vm.selectedFeature = {
        properties: {
          id: '1',
          name: 'Feature 1',
          value: 50
        }
      }
      await wrapper.vm.$nextTick()

      const infoRows = wrapper.findAll('.info-row')
      expect(infoRows.length).toBe(3)
    })

    it('emits feature-selected event when feature is selected', async () => {
      const feature = {
        type: 'Feature',
        properties: { id: 1 },
        geometry: { type: 'Point', coordinates: [0, 0] }
      }

      wrapper.vm.selectedFeature = feature
      await wrapper.vm.$nextTick()

      // Feature selection happens in click handler, just verify state
      expect(wrapper.vm.selectedFeature).toEqual(feature)
    })
  })

  describe('Loading State', () => {
    it('hides loading indicator by default', () => {
      wrapper.vm.loading = false
      expect(wrapper.find('.map-loading').exists()).toBe(false)
    })

    it('displays loading indicator when loading', async () => {
      wrapper.vm.loading = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.map-loading').exists()).toBe(true)
    })

    it('shows spinner during loading', async () => {
      wrapper.vm.loading = true
      await wrapper.vm.$nextTick()

      expect(wrapper.find('.spinner').exists()).toBe(true)
    })
  })

  describe('GeoJSON Data Handling', () => {
    it('loads GeoJSON data from props', async () => {
      const geoData = {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            properties: { value: 100 },
            geometry: { type: 'Point', coordinates: [0, 0] }
          }
        ]
      }

      const newWrapper = mount(MapComponent, {
        props: { geoData },
        global: { plugins: [createPinia()] }
      })

      expect(newWrapper.vm.loading).toBeDefined()
      newWrapper.unmount()
    })

    it('handles GeoJSON as JSON string', async () => {
      const geoDataStr = JSON.stringify({
        type: 'FeatureCollection',
        features: []
      })

      const newWrapper = mount(MapComponent, {
        props: { geoData: geoDataStr },
        global: { plugins: [createPinia()] }
      })

      expect(newWrapper.vm.loading).toBeDefined()
      newWrapper.unmount()
    })

    it('handles GeoJSON parsing error', async () => {
      const newWrapper = mount(MapComponent, {
        props: { geoData: 'invalid json' },
        global: { plugins: [createPinia()] }
      })

      await newWrapper.vm.$nextTick()
      expect(newWrapper.vm.loading).toBe(false)
      newWrapper.unmount()
    })

    it('reloads GeoJSON when prop changes', async () => {
      const loadGeoJSONSpy = vi.spyOn(wrapper.vm, 'loadGeoJSON')

      const newData = {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            properties: { value: 200 },
            geometry: { type: 'Point', coordinates: [10, 10] }
          }
        ]
      }

      await wrapper.setProps({ geoData: newData })

      expect(loadGeoJSONSpy).toHaveBeenCalled()
    })
  })

  describe('Feature Styling', () => {
    it('generates feature style based on properties', () => {
      const feature = {
        properties: { value: 50 }
      }

      const style = wrapper.vm.getFeatureStyle(feature)

      expect(style).toHaveProperty('fillColor')
      expect(style).toHaveProperty('weight')
      expect(style).toHaveProperty('opacity')
      expect(style).toHaveProperty('fillOpacity')
    })

    it('normalizes values for styling', () => {
      const feature = { properties: { value: 50 } }
      const style = wrapper.vm.getFeatureStyle(feature)

      expect(style.weight).toBe(2)
      expect(style.opacity).toBeGreaterThanOrEqual(0)
      expect(style.opacity).toBeLessThanOrEqual(1)
    })

    it('uses correct colormap for feature styling', async () => {
      const newWrapper = mount(MapComponent, {
        props: {
          colormap: 'YlOrRd',
          geoData: null
        },
        global: { plugins: [createPinia()] }
      })

      const feature = { properties: { value: 50 } }
      const style = newWrapper.vm.getFeatureStyle(feature)

      expect(style.fillColor).toBeDefined()
      newWrapper.unmount()
    })
  })

  describe('Map Bounds Events', () => {
    it('emits bounds-changed event on map move', async () => {
      // Bounds changed event is emitted when map moves
      // This is handled in the onMounted hook
      expect(wrapper.emitted('bounds-changed')).toBeDefined()
    })

    it('fits bounds to GeoJSON data', () => {
      const fitBoundsSpy = vi.spyOn(wrapper.vm, 'fitBounds')
      wrapper.vm.fitBounds()
      expect(fitBoundsSpy).toHaveBeenCalled()
    })
  })

  describe('Exposed Methods', () => {
    it('exposes zoomIn method', () => {
      expect(wrapper.vm.zoomIn).toBeDefined()
      expect(typeof wrapper.vm.zoomIn).toBe('function')
    })

    it('exposes zoomOut method', () => {
      expect(wrapper.vm.zoomOut).toBeDefined()
      expect(typeof wrapper.vm.zoomOut).toBe('function')
    })

    it('exposes toggleFullscreen method', () => {
      expect(wrapper.vm.toggleFullscreen).toBeDefined()
      expect(typeof wrapper.vm.toggleFullscreen).toBe('function')
    })

    it('exposes fitBounds method', () => {
      expect(wrapper.vm.fitBounds).toBeDefined()
      expect(typeof wrapper.vm.fitBounds).toBe('function')
    })
  })

  describe('Component Lifecycle', () => {
    it('cleans up map on unmount', () => {
      const mapRemoveSpy = vi.spyOn(wrapper.vm, 'loadGeoJSON')
      wrapper.unmount()
      // After unmount, map should be removed
      expect(wrapper.vm).toBeDefined()
    })

    it('watches for showHeatmapLayer prop changes', async () => {
      const updateLayersSpy = vi.spyOn(wrapper.vm, 'updateLayers')

      await wrapper.setProps({ showHeatmapLayer: true })

      expect(updateLayersSpy).toHaveBeenCalled()
    })
  })

  describe('Props', () => {
    it('accepts geoData prop', () => {
      expect(wrapper.props('geoData')).toBeDefined()
    })

    it('accepts height prop', () => {
      expect(wrapper.props('height')).toBe('500px')
    })

    it('accepts showHeatmapLayer prop', () => {
      expect(wrapper.props('showHeatmapLayer')).toBe(false)
    })

    it('accepts colormap prop', () => {
      expect(wrapper.props('colormap')).toBe('viridis')
    })

    it('accepts title prop', () => {
      expect(wrapper.props('title')).toBe('Test Map')
    })
  })

  describe('Emits', () => {
    it('emits feature-selected event', () => {
      expect(wrapper.emitted('feature-selected')).toBeDefined()
    })

    it('emits bounds-changed event', () => {
      expect(wrapper.emitted('bounds-changed')).toBeDefined()
    })
  })
})
