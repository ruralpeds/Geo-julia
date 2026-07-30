<template>
  <div class="map-studio flex h-full w-full">
    <!-- Sidebar for Layer Management -->
    <div class="w-80 bg-white border-r border-gray-300 flex flex-col h-full z-10 shadow-lg">
      <div class="p-4 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
        <h2 class="text-xl font-bold text-gray-800">Map Studio</h2>
      </div>

      <div class="p-4 flex-1 overflow-y-auto">
        <!-- Data Source Selection -->
        <div class="mb-6">
          <h3 class="text-sm font-semibold text-gray-600 mb-2 uppercase tracking-wider">Add Layer</h3>

          <div class="space-y-3">
            <select v-model="selectedDataset" class="w-full p-2 border border-gray-300 rounded text-sm bg-white">
              <option value="" disabled>Select Dataset or Result</option>
              <option v-for="ds in datasets" :key="ds.id" :value="ds">
                {{ ds.name }} ({{ ds.type }})
              </option>
            </select>

            <button
              @click="addLayer"
              :disabled="!selectedDataset"
              class="w-full py-2 bg-blue-600 hover:bg-blue-700 text-white rounded font-medium text-sm transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Add to Map
            </button>
          </div>
        </div>

        <!-- Layer List -->
        <div>
          <h3 class="text-sm font-semibold text-gray-600 mb-2 uppercase tracking-wider">Layers</h3>

          <div v-if="layers.length === 0" class="text-gray-500 text-sm italic p-4 text-center bg-gray-50 rounded border border-dashed border-gray-300">
            No layers added yet.
          </div>

          <div v-else class="space-y-3">
            <div
              v-for="(layer, index) in layers"
              :key="layer.id"
              class="border border-gray-200 rounded overflow-hidden shadow-sm transition"
              :class="{'border-blue-400 ring-1 ring-blue-400': activeLayerIndex === index}"
            >
              <!-- Layer Header -->
              <div
                class="bg-gray-100 p-2 flex items-center justify-between cursor-pointer hover:bg-gray-200"
                @click="activeLayerIndex = index"
              >
                <div class="flex items-center gap-2 overflow-hidden">
                  <input
                    type="checkbox"
                    v-model="layer.visible"
                    @click.stop
                    class="h-4 w-4 rounded text-blue-600 focus:ring-blue-500"
                  >
                  <span class="font-medium text-sm truncate" :title="layer.name">{{ layer.name }}</span>
                </div>
                <button @click.stop="removeLayer(index)" class="text-gray-400 hover:text-red-500">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                </button>
              </div>

              <!-- Layer Properties (expanded if active) -->
              <div v-if="activeLayerIndex === index" class="p-3 bg-white space-y-4 border-t border-gray-200">

                <!-- Visualization Type -->
                <div>
                  <label class="block text-xs font-medium text-gray-700 mb-1">Visualization Type</label>
                  <select v-model="layer.type" class="w-full p-1.5 border border-gray-300 rounded text-sm bg-gray-50">
                    <option value="geojson">Polygons / Points (2D)</option>
                    <option value="heatmap">Heatmap</option>
                    <option value="hexagon">3D Hexagon Binning</option>
                    <option value="extruded">3D Extruded Polygons</option>
                  </select>
                </div>

                <!-- Color Properties -->
                <div>
                  <label class="block text-xs font-medium text-gray-700 mb-1">Color</label>
                  <div class="flex gap-2 items-center">
                    <input type="color" v-model="layer.color" class="h-8 w-8 rounded cursor-pointer p-0 border-0">
                    <input type="range" v-model="layer.opacity" min="0" max="1" step="0.1" class="flex-1 accent-blue-600">
                    <span class="text-xs text-gray-500 w-8 text-right">{{ layer.opacity }}</span>
                  </div>
                </div>

                <!-- Data-Driven Styling (Choropleth/3D) -->
                <div v-if="['extruded', 'geojson'].includes(layer.type)">
                  <label class="block text-xs font-medium text-gray-700 mb-1">Style based on attribute</label>
                  <select v-model="layer.colorProperty" class="w-full p-1.5 border border-gray-300 rounded text-sm bg-gray-50">
                    <option value="">None (Uniform Color)</option>
                    <option v-for="prop in getLayerProperties(layer)" :key="prop" :value="prop">{{ prop }}</option>
                  </select>
                </div>

                <!-- 3D Elevation -->
                <div v-if="['extruded', 'hexagon'].includes(layer.type)">
                  <label class="block text-xs font-medium text-gray-700 mb-1">Elevation Attribute</label>
                  <select v-model="layer.elevationProperty" class="w-full p-1.5 border border-gray-300 rounded text-sm bg-gray-50">
                    <option value="">None (Count)</option>
                    <option v-for="prop in getNumericProperties(layer)" :key="prop" :value="prop">{{ prop }}</option>
                  </select>

                  <label class="block text-xs font-medium text-gray-700 mt-3 mb-1">Elevation Scale</label>
                  <input type="range" v-model="layer.elevationScale" min="1" max="100" class="w-full accent-blue-600">
                </div>

              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Map Container -->
    <div class="flex-1 relative bg-gray-200">
      <div id="deck-canvas" class="absolute inset-0 w-full h-full"></div>

      <!-- Base Map Toggle -->
      <div class="absolute bottom-4 right-4 bg-white rounded shadow-md p-2 z-10 flex gap-2">
        <button
          @click="mapStyle = 'light'"
          class="px-3 py-1 text-sm rounded transition"
          :class="mapStyle === 'light' ? 'bg-gray-200 font-semibold' : 'hover:bg-gray-100'"
        >Light</button>
        <button
          @click="mapStyle = 'dark'"
          class="px-3 py-1 text-sm rounded transition"
          :class="mapStyle === 'dark' ? 'bg-gray-800 text-white font-semibold' : 'hover:bg-gray-100'"
        >Dark</button>
        <button
          @click="mapStyle = 'satellite'"
          class="px-3 py-1 text-sm rounded transition"
          :class="mapStyle === 'satellite' ? 'bg-green-700 text-white font-semibold' : 'hover:bg-gray-100'"
        >Satellite</button>
      </div>

      <!-- Legend -->
      <div v-if="showLegend" class="absolute bottom-4 left-4 bg-white rounded shadow-md p-4 z-10 min-w-[200px]">
        <h4 class="font-semibold text-sm mb-2">{{ activeLayer?.name || 'Legend' }}</h4>
        <div v-if="activeLayer?.colorProperty" class="space-y-1">
          <div class="text-xs text-gray-500 mb-2">Based on: {{ activeLayer.colorProperty }}</div>
          <div class="h-2 w-full bg-gradient-to-r from-blue-100 to-blue-800 rounded"></div>
          <div class="flex justify-between text-xs text-gray-600 mt-1">
            <span>Low</span>
            <span>High</span>
          </div>
        </div>
        <div v-else class="text-xs text-gray-500 italic">No data-driven styling active.</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import { useAppStore } from '@/stores/app'
import { Deck } from '@deck.gl/core'
import { GeoJsonLayer } from '@deck.gl/layers'
import { HexagonLayer } from '@deck.gl/aggregation-layers'
import * as maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'

const appStore = useAppStore()

// State
const deckInstance = ref(null)
const mapInstance = ref(null)
const mapStyle = ref('dark')
const layers = ref([])
const activeLayerIndex = ref(-1)
const selectedDataset = ref('')

// Computed
const activeLayer = computed(() => activeLayerIndex.value >= 0 ? layers.value[activeLayerIndex.value] : null)
const showLegend = computed(() => layers.value.length > 0)

// Mock datasets for now (would come from API)
const datasets = ref([
  { id: '1', name: 'US Counties (TIGER)', type: 'geojson', url: 'https://raw.githubusercontent.com/visgl/deck.gl-data/master/examples/geojson/vancouver-blocks.json' },
  { id: '2', name: 'Healthcare Providers', type: 'points', url: 'https://raw.githubusercontent.com/visgl/deck.gl-data/master/examples/scatterplot/manhattan.json' },
  { id: '3', name: 'Recent 2SFCA Analysis', type: 'geojson_result', url: 'https://raw.githubusercontent.com/visgl/deck.gl-data/master/examples/geojson/vancouver-blocks.json' }
])

const mapStyles = {
  light: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
  dark: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
  satellite: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json'
}

// Initial view state
const INITIAL_VIEW_STATE = {
  longitude: -122.4, // Default to US (approx) but using deck.gl example coordinates for demo
  latitude: 37.74,
  zoom: 11,
  pitch: 30,
  bearing: 0
}

// Hex color to RGB array
const hexToRgb = (hex) => {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result ? [
    parseInt(result[1], 16),
    parseInt(result[2], 16),
    parseInt(result[3], 16)
  ] : [0, 100, 255];
}

onMounted(() => {
  initMap()
})

onUnmounted(() => {
  if (deckInstance.value) {
    deckInstance.value.finalize()
  }
  if (mapInstance.value) {
    mapInstance.value.remove()
  }
})

// Watch for style changes
watch(mapStyle, (newStyle) => {
  if (mapInstance.value) {
    mapInstance.value.setStyle(mapStyles[newStyle])
  }
})

// Watch for layer changes to re-render deck.gl
watch(layers, () => {
  renderDeckLayers()
}, { deep: true })

const initMap = () => {
  // Initialize MapLibre Base Map
  mapInstance.value = new maplibregl.Map({
    container: 'deck-canvas',
    style: mapStyles[mapStyle.value],
    interactive: false, // Deck.gl handles interaction
    center: [INITIAL_VIEW_STATE.longitude, INITIAL_VIEW_STATE.latitude],
    zoom: INITIAL_VIEW_STATE.zoom,
    pitch: INITIAL_VIEW_STATE.pitch,
    bearing: INITIAL_VIEW_STATE.bearing
  })

  // Initialize Deck.gl
  deckInstance.value = new Deck({
    canvas: document.createElement('canvas'),
    parent: document.getElementById('deck-canvas'),
    initialViewState: INITIAL_VIEW_STATE,
    controller: true,
    onViewStateChange: ({viewState}) => {
      mapInstance.value.jumpTo({
        center: [viewState.longitude, viewState.latitude],
        zoom: viewState.zoom,
        bearing: viewState.bearing,
        pitch: viewState.pitch
      })
    },
    layers: []
  })

  // Fix z-index so deck.gl is over maplibre but under UI controls
  deckInstance.value.canvas.style.position = 'absolute'
  deckInstance.value.canvas.style.top = '0'
  deckInstance.value.canvas.style.left = '0'
  deckInstance.value.canvas.style.pointerEvents = 'none' // Let events pass to maplibre if needed, though deck.gl handles controller
}

const renderDeckLayers = () => {
  if (!deckInstance.value) return

  const deckLayers = layers.value.filter(l => l.visible).map(layerConfig => {

    // Convert hex+opacity to RGBA array
    const rgb = hexToRgb(layerConfig.color)
    const rgba = [...rgb, Math.floor(layerConfig.opacity * 255)]

    if (layerConfig.type === 'hexagon' || layerConfig.type === 'heatmap') {
      return new HexagonLayer({
        id: `hex-${layerConfig.id}`,
        data: layerConfig.data,
        pickable: true,
        extruded: layerConfig.type === 'hexagon',
        radius: 200,
        elevationScale: layerConfig.elevationScale,
        getPosition: d => d.COORDINATES || d.geometry?.coordinates,
        // Simple color range for demo
        colorRange: [
          [1, 152, 189],
          [73, 227, 206],
          [216, 254, 181],
          [254, 237, 177],
          [254, 173, 84],
          [209, 55, 78]
        ]
      })
    }

    return new GeoJsonLayer({
      id: `geojson-${layerConfig.id}`,
      data: layerConfig.data,
      pickable: true,
      stroked: true,
      filled: true,
      extruded: layerConfig.type === 'extruded',
      pointType: 'circle',
      lineWidthMinPixels: 1,
      getFillColor: d => {
        // If data-driven styling is active
        if (layerConfig.colorProperty && d.properties[layerConfig.colorProperty]) {
          const val = d.properties[layerConfig.colorProperty]
          // Super simple mock color scale based on value (assumes numeric)
          return [0, Math.min(255, val * 10), 255 - Math.min(255, val * 5), rgba[3]]
        }
        return rgba
      },
      getLineColor: [255, 255, 255, 100],
      getPointRadius: 100,
      getLineWidth: 1,
      getElevation: d => {
        if (layerConfig.elevationProperty && d.properties[layerConfig.elevationProperty]) {
          return d.properties[layerConfig.elevationProperty] * layerConfig.elevationScale
        }
        return 30 * layerConfig.elevationScale
      },
      // Basic Tooltip
      autoHighlight: true
    })
  })

  deckInstance.value.setProps({ layers: deckLayers })
}

const addLayer = async () => {
  if (!selectedDataset.value) return

  appStore.addNotification('Loading dataset...', 'info', 2000)

  try {
    // In a real app, fetch from API. Here we fetch mock data
    const response = await fetch(selectedDataset.value.url)
    const data = await response.json()

    const newLayer = {
      id: Date.now().toString(),
      name: selectedDataset.value.name,
      data: data,
      visible: true,
      type: selectedDataset.value.type.includes('point') ? 'hexagon' : 'geojson',
      color: '#2563eb', // Default blue
      opacity: 0.8,
      colorProperty: '',
      elevationProperty: '',
      elevationScale: 10
    }

    layers.value.push(newLayer)
    activeLayerIndex.value = layers.value.length - 1
    selectedDataset.value = ''

    appStore.addNotification('Layer added successfully', 'success')
  } catch (error) {
    appStore.addNotification(`Failed to load layer: ${error.message}`, 'error')
  }
}

const removeLayer = (index) => {
  layers.value.splice(index, 1)
  if (activeLayerIndex.value === index) {
    activeLayerIndex.value = -1
  } else if (activeLayerIndex.value > index) {
    activeLayerIndex.value--
  }
}

// Helper functions to parse GeoJSON properties for UI selectors
const getLayerProperties = (layer) => {
  if (!layer || !layer.data || !layer.data.features || layer.data.features.length === 0) return []
  return Object.keys(layer.data.features[0].properties || {})
}

const getNumericProperties = (layer) => {
  if (!layer || !layer.data || !layer.data.features || layer.data.features.length === 0) return []
  const props = layer.data.features[0].properties || {}
  return Object.keys(props).filter(k => typeof props[k] === 'number')
}

</script>
