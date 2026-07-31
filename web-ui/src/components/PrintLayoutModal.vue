<template>
  <div class="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-[200]">
    <div class="bg-gray-100 w-[95vw] h-[95vh] rounded-lg shadow-2xl flex flex-col overflow-hidden">
      <!-- Header -->
      <div class="px-6 py-4 bg-white border-b border-gray-200 flex justify-between items-center shrink-0">
        <h2 class="text-xl font-bold text-gray-800 flex items-center gap-2">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 17h2a2 2 0 002-2v-4a2 2 0 00-2-2H5a2 2 0 00-2 2v4a2 2 0 002 2h2m2 4h6a2 2 0 002-2v-4a2 2 0 00-2-2H9a2 2 0 00-2 2v4a2 2 0 002 2zm8-12V5a2 2 0 00-2-2H9a2 2 0 00-2 2v4h10z"></path></svg>
          Print Layout Designer
        </h2>
        <div class="flex items-center gap-3">
          <select v-model="exportFormat" class="border border-gray-300 rounded px-3 py-1.5 text-sm bg-white">
            <option value="pdf">PDF Document</option>
            <option value="png">PNG Image</option>
            <option value="jpeg">JPEG Image</option>
          </select>
          <button @click="exportLayout" :disabled="isExporting" class="px-4 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded font-medium text-sm transition flex items-center gap-2 disabled:opacity-50">
            <svg v-if="isExporting" class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>
            {{ isExporting ? 'Exporting...' : 'Export' }}
          </button>
          <button @click="$emit('close')" class="p-1.5 text-gray-500 hover:text-gray-800 hover:bg-gray-200 rounded transition ml-2">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
          </button>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <!-- Toolbar Sidebar -->
        <div class="w-64 bg-white border-r border-gray-200 flex flex-col shadow-sm shrink-0 overflow-y-auto">
          <div class="p-4 border-b border-gray-100">
            <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Add Elements</h3>
            <div class="grid grid-cols-2 gap-2">
              <button @click="addElement('map')" class="flex flex-col items-center justify-center p-3 border border-gray-200 rounded hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition gap-1 group">
                <svg class="w-6 h-6 text-gray-400 group-hover:text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"></path></svg>
                <span class="text-xs font-medium">Map</span>
              </button>
              <button @click="addElement('title')" class="flex flex-col items-center justify-center p-3 border border-gray-200 rounded hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition gap-1 group">
                <svg class="w-6 h-6 text-gray-400 group-hover:text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path></svg>
                <span class="text-xs font-medium">Text</span>
              </button>
              <button @click="addElement('legend')" class="flex flex-col items-center justify-center p-3 border border-gray-200 rounded hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition gap-1 group">
                <svg class="w-6 h-6 text-gray-400 group-hover:text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"></path></svg>
                <span class="text-xs font-medium">Legend</span>
              </button>
              <button @click="addElement('scale')" class="flex flex-col items-center justify-center p-3 border border-gray-200 rounded hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition gap-1 group">
                <svg class="w-6 h-6 text-gray-400 group-hover:text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h16v4m-16 0v12a2 2 0 002 2h12a2 2 0 002-2V8"></path></svg>
                <span class="text-xs font-medium">Scale</span>
              </button>
              <button @click="addElement('image')" class="flex flex-col items-center justify-center p-3 border border-gray-200 rounded hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition gap-1 group">
                <svg class="w-6 h-6 text-gray-400 group-hover:text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>
                <span class="text-xs font-medium">Image</span>
              </button>
            </div>
          </div>

          <!-- Properties Panel -->
          <div v-if="selectedElementIndex !== null" class="p-4 flex-1">
            <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3 flex items-center justify-between">
              Properties
              <button @click="removeElement(selectedElementIndex)" class="text-red-500 hover:bg-red-50 p-1 rounded transition text-xs flex items-center">
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path></svg>
                Delete
              </button>
            </h3>

            <div class="space-y-4">
              <!-- Text Properties -->
              <div v-if="selectedElement.type === 'title'">
                <label class="block text-xs font-medium text-gray-700 mb-1">Text Content</label>
                <textarea v-model="selectedElement.content" rows="3" class="w-full p-2 border border-gray-300 rounded text-sm"></textarea>

                <label class="block text-xs font-medium text-gray-700 mb-1 mt-3">Font Size</label>
                <input type="number" v-model.number="selectedElement.style.fontSize" class="w-full p-1.5 border border-gray-300 rounded text-sm">

                <label class="block text-xs font-medium text-gray-700 mb-1 mt-3">Color</label>
                <input type="color" v-model="selectedElement.style.color" class="h-8 w-full rounded cursor-pointer p-0 border-0">

                <label class="block text-xs font-medium text-gray-700 mb-1 mt-3">Alignment</label>
                <select v-model="selectedElement.style.textAlign" class="w-full p-1.5 border border-gray-300 rounded text-sm">
                  <option value="left">Left</option>
                  <option value="center">Center</option>
                  <option value="right">Right</option>
                </select>
              </div>

              <!-- Map Properties -->
              <div v-if="selectedElement.type === 'map'">
                <div class="text-sm text-gray-600 mb-2">Map snapshot is bound to current Map Studio view.</div>
                <button @click="$emit('request-snapshot')" class="w-full py-1.5 bg-gray-200 hover:bg-gray-300 text-gray-800 rounded text-sm font-medium transition">
                  Refresh Snapshot
                </button>

                <label class="block text-xs font-medium text-gray-700 mb-1 mt-3">Border</label>
                <div class="flex items-center gap-2">
                  <input type="checkbox" v-model="selectedElement.style.hasBorder" class="rounded text-blue-600 focus:ring-blue-500">
                  <span class="text-sm">Show Frame</span>
                </div>
              </div>

              <!-- Legend Properties -->
              <div v-if="selectedElement.type === 'legend'">
                <label class="block text-xs font-medium text-gray-700 mb-1">Title</label>
                <input type="text" v-model="selectedElement.content.title" class="w-full p-1.5 border border-gray-300 rounded text-sm">
              </div>

              <!-- Image Properties -->
              <div v-if="selectedElement.type === 'image'">
                <label class="block text-xs font-medium text-gray-700 mb-1">Image URL</label>
                <input type="text" v-model="selectedElement.content.url" placeholder="https://example.com/logo.png" class="w-full p-1.5 border border-gray-300 rounded text-sm">
              </div>
            </div>
          </div>
          <div v-else class="p-6 text-center text-sm text-gray-400 italic">
            Select an element on the canvas to edit its properties.
          </div>
        </div>

        <!-- Canvas Area -->
        <div class="flex-1 bg-gray-200 overflow-auto p-8 flex justify-center" @click.self="selectedElementIndex = null">
          <!-- The Page -->
          <div
            id="print-layout-canvas"
            class="bg-white shadow-xl relative"
            :style="{ width: '800px', height: '1131px' }"
            @click.self="selectedElementIndex = null"
          >
            <!-- Render Elements -->
            <div
              v-for="(el, index) in elements"
              :key="el.id"
              class="absolute group select-none cursor-move"
              :class="{'ring-2 ring-blue-500 ring-offset-1 z-50': selectedElementIndex === index, 'hover:ring-1 hover:ring-blue-300': selectedElementIndex !== index}"
              :style="{
                left: `${el.x}px`,
                top: `${el.y}px`,
                width: el.width ? `${el.width}px` : 'auto',
                height: el.height ? `${el.height}px` : 'auto',
                zIndex: el.z || 10
              }"
              @mousedown="startDrag($event, index)"
              @click.stop="selectedElementIndex = index"
            >

              <!-- Map Element -->
              <div v-if="el.type === 'map'" class="w-full h-full" :class="{'border-2 border-gray-800': el.style.hasBorder}">
                <img v-if="mapSnapshotData" :src="mapSnapshotData" class="w-full h-full object-cover pointer-events-none" />
                <div v-else class="w-full h-full bg-blue-50 flex items-center justify-center border border-blue-200 text-blue-400 text-sm">
                  [Map Snapshot Loading...]
                </div>
              </div>

              <!-- Text Element -->
              <div v-else-if="el.type === 'title'"
                   class="w-full h-full p-2 whitespace-pre-wrap break-words"
                   :style="{
                     fontSize: `${el.style.fontSize}px`,
                     color: el.style.color,
                     textAlign: el.style.textAlign,
                     fontWeight: el.style.bold ? 'bold' : 'normal'
                   }">
                {{ el.content || 'Double click to edit' }}
              </div>

              <!-- Legend Element -->
              <div v-else-if="el.type === 'legend'" class="bg-white border border-gray-300 p-4 shadow-sm w-full h-full">
                <h4 class="font-bold text-sm mb-2">{{ el.content.title }}</h4>
                <div v-if="legendData" class="space-y-1">
                  <div class="text-xs text-gray-500 mb-2">Based on: {{ legendData.property }}</div>
                  <div class="h-3 w-full bg-gradient-to-r from-blue-100 to-blue-800 border border-gray-200 rounded-sm"></div>
                  <div class="flex justify-between text-[10px] text-gray-600 mt-1">
                    <span>Low</span>
                    <span>High</span>
                  </div>
                </div>
                <div v-else class="text-xs text-gray-400 italic">No active data styling.</div>
              </div>

              <!-- Scale Bar Element -->
              <div v-else-if="el.type === 'scale'" class="p-2 w-full h-full flex flex-col justify-end">
                <div class="border-b-2 border-l-2 border-r-2 border-gray-800 h-2 w-full flex justify-between items-end pb-1 relative">
                  <span class="text-[10px] font-medium absolute bottom-3 left-0">0</span>
                  <span class="text-[10px] font-medium absolute bottom-3 right-0">50 km</span>
                </div>
              </div>

              <!-- Image Element -->
              <div v-else-if="el.type === 'image'" class="w-full h-full flex items-center justify-center bg-gray-50 border border-gray-200">
                <img v-if="el.content && el.content.url" :src="el.content.url" class="max-w-full max-h-full object-contain pointer-events-none" @error="el.content.url = ''" />
                <span v-else class="text-xs text-gray-400">Placeholder Image</span>
              </div>

              <!-- Resize Handle -->
              <div v-if="selectedElementIndex === index"
                   class="absolute bottom-0 right-0 w-3 h-3 bg-blue-500 cursor-se-resize rounded-tl shadow"
                   @mousedown.stop="startResize($event, index)">
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAppStore } from '@/stores/app'
import html2canvas from 'html2canvas'
import jsPDF from 'jspdf'

const props = defineProps({
  mapSnapshotData: {
    type: String,
    default: ''
  },
  legendData: {
    type: Object,
    default: null
  }
})

const emit = defineEmits(['close', 'request-snapshot'])
const appStore = useAppStore()

const exportFormat = ref('pdf')
const isExporting = ref(false)

// Layout Elements State
const elements = ref([
  // Initial default layout
  {
    id: 'title_1',
    type: 'title',
    x: 40, y: 40, width: 720, height: 60, z: 20,
    content: 'GeoSpatial Analysis Report',
    style: { fontSize: 32, color: '#1f2937', textAlign: 'center', bold: true }
  },
  {
    id: 'map_1',
    type: 'map',
    x: 40, y: 120, width: 720, height: 750, z: 10,
    style: { hasBorder: true }
  },
  {
    id: 'legend_1',
    type: 'legend',
    x: 60, y: 720, width: 200, height: 120, z: 30,
    content: { title: 'Legend' },
    style: {}
  }
])

const selectedElementIndex = ref(null)
const selectedElement = computed(() =>
  selectedElementIndex.value !== null ? elements.value[selectedElementIndex.value] : null
)

// Add new element to canvas
const addElement = (type) => {
  const base = { id: `${type}_${Date.now()}`, type, x: 100, y: 100, z: 50, style: {} }

  if (type === 'title') {
    elements.value.push({ ...base, width: 300, height: 50, content: 'New Text Block', style: { fontSize: 16, color: '#000000', textAlign: 'left', bold: false } })
  } else if (type === 'map') {
    elements.value.push({ ...base, width: 400, height: 300, style: { hasBorder: true } })
  } else if (type === 'legend') {
    elements.value.push({ ...base, width: 200, height: 120, content: { title: 'Legend' } })
  } else if (type === 'scale') {
    elements.value.push({ ...base, width: 150, height: 40 })
  } else if (type === 'image') {
    elements.value.push({ ...base, width: 150, height: 150, content: { url: '' } })
  }

  selectedElementIndex.value = elements.value.length - 1
}

const removeElement = (index) => {
  elements.value.splice(index, 1)
  selectedElementIndex.value = null
}

// Drag & Drop / Resizing Logic
let isDragging = false
let isResizing = false
let startX, startY, startElX, startElY, startWidth, startHeight

const startDrag = (e, index) => {
  if (isResizing) return
  isDragging = true
  selectedElementIndex.value = index
  startX = e.clientX
  startY = e.clientY
  startElX = elements.value[index].x
  startElY = elements.value[index].y

  window.addEventListener('mousemove', onDrag)
  window.addEventListener('mouseup', stopDrag)
}

const onDrag = (e) => {
  if (!isDragging || selectedElementIndex.value === null) return
  const dx = e.clientX - startX
  const dy = e.clientY - startY

  // Snap to grid (10px) could be added here
  elements.value[selectedElementIndex.value].x = Math.max(0, startElX + dx)
  elements.value[selectedElementIndex.value].y = Math.max(0, startElY + dy)
}

const stopDrag = () => {
  isDragging = false
  window.removeEventListener('mousemove', onDrag)
  window.removeEventListener('mouseup', stopDrag)
}

const startResize = (e, index) => {
  e.stopPropagation()
  isResizing = true
  selectedElementIndex.value = index
  startX = e.clientX
  startY = e.clientY
  startWidth = elements.value[index].width
  startHeight = elements.value[index].height

  window.addEventListener('mousemove', onResize)
  window.addEventListener('mouseup', stopResize)
}

const onResize = (e) => {
  if (!isResizing || selectedElementIndex.value === null) return
  const dx = e.clientX - startX
  const dy = e.clientY - startY

  elements.value[selectedElementIndex.value].width = Math.max(50, startWidth + dx)
  elements.value[selectedElementIndex.value].height = Math.max(30, startHeight + dy)
}

const stopResize = () => {
  isResizing = false
  window.removeEventListener('mousemove', onResize)
  window.removeEventListener('mouseup', stopResize)
}

// Export logic
const exportLayout = async () => {
  try {
    isExporting.value = true
    const canvasEl = document.getElementById('print-layout-canvas')

    // Temporarily deselect to hide resize handles and borders
    const cachedIndex = selectedElementIndex.value
    selectedElementIndex.value = null

    // Allow Vue to render the deselected state
    // import { nextTick } from 'vue' -> will use nextTick and small delay
    await new Promise(r => setTimeout(r, 100))

    const canvas = await html2canvas(canvasEl, {
      scale: 2, // High resolution
      useCORS: true,
      logging: false,
      backgroundColor: '#ffffff'
    })

    // Restore selection
    selectedElementIndex.value = cachedIndex

    const imgData = canvas.toDataURL(`image/${exportFormat.value === 'jpeg' ? 'jpeg' : 'png'}`, 1.0)

    if (exportFormat.value === 'pdf') {
      // A4 Size in mm: 210 x 297
      const pdf = new jsPDF('p', 'mm', 'a4')
      const pdfWidth = pdf.internal.pageSize.getWidth()
      const pdfHeight = (canvas.height * pdfWidth) / canvas.width

      pdf.addImage(imgData, 'PNG', 0, 0, pdfWidth, pdfHeight)
      pdf.save('GeoSpatial_Map_Layout.pdf')
    } else {
      // Download as Image
      const link = document.createElement('a')
      link.download = `GeoSpatial_Map_Layout.${exportFormat.value}`
      link.href = imgData
      link.click()
    }

    appStore.addNotification(`Layout exported successfully as ${exportFormat.value.toUpperCase()}`, 'success')
  } catch (error) {
    console.error("Export failed:", error)
    appStore.addNotification('Failed to export layout. Check console for details.', 'error')
  } finally {
    isExporting.value = false
  }
}

onMounted(() => {
  // If no snapshot provided immediately, request one
  if (!props.mapSnapshotData) {
    emit('request-snapshot')
  }
})
</script>

<style scoped>
/* Disable scrolling on body while modal is open */
:global(body) {
  overflow: hidden;
}
</style>
