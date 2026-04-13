<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="text-2xl font-bold text-gray-800">New Analysis</h2>
        <button @click="$emit('close')" class="text-gray-600 hover:text-gray-800">✕</button>
      </div>

      <div class="modal-body space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Operation</label>
          <select v-model="selectedOp" class="w-full px-3 py-2 border border-gray-300 rounded">
            <optgroup label="Spatial Operations">
              <option value="buffer">Buffer</option>
              <option value="clip">Clip</option>
              <option value="dissolve">Dissolve</option>
              <option value="intersect">Intersect</option>
              <option value="union">Union</option>
              <option value="reproject">Reproject</option>
            </optgroup>
            <optgroup label="Statistical Methods">
              <option value="hotspot_analysis">Hotspot Analysis</option>
              <option value="cluster_analysis">Cluster Analysis</option>
              <option value="spatial_autocorrelation">Spatial Autocorrelation</option>
              <option value="kriging">Kriging Interpolation</option>
            </optgroup>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Async Job?</label>
          <label class="flex items-center gap-2">
            <input v-model="isAsync" type="checkbox" />
            <span class="text-sm text-gray-700">Submit as background job</span>
          </label>
        </div>
      </div>

      <div class="modal-footer">
        <button
          @click="$emit('close')"
          class="px-4 py-2 text-gray-700 border border-gray-300 rounded hover:bg-gray-50 transition"
        >
          Cancel
        </button>
        <button
          @click="handleSubmit"
          :disabled="!selectedOp"
          class="px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded transition"
        >
          Continue
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAppStore } from '@/stores/app'

const emit = defineEmits(['close'])
const appStore = useAppStore()

const selectedOp = ref('buffer')
const isAsync = ref(false)

function handleSubmit() {
  appStore.selectedOperation = selectedOp.value
  appStore.setCurrentPage('analysis')
  emit('close')
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 50;
}

.modal-content {
  background: white;
  border-radius: 0.5rem;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  width: 90%;
  max-width: 400px;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.5rem;
  border-bottom: 1px solid #e5e7eb;
}

.modal-body {
  padding: 1.5rem;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 1.5rem;
  border-top: 1px solid #e5e7eb;
}
</style>
