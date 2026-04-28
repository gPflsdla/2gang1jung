// ========================================================================
// 배리어프리 보행자 네비게이션 — 데이터 모델
// ========================================================================
// routeResponse.ts — 백엔드 API 응답 파싱용 타입 정의 + 변환 함수
// ========================================================================

import type { LatLngTuple } from "leaflet";

// ── 경유 노드 정보 ──
export interface PathNode {
  nodeId: string;
  name: string;
  lat: number;
  lng: number;
  isElevator: boolean;
}

// ── GeoJSON Feature (경로 LineString) ──
export interface RouteGeoJson {
  /** flutter_map 의 LatLng 와 동일하게 [위도, 경도] 순서로 저장 */
  coordinates: LatLngTuple[];
  totalDistance: number;
}

// ── 경로 탐색 API 전체 응답 ──
export interface RouteResponse {
  success: boolean;
  totalDistance: number;
  totalDistanceDisplay: string;
  nodeCount: number;
  pathNodes: PathNode[];
  routeGeoJson: RouteGeoJson | null;
  error?: string;
}

// ========================================================================
// JSON → 모델 파서 (Dart 의 fromJson 팩토리에 대응)
// ========================================================================

interface RawPathNode {
  node_id?: string;
  name?: string;
  lat?: number;
  lng?: number;
  is_elevator?: boolean;
}

interface RawRouteResponse {
  success?: boolean;
  total_distance?: number;
  total_distance_display?: string;
  node_count?: number;
  path_nodes?: RawPathNode[];
  route_geojson?: {
    geometry?: {
      type?: string;
      coordinates?: [number, number][];
    };
    properties?: { total_distance?: number };
  } | null;
  error?: string;
}

function parsePathNode(raw: RawPathNode): PathNode {
  return {
    nodeId: raw.node_id ?? "",
    name: raw.name ?? "",
    lat: raw.lat ?? 0,
    lng: raw.lng ?? 0,
    isElevator: raw.is_elevator ?? false,
  };
}

function parseRouteGeoJson(
  raw: RawRouteResponse["route_geojson"]
): RouteGeoJson | null {
  if (!raw) return null;

  const geometry = raw.geometry;
  let coordinates: LatLngTuple[] = [];

  if (geometry && geometry.type === "LineString" && geometry.coordinates) {
    // ★ GeoJSON 은 [경도, 위도] 순서 → Leaflet 의 [위도, 경도] 로 변환
    coordinates = geometry.coordinates.map(
      (coord) => [coord[1], coord[0]] as LatLngTuple
    );
  }

  return {
    coordinates,
    totalDistance: raw.properties?.total_distance ?? 0,
  };
}

export function parseRouteResponse(json: unknown): RouteResponse {
  const raw = (json ?? {}) as RawRouteResponse;

  // ── 실패 응답 처리 ──
  if (raw.success !== true) {
    return {
      success: false,
      totalDistance: 0,
      totalDistanceDisplay: "",
      nodeCount: 0,
      pathNodes: [],
      routeGeoJson: null,
      error: raw.error ?? "알 수 없는 오류가 발생했습니다.",
    };
  }

  // ── 성공 응답 파싱 ──
  return {
    success: true,
    totalDistance: raw.total_distance ?? 0,
    totalDistanceDisplay: raw.total_distance_display ?? "",
    nodeCount: raw.node_count ?? 0,
    pathNodes: (raw.path_nodes ?? []).map(parsePathNode),
    routeGeoJson: parseRouteGeoJson(raw.route_geojson),
  };
}
