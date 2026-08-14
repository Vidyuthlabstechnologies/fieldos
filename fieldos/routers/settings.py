from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import AppSetting
from fieldos.sarvam import SETTING_KEY, get_effective_api_key
from fieldos.schemas import SarvamKeyUpdate, SarvamStatusOut

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/sarvam", response_model=SarvamStatusOut)
def get_sarvam_status(
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return SarvamStatusOut(configured=bool(get_effective_api_key(db)))


@router.put("/sarvam", response_model=SarvamStatusOut, status_code=200)
def set_sarvam_key(
    body: SarvamKeyUpdate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.get(AppSetting, SETTING_KEY)
    if row is None:
        row = AppSetting(key=SETTING_KEY, value=body.api_key)
        db.add(row)
    else:
        row.value = body.api_key
    db.commit()
    return SarvamStatusOut(configured=True)


@router.delete("/sarvam", response_model=SarvamStatusOut)
def clear_sarvam_key(
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.get(AppSetting, SETTING_KEY)
    if row is not None:
        db.delete(row)
        db.commit()
    return SarvamStatusOut(configured=bool(get_effective_api_key(db)))
