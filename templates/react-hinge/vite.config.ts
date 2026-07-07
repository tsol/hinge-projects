import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import hingePlugin from 'hinge/plugin'

export default defineConfig({
  plugins: [
    react(),
    hingePlugin(),
  ],
  server: {
    cors: true,
    allowedHosts: ['.trycloudflare.com', '.loca.lt', 'localhost', '127.0.0.1'],
    hmr: true,
    fs: { strict: false },
  },
})
