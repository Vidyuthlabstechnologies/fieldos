"""FieldOS API entrypoint.

Portable by design: no Docker, no GPU, no local LLM required. Defaults to a
local SQLite database (see fieldos/config.py) and only needs SUPABASE_URL /
SUPABASE_SERVICE_ROLE_KEY (a free Supabase Cloud project) for auth.

Run:  uvicorn api:app --reload
Then: curl http://localhost:8000/docs  (Swagger UI)
"""

from fieldos.app import create_fieldos_app

app = create_fieldos_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
