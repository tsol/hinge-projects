import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import hingePlugin from 'hinge/plugin'

export default defineConfig({
  plugins: [
    vue(),
    hingePlugin(),
  ],
  server: {
    cors: true,
    allowedHosts: ['.trycloudflare.com', '.loca.lt', 'localhost', '127.0.0.1'],
    hmr: false,
    fs: { strict: false },
  },
})
