"""
========================================================================
배리어프리 보행자 네비게이션 — Django App Config
========================================================================
"""

from django.apps import AppConfig


class NavigationConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "navigation"
    verbose_name = "배리어프리 네비게이션"
