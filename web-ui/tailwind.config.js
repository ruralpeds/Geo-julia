/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#2563eb',
        secondary: '#7c3aed',
        danger: '#dc2626',
        success: '#16a34a',
        warning: '#ea580c',
        info: '#0891b2'
      },
      spacing: {
        '128': '32rem',
        '144': '36rem'
      },
      fontSize: {
        xs: ['0.75rem', { lineHeight: '1rem' }],
        sm: ['0.875rem', { lineHeight: '1.25rem' }],
        base: ['1rem', { lineHeight: '1.5rem' }],
        lg: ['1.125rem', { lineHeight: '1.75rem' }],
        xl: ['1.25rem', { lineHeight: '1.75rem' }],
        '2xl': ['1.5rem', { lineHeight: '2rem' }],
        '3xl': ['1.875rem', { lineHeight: '2.25rem' }],
        '4xl': ['2.25rem', { lineHeight: '2.5rem' }]
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          '"Helvetica Neue"',
          'Arial',
          'sans-serif'
        ]
      },
      animation: {
        spin: 'spin 1s linear infinite',
        pulse: 'pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        bounce: 'bounce 1s infinite',
        slideIn: 'slideIn 0.3s ease-out',
        fadeIn: 'fadeIn 0.3s ease-out'
      },
      keyframes: {
        slideIn: {
          from: { transform: 'translateX(-100%)', opacity: '0' },
          to: { transform: 'translateX(0)', opacity: '1' }
        },
        fadeIn: {
          from: { opacity: '0' },
          to: { opacity: '1' }
        }
      }
    }
  },
  plugins: [
    // Custom plugin for component utilities
    function ({ addComponents, theme }) {
      addComponents({
        // Button variants
        '.btn': {
          '@apply px-4 py-2 rounded-lg font-medium transition duration-200': {}
        },
        '.btn-primary': {
          '@apply bg-blue-600 text-white hover:bg-blue-700': {}
        },
        '.btn-secondary': {
          '@apply bg-gray-200 text-gray-800 hover:bg-gray-300': {}
        },
        '.btn-danger': {
          '@apply bg-red-600 text-white hover:bg-red-700': {}
        },
        '.btn-success': {
          '@apply bg-green-600 text-white hover:bg-green-700': {}
        },
        '.btn:disabled': {
          '@apply bg-gray-400 cursor-not-allowed': {}
        },

        // Card variants
        '.card': {
          '@apply bg-white rounded-lg shadow-md p-6': {}
        },
        '.card-sm': {
          '@apply bg-white rounded-lg shadow-sm p-4': {}
        },

        // Badge variants
        '.badge': {
          '@apply inline-flex items-center px-3 py-1 rounded-full text-sm font-medium': {}
        },
        '.badge-blue': {
          '@apply bg-blue-100 text-blue-800': {}
        },
        '.badge-green': {
          '@apply bg-green-100 text-green-800': {}
        },
        '.badge-red': {
          '@apply bg-red-100 text-red-800': {}
        },
        '.badge-yellow': {
          '@apply bg-yellow-100 text-yellow-800': {}
        },

        // Alert variants
        '.alert': {
          '@apply px-4 py-3 rounded-lg': {}
        },
        '.alert-success': {
          '@apply bg-green-50 text-green-800 border border-green-200': {}
        },
        '.alert-error': {
          '@apply bg-red-50 text-red-800 border border-red-200': {}
        },
        '.alert-warning': {
          '@apply bg-yellow-50 text-yellow-800 border border-yellow-200': {}
        },
        '.alert-info': {
          '@apply bg-blue-50 text-blue-800 border border-blue-200': {}
        },

        // Input variants
        '.input': {
          '@apply w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition': {}
        },
        '.input:disabled': {
          '@apply bg-gray-100 text-gray-500 cursor-not-allowed': {}
        }
      })
    }
  ]
}
