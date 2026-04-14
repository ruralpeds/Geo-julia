<template>
  <div class="chart-container">
    <div class="chart-header">
      <h2 class="chart-title">{{ title }}</h2>
      <div class="chart-controls">
        <button @click="downloadChart" class="control-btn" title="Download chart">📥</button>
        <button @click="toggleLegend" class="control-btn" title="Toggle legend">📋</button>
      </div>
    </div>

    <canvas ref="chartCanvas" class="chart-canvas"></canvas>

    <div v-if="loading" class="chart-loading">
      <div class="spinner"></div>
    </div>

    <div v-if="error" class="chart-error">
      <p>{{ error }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import Chart from 'chart.js/auto'

const props = defineProps({
  type: {
    type: String,
    default: 'bar',
    validator: (val) => ['bar', 'line', 'scatter', 'histogram', 'pie', 'doughnut'].includes(val)
  },
  data: {
    type: Object,
    required: true
  },
  options: {
    type: Object,
    default: () => ({})
  },
  title: {
    type: String,
    default: 'Chart'
  },
  height: {
    type: String,
    default: '400px'
  }
})

const chartCanvas = ref(null)
let chartInstance = null
const loading = ref(false)
const error = ref(null)
const showLegend = ref(true)

// Initialize chart
onMounted(() => {
  if (props.data) {
    createChart()
  }
})

onUnmounted(() => {
  if (chartInstance) {
    chartInstance.destroy()
  }
})

// Watch for data changes
watch(
  () => props.data,
  (newData) => {
    if (newData) {
      updateChart(newData)
    }
  },
  { deep: true }
)

watch(
  () => props.type,
  () => {
    if (chartInstance) {
      chartInstance.destroy()
    }
    createChart()
  }
)

function createChart() {
  if (!chartCanvas.value) return

  loading.value = true
  error.value = null

  try {
    const ctx = chartCanvas.value.getContext('2d')

    // Prepare chart data
    const chartData = prepareData(props.data)

    // Default options
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        title: {
          display: true,
          text: props.title,
          font: { size: 16, weight: 'bold' },
          padding: { top: 10, bottom: 10 }
        },
        legend: {
          display: showLegend.value,
          position: 'top'
        },
        tooltip: {
          backgroundColor: 'rgba(0, 0, 0, 0.8)',
          padding: 12,
          titleFont: { size: 14 },
          bodyFont: { size: 12 },
          displayColors: true
        }
      },
      scales:
        props.type !== 'pie' && props.type !== 'doughnut'
          ? {
              y: {
                display: true,
                grid: { color: 'rgba(0, 0, 0, 0.1)' },
                ticks: { font: { size: 11 } }
              },
              x: {
                display: true,
                grid: { display: false },
                ticks: { font: { size: 11 } }
              }
            }
          : undefined
    }

    // Merge options
    const mergedOptions = {
      ...defaultOptions,
      ...props.options
    }

    chartInstance = new Chart(ctx, {
      type: props.type,
      data: chartData,
      options: mergedOptions
    })
  } catch (err) {
    error.value = `Failed to create chart: ${err.message}`
  } finally {
    loading.value = false
  }
}

function updateChart(newData) {
  if (!chartInstance) {
    createChart()
    return
  }

  try {
    const chartData = prepareData(newData)

    // Update data
    chartInstance.data.labels = chartData.labels
    chartInstance.data.datasets = chartData.datasets

    chartInstance.update()
  } catch (err) {
    error.value = `Failed to update chart: ${err.message}`
  }
}

function prepareData(rawData) {
  // If data is already in chart format
  if (rawData.labels && rawData.datasets) {
    return rawData
  }

  // Convert from array format
  if (Array.isArray(rawData)) {
    return {
      labels: rawData.map((item, idx) => item.label || `Item ${idx + 1}`),
      datasets: [
        {
          label: 'Values',
          data: rawData.map((item) => item.value),
          backgroundColor: 'rgba(75, 192, 192, 0.6)',
          borderColor: 'rgba(75, 192, 192, 1)',
          borderWidth: 1
        }
      ]
    }
  }

  // Default empty format
  return {
    labels: [],
    datasets: []
  }
}

function downloadChart() {
  if (!chartInstance) return

  try {
    const image = chartInstance.toBase64Image()
    const link = document.createElement('a')
    link.href = image
    link.download = `chart-${props.type}-${Date.now()}.png`
    link.click()
  } catch (err) {
    error.value = 'Failed to download chart'
  }
}

function toggleLegend() {
  showLegend.value = !showLegend.value
  if (chartInstance) {
    chartInstance.options.plugins.legend.display = showLegend.value
    chartInstance.update()
  }
}

defineExpose({
  downloadChart,
  toggleLegend,
  update: updateChart
})
</script>

<style scoped>
.chart-container {
  position: relative;
  width: 100%;
  padding: 1rem;
  background: white;
  border-radius: 0.5rem;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.chart-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.chart-title {
  font-size: 1.25rem;
  font-weight: bold;
  color: #333;
  margin: 0;
}

.chart-controls {
  display: flex;
  gap: 8px;
}

.control-btn {
  padding: 6px 12px;
  background: #f0f0f0;
  border: 1px solid #ddd;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s;
}

.control-btn:hover {
  background: #e0e0e0;
  border-color: #999;
}

.chart-canvas {
  max-height: v-bind(height);
  min-height: 200px;
}

.chart-loading {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  display: flex;
  flex-direction: column;
  align-items: center;
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

.chart-error {
  padding: 1rem;
  background-color: #fee;
  border: 1px solid #fcc;
  border-radius: 4px;
  color: #c33;
  margin-top: 1rem;
}

.chart-error p {
  margin: 0;
  font-size: 14px;
}
</style>
