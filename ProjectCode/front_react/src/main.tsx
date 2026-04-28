// ========================================================================
// 배리어프리(Barrier-Free) 보행자 네비게이션 — React 앱 진입점
// ========================================================================
// main.tsx — Flutter 의 main() 에 대응
// ========================================================================

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import App from "./App";
import "./index.css";

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("#root 요소를 찾을 수 없습니다. index.html 을 확인하세요.");
}

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>
);
