from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from fieldos.auth import (
    create_session,
    hash_password,
    verify_password,
    verify_token,
)
from fieldos.models import Session as SessionModel
from fieldos.models import User


def test_hash_password_round_trips():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", hashed)


def test_verify_password_rejects_wrong_password():
    hashed = hash_password("correct horse battery staple")
    assert not verify_password("wrong password", hashed)


def test_hash_password_handles_passwords_longer_than_bcrypt_72_byte_limit():
    # bcrypt silently truncates input past 72 bytes; the SHA-256 pre-hash
    # in fieldos.auth means this must NOT happen here.
    long_password = "x" * 200
    hashed = hash_password(long_password)
    assert verify_password(long_password, hashed)
    assert not verify_password("x" * 199, hashed)


def test_verify_token_returns_current_user_for_valid_session(db_session):
    user = User(username="pm1", name="PM One", password_hash=hash_password("password123"))
    db_session.add(user)
    db_session.flush()
    token = create_session(db_session, user.id)

    current_user = verify_token(token, db_session)

    assert current_user.id == user.id
    assert current_user.username == "pm1"


def test_verify_token_raises_401_for_unknown_token(db_session):
    with pytest.raises(HTTPException) as exc_info:
        verify_token("no-such-token", db_session)
    assert exc_info.value.status_code == 401


def test_verify_token_raises_401_for_expired_session(db_session):
    user = User(username="pm2", name="PM Two", password_hash=hash_password("password123"))
    db_session.add(user)
    db_session.flush()
    db_session.add(
        SessionModel(token="expired-token", user_id=user.id, expires_at=datetime.utcnow() - timedelta(days=1))
    )
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        verify_token("expired-token", db_session)
    assert exc_info.value.status_code == 401
