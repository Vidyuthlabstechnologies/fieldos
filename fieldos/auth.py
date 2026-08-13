from fastapi import Depends, Header, HTTPException
from supabase import Client, create_client

from fieldos.config import settings


def get_supabase_admin() -> Client:
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


class CurrentUser:
    def __init__(self, id: str, email: str | None, phone: str | None):
        self.id = id
        self.email = email
        self.phone = phone


def verify_token(token: str, supabase) -> CurrentUser:
    resp = supabase.auth.get_user(token)
    if resp is None or resp.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    u = resp.user
    return CurrentUser(id=u.id, email=u.email, phone=u.phone)


def get_current_user(
    authorization: str | None = Header(default=None),
    supabase: Client = Depends(get_supabase_admin),
) -> CurrentUser:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    return verify_token(token, supabase)
