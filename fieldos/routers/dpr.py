import httpx
from fastapi import APIRouter, Depends, HTTPException, UploadFile

from sqlalchemy.orm import Session

from fieldos import sarvam
from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import DPREntry, DPRPhoto
from fieldos.permissions import require_project_access
from fieldos.schemas import DPREntryCreate, DPREntryOut, DPRPhotoCreate, DPRPhotoOut, DPRVoiceDraft

router = APIRouter(prefix="/projects/{project_id}/dpr", tags=["dpr"])


@router.post("", response_model=DPREntryOut, status_code=201)
def create_dpr_entry(
    project_id: str,
    body: DPREntryCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    entry = DPREntry(
        project_id=project_id,
        created_by=current_user.id,
        entry_date=body.entry_date,
        work_summary=body.work_summary,
        manpower_count=body.manpower_count,
        weather=body.weather,
        status="confirmed",
        source="manual",
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get("", response_model=list[DPREntryOut])
def list_dpr_entries(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(DPREntry)
        .filter(DPREntry.project_id == project_id)
        .order_by(DPREntry.entry_date.desc())
        .all()
    )


@router.post("/voice-draft", response_model=DPRVoiceDraft)
def create_dpr_voice_draft(
    project_id: str,
    audio: UploadFile,
    language_code: str = "unknown",
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Transcribes + structures a spoken DPR into a draft -- NOT saved. The
    caller reviews/edits the draft, then POSTs it to the normal create-entry
    endpoint like any manually-typed DPR. See fieldos/sarvam.py."""
    require_project_access(db, project_id, current_user.id)

    api_key = sarvam.get_effective_api_key(db)
    if not api_key:
        raise HTTPException(
            status_code=503, detail="Voice-to-DPR isn't configured -- add a Sarvam API key in Settings"
        )

    audio_bytes = audio.file.read()
    try:
        transcript = sarvam.transcribe_audio(audio_bytes, audio.filename or "recording.webm", api_key, language_code)
        if not transcript.strip():
            raise HTTPException(status_code=422, detail="No speech detected in the recording -- try again")
        structured = sarvam.structure_dpr_from_transcript(transcript, api_key)
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Voice transcription failed: {e}")

    return DPRVoiceDraft(transcript=transcript, **structured)


@router.post("/{dpr_id}/photos", response_model=DPRPhotoOut, status_code=201)
def add_dpr_photo(
    project_id: str,
    dpr_id: str,
    body: DPRPhotoCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    entry = db.get(DPREntry, dpr_id)
    if entry is None or entry.project_id != project_id:
        raise HTTPException(status_code=404, detail="DPR entry not found")

    photo = DPRPhoto(dpr_entry_id=dpr_id, photo_url=body.photo_url, caption=body.caption)
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo
