import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import fieldos.models  # noqa: F401  ensures all models are registered on Base.metadata
from fieldos.db import Base


@pytest.fixture()
def db_session():
    # StaticPool is required here: FastAPI's TestClient runs sync endpoints in a
    # worker thread, and without a shared connection, SQLite's `:memory:` DB would
    # be a fresh empty database per thread/connection ("no such table: ..." errors).
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)


from fastapi.testclient import TestClient

from fieldos.app import create_fieldos_app
from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db


def build_client(db_session, user_id="test-user-1"):
    app = create_fieldos_app()

    def override_get_db():
        yield db_session

    def override_get_current_user():
        return CurrentUser(id=user_id, email=f"{user_id}@example.com", phone=None)

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user
    return TestClient(app)
