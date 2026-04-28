"""
========================================================================
배리어프리 보행자 네비게이션 — URL 설정
========================================================================
navigation 앱의 API 엔드포인트 라우팅을 정의한다.

엔드포인트 목록:
  POST /api/v1/route/    — 최단 경로 탐색 (JSON Body)
  GET  /api/v1/route/    — 최단 경로 탐색 (Query Params)
  GET  /api/v1/health/   — 라우팅 엔진 헬스체크
========================================================================
"""

from django.urls import path

from .views import HealthCheckView, RouteView

app_name = "navigation"

urlpatterns = [
    # ── 경로 탐색 API ──
    path("route/", RouteView.as_view(), name="route"),

    # ── 헬스체크 ──
    path("health/", HealthCheckView.as_view(), name="health"),
]

# =====================================================================
# 프로젝트 루트 urls.py 에 아래와 같이 포함하세요:
# =====================================================================
#
# from django.urls import path, include
#
# urlpatterns = [
#     path("admin/", admin.site.urls),
#     path("api/v1/", include("navigation.urls", namespace="navigation")),
# ]
