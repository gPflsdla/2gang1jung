// ========================================================================
// 배리어프리 보행자 네비게이션 — 데이터 모델
// ========================================================================
// route_response.dart — 백엔드 API 응답 파싱용 모델 클래스
// ========================================================================

import 'package:latlong2/latlong.dart';

/// ── 경로 탐색 API 전체 응답 ──
class RouteResponse {
  final bool success;
  final double totalDistance;
  final String totalDistanceDisplay;
  final int nodeCount;
  final List<PathNode> pathNodes;
  final RouteGeoJson? routeGeoJson;
  final String? error;

  const RouteResponse({
    required this.success,
    this.totalDistance = 0.0,
    this.totalDistanceDisplay = '',
    this.nodeCount = 0,
    this.pathNodes = const [],
    this.routeGeoJson,
    this.error,
  });

  /// JSON → RouteResponse 팩토리 생성자
  factory RouteResponse.fromJson(Map<String, dynamic> json) {
    // ── 실패 응답 처리 ──
    if (json['success'] != true) {
      return RouteResponse(
        success: false,
        error: json['error'] as String? ?? '알 수 없는 오류가 발생했습니다.',
      );
    }

    // ── 성공 응답 파싱 ──
    return RouteResponse(
      success: true,
      totalDistance: (json['total_distance'] as num?)?.toDouble() ?? 0.0,
      totalDistanceDisplay: json['total_distance_display'] as String? ?? '',
      nodeCount: json['node_count'] as int? ?? 0,
      // path_nodes 파싱
      pathNodes: (json['path_nodes'] as List<dynamic>?)
              ?.map((e) => PathNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      // route_geojson 파싱
      routeGeoJson: json['route_geojson'] != null
          ? RouteGeoJson.fromJson(json['route_geojson'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// ── 경유 노드 정보 ──
class PathNode {
  final String nodeId;
  final String name;
  final double lat;
  final double lng;
  final bool isElevator;

  const PathNode({
    required this.nodeId,
    required this.name,
    required this.lat,
    required this.lng,
    this.isElevator = false,
  });

  factory PathNode.fromJson(Map<String, dynamic> json) {
    return PathNode(
      nodeId: json['node_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      isElevator: json['is_elevator'] as bool? ?? false,
    );
  }

  /// LatLng 변환 (flutter_map 호환)
  LatLng toLatLng() => LatLng(lat, lng);
}

/// ── GeoJSON Feature (경로 LineString) ──
class RouteGeoJson {
  final List<LatLng> coordinates;
  final double totalDistance;

  const RouteGeoJson({
    required this.coordinates,
    this.totalDistance = 0.0,
  });

  /// GeoJSON Feature → RouteGeoJson 파싱
  ///
  /// ★ 입력 구조:
  /// {
  ///   "type": "Feature",
  ///   "geometry": {
  ///     "type": "LineString",
  ///     "coordinates": [[lng, lat], [lng, lat], ...]
  ///   },
  ///   "properties": { "total_distance": 342.57 }
  /// }
  factory RouteGeoJson.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final properties = json['properties'] as Map<String, dynamic>?;

    List<LatLng> coords = [];

    if (geometry != null && geometry['type'] == 'LineString') {
      final rawCoords = geometry['coordinates'] as List<dynamic>?;
      if (rawCoords != null) {
        coords = rawCoords.map((coord) {
          final c = coord as List<dynamic>;
          // ★ GeoJSON 은 [경도, 위도] 순서 → LatLng(위도, 경도) 로 변환
          return LatLng(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
          );
        }).toList();
      }
    }

    return RouteGeoJson(
      coordinates: coords,
      totalDistance:
          (properties?['total_distance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
