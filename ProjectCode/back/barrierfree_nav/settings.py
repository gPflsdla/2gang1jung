"""
========================================================================
배리어프리 보행자 네비게이션 — Django settings
========================================================================
PostGIS + pgRouting + django-leaflet 기반 관리자 모드 환경 설정.
========================================================================
"""

from pathlib import Path

# =====================================================================
# 기본 경로
# =====================================================================
BASE_DIR = Path(__file__).resolve().parent.parent


# =====================================================================
# 보안 / 디버그
# =====================================================================
# ★ 운영 환경에서는 환경 변수로 분리하세요.
SECRET_KEY = "django-insecure-change-me-in-production"
DEBUG = True
ALLOWED_HOSTS = ["*"]


# =====================================================================
# 애플리케이션 정의
# =====================================================================
INSTALLED_APPS = [
    # ── Django 기본 앱 ──
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    # ── Django GIS 프레임워크 (PostGIS 연동 필수) ──
    "django.contrib.gis",

    # ── 서드파티 ──
    "rest_framework",       # Django REST Framework
    "leaflet",              # Leaflet 지도 위젯 (Admin 지도 UI 핵심)

    # ── 현재 네비게이션 앱 ──
    "navigation",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "barrierfree_nav.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "barrierfree_nav.wsgi.application"


# =====================================================================
# DATABASE 설정 — PostGIS 엔진 사용
# =====================================================================
DATABASES = {
    "default": {
        # ★ django.db.backends.postgresql 이 아닌 PostGIS 전용 엔진 사용!
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": "barrierfree_nav",
        "USER": "postgres",
        "PASSWORD": "your_password",
        "HOST": "localhost",
        "PORT": "5432",
    }
}


# =====================================================================
# 비밀번호 검증
# =====================================================================
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]


# =====================================================================
# 국제화 / 시간대
# =====================================================================
LANGUAGE_CODE = "ko-kr"
TIME_ZONE = "Asia/Seoul"
USE_I18N = True
USE_TZ = True


# =====================================================================
# 정적 파일 / 기본 PK 타입
# =====================================================================
STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"


# =====================================================================
# Django REST Framework
# =====================================================================
REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
        "rest_framework.renderers.BrowsableAPIRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
    ],
}


# =====================================================================
# LEAFLET_CONFIG — django-leaflet 전역 지도 설정
# =====================================================================
LEAFLET_CONFIG = {
    # ── 기본 타일 레이어 (배경 지도) ──
    "TILES": [
        (
            # 기본: OpenStreetMap
            "OpenStreetMap",
            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            {
                "attribution": "&copy; OpenStreetMap contributors",
                "maxZoom": 22,
            },
        ),
        (
            # 대안: CartoDB Positron (깔끔한 디자인)
            "CartoDB Light",
            "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
            {
                "attribution": "&copy; OpenStreetMap contributors &copy; CARTO",
                "maxZoom": 22,
            },
        ),
    ],

    # ── 초기 지도 뷰 설정 ──
    # 서울시청 좌표 (프로젝트 대상 지역에 맞게 수정)
    "DEFAULT_CENTER": (37.5665, 126.9780),
    "DEFAULT_ZOOM": 17,                      # 보행 네트워크에 적합한 줌 레벨
    "MIN_ZOOM": 5,
    "MAX_ZOOM": 22,

    # ── 지도 크기 기본값 ──
    "MAP_SIZE": ("100%", "500px"),

    # ── Leaflet.draw 플러그인 (도형 그리기 도구) ──
    "PLUGINS": {
        "draw": {
            "css": [
                "leaflet-draw/dist/leaflet.draw.css",
            ],
            "js": [
                "leaflet-draw/dist/leaflet.draw.js",
            ],
            "auto-include": True,
        },
    },

    # ── 기타 옵션 ──
    "SCALE": "both",          # 축척 표시 (미터 + 마일)
    "MINIMAP": False,         # 미니맵 비활성화 (Admin 에서는 불필요)
    "ATTRIBUTION_PREFIX": "배리어프리 네비게이션",
    "RESET_VIEW": False,      # 편집 시 뷰 리셋 방지
}


# =====================================================================
# GDAL / GEOS 라이브러리 경로 (OS 별 필요 시 설정)
# =====================================================================
# macOS (Homebrew)
# GDAL_LIBRARY_PATH = "/opt/homebrew/lib/libgdal.dylib"
# GEOS_LIBRARY_PATH = "/opt/homebrew/lib/libgeos_c.dylib"

# Ubuntu/Debian — 일반적으로 자동 감지되므로 설정 불필요
# GDAL_LIBRARY_PATH = "/usr/lib/libgdal.so"
# GEOS_LIBRARY_PATH = "/usr/lib/libgeos_c.so"

# Windows
# GDAL_LIBRARY_PATH = r"C:\OSGeo4W\bin\gdal309.dll"


# =====================================================================
# 로깅
# =====================================================================
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "[{asctime}] {levelname} {name} — {message}",
            "style": "{",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        },
    },
    "loggers": {
        "navigation": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}
