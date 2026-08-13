from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from fieldos.auth import verify_token


class FakeAuth:
    def __init__(self, user):
        self._user = user

    def get_user(self, token):
        if token == "valid-token":
            return SimpleNamespace(user=self._user)
        return SimpleNamespace(user=None)


class FakeSupabase:
    def __init__(self, user):
        self.auth = FakeAuth(user)


def test_verify_token_returns_current_user_for_valid_token():
    fake_user = SimpleNamespace(id="user-123", email="pm@site.com", phone=None)
    supabase = FakeSupabase(fake_user)

    current_user = verify_token("valid-token", supabase)

    assert current_user.id == "user-123"
    assert current_user.email == "pm@site.com"


def test_verify_token_raises_401_for_invalid_token():
    supabase = FakeSupabase(user=None)

    with pytest.raises(HTTPException) as exc_info:
        verify_token("bad-token", supabase)

    assert exc_info.value.status_code == 401
