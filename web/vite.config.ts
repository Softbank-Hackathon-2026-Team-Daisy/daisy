import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
import { defineConfig, loadEnv } from 'vite'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // 다른 폴더에서 vite를 띄워도(.claude/launch.json) web/의 .env를 읽게 이 파일 위치 기준으로 읽어요
  const env = loadEnv(mode, fileURLToPath(new URL('.', import.meta.url)), '')
  // VITE_PROXY_TARGET을 주면 개발 서버가 /api를 그 서버로 넘겨요 — 개발 API(api.unibloom.cloud)는 localhost를 CORS로 막아서예요
  // 그때는 VITE_API_BASE_URL=/api 로 써요 (.env.example)
  const proxyTarget = env.VITE_PROXY_TARGET
  return {
    plugins: [react()],
    // 서버 CORS 허용 Origin이 localhost:5173이라 포트를 고정해요 (SPEC.md §6-2)
    server: {
      port: 5173,
      strictPort: true,
      proxy: proxyTarget
        ? { '/api': { target: proxyTarget, changeOrigin: true, rewrite: (path) => path.replace(/^\/api/, '') } }
        : undefined,
    },
  }
})
