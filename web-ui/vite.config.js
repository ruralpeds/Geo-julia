import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '')
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true
      }
    },
    // Optimize chunk sizes
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      output: {
        // Code splitting strategy
        manualChunks: {
          // Core framework
          'vendor': ['vue', 'pinia'],
          // Routing
          'router': ['vue-router'],
          // Utilities
          'date-utils': ['date-fns'],
          'http-client': ['axios'],
          // Visualization libraries (lazy load)
          'charts': ['chart.js'],
          'maps': ['leaflet']
        },
        // Optimize entry chunk
        entryFileNames: 'js/[name]-[hash].js',
        chunkFileNames: 'js/[name]-[hash].js',
        assetFileNames: (assetInfo) => {
          const info = assetInfo.name.split('.')
          const ext = info[info.length - 1]
          if (/png|jpe?g|gif|svg/.test(ext)) {
            return `images/[name]-[hash][extname]`
          } else if (/woff|woff2|eot|ttf|otf/.test(ext)) {
            return `fonts/[name]-[hash][extname]`
          } else if (ext === 'css') {
            return `css/[name]-[hash][extname]`
          }
          return `[name]-[hash][extname]`
        }
      },
      // Optimize for tree-shaking
      external: [],
      treeshake: {
        moduleSideEffects: false
      }
    },
    // CSS optimization
    cssCodeSplit: true,
    reportCompressedSize: true,
    // Optimizations
    lib: undefined
  },
  // Optimization settings
  optimizeDeps: {
    include: [
      'vue',
      'pinia',
      'axios',
      'date-fns'
    ],
    exclude: [
      'chart.js',
      'leaflet'
    ]
  }
})
