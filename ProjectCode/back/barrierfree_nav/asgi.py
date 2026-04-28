"""
ASGI config for barrierfree_nav project.
"""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "barrierfree_nav.settings")

application = get_asgi_application()
