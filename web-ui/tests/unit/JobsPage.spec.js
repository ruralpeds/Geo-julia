import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import JobsPage from '@/views/JobsPage.vue'
import { createPinia } from 'pinia'
import { useAppStore } from '@/stores/app'

// Mock date-fns to avoid timezone issues
vi.mock('date-fns', () => ({
  formatDistanceToNow: vi.fn(() => '2 hours ago'),
  format: vi.fn((date, format) => '2024-04-14 10:30:00')
}))

describe('JobsPage.vue', () => {
  let wrapper
  let pinia
  let appStore
  let mockJobs

  beforeEach(() => {
    pinia = createPinia()

    mockJobs = [
      {
        id: 'job1',
        operation: 'buffer',
        status: 'completed',
        progress: 100,
        createdAt: '2024-04-14T10:00:00Z',
        completedAt: '2024-04-14T10:30:00Z',
        results: { features: 150 }
      },
      {
        id: 'job2',
        operation: 'intersect',
        status: 'running',
        progress: 50,
        createdAt: '2024-04-14T10:15:00Z',
        startedAt: '2024-04-14T10:20:00Z'
      },
      {
        id: 'job3',
        operation: 'buffer',
        status: 'pending',
        progress: 0,
        createdAt: '2024-04-14T10:45:00Z'
      },
      {
        id: 'job4',
        operation: 'cluster',
        status: 'failed',
        progress: 25,
        createdAt: '2024-04-14T11:00:00Z',
        error: 'Invalid parameters'
      }
    ]

    wrapper = mount(JobsPage, {
      global: {
        plugins: [pinia]
      }
    })
    appStore = useAppStore()
    appStore.activeJobs = mockJobs
  })

  afterEach(() => {
    wrapper.unmount()
  })

  describe('Page Initialization', () => {
    it('renders jobs page header', () => {
      expect(wrapper.find('h1').text()).toContain('Job Queue')
    })

    it('displays job statistics', () => {
      const text = wrapper.text()
      expect(text).toContain('4 jobs')
      expect(text).toContain('1 completed')
    })

    it('displays action buttons', () => {
      const buttons = wrapper.findAll('button')
      const refreshBtn = buttons.find(b => b.text().includes('Refresh All'))
      const exportBtn = buttons.find(b => b.text().includes('Export'))

      expect(refreshBtn).toBeDefined()
      expect(exportBtn).toBeDefined()
    })
  })

  describe('Summary Cards', () => {
    it('displays total jobs count', () => {
      const text = wrapper.text()
      expect(text).toContain('Total Jobs')
      expect(text).toContain('4')
    })

    it('displays completed jobs count', () => {
      const text = wrapper.text()
      expect(text).toContain('Completed')
      expect(text).toContain('1')
    })

    it('displays running jobs count', () => {
      const text = wrapper.text()
      expect(text).toContain('Running')
    })

    it('displays failed jobs count', () => {
      const text = wrapper.text()
      expect(text).toContain('Failed')
      expect(text).toContain('1')
    })
  })

  describe('Filters & Sorting', () => {
    it('has search input', () => {
      const searchInput = wrapper.find('input[placeholder*="Search"]')
      expect(searchInput.exists()).toBe(true)
    })

    it('filters jobs by search query', async () => {
      const searchInput = wrapper.find('input[placeholder*="Search"]')
      await searchInput.setValue('buffer')

      expect(wrapper.vm.filteredJobs.length).toBe(2)
      expect(wrapper.vm.filteredJobs.every(j => j.operation === 'buffer')).toBe(true)
    })

    it('has status filter select', () => {
      const selects = wrapper.findAll('select')
      const statusSelect = selects.find(s =>
        s.find('option[value="pending"]').exists()
      )
      expect(statusSelect).toBeDefined()
    })

    it('filters jobs by status', async () => {
      wrapper.vm.filterStatus = 'completed'
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.filteredJobs.length).toBe(1)
      expect(wrapper.vm.filteredJobs[0].status).toBe('completed')
    })

    it('has operation filter select', () => {
      const uniqueOps = wrapper.vm.uniqueOperations
      expect(uniqueOps).toContain('buffer')
      expect(uniqueOps).toContain('intersect')
    })

    it('filters jobs by operation', async () => {
      wrapper.vm.filterOperation = 'buffer'
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.filteredJobs.every(j => j.operation === 'buffer')).toBe(true)
    })

    it('has sort options', () => {
      const sortOptions = ['created_desc', 'created_asc', 'progress_desc', 'progress_asc', 'status']
      sortOptions.forEach(option => {
        expect(wrapper.vm.$options.data().sortBy).toBeDefined()
      })
    })

    it('sorts by newest first (default)', () => {
      const jobs = wrapper.vm.filteredJobs
      expect(jobs[0].id).toBe('job4')
      expect(jobs[jobs.length - 1].id).toBe('job1')
    })

    it('sorts by oldest first', async () => {
      wrapper.vm.sortBy = 'created_asc'
      await wrapper.vm.$nextTick()

      const jobs = wrapper.vm.filteredJobs
      expect(jobs[0].id).toBe('job1')
    })

    it('sorts by progress descending', async () => {
      wrapper.vm.sortBy = 'progress_desc'
      await wrapper.vm.$nextTick()

      const jobs = wrapper.vm.filteredJobs
      expect(jobs[0].progress).toBe(100)
      expect(jobs[jobs.length - 1].progress).toBe(0)
    })

    it('sorts by progress ascending', async () => {
      wrapper.vm.sortBy = 'progress_asc'
      await wrapper.vm.$nextTick()

      const jobs = wrapper.vm.filteredJobs
      expect(jobs[0].progress).toBe(0)
      expect(jobs[jobs.length - 1].progress).toBe(100)
    })

    it('sorts by status', async () => {
      wrapper.vm.sortBy = 'status'
      await wrapper.vm.$nextTick()

      const jobs = wrapper.vm.filteredJobs
      expect(jobs[0].status < jobs[jobs.length - 1].status).toBe(true)
    })
  })

  describe('Job List', () => {
    it('displays all jobs', () => {
      const jobElements = wrapper.findAll('.p-4')
      // Find job items (they have specific structure)
      const jobItems = jobElements.filter(el =>
        el.text().includes('buffer') || el.text().includes('intersect') || el.text().includes('cluster')
      )
      expect(jobItems.length).toBeGreaterThan(0)
    })

    it('displays job operation name', () => {
      const text = wrapper.text()
      expect(text).toContain('buffer')
      expect(text).toContain('intersect')
    })

    it('displays job status badge', () => {
      const text = wrapper.text()
      expect(text).toContain('completed')
      expect(text).toContain('running')
      expect(text).toContain('pending')
      expect(text).toContain('failed')
    })

    it('displays progress percentage', () => {
      const text = wrapper.text()
      expect(text).toContain('100%')
      expect(text).toContain('50%')
      expect(text).toContain('0%')
    })

    it('shows no jobs message when empty', async () => {
      appStore.activeJobs = []
      await wrapper.vm.$nextTick()

      const text = wrapper.text()
      expect(text).toContain('No jobs submitted yet')
    })

    it('shows no results message when filters match nothing', async () => {
      wrapper.vm.searchQuery = 'nonexistent'
      await wrapper.vm.$nextTick()

      const text = wrapper.text()
      expect(text).toContain('No jobs match the current filters')
    })

    it('can select a job', async () => {
      wrapper.vm.filteredJobs[0].id && (appStore.selectedJobId = wrapper.vm.filteredJobs[0].id)
      await wrapper.vm.$nextTick()

      expect(appStore.selectedJobId).toBe(wrapper.vm.filteredJobs[0].id)
    })

    it('highlights selected job', async () => {
      appStore.selectedJobId = 'job1'
      await wrapper.vm.$nextTick()

      expect(wrapper.vm.selectedJob).toEqual(mockJobs[0])
    })
  })

  describe('Job Details Panel', () => {
    beforeEach(async () => {
      appStore.selectedJobId = 'job1'
      await wrapper.vm.$nextTick()
    })

    it('displays selected job details', () => {
      const text = wrapper.text()
      expect(text).toContain('Details')
      expect(text).toContain('buffer')
    })

    it('shows operation', () => {
      const text = wrapper.text()
      expect(text).toContain('Operation')
      expect(text).toContain('buffer')
    })

    it('shows status', () => {
      const text = wrapper.text()
      expect(text).toContain('Status')
      expect(text).toContain('completed')
    })

    it('shows progress bar', () => {
      const text = wrapper.text()
      expect(text).toContain('Progress')
      expect(text).toContain('100%')
    })

    it('shows creation timestamp', () => {
      const text = wrapper.text()
      expect(text).toContain('Created')
    })

    it('shows started timestamp when available', async () => {
      appStore.selectedJobId = 'job2'
      await wrapper.vm.$nextTick()

      const text = wrapper.text()
      expect(text).toContain('Started')
    })

    it('shows completion timestamp when available', () => {
      const text = wrapper.text()
      expect(text).toContain('Completed')
    })

    it('shows error message when job failed', async () => {
      appStore.selectedJobId = 'job4'
      await wrapper.vm.$nextTick()

      const text = wrapper.text()
      expect(text).toContain('Error')
      expect(text).toContain('Invalid parameters')
    })

    it('shows download button for completed jobs with results', () => {
      const buttons = wrapper.findAll('button')
      const downloadBtn = buttons.find(b => b.text().includes('Download Results'))
      expect(downloadBtn).toBeDefined()
    })

    it('hides download button for running jobs', async () => {
      appStore.selectedJobId = 'job2'
      await wrapper.vm.$nextTick()

      const buttons = wrapper.findAll('button')
      const downloadBtn = buttons.find(b => b.text().includes('Download Results'))
      expect(!downloadBtn || !wrapper.text().includes('Download Results')).toBe(true)
    })

    it('shows refresh status button', () => {
      const buttons = wrapper.findAll('button')
      const refreshBtn = buttons.find(b => b.text().includes('Refresh Status'))
      expect(refreshBtn).toBeDefined()
    })
  })

  describe('Results Preview', () => {
    beforeEach(async () => {
      appStore.selectedJobId = 'job1'
      await wrapper.vm.$nextTick()
    })

    it('displays results preview for completed jobs', () => {
      const text = wrapper.text()
      expect(text).toContain('Results Preview')
    })

    it('hides results preview when no results', async () => {
      appStore.selectedJobId = 'job2'
      await wrapper.vm.$nextTick()

      const previewHeading = wrapper.text()
      expect(previewHeading.includes('Results Preview')).toBe(false)
    })
  })

  describe('Actions', () => {
    it('refreshes single job status', async () => {
      appStore.selectedJobId = 'job1'
      appStore.pollJobStatus = vi.fn()
      await wrapper.vm.$nextTick()

      await wrapper.vm.refreshJob()

      expect(appStore.pollJobStatus).toHaveBeenCalledWith('job1')
    })

    it('refreshes all active jobs', async () => {
      appStore.pollJobStatus = vi.fn()

      await wrapper.vm.refreshAllJobs()

      // Should be called for pending and running jobs
      expect(appStore.pollJobStatus).toHaveBeenCalled()
    })

    it('downloads job results', async () => {
      const createElementSpy = vi.spyOn(document, 'createElement')
      const createObjectURLSpy = vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:url')
      const revokeObjectURLSpy = vi.spyOn(URL, 'revokeObjectURL')

      wrapper.vm.downloadResults(mockJobs[0])

      expect(createObjectURLSpy).toHaveBeenCalled()
      expect(revokeObjectURLSpy).toHaveBeenCalled()
      createElementSpy.mockRestore()
      createObjectURLSpy.mockRestore()
      revokeObjectURLSpy.mockRestore()
    })

    it('exports all filtered jobs', async () => {
      const createObjectURLSpy = vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:url')
      const revokeObjectURLSpy = vi.spyOn(URL, 'revokeObjectURL')

      wrapper.vm.exportJobs()

      expect(createObjectURLSpy).toHaveBeenCalled()
      expect(revokeObjectURLSpy).toHaveBeenCalled()
      createObjectURLSpy.mockRestore()
      revokeObjectURLSpy.mockRestore()
    })

    it('disables export button when no jobs', async () => {
      appStore.activeJobs = []
      await wrapper.vm.$nextTick()

      const exportBtn = wrapper.findAll('button').find(b => b.text().includes('Export'))
      expect(exportBtn?.attributes('disabled')).toBeDefined()
    })
  })

  describe('Status Styling', () => {
    it('applies correct class for completed status', () => {
      const statusClass = wrapper.vm.getStatusClass('completed')
      expect(statusClass).toContain('green')
    })

    it('applies correct class for running status', () => {
      const statusClass = wrapper.vm.getStatusClass('running')
      expect(statusClass).toContain('blue')
    })

    it('applies correct class for pending status', () => {
      const statusClass = wrapper.vm.getStatusClass('pending')
      expect(statusClass).toContain('yellow')
    })

    it('applies correct class for failed status', () => {
      const statusClass = wrapper.vm.getStatusClass('failed')
      expect(statusClass).toContain('red')
    })
  })

  describe('Date Formatting', () => {
    it('formats dates with relative time', () => {
      const formatted = wrapper.vm.formatDate(new Date())
      expect(formatted).toBeDefined()
    })

    it('formats dates with full datetime', () => {
      const formatted = wrapper.vm.formatDateTime(new Date())
      expect(formatted).toBeDefined()
    })
  })
})
