"""
========================================================================
배리어프리 보행자 네비게이션 — 프로젝트 루트 URL 설정
========================================================================
  /admin/      → Django Admin (Leaflet 지도 기반 관리자)
  /api/v1/     → navigation 앱 API
========================================================================
"""

from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("navigation.urls", namespace="navigation")),
]
