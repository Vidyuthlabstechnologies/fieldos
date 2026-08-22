"""Confirms api.py exposes all FieldOS routes. api.py is a thin, dependency-free
entrypoint (see fieldos/app.py) with no RAG/GPU/model dependencies, so importing
it directly here is safe and cheap."""
from api import app

# realtime is excluded: it's a WebSocket-only router, and APIWebSocketRoute
# carries no `tags` attribute at all (tags are an OpenAPI/HTTP concept) --
# checked separately below via its path instead.
EXPECTED_TAGS = {
    "companies", "projects", "tasks", "dpr", "issues", "dashboard", "estimation",
    "settings", "portability", "materials", "workers", "attendance", "documents",
    "procurement", "equipment", "inspections", "billing",
}
EXPECTED_WEBSOCKET_PATHS = {"/projects/{project_id}/ws"}


def _collect(routes):
    # FastAPI's newer versions wrap included routers in an opaque _IncludedRouter
    # instead of flattening them into plain APIRoute objects on app.routes, so a
    # shallow getattr(route, "tags", []) silently sees nothing -- walk both the
    # old (flat) and new (original_router-wrapped) shapes.
    tags, paths = set(), set()
    for route in routes:
        tags.update(getattr(route, "tags", None) or [])
        path = getattr(route, "path", None)
        if path:
            paths.add(path)
        nested = getattr(route, "routes", None)
        if nested:
            nested_tags, nested_paths = _collect(nested)
            tags.update(nested_tags)
            paths.update(nested_paths)
        original_router = getattr(route, "original_router", None)
        if original_router is not None:
            nested_tags, nested_paths = _collect(getattr(original_router, "routes", []))
            tags.update(nested_tags)
            paths.update(nested_paths)
    return tags, paths


def test_api_py_includes_all_fieldos_routers():
    mounted_tags, mounted_paths = _collect(app.routes)
    assert EXPECTED_TAGS <= mounted_tags, f"missing routers: {EXPECTED_TAGS - mounted_tags}"
    assert EXPECTED_WEBSOCKET_PATHS <= mounted_paths, (
        f"missing websocket routes: {EXPECTED_WEBSOCKET_PATHS - mounted_paths}"
    )
