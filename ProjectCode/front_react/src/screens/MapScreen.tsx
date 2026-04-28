// ========================================================================
// 배리어프리 보행자 네비게이션 — 메인 지도 화면
// ========================================================================
// MapScreen.tsx — 전체 화면 지도 + 마커 + 경로 폴리라인 + 정보 패널
//
// ★ 사용자 흐름:
//   1) 지도 클릭 → 출발지 마커 설정 (초록색)
//   2) 다시 클릭 → 도착지 마커 설정 (빨간색)
//   3) 자동으로 API 호출 → 경로 수신 → 폴리라인 렌더링
//   4) 하단 패널에 총 거리 + 경유 엘리베이터 정보 표시
//
// (Flutter 원본은 LongPress 였으나 웹에서는 Click 으로 대체)
// ========================================================================

import { useEffect, useMemo, useRef, useState } from "react";
import {
  MapContainer,
  Marker,
  Polyline,
  TileLayer,
  useMap,
  useMapEvents,
} from "react-leaflet";
import L, { type LatLngBoundsExpression, type LatLngTuple } from "leaflet";
import "leaflet/dist/leaflet.css";

import { fetchRoute } from "../api/routeApi";
import type { PathNode, RouteResponse } from "../models/routeResponse";
import "./MapScreen.css";

// ── 초기 지도 설정 (서울시청 근처) ──
const INITIAL_CENTER: LatLngTuple = [37.5665, 126.978];
const INITIAL_ZOOM = 17;


// ========================================================================
// 커스텀 마커 아이콘 (Leaflet 기본 아이콘 대신 DivIcon 사용)
// ========================================================================

function createMarkerIcon(
  color: string,
  iconSvg: string,
  label: string
): L.DivIcon {
  const html = `
    <div class="bf-marker">
      <div class="bf-marker-label" style="background:${color}">${label}</div>
      <div class="bf-marker-icon" style="color:${color}">${iconSvg}</div>
    </div>
  `;
  return L.divIcon({
    html,
    className: "bf-marker-wrapper",
    iconSize: [50, 60],
    iconAnchor: [25, 60],
  });
}

// 출발지 (초록 / trip_origin)
const START_ICON = createMarkerIcon(
  "#2E7D32",
  // SVG: 동심원
  `<svg viewBox="0 0 24 24" width="30" height="30" fill="currentColor">
     <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none"/>
     <circle cx="12" cy="12" r="4" fill="currentColor"/>
   </svg>`,
  "출발"
);

// 도착지 (빨강 / location_on)
const END_ICON = createMarkerIcon(
  "#C62828",
  // SVG: 위치 핀
  `<svg viewBox="0 0 24 24" width="30" height="30" fill="currentColor">
     <path d="M12 2C8 2 5 5 5 9c0 5 7 13 7 13s7-8 7-13c0-4-3-7-7-7zm0 9.5a2.5 2.5 0 110-5 2.5 2.5 0 010 5z"/>
   </svg>`,
  "도착"
);

// 엘리베이터 (인디고 / elevator)
const ELEVATOR_ICON = L.divIcon({
  html: `
    <div class="bf-elevator-marker" title="엘리베이터">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="white">
        <path d="M7 2v20h10V2H7zm4 4l-2 3h4l-2-3zm0 12l2-3H9l2 3z"/>
      </svg>
    </div>
  `,
  className: "bf-elevator-wrapper",
  iconSize: [40, 40],
  iconAnchor: [20, 20],
});


// ========================================================================
// 지도 클릭 → 부모 콜백 호출
// ========================================================================
function MapClickHandler({
  onClick,
}: {
  onClick: (latlng: LatLngTuple) => void;
}) {
  useMapEvents({
    click(e) {
      onClick([e.latlng.lat, e.latlng.lng]);
    },
  });
  return null;
}


// ========================================================================
// 경로가 갱신될 때 카메라를 자동으로 맞추는 헬퍼
// ========================================================================
function FitBoundsOnRouteChange({
  bounds,
}: {
  bounds: LatLngBoundsExpression | null;
}) {
  const map = useMap();
  useEffect(() => {
    if (!bounds) return;
    map.fitBounds(bounds, { padding: [60, 60] });
  }, [bounds, map]);
  return null;
}


// ========================================================================
// 메인 컴포넌트
// ========================================================================

type StatusKey = "needStart" | "needEnd" | "loading" | "success" | "reset";

export default function MapScreen() {
  // ── 상태 ──
  const [startPoint, setStartPoint] = useState<LatLngTuple | null>(null);
  const [endPoint, setEndPoint] = useState<LatLngTuple | null>(null);
  const [routeData, setRouteData] = useState<RouteResponse | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // 진행 중인 fetch 를 취소하기 위한 ref
  const abortRef = useRef<AbortController | null>(null);

  // ── 폴리라인 좌표 ──
  const routeCoords: LatLngTuple[] = useMemo(
    () => routeData?.routeGeoJson?.coordinates ?? [],
    [routeData]
  );

  // ── 카메라 자동 맞춤용 bounds ──
  const fitBounds: LatLngBoundsExpression | null = useMemo(() => {
    if (routeCoords.length === 0) return null;
    const all: LatLngTuple[] = [...routeCoords];
    if (startPoint) all.push(startPoint);
    if (endPoint) all.push(endPoint);
    return L.latLngBounds(all);
  }, [routeCoords, startPoint, endPoint]);

  // 언마운트 시 진행 중 요청 취소
  useEffect(
    () => () => {
      abortRef.current?.abort();
    },
    []
  );

  // ─────────────────────────────────────────
  // 클릭 → 마커 설정 → API 호출
  // ─────────────────────────────────────────

  /**
   * ★ 클릭 흐름:
   *   1회차 → 출발지(초록)
   *   2회차 → 도착지(빨강) + 경로 요청
   *   3회차 → 초기화 + 새 출발지
   */
  const handleMapClick = (point: LatLngTuple) => {
    if (startPoint === null) {
      setStartPoint(point);
      setEndPoint(null);
      setRouteData(null);
      setErrorMessage(null);
    } else if (endPoint === null) {
      setEndPoint(point);
      // 다음 effect 에서 fetchRouteFor() 호출되도록 트리거
      void runRouteRequest(startPoint, point);
    } else {
      setStartPoint(point);
      setEndPoint(null);
      setRouteData(null);
      setErrorMessage(null);
    }
  };

  /** 백엔드 경로 탐색 API 호출 */
  const runRouteRequest = async (
    start: LatLngTuple,
    end: LatLngTuple
  ): Promise<void> => {
    // 이전 요청 취소
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setIsLoading(true);
    setErrorMessage(null);
    setRouteData(null);

    const response = await fetchRoute({
      start,
      end,
      signal: controller.signal,
    });

    // 사이에 사용자가 abort 했다면 결과 무시
    if (controller.signal.aborted) return;

    setIsLoading(false);
    setRouteData(response);

    if (!response.success) {
      setErrorMessage(response.error ?? "경로를 찾을 수 없습니다.");
    }
  };

  const handleClearAll = () => {
    abortRef.current?.abort();
    setStartPoint(null);
    setEndPoint(null);
    setRouteData(null);
    setErrorMessage(null);
    setIsLoading(false);
  };

  const handleRetry = () => {
    if (startPoint && endPoint) {
      void runRouteRequest(startPoint, endPoint);
    }
  };

  // ── 상단 배너 메시지 결정 ──
  const status: { key: StatusKey; msg: string; icon: string; color: string } =
    (() => {
      if (startPoint === null) {
        return {
          key: "needStart",
          msg: "지도를 클릭하여 출발지를 설정하세요",
          icon: "👆",
          color: "#37474F",
        };
      }
      if (endPoint === null) {
        return {
          key: "needEnd",
          msg: "도착지를 클릭하여 설정하세요",
          icon: "🚩",
          color: "#2E7D32",
        };
      }
      if (isLoading) {
        return {
          key: "loading",
          msg: "배리어프리 경로를 탐색 중입니다…",
          icon: "🧭",
          color: "#1565C0",
        };
      }
      if (routeData?.success) {
        return {
          key: "success",
          msg: `경로 안내 준비 완료 (${routeData.totalDistanceDisplay})`,
          icon: "✅",
          color: "#2E7D32",
        };
      }
      return {
        key: "reset",
        msg: "경로를 초기화하려면 지도를 다시 클릭하세요",
        icon: "ℹ️",
        color: "#607D8B",
      };
    })();

  // ── 엘리베이터 노드 추출 ──
  const elevatorNodes: PathNode[] =
    routeData?.pathNodes.filter((n) => n.isElevator) ?? [];

  // =====================================================================
  // 렌더
  // =====================================================================
  return (
    <div className="bf-app">
      {/* ── 지도 ── */}
      <MapContainer
        center={INITIAL_CENTER}
        zoom={INITIAL_ZOOM}
        minZoom={5}
        maxZoom={22}
        style={{ height: "100%", width: "100%" }}
        zoomControl={true}
      >
        <TileLayer
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          maxZoom={22}
        />

        <MapClickHandler onClick={handleMapClick} />
        <FitBoundsOnRouteChange bounds={fitBounds} />

        {/* ── 경로 폴리라인 (외곽선 + 메인) ── */}
        {routeCoords.length > 0 && (
          <>
            <Polyline
              positions={routeCoords}
              pathOptions={{
                color: "#1565C0",
                opacity: 0.4,
                weight: 10,
              }}
            />
            <Polyline
              positions={routeCoords}
              pathOptions={{
                color: "#1976D2",
                weight: 6,
              }}
            />
          </>
        )}

        {/* ── 엘리베이터 마커 ── */}
        {routeData?.success &&
          elevatorNodes.map((n) => (
            <Marker
              key={n.nodeId}
              position={[n.lat, n.lng]}
              icon={ELEVATOR_ICON}
              title={`엘리베이터: ${n.name}`}
            />
          ))}

        {/* ── 출발/도착 마커 ── */}
        {startPoint && (
          <Marker position={startPoint} icon={START_ICON} title="출발지" />
        )}
        {endPoint && (
          <Marker position={endPoint} icon={END_ICON} title="도착지" />
        )}
      </MapContainer>

      {/* ── 상단 안내 배너 ── */}
      <div
        className="bf-top-banner"
        style={{ backgroundColor: `${status.color}F2` }}
      >
        <span className="bf-top-banner-icon">{status.icon}</span>
        <span className="bf-top-banner-text">{status.msg}</span>
      </div>

      {/* ── 로딩 오버레이 ── */}
      {isLoading && (
        <div className="bf-loading-overlay">
          <div className="bf-loading-card">
            <div className="bf-spinner" />
            <p className="bf-loading-title">배리어프리 경로 탐색 중…</p>
            <p className="bf-loading-sub">
              장애물을 회피하는 최적 경로를 계산하고 있습니다
            </p>
          </div>
        </div>
      )}

      {/* ── 하단 경로 정보 패널 ── */}
      {routeData?.success && !isLoading && (
        <div className="bf-info-panel">
          <div className="bf-info-header">
            <span className="bf-info-header-icon">♿</span>
            <div className="bf-info-header-text">
              <span className="bf-info-header-label">배리어프리 경로</span>
              <span className="bf-info-header-distance">
                {routeData.totalDistanceDisplay}
              </span>
            </div>
            <span className="bf-info-header-badge">
              {routeData.nodeCount}개 구간
            </span>
          </div>

          {elevatorNodes.length > 0 && (
            <div className="bf-info-elevators">
              <div className="bf-info-elevators-title">
                🛗 엘리베이터 {elevatorNodes.length}곳 경유
              </div>
              <ul className="bf-info-elevators-list">
                {elevatorNodes.map((n) => (
                  <li key={n.nodeId}>• {n.name || "엘리베이터"}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="bf-info-note">
            ℹ️ 계단·급경사를 회피하는 최단 거리 경로입니다
          </div>
        </div>
      )}

      {/* ── 에러 패널 ── */}
      {errorMessage && !isLoading && (
        <div className="bf-error-panel">
          <span className="bf-error-icon">⚠️</span>
          <div className="bf-error-text">
            <strong>경로를 찾을 수 없습니다</strong>
            <span>{errorMessage}</span>
          </div>
          <button
            className="bf-error-retry"
            onClick={handleRetry}
            title="다시 시도"
          >
            ↻
          </button>
        </div>
      )}

      {/* ── 초기화 FAB ── */}
      {startPoint && (
        <button
          className="bf-fab-clear"
          onClick={handleClearAll}
          title="경로 초기화"
        >
          ✕
        </button>
      )}
    </div>
  );
}
