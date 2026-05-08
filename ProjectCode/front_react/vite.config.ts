import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// ========================================================================
// Vite 설정
// ========================================================================
// - dev 서버에서 백엔드 API 를 프록시하여 CORS 이슈 회피
// - 백엔드 주소가 다르면 VITE_API_BASE_URL 로 직접 호출하도록 변경 가능
// ========================================================================

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // ★ /api/* 요청을 Django 서버로 프록시
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
      },
    },
  },
});
