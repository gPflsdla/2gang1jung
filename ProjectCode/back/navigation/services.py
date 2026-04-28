"""
========================================================================
배리어프리 보행자 네비게이션 — 라우팅 서비스 (핵심 엔진)
========================================================================
pgRouting 의 pgr_dijkstra 를 활용한 최단 거리 경로 탐색 서비스.

★ 핵심 비즈니스 로직 구현부:
  1. Obstacle 회피  — 장애물과 교차하는 Edge 를 완전 제외
  2. 순수 물리적 거리 — length(미터) 만을 cost 로 사용
  3. 엘리베이터 노드  — 수직 이동 거리 0 (별도 가중치 없음)
========================================================================
"""

import json
import logging
from dataclasses import dataclass, field
from typing import Optional

from django.contrib.gis.geos import GEOSGeometry, LineString, Point
from django.db import connection

logger = logging.getLogger(__name__)


# =====================================================================
# 데이터 클래스 — 라우팅 결과 구조체
# =====================================================================
@dataclass
class RouteNode:
    """경로를 구성하는 개별 노드"""
    node_id: str          # UUID 문자열
    name: str
    lat: float
    lng: float
    is_elevator: bool


@dataclass
class RouteResult:
    """경로 탐색 결과 전체"""
    success: bool
    total_distance: float = 0.0              # 총 거리 (미터)
    path_nodes: list = field(default_factory=list)   # List[RouteNode]
    edge_geometries: list = field(default_factory=list)  # List[dict] — Edge GeoJSON
    error_message: str = ""


# =====================================================================
# SQL 쿼리 상수
# =====================================================================

# ── 1단계: 사용자 좌표에서 가장 가까운 Node 찾기 ──
# geography 타입이므로 ST_Distance 가 미터 단위를 반환한다.
# 반경 500m 이내에서 가장 가까운 노드를 선택한다.
NEAREST_NODE_SQL = """
    SELECT
        id,
        name,
        ST_X(geom::geometry) AS lng,
        ST_Y(geom::geometry) AS lat,
        ST_Distance(geom, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) AS dist
    FROM nav_node
    ORDER BY geom <-> ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography
    LIMIT 1;
"""

# ── 2단계: pgRouting 용 Edge 집합 SQL (pgr_dijkstra 내부에서 실행됨) ──
# ★ 핵심 1: Obstacle 과 ST_Intersects 하는 Edge 를 완전 제외
# ★ 핵심 2: 사용 불가(is_available=False) 엘리베이터에 연결된 Edge 제외
# ★ 핵심 3: cost = length (순수 물리적 거리, 시간 가중치 없음)
#
# 주의: Node PK가 UUID 이므로 pgRouting 호환을 위해
#       DENSE_RANK() 로 정수 ID 매핑을 수행한다.
#       이 매핑은 edges SQL 과 start/end ID 조회에서 동일하게 적용되어야 한다.
PGROUTING_EDGES_SQL = """
    WITH
    -- ──────────────────────────────────────────────
    -- UUID → 정수 매핑 (pgRouting 호환)
    -- DENSE_RANK() + ORDER BY id 로 결정적(deterministic) 매핑 보장
    -- ──────────────────────────────────────────────
    node_int_map AS (
        SELECT
            id AS uuid_id,
            DENSE_RANK() OVER (ORDER BY id)::bigint AS int_id
        FROM nav_node
    ),

    -- ──────────────────────────────────────────────
    -- 활성 장애물 목록 (라우팅 시 제외 대상 판별용)
    -- ──────────────────────────────────────────────
    active_obstacles AS (
        SELECT geom
        FROM nav_obstacle
        WHERE is_active = TRUE
    ),

    -- ──────────────────────────────────────────────
    -- 사용 불가 엘리베이터의 Node UUID 목록
    -- ──────────────────────────────────────────────
    disabled_elevator_nodes AS (
        SELECT node_id AS uuid_id
        FROM nav_elevator_node
        WHERE is_available = FALSE
    )

    -- ──────────────────────────────────────────────
    -- 최종 Edge 집합: 장애물 교차 & 고장 엘리베이터 제외
    -- ──────────────────────────────────────────────
    SELECT
        ROW_NUMBER() OVER ()::integer       AS id,
        src_map.int_id::bigint              AS source,
        tgt_map.int_id::bigint              AS target,
        e.length::double precision          AS cost,
        CASE
            WHEN e.is_bidirectional
            THEN e.length::double precision
            ELSE -1.0                       -- 음수 = 역방향 통행 불가
        END                                 AS reverse_cost
    FROM nav_edge e
    -- UUID → 정수 매핑 조인
    INNER JOIN node_int_map src_map
        ON src_map.uuid_id = e.source_id
    INNER JOIN node_int_map tgt_map
        ON tgt_map.uuid_id = e.target_id
    -- ★ 장애물 교차 Edge 제외
    WHERE NOT EXISTS (
        SELECT 1
        FROM active_obstacles o
        WHERE ST_Intersects(
            e.geom::geometry,   -- geography → geometry 캐스팅 (ST_Intersects 호환)
            o.geom
        )
    )
    -- ★ 고장 엘리베이터 연결 Edge 제외
    AND e.source_id NOT IN (SELECT uuid_id FROM disabled_elevator_nodes)
    AND e.target_id NOT IN (SELECT uuid_id FROM disabled_elevator_nodes)
"""

# ── 3단계: 특정 UUID 노드의 정수 ID 조회 ──
NODE_INT_ID_SQL = """
    SELECT int_id FROM (
        SELECT
            id AS uuid_id,
            DENSE_RANK() OVER (ORDER BY id)::bigint AS int_id
        FROM nav_node
    ) nm
    WHERE uuid_id = %s;
"""

# ── 4단계: pgr_dijkstra 실행 + 결과에 원본 Node 정보 조인 ──
DIJKSTRA_FULL_SQL = """
    WITH
    -- UUID → 정수 매핑 (결과 역매핑용)
    node_int_map AS (
        SELECT
            id AS uuid_id,
            DENSE_RANK() OVER (ORDER BY id)::bigint AS int_id
        FROM nav_node
    ),

    -- pgr_dijkstra 실행
    dijkstra_result AS (
        SELECT *
        FROM pgr_dijkstra(
            $edges${edges_sql}$edges$,
            {start_int_id},
            {end_int_id},
            directed := true
        )
    )

    -- 결과에 Node 원본 정보 + Edge 선형 데이터 조인
    SELECT
        dr.seq,
        dr.path_seq,
        dr.node                               AS int_node_id,
        dr.edge                               AS int_edge_id,
        dr.cost                               AS step_cost,
        dr.agg_cost                           AS accumulated_cost,
        -- Node 원본 정보
        nim.uuid_id                           AS node_uuid,
        n.name                                AS node_name,
        ST_Y(n.geom::geometry)                AS node_lat,
        ST_X(n.geom::geometry)                AS node_lng,
        -- 엘리베이터 여부
        CASE
            WHEN ev.id IS NOT NULL THEN TRUE
            ELSE FALSE
        END                                   AS is_elevator,
        -- Edge 선형 (GeoJSON) — 마지막 row 는 edge=-1 이므로 NULL
        CASE
            WHEN dr.edge != -1 THEN (
                SELECT ST_AsGeoJSON(e2.geom::geometry)
                FROM nav_edge e2
                INNER JOIN node_int_map src ON src.uuid_id = e2.source_id
                INNER JOIN node_int_map tgt ON tgt.uuid_id = e2.target_id
                -- edge id 는 ROW_NUMBER 기반이므로 source/target 쌍으로 매칭
                WHERE (
                    (src.int_id = dr.node AND tgt.int_id = (
                        SELECT node FROM dijkstra_result dr2
                        WHERE dr2.path_seq = dr.path_seq + 1
                    ))
                    OR
                    (tgt.int_id = dr.node AND src.int_id = (
                        SELECT node FROM dijkstra_result dr2
                        WHERE dr2.path_seq = dr.path_seq + 1
                    ))
                )
                LIMIT 1
            )
            ELSE NULL
        END                                   AS edge_geojson
    FROM dijkstra_result dr
    -- 정수 ID → UUID 역매핑
    INNER JOIN node_int_map nim
        ON nim.int_id = dr.node
    -- Node 테이블 조인 (좌표, 이름)
    INNER JOIN nav_node n
        ON n.id = nim.uuid_id
    -- 엘리베이터 여부 (LEFT JOIN)
    LEFT JOIN nav_elevator_node ev
        ON ev.node_id = n.id
    ORDER BY dr.seq;
"""


# =====================================================================
# 라우팅 서비스 클래스
# =====================================================================
class RoutingService:
    """
    배리어프리 최단 거리 경로 탐색 서비스.

    사용법:
        service = RoutingService()
        result = service.find_route(
            start_lng=126.9780, start_lat=37.5665,
            end_lng=126.9820,   end_lat=37.5700,
        )
    """

    # 가장 가까운 노드 검색 반경 (미터)
    MAX_SNAP_DISTANCE = 500.0

    def find_route(
        self,
        start_lng: float,
        start_lat: float,
        end_lng: float,
        end_lat: float,
    ) -> RouteResult:
        """
        출발지/도착지 좌표로부터 배리어프리 최단 경로를 탐색한다.

        Args:
            start_lng: 출발지 경도
            start_lat: 출발지 위도
            end_lng:   도착지 경도
            end_lat:   도착지 위도

        Returns:
            RouteResult: 경로 탐색 결과 (성공/실패, 노드 목록, 거리 등)
        """
        try:
            # ── STEP 1: 출발/도착 좌표에서 가장 가까운 Node 탐색 ──
            start_node = self._find_nearest_node(start_lng, start_lat)
            if not start_node:
                return RouteResult(
                    success=False,
                    error_message=(
                        f"출발지 근처({self.MAX_SNAP_DISTANCE}m 이내)에 "
                        f"보행 네트워크 노드가 없습니다."
                    ),
                )

            end_node = self._find_nearest_node(end_lng, end_lat)
            if not end_node:
                return RouteResult(
                    success=False,
                    error_message=(
                        f"도착지 근처({self.MAX_SNAP_DISTANCE}m 이내)에 "
                        f"보행 네트워크 노드가 없습니다."
                    ),
                )

            start_uuid, start_name = start_node["id"], start_node["name"]
            end_uuid, end_name = end_node["id"], end_node["name"]

            logger.info(
                "경로 탐색 시작: %s(%s) → %s(%s)",
                start_name, start_uuid, end_name, end_uuid,
            )

            # 출발/도착 노드가 동일한 경우
            if start_uuid == end_uuid:
                return RouteResult(
                    success=True,
                    total_distance=0.0,
                    path_nodes=[
                        RouteNode(
                            node_id=str(start_uuid),
                            name=start_name,
                            lat=start_node["lat"],
                            lng=start_node["lng"],
                            is_elevator=False,
                        )
                    ],
                )

            # ── STEP 2: 노드 UUID → pgRouting 정수 ID 변환 ──
            start_int_id = self._get_node_int_id(start_uuid)
            end_int_id = self._get_node_int_id(end_uuid)

            if start_int_id is None or end_int_id is None:
                return RouteResult(
                    success=False,
                    error_message="노드 ID 매핑에 실패했습니다.",
                )

            # ── STEP 3: pgr_dijkstra 실행 ──
            route_rows = self._execute_dijkstra(start_int_id, end_int_id)

            if not route_rows:
                return RouteResult(
                    success=False,
                    error_message=(
                        "경로를 찾을 수 없습니다. "
                        "장애물로 인해 모든 경로가 차단되었거나, "
                        "네트워크가 연결되어 있지 않습니다."
                    ),
                )

            # ── STEP 4: 결과 파싱 및 RouteResult 조립 ──
            return self._build_route_result(route_rows)

        except Exception as e:
            logger.exception("경로 탐색 중 예외 발생: %s", str(e))
            return RouteResult(
                success=False,
                error_message=f"경로 탐색 중 오류가 발생했습니다: {str(e)}",
            )

    # =================================================================
    # STEP 1: 가장 가까운 노드 탐색
    # =================================================================
    def _find_nearest_node(
        self, lng: float, lat: float
    ) -> Optional[dict]:
        """
        주어진 좌표에서 가장 가까운 Node 를 반환한다.
        MAX_SNAP_DISTANCE 이내에 노드가 없으면 None.

        ★ PostGIS 의 KNN (<-> 연산자) 인덱스를 활용하여
          전체 테이블 스캔 없이 빠르게 최근접 노드를 찾는다.
        """
        with connection.cursor() as cursor:
            cursor.execute(NEAREST_NODE_SQL, [lng, lat, lng, lat])
            row = cursor.fetchone()

        if not row:
            return None

        node_id, name, node_lng, node_lat, dist = row

        # 반경 초과 시 None
        if dist > self.MAX_SNAP_DISTANCE:
            logger.warning(
                "가장 가까운 노드(%s)가 %.1fm 거리에 있어 반경(%.0fm) 초과",
                name, dist, self.MAX_SNAP_DISTANCE,
            )
            return None

        return {
            "id": node_id,
            "name": name or "",
            "lng": node_lng,
            "lat": node_lat,
            "distance": dist,
        }

    # =================================================================
    # STEP 2: UUID → 정수 ID 매핑
    # =================================================================
    def _get_node_int_id(self, node_uuid) -> Optional[int]:
        """
        Node UUID 를 pgRouting 호환 정수 ID 로 변환한다.
        DENSE_RANK(ORDER BY id) 기반으로 결정적 매핑을 보장한다.
        """
        with connection.cursor() as cursor:
            cursor.execute(NODE_INT_ID_SQL, [node_uuid])
            row = cursor.fetchone()
        return row[0] if row else None

    # =================================================================
    # STEP 3: pgr_dijkstra 실행
    # =================================================================
    def _execute_dijkstra(
        self, start_int_id: int, end_int_id: int
    ) -> list:
        """
        pgr_dijkstra 를 실행하고 결과 row 목록을 반환한다.

        ★ PGROUTING_EDGES_SQL 이 pgr_dijkstra 의 첫 번째 인자로 전달되어
          pgRouting 내부에서 독립적으로 실행된다.
        ★ 장애물 교차 Edge 제외 + 고장 엘리베이터 제외 로직이
          이 SQL 안에 포함되어 있다.
        """
        # edges SQL 과 start/end ID 를 문자열 포매팅으로 조립
        # (pgr_dijkstra 의 SQL 인자는 $$ 리터럴로 전달하므로 SQL injection 안전)
        final_sql = DIJKSTRA_FULL_SQL.format(
            edges_sql=PGROUTING_EDGES_SQL,
            start_int_id=int(start_int_id),  # 정수 강제 변환 (안전)
            end_int_id=int(end_int_id),
        )

        with connection.cursor() as cursor:
            cursor.execute(final_sql)
            columns = [col[0] for col in cursor.description]
            rows = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return rows

    # =================================================================
    # STEP 4: 결과 조립
    # =================================================================
    def _build_route_result(self, route_rows: list) -> RouteResult:
        """
        pgr_dijkstra 결과 row 들을 RouteResult 구조체로 변환한다.

        반환 데이터:
          - path_nodes : 경유 노드 목록 (순서대로)
          - edge_geometries : 각 Edge 의 GeoJSON dict
          - total_distance : 최종 누적 거리 (마지막 row 의 agg_cost)
        """
        path_nodes = []
        edge_geometries = []
        total_distance = 0.0

        for row in route_rows:
            # ── 노드 정보 수집 ──
            path_nodes.append(
                RouteNode(
                    node_id=str(row["node_uuid"]),
                    name=row["node_name"] or "",
                    lat=row["node_lat"],
                    lng=row["node_lng"],
                    is_elevator=row["is_elevator"],
                )
            )

            # ── Edge GeoJSON 수집 (마지막 노드는 edge 없음) ──
            if row["edge_geojson"]:
                try:
                    geojson = json.loads(row["edge_geojson"])
                    edge_geometries.append(
                        {
                            "type": "Feature",
                            "geometry": geojson,
                            "properties": {
                                "step_cost": row["step_cost"],
                                "accumulated_cost": row["accumulated_cost"],
                            },
                        }
                    )
                except (json.JSONDecodeError, TypeError):
                    pass

            # ── 총 거리: 마지막 row 의 agg_cost 가 전체 경로 거리 ──
            total_distance = row["accumulated_cost"]

        return RouteResult(
            success=True,
            total_distance=total_distance,
            path_nodes=path_nodes,
            edge_geometries=edge_geometries,
        )


# =====================================================================
# GeoJSON 변환 유틸리티
# =====================================================================
def build_route_geojson(result: RouteResult) -> dict:
    """
    RouteResult 의 노드 좌표들을 하나의 LineString GeoJSON Feature 로 조합한다.
    프론트엔드에서 지도에 경로 선(Polyline)을 그릴 때 사용한다.
    """
    if not result.path_nodes:
        return {}

    coordinates = [
        [node.lng, node.lat] for node in result.path_nodes
    ]

    return {
        "type": "Feature",
        "geometry": {
            "type": "LineString",
            "coordinates": coordinates,
        },
        "properties": {
            "total_distance": round(result.total_distance, 2),
            "node_count": len(result.path_nodes),
        },
    }


def build_edges_geojson(result: RouteResult) -> dict:
    """
    RouteResult 의 개별 Edge GeoJSON 들을 FeatureCollection 으로 묶는다.
    프론트엔드에서 구간별 상세 경로를 표현할 때 사용한다.
    """
    return {
        "type": "FeatureCollection",
        "features": result.edge_geometries,
    }


def format_distance(meters: float) -> str:
    """거리를 사람이 읽기 좋은 형태로 포매팅"""
    if meters >= 1000:
        return f"{meters / 1000:.1f}km"
    return f"{meters:.1f}m"
