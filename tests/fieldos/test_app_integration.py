"""Confirms api.py exposes the FieldOS routes alongside the existing RAG routes,
without needing to load the RAG retriever (which requires GPU/model downloads)."""
import ast
from pathlib import Path


def test_api_py_includes_all_fieldos_routers():
    source = Path("api.py").read_text(encoding="utf-8")
    tree = ast.parse(source)
    include_router_calls = [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "include_router"
    ]
    assert len(include_router_calls) >= 6, "expected companies, projects, tasks, dpr, issues, dashboard routers mounted"
