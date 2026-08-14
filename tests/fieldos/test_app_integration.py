"""Confirms api.py exposes all FieldOS routes. api.py is a thin, dependency-free
entrypoint (see fieldos/app.py) with no RAG/GPU/model dependencies, so importing
it directly here is safe and cheap."""
from api import app

EXPECTED_TAGS = {"companies", "projects", "tasks", "dpr", "issues", "dashboard", "estimation"}


def test_api_py_includes_all_fieldos_routers():
    mounted_tags = {tag for route in app.routes for tag in getattr(route, "tags", [])}
    assert EXPECTED_TAGS <= mounted_tags, f"missing routers: {EXPECTED_TAGS - mounted_tags}"
