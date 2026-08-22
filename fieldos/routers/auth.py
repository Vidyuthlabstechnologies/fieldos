from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, create_session, get_current_user, hash_password, verify_password
from fieldos.db import get_db
from fieldos.models import User
from fieldos.schemas import LoginRequest, RegisterRequest, SessionOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=SessionOut, status_code=201)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == body.username).first()
    if existing is not None:
        raise HTTPException(status_code=409, detail="Username already taken")

    user = User(username=body.username, name=body.name, password_hash=hash_password(body.password))
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        # Two requests can both pass the existence check above before either
        # commits (confirmed under real concurrent load: 10 simultaneous
        # registrations of the same username produced 9 raw 500s here
        # before this fix). The UNIQUE constraint is the real guard; this
        # just turns its failure into the same clean 409 the check above
        # already returns for the non-racing case.
        db.rollback()
        raise HTTPException(status_code=409, detail="Username already taken")
    token = create_session(db, user.id)
    return SessionOut(token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=SessionOut)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == body.username).first()
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    token = create_session(db, user.id)
    return SessionOut(token=token, user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def me(current_user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    user = db.get(User, current_user.id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return UserOut.model_validate(user)
