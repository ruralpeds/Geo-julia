<template>
  <div class="form-field-wrapper">
    <!-- Label -->
    <label v-if="field.label" :for="fieldId" class="block text-sm font-medium text-gray-700 mb-1">
      {{ field.label }}
      <span v-if="field.required" class="text-red-500">*</span>
    </label>

    <!-- Help Text (above input) -->
    <p v-if="field.help" class="text-xs text-gray-500 mb-2">{{ field.help }}</p>

    <!-- Input Components -->
    <!-- Text Input -->
    <input
      v-if="field.type === 'text'"
      :id="fieldId"
      v-model="internalValue"
      type="text"
      :placeholder="field.placeholder"
      :disabled="field.disabled"
      class="input-field"
      @blur="validateField"
    />

    <!-- Number Input -->
    <input
      v-else-if="field.type === 'number'"
      :id="fieldId"
      v-model.number="internalValue"
      type="number"
      :min="field.min"
      :max="field.max"
      :step="field.step || 1"
      :disabled="field.disabled"
      class="input-field"
      @blur="validateField"
    />

    <!-- Range Slider -->
    <div v-else-if="field.type === 'range'" class="range-wrapper">
      <input
        :id="fieldId"
        v-model.number="internalValue"
        type="range"
        :min="field.min"
        :max="field.max"
        :step="field.step || 0.01"
        :disabled="field.disabled"
        class="range-slider"
      />
      <span class="range-value">{{ internalValue }}{{ field.unit ? ' ' + field.unit : '' }}</span>
    </div>

    <!-- Select Dropdown -->
    <select
      v-else-if="field.type === 'select'"
      :id="fieldId"
      v-model="internalValue"
      :disabled="field.disabled || !field.options?.length"
      class="input-field"
      @change="validateField"
    >
      <option value="">-- Select {{ field.label }} --</option>
      <option v-for="option in field.options" :key="option" :value="option">
        {{ formatOption(option) }}
      </option>
    </select>

    <!-- Multi-Select -->
    <div v-else-if="field.type === 'multi-select'" class="multi-select-wrapper">
      <div class="selected-items mb-2 flex flex-wrap gap-1">
        <span v-for="item in internalValue" :key="item" class="badge">
          {{ formatOption(item) }}
          <button
            type="button"
            @click="removeFromSelection(item)"
            class="ml-1 text-red-500 hover:text-red-700"
          >
            ✕
          </button>
        </span>
      </div>
      <select
        :id="fieldId"
        :disabled="field.disabled || !field.options?.length"
        class="input-field"
        @change="addToSelection"
      >
        <option value="">-- Add {{ field.label }} --</option>
        <option v-for="option in availableOptions" :key="option" :value="option">
          {{ formatOption(option) }}
        </option>
      </select>
    </div>

    <!-- Checkbox -->
    <div v-else-if="field.type === 'checkbox'" class="checkbox-wrapper">
      <input
        :id="fieldId"
        v-model="internalValue"
        type="checkbox"
        :disabled="field.disabled"
        class="checkbox-input"
      />
      <label :for="fieldId" class="ml-2 text-sm text-gray-700">
        {{ field.checkboxLabel || field.label }}
      </label>
    </div>

    <!-- Textarea -->
    <textarea
      v-else-if="field.type === 'textarea'"
      :id="fieldId"
      v-model="internalValue"
      :placeholder="field.placeholder"
      :disabled="field.disabled"
      :rows="field.rows || 4"
      class="input-field"
      @blur="validateField"
    />

    <!-- Error Message -->
    <p v-if="error" class="text-xs text-red-500 mt-1">{{ error }}</p>

    <!-- Unit Display -->
    <p v-if="field.unit && field.type !== 'range'" class="text-xs text-gray-500 mt-1">
      Unit: {{ field.unit }}
    </p>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'

const props = defineProps({
  field: {
    type: Object,
    required: true
  },
  modelValue: {
    type: [String, Number, Boolean, Array],
    default: null
  }
})

const emit = defineEmits(['update:modelValue', 'validate'])

const internalValue = ref(props.modelValue ?? props.field.default ?? '')
const error = ref('')
const fieldId = computed(() => `field_${props.field.name}_${Date.now()}`)

// Watch for external value changes
watch(
  () => props.modelValue,
  (newVal) => {
    if (newVal !== undefined) {
      internalValue.value = newVal
    }
  }
)

// Watch for internal changes
watch(internalValue, (newVal) => {
  emit('update:modelValue', newVal)
  error.value = ''
})

// Multi-select helpers
const availableOptions = computed(() => {
  if (props.field.type !== 'multi-select') return []
  return props.field.options?.filter(opt => !internalValue.value?.includes(opt)) || []
})

function addToSelection(event) {
  const value = event.target.value
  if (value) {
    const selected = Array.isArray(internalValue.value) ? internalValue.value : []
    internalValue.value = [...selected, value]
    event.target.value = ''
  }
}

function removeFromSelection(item) {
  internalValue.value = internalValue.value.filter(v => v !== item)
}

// Validation
function validateField() {
  error.value = ''

  // Required validation
  if (props.field.required) {
    if (
      internalValue.value === null ||
      internalValue.value === undefined ||
      internalValue.value === '' ||
      (Array.isArray(internalValue.value) && internalValue.value.length === 0)
    ) {
      error.value = `${props.field.label} is required`
      emit('validate', false)
      return
    }
  }

  // Number validation
  if (props.field.type === 'number' || props.field.type === 'range') {
    if (props.field.min !== undefined && internalValue.value < props.field.min) {
      error.value = `Minimum value is ${props.field.min}`
      emit('validate', false)
      return
    }
    if (props.field.max !== undefined && internalValue.value > props.field.max) {
      error.value = `Maximum value is ${props.field.max}`
      emit('validate', false)
      return
    }
  }

  // Custom validator function
  if (props.field.validator) {
    const result = props.field.validator(internalValue.value)
    if (result !== true) {
      error.value = result
      emit('validate', false)
      return
    }
  }

  emit('validate', true)
}

// Format option display
function formatOption(option) {
  return String(option)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

// Expose validation
defineExpose({ validateField })
</script>

<style scoped>
.form-field-wrapper {
  margin-bottom: 1rem;
}

.input-field {
  @apply w-full px-3 py-2 border border-gray-300 rounded-lg
    focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent
    disabled:bg-gray-100 disabled:text-gray-500 disabled:cursor-not-allowed
    transition duration-200;
}

.range-wrapper {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.range-slider {
  flex: 1;
  height: 6px;
  border-radius: 3px;
  background: #ddd;
  outline: none;
  -webkit-appearance: none;
}

.range-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: #2563eb;
  cursor: pointer;
  transition: background 0.3s ease;
}

.range-slider::-webkit-slider-thumb:hover {
  background: #1d4ed8;
}

.range-slider::-moz-range-thumb {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: #2563eb;
  cursor: pointer;
  border: none;
  transition: background 0.3s ease;
}

.range-slider::-moz-range-thumb:hover {
  background: #1d4ed8;
}

.range-value {
  @apply min-w-20 text-sm font-medium text-gray-700;
}

.multi-select-wrapper {
  border: 1px solid #d1d5db;
  border-radius: 0.5rem;
  padding: 0.5rem;
  background-color: #f9fafb;
}

.badge {
  @apply inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-800 rounded text-sm;
}

.checkbox-wrapper {
  display: flex;
  align-items: center;
}

.checkbox-input {
  @apply w-4 h-4 text-blue-600 rounded border-gray-300
    focus:ring-2 focus:ring-blue-500
    cursor-pointer;
}
</style>
