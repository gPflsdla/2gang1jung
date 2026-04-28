"""
========================================================================
배리어프리(Barrier-Free) 보행자 네비게이션 시스템
Django 데이터베이스 모델 (PostGIS 기반)
========================================================================
- Node       : 교차로·지점 (보행 네트워크 그래프의 꼭짓점)
- Edge       : 두 Node를 잇는 도로/길 (그래프의 간선)
- ElevatorNode : 건물 내 엘리베이터 (수직 이동 거리 = 0인 특수 노드)
- Obstacle   : 관리자가 지정한 장애물 영역 (계단·급경사 등)
========================================================================
"""

import uuid

from django.contrib.gis.db import models as gis_models
from django.contrib.gis.geos import GEOSGeometry
from django.contrib.gis.measure import D
from django.db import models


# ──────────────────────────────────────────────
# 1. Node 모델 — 보행 네트워크의 노드(꼭짓점)
# ──────────────────────────────────────────────
class Node(models.Model):
    """
    교차로, 건물 출입구, 횡단보도 끝점 등 보행 네트워크 상의 **지점**을 표현한다.
    pgRouting에서 source/target 역할을 수행하는 핵심 엔티티이다.
    """

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        help_text="노드 고유 식별자 (UUID v4)",
    )

    # ---- 공간 필드 ----
    # SRID 4326 = WGS 84 경위도 좌표계 (GPS 기본 좌표계)
    # geography=True → 구면 위에서의 실제 미터 거리 계산 가능
    geom = gis_models.PointField(
        srid=4326,
        geography=True,
        verbose_name="좌표(Point)",
        help_text="노드의 WGS 84 좌표 (경도, 위도)",
    )

    # ---- 속성 필드 ----
    name = models.CharField(
        max_length=200,
        blank=True,
        default="",
        verbose_name="지점 이름",
        help_text="교차로명, 건물 출입구명 등 사람이 읽을 수 있는 이름",
    )

    floor = models.IntegerField(
        default=1,
        verbose_name="층 수",
        help_text="해당 노드가 위치한 층 (지상 1층 = 1, 지하 1층 = -1)",
    )

    is_entrance = models.BooleanField(
        default=False,
        verbose_name="건물 출입구 여부",
        help_text="True이면 건물 출입구로서 ElevatorNode 연결 대상이 됨",
    )

    # ---- 메타 ----
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성 시각")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정 시각")

    class Meta:
        db_table = "nav_node"
        verbose_name = "노드"
        verbose_name_plural = "노드 목록"
        indexes = [
            # 공간 인덱스는 PointField(geography=True) 생성 시 자동으로
            # GiST 인덱스가 생성되므로 별도 설정하지 않는다.
        ]

    def __str__(self) -> str:
        return f"[Node] {self.name or '이름 없음'} ({self.geom.x:.6f}, {self.geom.y:.6f})"


# ──────────────────────────────────────────────
# 2. Edge 모델 — 두 Node를 잇는 간선(도로/길)
# ──────────────────────────────────────────────
class Edge(models.Model):
    """
    보행 네트워크 그래프의 **간선**으로, 두 Node 사이 실제 보행 경로를 표현한다.
    length 필드는 save() 시 LineString의 물리적 길이(미터)로 자동 계산된다.
    pgRouting 쿼리에서 cost/reverse_cost 로 사용된다.
    """

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        help_text="간선 고유 식별자 (UUID v4)",
    )

    # ---- 그래프 관계 ----
    source = models.ForeignKey(
        Node,
        on_delete=models.CASCADE,
        related_name="edges_from",
        verbose_name="출발 노드",
        help_text="이 간선의 시작 지점 (Node FK)",
    )

    target = models.ForeignKey(
        Node,
        on_delete=models.CASCADE,
        related_name="edges_to",
        verbose_name="도착 노드",
        help_text="이 간선의 끝 지점 (Node FK)",
    )

    # ---- 공간 필드 ----
    # geography=True 로 설정하여 .length 속성이 미터 단위를 반환하도록 한다.
    geom = gis_models.LineStringField(
        srid=4326,
        geography=True,
        verbose_name="경로 선형(LineString)",
        help_text="두 노드를 잇는 실제 보행 경로의 선형 데이터",
    )

    # ---- 비용(거리) 필드 ----
    length = models.FloatField(
        default=0.0,
        verbose_name="물리적 거리(m)",
        help_text="LineString의 실제 길이(미터). save() 시 자동 계산됨",
    )

    # ---- 양방향 통행 여부 ----
    is_bidirectional = models.BooleanField(
        default=True,
        verbose_name="양방향 통행 가능",
        help_text="True이면 양방향, False이면 source→target 단방향만 가능",
    )

    # ---- 메타 ----
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성 시각")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정 시각")

    class Meta:
        db_table = "nav_edge"
        verbose_name = "간선"
        verbose_name_plural = "간선 목록"
        indexes = [
            models.Index(fields=["source", "target"], name="idx_edge_src_tgt"),
        ]

    def __str__(self) -> str:
        return (
            f"[Edge] {self.source.name or self.source_id} → "
            f"{self.target.name or self.target_id}  ({self.length:.2f}m)"
        )

    # ──── length 자동 계산 (save 오버라이딩) ────
    def save(self, *args, **kwargs):
        """
        저장 시 LineString(geom)의 물리적 길이를 미터 단위로 계산하여
        length 필드에 자동 기록한다.

        ★ geography=True 일 때 GEOSGeometry.length 는 **미터**를 반환하므로
           별도 좌표 변환(ST_Transform) 없이 정확한 실거리를 얻을 수 있다.
        """
        if self.geom:
            # geography=True 이므로 .length 가 미터 단위 실거리
            self.length = self.geom.length
        super().save(*args, **kwargs)


# ──────────────────────────────────────────────
# 3. ElevatorNode 모델 — 엘리베이터 특수 노드
# ──────────────────────────────────────────────
class ElevatorNode(models.Model):
    """
    건물 내 엘리베이터를 표현하는 **특수 노드**.

    ★ 핵심 비즈니스 로직:
      - 엘리베이터는 고도를 무시하는 '단일 노드(Single Point Node)'이다.
      - 이 노드를 경유하는 Edge의 수직 이동 거리는 0으로 간주된다.
      - 건물 출입구 Node → ElevatorNode 를 잇는 Edge는 length=0 으로
        생성되어, 평지를 빙 둘러가는 것보다 건물 관통이 최단이면
        자동으로 엘리베이터 경유 경로가 선택된다.

    Node 와 1:1 관계(OneToOneField)로 연결되어,
    해당 Node가 '엘리베이터'임을 명시적으로 식별할 수 있게 한다.
    """

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        help_text="엘리베이터 노드 고유 식별자",
    )

    # ---- Node 와의 1:1 연결 ----
    node = models.OneToOneField(
        Node,
        on_delete=models.CASCADE,
        related_name="elevator",
        verbose_name="연결 노드",
        help_text="이 엘리베이터가 위치한 Node (1:1 관계)",
    )

    # ---- 식별·정보 필드 ----
    name = models.CharField(
        max_length=200,
        verbose_name="엘리베이터 이름",
        help_text="예: '공학관 1동 엘리베이터', '지하철역 3번 출구 E/V'",
    )

    building_name = models.CharField(
        max_length=200,
        blank=True,
        default="",
        verbose_name="건물명",
        help_text="엘리베이터가 소속된 건물 이름",
    )

    available_floors = models.CharField(
        max_length=100,
        blank=True,
        default="",
        verbose_name="운행 층 정보",
        help_text="운행 가능한 층 목록 (예: 'B2,B1,1,2,3,4,5')",
    )

    is_available = models.BooleanField(
        default=True,
        verbose_name="사용 가능 여부",
        help_text="고장·점검 등으로 사용 불가 시 False 로 설정하면 라우팅에서 제외",
    )

    # ---- 메타 ----
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성 시각")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정 시각")

    class Meta:
        db_table = "nav_elevator_node"
        verbose_name = "엘리베이터 노드"
        verbose_name_plural = "엘리베이터 노드 목록"

    def __str__(self) -> str:
        status = "운행중" if self.is_available else "사용불가"
        return f"[E/V] {self.name} ({status})"


# ──────────────────────────────────────────────
# 4. Obstacle 모델 — 장애물(계단·급경사) 영역
# ──────────────────────────────────────────────
class Obstacle(models.Model):
    """
    관리자가 지도 위에 그리는 **장애물 영역** (계단, 급경사 등).

    ★ 핵심 비즈니스 로직:
      - 라우팅 시 이 장애물의 geom 과 Intersect(교차)하는 Edge 는
        탐색에서 **완전히 제외** 된다.
      - GeometryField 를 사용하여 Polygon, LineString, MultiPolygon 등
        모든 Geometry 타입을 유연하게 저장할 수 있다.

    관리자가 넓은 계단 영역은 Polygon 으로, 좁은 경사 구간은
    LineString(일정 버퍼 적용)으로 그릴 수 있어 실무 유연성을 확보한다.
    """

    # ---- 장애물 종류 상수 ----
    class ObstacleType(models.TextChoices):
        STAIRS = "STAIRS", "계단"
        STEEP_SLOPE = "STEEP_SLOPE", "급경사"
        CONSTRUCTION = "CONSTRUCTION", "공사 구간"
        UNPAVED = "UNPAVED", "비포장 구간"
        NARROW_PATH = "NARROW_PATH", "협소 통로"
        OTHER = "OTHER", "기타"

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        help_text="장애물 고유 식별자",
    )

    # ---- 공간 필드 ----
    # GeometryField → Polygon, LineString, MultiPolygon 등 모두 수용 가능
    geom = gis_models.GeometryField(
        srid=4326,
        verbose_name="장애물 영역(Geometry)",
        help_text=(
            "관리자가 지도에서 그린 장애물 영역. "
            "Polygon(면), LineString(선), MultiPolygon(복합 면) 모두 허용"
        ),
    )

    # ---- 속성 필드 ----
    obstacle_type = models.CharField(
        max_length=20,
        choices=ObstacleType.choices,
        default=ObstacleType.OTHER,
        verbose_name="장애물 종류",
        help_text="계단(STAIRS), 급경사(STEEP_SLOPE), 공사 구간 등",
    )

    name = models.CharField(
        max_length=200,
        blank=True,
        default="",
        verbose_name="장애물 이름",
        help_text="예: '공학관 뒤편 계단', '정문 언덕 급경사'",
    )

    description = models.TextField(
        blank=True,
        default="",
        verbose_name="상세 설명",
        help_text="장애물에 대한 추가 설명 (관리자 참고용)",
    )

    is_active = models.BooleanField(
        default=True,
        verbose_name="활성 여부",
        help_text="False 로 설정하면 라우팅 제외 대상에서 임시 해제",
    )

    # ---- 메타 ----
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성 시각")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정 시각")

    class Meta:
        db_table = "nav_obstacle"
        verbose_name = "장애물"
        verbose_name_plural = "장애물 목록"

    def __str__(self) -> str:
        label = self.get_obstacle_type_display()
        return f"[장애물] {self.name or '이름 없음'} ({label})"
