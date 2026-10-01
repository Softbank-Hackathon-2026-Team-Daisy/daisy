import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // 서버 CORS 허용 Origin이 localhost:5173이라 포트를 고정해요 (SPEC.md §6-2)
  server: { port: 5173, strictPort: true },
})
