"""Local, fully offline authentication.

Passwords are hashed with bcrypt (SHA-256 pre-hashed first, since bcrypt
itself silently truncates input past 72 bytes -- pre-hashing means long
passwords are never quietly weakened). Sessions are opaque random tokens
stored server-side, not JWTs -- there's no distributed-verification need
for a single local install, and a DB-backed token is trivial to revoke.
"""

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session as DBSession

from fieldos.db import get_db
from fieldos.models import Session as SessionModel
from fieldos.models import User

SESSION_TTL_DAYS = 30
MIN_PASSWORD_LENGTH = 8


def _prehash(password: str) -> bytes:
    return hashlib.sha256(password.encode("utf-8")).digest()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_prehash(password), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(_prehash(password), password_hash.encode("utf-8"))


def create_session(db: DBSession, user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    db.add(
        SessionModel(
            token=token,
            user_id=user_id,
            expires_at=(datetime.now(timezone.utc) + timedelta(days=SESSION_TTL_DAYS)).replace(tzinfo=None),
        )
    )
    db.commit()
    return token


class CurrentUser:
    def __init__(self, id: str, username: str):
        self.id = id
        self.username = username


def verify_token(token: str, db: DBSession) -> CurrentUser:
    session = db.get(SessionModel, token)
    if session is None or session.expires_at < datetime.now(timezone.utc).replace(tzinfo=None):
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    user = db.get(User, session.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return CurrentUser(id=user.id, username=user.username)


def get_current_user(
    authorization: str | None = Header(default=None),
    db: DBSession = Depends(get_db),
) -> CurrentUser:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    return verify_token(token, db)
