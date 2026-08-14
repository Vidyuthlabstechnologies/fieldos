# PyInstaller spec for the packaged FieldOS backend.
#
# Bundles desktop_app.py (see that file's docstring) into a single native
# executable -- no Python install required on the end user's laptop. This
# only bundles the API backend; the static frontend (frontend/out, built by
# `npm run build` with output: 'export') is loaded directly by the Tauri
# shell (Task 26), not served by this process.
#
# Build with: pyinstaller desktop_app.spec

import pathlib

block_cipher = None

repo_root = pathlib.Path(".").resolve()

a = Analysis(
    ["desktop_app.py"],
    pathex=[str(repo_root)],
    binaries=[],
    datas=[
        # Alembic reads migration files from disk at runtime (not via the
        # normal frozen-import system) -- must ship as real data files.
        (str(repo_root / "fieldos" / "alembic" / "env.py"), "fieldos/alembic"),
        (str(repo_root / "fieldos" / "alembic" / "versions"), "fieldos/alembic/versions"),
    ],
    hiddenimports=[
        "bcrypt",
        "uvicorn.logging",
        "uvicorn.loops",
        "uvicorn.loops.auto",
        "uvicorn.protocols",
        "uvicorn.protocols.http",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan",
        "uvicorn.lifespan.on",
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="FieldOS-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
)
