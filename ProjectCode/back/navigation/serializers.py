"""
========================================================================
배리어프리 보행자 네비게이션 — Serializers
========================================================================
경로 탐색 API 의 요청(Request) 검증 및 응답(Response) 직렬화를 담당한다.
========================================================================
"""

from rest_framework import serializers


# =====================================================================
# 1. 경로 탐색 요청 Serializer
# =====================================================================
class RouteRequestSerializer(serializers.Serializer):
    """
    클라이언트로부터 출발지/도착지 좌표를 받아 검증한다.

    ★ 요청 예시 (JSON):
    {
        "start_lat": 37.5665,
        "start_lng": 126.9780,
        "end_lat": 37.5700,
        "end_lng": 126.9820
    }
    """

    # ── 출발지 좌표 ──
    start_lat = serializers.FloatField(
        min_value=-90,
        max_value=90,
        help_text="출발지 위도 (WGS 84)",
    )
    start_lng = serializers.FloatField(
        min_value=-180,
        max_value=180,
        help_text="출발지 경도 (WGS 84)",
    )

    # ── 도착지 좌표 ──
    end_lat = serializers.FloatField(
        min_value=-90,
        max_value=90,
        help_text="도착지 위도 (WGS 84)",
    )
    end_lng = serializers.FloatField(
        min_value=-180,
        max_value=180,
        help_text="도착지 경도 (WGS 84)",
    )

    def validate(self, attrs):
        """출발지와 도착지가 동일한 좌표인지 검증"""
        if (
            attrs["start_lat"] == attrs["end_lat"]
            and attrs["start_lng"] == attrs["end_lng"]
        ):
            raise serializers.ValidationError(
                "출발지와 도착지가 동일합니다. 서로 다른 좌표를 입력하세요."
            )
        return attrs


# =====================================================================
# 2. 경로 탐색 응답 Serializer
# =====================================================================
class RouteNodeSerializer(serializers.Serializer):
    """경로를 구성하는 개별 노드 정보"""
    node_id = serializers.UUIDField(help_text="노드 UUID")
    name = serializers.CharField(help_text="노드 이름")
    lat = serializers.FloatField(help_text="위도")
    lng = serializers.FloatField(help_text="경도")
    is_elevator = serializers.BooleanField(help_text="엘리베이터 노드 여부")


class RouteResponseSerializer(serializers.Serializer):
    """
    경로 탐색 결과를 직렬화한다.

    ★ 응답 예시 (JSON):
    {
        "success": true,
        "total_distance": 342.57,
        "total_distance_display": "342.6m",
        "node_count": 5,
        "path_nodes": [
            {
                "node_id": "...",
                "name": "정문 입구",
                "lat": 37.5665,
                "lng": 126.9780,
                "is_elevator": false
            },
            ...
        ],
        "route_geojson": {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[126.978, 37.566], ...]
            },
            "properties": {
                "total_distance": 342.57
            }
        },
        "edges_geojson": {
            "type": "FeatureCollection",
            "features": [...]
        }
    }
    """

    success = serializers.BooleanField(help_text="경로 탐색 성공 여부")
    total_distance = serializers.FloatField(help_text="총 거리 (미터)")
    total_distance_display = serializers.CharField(help_text="표시용 거리 문자열")
    node_count = serializers.IntegerField(help_text="경유 노드 수")
    path_nodes = RouteNodeSerializer(many=True, help_text="경유 노드 목록 (순서대로)")
    route_geojson = serializers.DictField(
        help_text="전체 경로를 하나의 LineString 으로 합친 GeoJSON Feature"
    )
    edges_geojson = serializers.DictField(
        help_text="경로를 구성하는 개별 Edge 들의 GeoJSON FeatureCollection"
    )
