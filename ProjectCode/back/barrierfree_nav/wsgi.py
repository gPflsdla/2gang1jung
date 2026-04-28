"""
WSGI config for barrierfree_nav project.
"""
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "barrierfree_nav.settings")

application = get_wsgi_application()
