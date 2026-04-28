"""
========================================================================
배리어프리 보행자 네비게이션 — API Views (Django REST Framework)
========================================================================
경로 탐색 API 엔드포인트를 제공한다.

엔드포인트:
  POST /api/v1/route/   — 최단 경로 탐색
  GET  /api/v1/route/   — 쿼리 파라미터 방식 최단 경로 탐색
  GET  /api/v1/health/  — 라우팅 엔진 헬스체크
========================================================================
"""

import logging
import time

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from .serializers import RouteRequestSerializer, RouteResponseSerializer
from .services import (
    RoutingService,
    build_edges_geojson,
    build_route_geojson,
    format_distance,
)

logger = logging.getLogger(__name__)


# =====================================================================
# 1. 경로 탐색 API
# =====================================================================
class RouteView(APIView):
    """
    배리어프리 최단 경로 탐색 API.

    ★ 핵심 로직 요약:
      1. 클라이언트로부터 출발지/도착지 좌표를 수신
      2. 각 좌표에서 가장 가까운 보행 네트워크 Node 를 탐색 (snap)
      3. 장애물(Obstacle)과 교차하는 Edge 를 제외한 뒤
         pgr_dijkstra 로 순수 물리적 거리 기반 최단 경로 계산
      4. 경로를 GeoJSON LineString + 총 거리로 반환

    ---
    ## POST /api/v1/route/

    **Request Body (JSON):**
    ```json
    {
        "start_lat": 37.5665,
        "start_lng": 126.9780,
        "end_lat": 37.5700,
        "end_lng": 126.9820
    }
    ```

    **Response (200 OK):**
    ```json
    {
        "success": true,
        "total_distance": 342.57,
        "total_distance_display": "342.6m",
        "node_count": 5,
        "path_nodes": [...],
        "route_geojson": { "type": "Feature", ... },
        "edges_geojson": { "type": "FeatureCollection", ... }
    }
    ```

    ---
    ## GET /api/v1/route/?start_lat=...&start_lng=...&end_lat=...&end_lng=...

    쿼리 파라미터 방식도 지원한다 (브라우저 테스트 편의).
    """

    # 인증 없이 공개 접근 허용 (필요 시 permission_classes 추가)
    # permission_classes = [AllowAny]

    def post(self, request):
        """POST 방식 경로 탐색 (JSON Body)"""
        return self._handle_route_request(request.data)

    def get(self, request):
        """GET 방식 경로 탐색 (Query Params — 테스트 편의용)"""
        return self._handle_route_request(request.query_params)

    def _handle_route_request(self, data) -> Response:
        """
        경로 탐색 공통 핸들러.

        1) 입력 검증 (Serializer)
        2) 라우팅 서비스 호출
        3) 응답 조립 및 반환
        """
        # ── 1. 입력 검증 ──
        serializer = RouteRequestSerializer(data=data)
        if not serializer.is_valid():
            return Response(
                {
                    "success": False,
                    "error": "입력값이 올바르지 않습니다.",
                    "details": serializer.errors,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        validated = serializer.validated_data

        # ── 2. 라우팅 서비스 실행 ──
        start_time = time.monotonic()

        service = RoutingService()
        result = service.find_route(
            start_lng=validated["start_lng"],
            start_lat=validated["start_lat"],
            end_lng=validated["end_lng"],
            end_lat=validated["end_lat"],
        )

        elapsed_ms = (time.monotonic() - start_time) * 1000
        logger.info("경로 탐색 완료: %.1fms (성공=%s)", elapsed_ms, result.success)

        # ── 3-A. 실패 시 ──
        if not result.success:
            return Response(
                {
                    "success": False,
                    "error": result.error_message,
                },
                status=status.HTTP_404_NOT_FOUND,
            )

        # ── 3-B. 성공 시 — 응답 조립 ──
        response_data = {
            "success": True,
            # ── 거리 정보 ──
            "total_distance": round(result.total_distance, 2),
            "total_distance_display": format_distance(result.total_distance),
            # ── 경유 노드 목록 ──
            "node_count": len(result.path_nodes),
            "path_nodes": [
                {
                    "node_id": node.node_id,
                    "name": node.name,
                    "lat": node.lat,
                    "lng": node.lng,
                    "is_elevator": node.is_elevator,
                }
                for node in result.path_nodes
            ],
            # ── GeoJSON — 프론트엔드 지도 렌더링용 ──
            "route_geojson": build_route_geojson(result),
            "edges_geojson": build_edges_geojson(result),
            # ── 성능 메트릭 (디버깅용) ──
            "meta": {
                "query_time_ms": round(elapsed_ms, 1),
            },
        }

        return Response(response_data, status=status.HTTP_200_OK)


# =====================================================================
# 2. 헬스체크 API
# =====================================================================
class HealthCheckView(APIView):
    """
    라우팅 엔진의 상태를 점검한다.

    GET /api/v1/health/

    체크 항목:
      - PostgreSQL 연결
      - PostGIS 확장 설치 여부
      - pgRouting 확장 설치 여부
      - Node/Edge 데이터 존재 여부
    """

    def get(self, request):
        from django.db import connection

        checks = {}

        try:
            with connection.cursor() as cursor:
                # PostGIS 버전 확인
                cursor.execute("SELECT PostGIS_Version();")
                checks["postgis_version"] = cursor.fetchone()[0]

                # pgRouting 버전 확인
                cursor.execute("SELECT pgr_version();")
                checks["pgrouting_version"] = cursor.fetchone()[0]

                # 데이터 통계
                cursor.execute("SELECT COUNT(*) FROM nav_node;")
                checks["node_count"] = cursor.fetchone()[0]

                cursor.execute("SELECT COUNT(*) FROM nav_edge;")
                checks["edge_count"] = cursor.fetchone()[0]

                cursor.execute(
                    "SELECT COUNT(*) FROM nav_obstacle WHERE is_active = TRUE;"
                )
                checks["active_obstacle_count"] = cursor.fetchone()[0]

                cursor.execute(
                    "SELECT COUNT(*) FROM nav_elevator_node WHERE is_available = TRUE;"
                )
                checks["active_elevator_count"] = cursor.fetchone()[0]

            return Response(
                {
                    "status": "healthy",
                    "checks": checks,
                },
                status=status.HTTP_200_OK,
            )

        except Exception as e:
            logger.exception("헬스체크 실패: %s", str(e))
            return Response(
                {
                    "status": "unhealthy",
                    "error": str(e),
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
