#!/usr/bin/env python
"""
========================================================================
배리어프리 보행자 네비게이션 — Django 관리 스크립트
========================================================================
runserver, migrate, makemigrations, createsuperuser 등
모든 Django 명령의 진입점.
========================================================================
"""
import os
import sys


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "barrierfree_nav.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Django 를 import 할 수 없습니다. 가상환경을 활성화했는지, "
            "requirements.txt 의 패키지가 설치되었는지 확인하세요."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
