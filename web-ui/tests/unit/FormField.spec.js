import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import FormField from '@/components/FormField.vue'

describe('FormField.vue', () => {
  let wrapper

  const createWrapper = (props = {}) => {
    return mount(FormField, {
      props: {
        field: {
          name: 'testField',
          label: 'Test Field',
          type: 'text',
          required: false,
          default: '',
          help: 'Test help text',
          ...props.field
        },
        modelValue: props.modelValue || ''
      }
    })
  }

  describe('Text Input', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        field: { type: 'text', placeholder: 'Enter text' }
      })
    })

    it('renders text input', () => {
      const input = wrapper.find('input[type="text"]')
      expect(input.exists()).toBe(true)
    })

    it('displays label', () => {
      const label = wrapper.find('label')
      expect(label.text()).toContain('Test Field')
    })

    it('displays help text', () => {
      const help = wrapper.find('.form-field-wrapper')
      expect(wrapper.html()).toContain('Test help text')
    })

    it('updates v-model on input', async () => {
      const input = wrapper.find('input[type="text"]')
      await input.setValue('test value')
      expect(wrapper.emitted('update:modelValue')[0]).toEqual(['test value'])
    })

    it('shows placeholder', () => {
      const input = wrapper.find('input[type="text"]')
      expect(input.attributes('placeholder')).toBe('Enter text')
    })
  })

  describe('Number Input', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        field: {
          type: 'number',
          min: 0,
          max: 100,
          step: 5,
          default: 50
        },
        modelValue: 50
      })
    })

    it('renders number input', () => {
      const input = wrapper.find('input[type="number"]')
      expect(input.exists()).toBe(true)
    })

    it('applies min/max/step constraints', () => {
      const input = wrapper.find('input[type="number"]')
      expect(input.attributes('min')).toBe('0')
      expect(input.attributes('max')).toBe('100')
      expect(input.attributes('step')).toBe('5')
    })

    it('validates min value', async () => {
      const input = wrapper.find('input[type="number"]')
      await input.setValue(-10)
      wrapper.vm.validateField()
      expect(wrapper.vm.error).toContain('Minimum value is 0')
    })

    it('validates max value', async () => {
      const input = wrapper.find('input[type="number"]')
      await input.setValue(150)
      wrapper.vm.validateField()
      expect(wrapper.vm.error).toContain('Maximum value is 100')
    })
  })

  describe('Select Dropdown', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        field: {
          type: 'select',
          options: ['Option 1', 'Option 2', 'Option 3']
        }
      })
    })

    it('renders select element', () => {
      const select = wrapper.find('select')
      expect(select.exists()).toBe(true)
    })

    it('renders all options', () => {
      const options = wrapper.findAll('option')
      expect(options.length).toBe(4) // placeholder + 3 options
    })

    it('updates v-model on selection', async () => {
      const select = wrapper.find('select')
      await select.setValue('Option 2')
      expect(wrapper.emitted('update:modelValue')[0]).toEqual(['Option 2'])
    })

    it('disables when no options available', async () => {
      const newWrapper = createWrapper({
        field: {
          type: 'select',
          options: []
        }
      })
      const select = newWrapper.find('select')
      expect(select.attributes('disabled')).toBeDefined()
    })
  })

  describe('Checkbox', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        field: { type: 'checkbox' }
      })
    })

    it('renders checkbox input', () => {
      const input = wrapper.find('input[type="checkbox"]')
      expect(input.exists()).toBe(true)
    })

    it('toggles checkbox value', async () => {
      const input = wrapper.find('input[type="checkbox"]')
      await input.setValue(true)
      expect(wrapper.emitted('update:modelValue')[0]).toEqual([true])
    })
  })

  describe('Validation', () => {
    it('validates required field', async () => {
      wrapper = createWrapper({
        field: { type: 'text', required: true },
        modelValue: ''
      })
      wrapper.vm.validateField()
      expect(wrapper.vm.error).toContain('is required')
    })

    it('accepts valid required field', async () => {
      wrapper = createWrapper({
        field: { type: 'text', required: true },
        modelValue: 'valid text'
      })
      wrapper.vm.validateField()
      expect(wrapper.vm.error).toBe('')
    })

    it('uses custom validator if provided', async () => {
      wrapper = createWrapper({
        field: {
          type: 'text',
          validator: (value) => {
            return value.includes('@') ? true : 'Must include @'
          }
        },
        modelValue: 'invalid'
      })
      wrapper.vm.validateField()
      expect(wrapper.vm.error).toBe('Must include @')
    })

    it('emits validate event', async () => {
      wrapper = createWrapper({
        field: { type: 'text' },
        modelValue: 'test'
      })
      wrapper.vm.validateField()
      expect(wrapper.emitted('validate')).toBeDefined()
    })
  })

  describe('Multi-Select', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        field: {
          type: 'multi-select',
          options: ['Option 1', 'Option 2', 'Option 3']
        },
        modelValue: ['Option 1']
      })
    })

    it('renders multi-select component', () => {
      const select = wrapper.find('select')
      expect(select.exists()).toBe(true)
    })

    it('displays selected items as badges', () => {
      const badges = wrapper.findAll('.badge')
      expect(badges.length).toBe(1)
      expect(badges[0].text()).toContain('Option 1')
    })

    it('removes item from selection', async () => {
      const badge = wrapper.find('.badge')
      await badge.find('button').trigger('click')
      expect(wrapper.vm.internalValue).toEqual([])
    })
  })

  describe('Disabled State', () => {
    it('disables input when disabled prop is true', () => {
      wrapper = createWrapper({
        field: { type: 'text', disabled: true }
      })
      const input = wrapper.find('input')
      expect(input.attributes('disabled')).toBeDefined()
    })

    it('applies disabled styling', () => {
      wrapper = createWrapper({
        field: { type: 'text', disabled: true }
      })
      const input = wrapper.find('input')
      expect(input.classes()).toContain('disabled:bg-gray-100')
    })
  })

  describe('Error Display', () => {
    it('displays error message when present', async () => {
      wrapper = createWrapper()
      wrapper.vm.error = 'Test error message'
      await wrapper.vm.$nextTick()
      expect(wrapper.html()).toContain('Test error message')
    })

    it('clears error on input change', async () => {
      wrapper = createWrapper({
        field: { type: 'text', required: true }
      })
      wrapper.vm.error = 'Initial error'
      const input = wrapper.find('input')
      await input.setValue('new value')
      expect(wrapper.vm.error).toBe('')
    })
  })
})
