// ========================================================================
// 배리어프리 보행자 네비게이션 — API 서비스
// ========================================================================
// routeApi.ts — 백엔드 경로 탐색 API 통신 담당
// ========================================================================

import type { LatLngTuple } from "leaflet";

import type { RouteResponse } from "../models/routeResponse";
import { parseRouteResponse } from "../models/routeResponse";

// ── 백엔드 서버 기본 주소 ──
//   개발: vite.config.ts 의 proxy 설정으로 /api/* 가 Django 로 전달됨
//   운영: VITE_API_BASE_URL 환경 변수로 절대 주소 지정 가능
const DEFAULT_BASE_URL =
  import.meta.env.VITE_API_BASE_URL ?? "/api/v1";

// ── 요청 타임아웃 (밀리초) ──
const TIMEOUT_MS = 15_000;


// ========================================================================
// 경로 탐색 API 호출
// ========================================================================

export interface FetchRouteArgs {
  start: LatLngTuple;  // [위도, 경도]
  end: LatLngTuple;
  baseUrl?: string;
  signal?: AbortSignal;
}

/**
 * 출발지/도착지 좌표로 배리어프리 최단 경로를 요청한다.
 *
 * ★ POST /api/v1/route/ 엔드포인트를 호출한다.
 */
export async function fetchRoute({
  start,
  end,
  baseUrl = DEFAULT_BASE_URL,
  signal,
}: FetchRouteArgs): Promise<RouteResponse> {
  const url = `${baseUrl}/route/`;

  // ── 요청 바디 구성 ──
  const body = JSON.stringify({
    start_lat: start[0],
    start_lng: start[1],
    end_lat: end[0],
    end_lng: end[1],
  });

  // ── 타임아웃 처리 (외부 signal 과 결합) ──
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => timeoutController.abort(), TIMEOUT_MS);

  // 외부 signal 이 abort 되면 내부 controller 도 abort
  if (signal) {
    if (signal.aborted) timeoutController.abort();
    else signal.addEventListener("abort", () => timeoutController.abort());
  }

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body,
      signal: timeoutController.signal,
    });

    // ── 응답 파싱 ──
    let json: unknown;
    try {
      json = await response.json();
    } catch {
      return {
        success: false,
        totalDistance: 0,
        totalDistanceDisplay: "",
        nodeCount: 0,
        pathNodes: [],
        routeGeoJson: null,
        error: "서버 응답을 파싱할 수 없습니다.",
      };
    }

    if (response.ok) {
      return parseRouteResponse(json);
    }

    // ── 4xx / 5xx 에러 처리 ──
    const errorMsg =
      (json as { error?: string })?.error ??
      `서버 오류가 발생했습니다. (${response.status})`;
    return {
      success: false,
      totalDistance: 0,
      totalDistanceDisplay: "",
      nodeCount: 0,
      pathNodes: [],
      routeGeoJson: null,
      error: errorMsg,
    };
  } catch (err) {
    // ── 네트워크 / 타임아웃 / Abort 등 ──
    let message = "알 수 없는 오류가 발생했습니다.";
    if (err instanceof DOMException && err.name === "AbortError") {
      message = "요청이 시간 초과되었거나 취소되었습니다.";
    } else if (err instanceof TypeError) {
      // fetch 실패는 보통 네트워크 단절
      message = "서버에 연결할 수 없습니다.\n네트워크 연결을 확인하세요.";
    } else if (err instanceof Error) {
      message = `네트워크 오류: ${err.message}`;
    }
    return {
      success: false,
      totalDistance: 0,
      totalDistanceDisplay: "",
      nodeCount: 0,
      pathNodes: [],
      routeGeoJson: null,
      error: message,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}


// ========================================================================
// 헬스체크
// ========================================================================

export async function healthCheck(
  baseUrl: string = DEFAULT_BASE_URL
): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5_000);
    const response = await fetch(`${baseUrl}/health/`, {
      signal: controller.signal,
    });
    clearTimeout(timeout);
    return response.ok;
  } catch {
    return false;
  }
}
