# 배리어프리 네비게이션 — 관리자 모드 환경 설정 가이드

## 1. Python 패키지 설치

```bash
# Django + DRF (이미 설치된 경우 생략)
pip install Django djangorestframework

# ★ PostGIS 연동 필수 패키지
pip install psycopg2-binary       # PostgreSQL 드라이버

# ★ 관리자 지도 UI 핵심 라이브러리
pip install django-leaflet        # Leaflet 지도 위젯 (Admin 통합)

# (선택) 고급 GIS 위젯이 필요한 경우
# pip install django-geojson      # GeoJSON 시리얼라이저 (API 단계에서 사용)
```

## 2. 시스템 라이브러리 설치 (OS별)

PostGIS, GDAL, GEOS 는 Django GIS 가 동작하기 위한 필수 시스템 의존성입니다.

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y \
    postgresql postgresql-contrib \
    postgis postgresql-16-postgis-3 \
    gdal-bin libgdal-dev \
    libgeos-dev \
    libproj-dev
```

### macOS (Homebrew)

```bash
brew install postgresql postgis gdal geos proj
```

### Windows

```
OSGeo4W 설치 프로그램 사용을 권장합니다:
https://trac.osgeo.org/osgeo4w/
→ Express Install → 모두 선택
```

## 3. PostgreSQL + PostGIS 데이터베이스 생성

```bash
# PostgreSQL 접속
sudo -u postgres psql

# DB 생성 및 PostGIS 확장 활성화
CREATE DATABASE barrierfree_nav;
\c barrierfree_nav
CREATE EXTENSION postgis;
CREATE EXTENSION pgrouting;    -- 단계 3(라우팅)에서 사용
\q
```

## 4. Django 마이그레이션 실행

```bash
python manage.py makemigrations navigation
python manage.py migrate
python manage.py createsuperuser
```

## 5. 개발 서버 실행 및 관리자 접속

```bash
python manage.py runserver
```

브라우저에서 `http://localhost:8000/admin/` 접속 후 로그인하면
Leaflet 지도가 포함된 관리자 인터페이스를 확인할 수 있습니다.

## 6. requirements.txt (종합)

```
Django>=4.2,<6.0
djangorestframework>=3.14
psycopg2-binary>=2.9
django-leaflet>=0.30
```
