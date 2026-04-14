<template>
  <div class="map-container">
    <div ref="mapElement" class="map-wrapper"></div>

    <!-- Map Controls -->
    <div class="map-controls">
      <!-- Zoom Controls -->
      <button @click="zoomIn" class="control-btn" title="Zoom in">+</button>
      <button @click="zoomOut" class="control-btn" title="Zoom out">−</button>

      <!-- Fullscreen Button -->
      <button @click="toggleFullscreen" class="control-btn" title="Toggle fullscreen">⛶</button>
    </div>

    <!-- Layer Control -->
    <div class="layer-control">
      <h3 class="control-title">Layers</h3>
      <div class="layer-options">
        <label class="checkbox-label">
          <input v-model="showGeoJSON" type="checkbox" @change="updateLayers" />
          <span>Data</span>
        </label>
        <label class="checkbox-label">
          <input v-model="showHeatmap" type="checkbox" @change="updateLayers" />
          <span>Heatmap</span>
        </label>
      </div>
    </div>

    <!-- Map Legend -->
    <div v-if="showLegend" class="map-legend">
      <h3 class="legend-title">{{ legendTitle }}</h3>
      <div class="legend-items">
        <div v-for="(color, label) in colorScale" :key="label" class="legend-item">
          <div class="legend-color" :style="{ backgroundColor: color }"></div>
          <span class="legend-label">{{ label }}</span>
        </div>
      </div>
    </div>

    <!-- Map Info -->
    <div v-if="selectedFeature" class="map-info">
      <h3 class="info-title">Feature Info</h3>
      <div class="info-content">
        <div v-for="(value, key) in selectedFeature.properties" :key="key" class="info-row">
          <span class="info-key">{{ key }}:</span>
          <span class="info-value">{{ value }}</span>
        </div>
      </div>
    </div>

    <!-- Loading Indicator -->
    <div v-if="loading" class="map-loading">
      <div class="spinner"></div>
      <p>Loading map...</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useAppStore } from '@/stores/app'

const props = defineProps({
  geoData: {
    type: Object,
    default: null
  },
  height: {
    type: String,
    default: '500px'
  },
  showHeatmapLayer: {
    type: Boolean,
    default: false
  },
  colormap: {
    type: String,
    default: 'viridis'
  },
  title: {
    type: String,
    default: 'Map Visualization'
  }
})

const emit = defineEmits(['feature-selected', 'bounds-changed'])

const appStore = useAppStore()

// Map instance
let map = null
let geoJSONLayer = null
let heatmapLayer = null

// UI State
const mapElement = ref(null)
const loading = ref(false)
const showGeoJSON = ref(true)
const showHeatmap = ref(props.showHeatmapLayer)
const selectedFeature = ref(null)
const showLegend = ref(true)
const legendTitle = ref(props.title)

// Color scale for legend
const colorScale = computed(() => {
  const scales = {
    viridis: {
      'Low': '#440154',
      'Mid-Low': '#31688e',
      'Mid': '#35b779',
      'Mid-High': '#fde724',
      'High': '#fde724'
    },
    YlOrRd: {
      'Low': '#ffffcc',
      'Mid': '#ffeda0',
      'Mid-High': '#fed976',
      'High': '#f03b20',
      'Very High': '#bd0026'
    },
    Blues: {
      'Low': '#f7fbff',
      'Mid': '#9ecae1',
      'High': '#3182bd',
      'Very High': '#08519c'
    }
  }
  return scales[props.colormap] || scales.viridis
})

// Initialize map
onMounted(() => {
  if (!mapElement.value) return

  // Create map
  map = L.map(mapElement.value).setView([20, 0], 2)

  // Add tile layer
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors',
    maxZoom: 19
  }).addTo(map)

  // Add custom controls
  addCustomControls()

  // Load GeoJSON if available
  if (props.geoData) {
    loadGeoJSON(props.geoData)
  }

  // Listen for map events
  map.on('moveend', () => {
    const bounds = map.getBounds()
    emit('bounds-changed', {
      north: bounds.getNorth(),
      south: bounds.getSouth(),
      east: bounds.getEast(),
      west: bounds.getWest()
    })
  })
})

onUnmounted(() => {
  if (map) {
    map.remove()
  }
})

// Watch for prop changes
watch(
  () => props.geoData,
  (newData) => {
    if (newData) {
      loadGeoJSON(newData)
    }
  }
)

watch(
  () => props.showHeatmapLayer,
  (newVal) => {
    showHeatmap.value = newVal
    updateLayers()
  }
)

// Load GeoJSON data
function loadGeoJSON(data) {
  loading.value = true

  try {
    // Remove existing layer
    if (geoJSONLayer) {
      map.removeLayer(geoJSONLayer)
    }

    // Parse GeoJSON
    let geoJSON = data
    if (typeof data === 'string') {
      geoJSON = JSON.parse(data)
    }

    // Create GeoJSON layer with styling
    geoJSONLayer = L.geoJSON(geoJSON, {
      style: getFeatureStyle,
      onEachFeature: onEachFeature,
      pointToLayer: pointToLayer
    }).addTo(map)

    // Fit bounds
    const bounds = geoJSONLayer.getBounds()
    if (bounds.isValid()) {
      map.fitBounds(bounds, { padding: [50, 50] })
    }

    appStore.addNotification('Map data loaded successfully', 'success')
  } catch (error) {
    appStore.addNotification(`Failed to load map data: ${error.message}`, 'error')
  } finally {
    loading.value = false
  }
}

// Style features based on properties
function getFeatureStyle(feature) {
  const properties = feature.properties || {}
  const value = properties.value || properties.temperature || 0

  // Normalize value to 0-1
  const normalized = Math.min(Math.max(value / 100, 0), 1)

  // Get color from colormap
  let color = '#3388ff'
  if (props.colormap === 'YlOrRd') {
    if (normalized < 0.2) color = '#ffffcc'
    else if (normalized < 0.4) color = '#ffeda0'
    else if (normalized < 0.6) color = '#fed976'
    else if (normalized < 0.8) color = '#f03b20'
    else color = '#bd0026'
  } else if (props.colormap === 'Blues') {
    if (normalized < 0.2) color = '#f7fbff'
    else if (normalized < 0.4) color = '#deebf7'
    else if (normalized < 0.6) color = '#9ecae1'
    else if (normalized < 0.8) color = '#3182bd'
    else color = '#08519c'
  }

  return {
    fillColor: color,
    weight: 2,
    opacity: 0.9,
    color: '#555',
    dashArray: '',
    fillOpacity: 0.7
  }
}

// Point to layer converter
function pointToLayer(feature, latlng) {
  const properties = feature.properties || {}
  const value = properties.value || properties.temperature || 0
  const size = Math.max(4, Math.min(12, value / 10))

  return L.circleMarker(latlng, {
    radius: size,
    fillColor: '#3388ff',
    color: '#555',
    weight: 2,
    opacity: 1,
    fillOpacity: 0.7
  })
}

// Handle feature interactions
function onEachFeature(feature, layer) {
  // Create popup
  const properties = feature.properties || {}
  let popupContent = '<div class="popup-content">'

  for (const [key, value] of Object.entries(properties)) {
    popupContent += `<p><strong>${key}:</strong> ${value}</p>`
  }

  popupContent += '</div>'

  layer.bindPopup(popupContent)

  // Click handler
  layer.on('click', () => {
    selectedFeature.value = feature
    emit('feature-selected', feature)
  })

  // Hover effects
  layer.on('mouseover', () => {
    layer.setStyle({ weight: 3, opacity: 1, fillOpacity: 0.9 })
  })

  layer.on('mouseout', () => {
    layer.setStyle({ weight: 2, opacity: 0.9, fillOpacity: 0.7 })
  })
}

// Update layer visibility
function updateLayers() {
  if (!map) return

  if (geoJSONLayer) {
    if (showGeoJSON.value) {
      map.addLayer(geoJSONLayer)
    } else {
      map.removeLayer(geoJSONLayer)
    }
  }

  // TODO: Add heatmap layer
  if (showHeatmap.value && props.geoData) {
    // Heatmap implementation would go here
  }
}

// Map controls
function addCustomControls() {
  // These are handled by the UI template
}

function zoomIn() {
  if (map) map.zoomIn()
}

function zoomOut() {
  if (map) map.zoomOut()
}

function toggleFullscreen() {
  if (mapElement.value) {
    if (!document.fullscreenElement) {
      mapElement.value.parentElement.requestFullscreen().catch((err) => {
        console.error(`Fullscreen error: ${err.message}`)
      })
    } else {
      document.exitFullscreen()
    }
  }
}

// Expose methods
defineExpose({
  zoomIn,
  zoomOut,
  toggleFullscreen,
  fitBounds: () => {
    if (geoJSONLayer) {
      const bounds = geoJSONLayer.getBounds()
      if (bounds.isValid()) {
        map.fitBounds(bounds, { padding: [50, 50] })
      }
    }
  }
})
</script>

<style scoped>
.map-container {
  position: relative;
  width: 100%;
  height: v-bind(height);
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.map-wrapper {
  width: 100%;
  height: 100%;
}

.map-controls {
  position: absolute;
  top: 10px;
  right: 10px;
  display: flex;
  flex-direction: column;
  gap: 5px;
  z-index: 400;
}

.control-btn {
  width: 40px;
  height: 40px;
  background: white;
  border: 2px solid #ccc;
  border-radius: 4px;
  cursor: pointer;
  font-size: 18px;
  font-weight: bold;
  transition: all 0.2s;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.control-btn:hover {
  background: #f5f5f5;
  border-color: #999;
}

.control-btn:active {
  transform: scale(0.95);
}

.layer-control {
  position: absolute;
  bottom: 20px;
  left: 10px;
  background: white;
  border-radius: 4px;
  padding: 10px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  z-index: 400;
  min-width: 150px;
}

.control-title {
  font-size: 12px;
  font-weight: bold;
  margin: 0 0 8px 0;
  color: #333;
}

.layer-options {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  font-size: 12px;
  user-select: none;
}

.checkbox-label input {
  cursor: pointer;
  width: 16px;
  height: 16px;
}

.map-legend {
  position: absolute;
  top: 50px;
  right: 10px;
  background: white;
  border-radius: 4px;
  padding: 12px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  z-index: 400;
  max-width: 200px;
}

.legend-title {
  font-size: 12px;
  font-weight: bold;
  margin: 0 0 8px 0;
  color: #333;
}

.legend-items {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 8px;
}

.legend-color {
  width: 24px;
  height: 24px;
  border-radius: 3px;
  border: 1px solid #ddd;
}

.legend-label {
  font-size: 11px;
  color: #666;
}

.map-info {
  position: absolute;
  bottom: 20px;
  right: 10px;
  background: white;
  border-radius: 4px;
  padding: 12px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  z-index: 400;
  max-width: 250px;
  max-height: 300px;
  overflow-y: auto;
}

.info-title {
  font-size: 12px;
  font-weight: bold;
  margin: 0 0 8px 0;
  color: #333;
}

.info-content {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.info-row {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  font-size: 11px;
}

.info-key {
  font-weight: bold;
  color: #666;
  min-width: 80px;
}

.info-value {
  color: #333;
  text-align: right;
}

.map-loading {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.8);
  z-index: 500;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 4px solid #f3f3f3;
  border-top: 4px solid #3498db;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

.popup-content {
  font-size: 12px;
}

.popup-content p {
  margin: 4px 0;
  padding: 0;
}
</style>
