"""
========================================================================
배리어프리(Barrier-Free) 보행자 네비게이션 시스템
Django Admin 설정 — Leaflet 지도 기반 관리자 인터페이스
========================================================================
django-leaflet 라이브러리를 활용하여 관리자가 지도 위에서 직접
마커(Node), 선(Edge), 다각형(Obstacle)을 그려서 저장할 수 있다.
========================================================================
"""

from django.contrib import admin
from django.contrib.gis.db import models as gis_models
from django.utils.html import format_html

# ── django-leaflet 의 지도 위젯 ──
from leaflet.admin import LeafletGeoAdmin, LeafletGeoAdminMixin
from leaflet.forms.widgets import LeafletWidget

# ── 현재 앱 모델 ──
from .models import Edge, ElevatorNode, Node, Obstacle


# =====================================================================
# 공통 Leaflet 위젯 설정 오버라이드
# =====================================================================
# LeafletGeoAdmin 은 기본적으로 모든 GeometryField 에 Leaflet 위젯을
# 자동 매핑하지만, 모델별로 draw 옵션을 세밀하게 제어하기 위해
# formfield_overrides 를 커스터마이징한다.

# Point 전용 위젯 설정 (Node, ElevatorNode)
POINT_WIDGET_ATTRS = {
    "map_width": "100%",        # 지도 폭: 관리자 패널에 꽉 차도록
    "map_height": "500px",      # 지도 높이: 충분히 넓게
    "display_raw": True,        # WKT 원본 표시 (디버깅용)
    "map_srid": 4326,           # WGS 84 좌표계
    "settings_overrides": {
        # ── Leaflet.draw 플러그인 옵션 ──
        # Point 만 그릴 수 있도록 나머지 도형 비활성화
        "PLUGINS": {
            "draw": {
                "js": [
                    "leaflet-draw/dist/leaflet.draw.js",
                ],
                "css": [
                    "leaflet-draw/dist/leaflet.draw.css",
                ],
                "auto-include": True,
            }
        }
    },
}

# LineString 전용 위젯 설정 (Edge)
LINE_WIDGET_ATTRS = {
    "map_width": "100%",
    "map_height": "500px",
    "display_raw": True,
    "map_srid": 4326,
}

# Geometry 전용 위젯 설정 (Obstacle — Polygon, LineString 등 모두 허용)
GEOMETRY_WIDGET_ATTRS = {
    "map_width": "100%",
    "map_height": "600px",      # 장애물 영역은 넓게 보면서 그려야 하므로 더 큼
    "display_raw": True,
    "map_srid": 4326,
}


# =====================================================================
# 1. Node Admin — 보행 네트워크 노드 관리
# =====================================================================
@admin.register(Node)
class NodeAdmin(LeafletGeoAdmin):
    """
    ★ 관리자가 지도 위에서 클릭하여 Point 마커를 찍으면
      해당 좌표가 geom 필드에 자동 입력된다.
    """

    # ── 목록 페이지 설정 ──
    list_display = (
        "name",
        "floor",
        "is_entrance",
        "has_elevator",       # 커스텀 컬럼: 엘리베이터 연결 여부
        "coordinates_display",  # 커스텀 컬럼: 좌표 미리보기
        "updated_at",
    )
    list_filter = ("is_entrance", "floor")
    search_fields = ("name",)
    list_editable = ("is_entrance",)          # 목록에서 바로 체크 가능
    list_per_page = 50
    ordering = ("-updated_at",)

    # ── 상세 페이지 필드 배치 ──
    fieldsets = (
        (
            "📍 기본 정보",
            {
                "fields": ("name", "floor", "is_entrance"),
            },
        ),
        (
            "🗺️ 위치 (지도에서 클릭하여 마커를 찍으세요)",
            {
                "fields": ("geom",),
                "description": (
                    "아래 지도에서 원하는 위치를 클릭하면 자동으로 좌표가 입력됩니다. "
                    "기존 마커를 드래그하여 위치를 수정할 수도 있습니다."
                ),
            },
        ),
    )
    readonly_fields = ("created_at", "updated_at")

    # ── Leaflet 지도 위젯 세부 설정 ──
    # LeafletGeoAdmin 이 자동으로 PointField 에 Leaflet 위젯을 적용한다.
    # 아래 settings_overrides 로 지도의 초기 중심·줌 레벨 등을 제어한다.
    settings_overrides = {
        "DEFAULT_CENTER": (37.5665, 126.9780),  # 서울시청 (초기 지도 중심)
        "DEFAULT_ZOOM": 17,                      # 보행 단위에 적합한 줌 레벨
        "MIN_ZOOM": 10,
        "MAX_ZOOM": 22,
        "TILES": [
            (
                "OpenStreetMap",
                "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                {
                    "attribution": "&copy; OpenStreetMap contributors",
                    "maxZoom": 22,
                },
            ),
        ],
    }

    # ── 커스텀 목록 컬럼 메서드 ──
    @admin.display(boolean=True, description="엘리베이터")
    def has_elevator(self, obj):
        """이 노드에 연결된 ElevatorNode 가 있는지 표시"""
        return hasattr(obj, "elevator")

    @admin.display(description="좌표 (경도, 위도)")
    def coordinates_display(self, obj):
        """목록에서 좌표를 읽기 쉽게 표시"""
        if obj.geom:
            return f"({obj.geom.x:.6f}, {obj.geom.y:.6f})"
        return "-"


# =====================================================================
# 2. Edge Admin — 보행 경로(간선) 관리
# =====================================================================
@admin.register(Edge)
class EdgeAdmin(LeafletGeoAdmin):
    """
    ★ 관리자가 지도 위에서 LineString 을 직접 그려 간선을 등록한다.
      출발/도착 Node 를 드롭다운에서 선택하고, 지도에서 경로를 그리면
      save() 시 length 가 자동 계산된다.
    """

    # ── 목록 페이지 설정 ──
    list_display = (
        "edge_label",
        "source",
        "target",
        "length_display",
        "is_bidirectional",
        "updated_at",
    )
    list_filter = ("is_bidirectional",)
    search_fields = (
        "source__name",
        "target__name",
    )
    list_per_page = 50
    ordering = ("-updated_at",)

    # ── 외래키 선택 최적화 ──
    raw_id_fields = ("source", "target")       # 노드가 많을 때 팝업 검색 활성화
    autocomplete_fields = ("source", "target")  # 자동완성 (search_fields 필요)

    # ── 상세 페이지 필드 배치 ──
    fieldsets = (
        (
            "🔗 연결 노드",
            {
                "fields": ("source", "target", "is_bidirectional"),
            },
        ),
        (
            "🗺️ 경로 선형 (지도에서 선을 그려주세요)",
            {
                "fields": ("geom",),
                "description": (
                    "아래 지도에서 출발점부터 도착점까지 경로를 따라 선(LineString)을 그리세요. "
                    "저장 시 물리적 거리(미터)가 자동 계산됩니다."
                ),
            },
        ),
        (
            "📏 거리 정보 (자동 계산)",
            {
                "fields": ("length",),
                "description": "이 필드는 저장 시 자동으로 계산됩니다. 수동 수정은 권장하지 않습니다.",
            },
        ),
    )
    readonly_fields = ("length", "created_at", "updated_at")

    # ── Leaflet 지도 설정 ──
    settings_overrides = {
        "DEFAULT_CENTER": (37.5665, 126.9780),
        "DEFAULT_ZOOM": 17,
        "MIN_ZOOM": 10,
        "MAX_ZOOM": 22,
    }

    # ── 커스텀 목록 컬럼 메서드 ──
    @admin.display(description="구간")
    def edge_label(self, obj):
        src = obj.source.name or str(obj.source_id)[:8]
        tgt = obj.target.name or str(obj.target_id)[:8]
        return f"{src} → {tgt}"

    @admin.display(description="거리")
    def length_display(self, obj):
        """거리를 사람이 읽기 좋은 형태로 표시"""
        if obj.length >= 1000:
            return f"{obj.length / 1000:.2f} km"
        return f"{obj.length:.1f} m"


# =====================================================================
# 3. ElevatorNode Admin — 엘리베이터 관리 (Inline + Standalone)
# =====================================================================

# ── 3-A. Node 상세 페이지에 Inline 으로 표시 ──
class ElevatorNodeInline(LeafletGeoAdminMixin, admin.StackedInline):
    """
    Node 상세 페이지에서 곧바로 '이 노드는 엘리베이터입니다' 설정을
    추가/수정할 수 있도록 인라인 위젯으로 제공한다.
    """

    model = ElevatorNode
    extra = 0                  # 기본적으로 빈 폼을 보여주지 않음
    min_num = 0
    max_num = 1                # 하나의 Node 에 최대 1개의 ElevatorNode
    verbose_name = "엘리베이터 정보"
    verbose_name_plural = "엘리베이터 정보"

    fieldsets = (
        (
            None,
            {
                "fields": (
                    "name",
                    "building_name",
                    "available_floors",
                    "is_available",
                ),
                "description": (
                    "이 노드를 엘리베이터로 등록하려면 아래 정보를 입력하세요. "
                    "엘리베이터 경유 Edge 의 length 는 0 으로 설정하여 "
                    "수직 이동 비용이 발생하지 않도록 합니다."
                ),
            },
        ),
    )


# Node Admin 에 Inline 추가
NodeAdmin.inlines = [ElevatorNodeInline]


# ── 3-B. 독립 관리 페이지 (지도에서 엘리베이터 위치 확인/수정) ──
@admin.register(ElevatorNode)
class ElevatorNodeAdmin(LeafletGeoAdmin):
    """
    ★ 엘리베이터 전용 관리 페이지.
      지도에서 연결된 Node 의 위치를 확인하고,
      엘리베이터 속성(운행 층, 사용 가능 여부 등)을 관리한다.

    ★ ElevatorNode 자체에는 geom 이 없으므로 LeafletGeoAdmin 의
      지도 기능은 연결된 Node 편집 시 간접적으로 활용된다.
      여기서는 속성 관리에 집중한다.
    """

    # ── 목록 페이지 설정 ──
    list_display = (
        "name",
        "building_name",
        "available_floors",
        "is_available",
        "node_location_display",  # 커스텀: 연결된 노드의 좌표
        "updated_at",
    )
    list_filter = ("is_available", "building_name")
    search_fields = ("name", "building_name", "node__name")
    list_editable = ("is_available",)          # 목록에서 바로 운행 상태 전환
    list_per_page = 50
    ordering = ("building_name", "name")

    # ── 상세 페이지 필드 배치 ──
    fieldsets = (
        (
            "🛗 엘리베이터 정보",
            {
                "fields": ("name", "building_name", "available_floors", "is_available"),
            },
        ),
        (
            "📍 연결 노드",
            {
                "fields": ("node",),
                "description": (
                    "이 엘리베이터와 1:1로 연결된 노드를 선택하세요. "
                    "노드의 좌표가 곧 엘리베이터의 지도상 위치입니다. "
                    "새 노드를 먼저 생성한 후 여기서 연결하세요."
                ),
            },
        ),
    )
    raw_id_fields = ("node",)
    readonly_fields = ("created_at", "updated_at")

    # ── 커스텀 목록 컬럼 ──
    @admin.display(description="노드 위치")
    def node_location_display(self, obj):
        """연결된 Node 의 좌표를 표시"""
        if obj.node and obj.node.geom:
            return f"({obj.node.geom.x:.6f}, {obj.node.geom.y:.6f})"
        return "-"


# =====================================================================
# 4. Obstacle Admin — 장애물(계단·급경사) 영역 관리
# =====================================================================
@admin.register(Obstacle)
class ObstacleAdmin(LeafletGeoAdmin):
    """
    ★ 관리자가 지도 위에서 다각형(Polygon), 선(LineString), 복합 면(MultiPolygon)을
      직접 그려서 장애물 영역을 등록한다.

    ★ GeometryField 를 사용하므로 Leaflet.draw 의 모든 도형 도구
      (Polygon, Rectangle, Polyline, Circle 등)가 활성화된다.
      관리자는 상황에 맞는 도형을 자유롭게 선택할 수 있다.

    ★ 저장된 장애물 영역과 겹치는(ST_Intersects) Edge 는
      라우팅 쿼리에서 완전히 제외된다.
    """

    # ── 목록 페이지 설정 ──
    list_display = (
        "name",
        "obstacle_type_badge",   # 커스텀: 종류를 컬러 배지로 표시
        "is_active",
        "geometry_type_display",  # 커스텀: 저장된 Geometry 타입 표시
        "updated_at",
    )
    list_filter = ("obstacle_type", "is_active")
    search_fields = ("name", "description")
    list_editable = ("is_active",)
    list_per_page = 50
    ordering = ("-updated_at",)

    # ── 상세 페이지 필드 배치 ──
    fieldsets = (
        (
            "⚠️ 장애물 정보",
            {
                "fields": ("name", "obstacle_type", "description", "is_active"),
            },
        ),
        (
            "🗺️ 장애물 영역 (지도에서 도형을 그려주세요)",
            {
                "fields": ("geom",),
                "description": (
                    "아래 지도의 왼쪽 도구모음에서 그리기 도구를 선택한 후 "
                    "장애물 영역을 그려주세요.\n"
                    "• Polygon(다각형): 넓은 계단 영역, 광장 등\n"
                    "• Polyline(선): 좁은 경사 구간, 도로 위 턱 등\n"
                    "• Rectangle(사각형): 공사 구간 등 직사각형 영역\n\n"
                    "그린 영역과 겹치는 모든 보행 경로(Edge)는 "
                    "라우팅에서 자동으로 제외됩니다."
                ),
            },
        ),
    )
    readonly_fields = ("created_at", "updated_at")

    # ── Leaflet 지도 설정 (장애물용 — 더 넓은 뷰) ──
    settings_overrides = {
        "DEFAULT_CENTER": (37.5665, 126.9780),  # 서울시청
        "DEFAULT_ZOOM": 17,
        "MIN_ZOOM": 10,
        "MAX_ZOOM": 22,
        # GeometryField 는 모든 draw 도구 활성화됨 (Leaflet 기본 동작)
    }

    # ── GeometryField 에 Leaflet 위젯 명시 적용 ──
    formfield_overrides = {
        gis_models.GeometryField: {
            "widget": LeafletWidget(
                attrs={
                    "map_width": "100%",
                    "map_height": "600px",
                    "display_raw": True,
                    "map_srid": 4326,
                }
            )
        },
    }

    # ── 커스텀 목록 컬럼 메서드 ──
    @admin.display(description="종류")
    def obstacle_type_badge(self, obj):
        """장애물 종류를 시각적으로 구분되는 컬러 배지로 표시"""
        color_map = {
            "STAIRS": "#e74c3c",       # 빨강 — 계단
            "STEEP_SLOPE": "#e67e22",  # 주황 — 급경사
            "CONSTRUCTION": "#f39c12",  # 노랑 — 공사
            "UNPAVED": "#8B4513",      # 갈색 — 비포장
            "NARROW_PATH": "#9b59b6",  # 보라 — 협소
            "OTHER": "#95a5a6",        # 회색 — 기타
        }
        color = color_map.get(obj.obstacle_type, "#95a5a6")
        label = obj.get_obstacle_type_display()
        return format_html(
            '<span style="'
            "background-color: {}; color: #fff; padding: 3px 10px; "
            'border-radius: 12px; font-size: 11px; font-weight: bold;"'
            ">{}</span>",
            color,
            label,
        )

    @admin.display(description="도형 타입")
    def geometry_type_display(self, obj):
        """저장된 Geometry 의 실제 타입을 표시 (Polygon, LineString 등)"""
        if obj.geom:
            return obj.geom.geom_type
        return "-"


# =====================================================================
# Admin Site 전역 커스터마이징
# =====================================================================
admin.site.site_header = "🦽 배리어프리 네비게이션 관리자"
admin.site.site_title = "BF-Nav Admin"
admin.site.index_title = "보행 네트워크 & 장애물 관리"
