from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Company, CompanyMember
from fieldos.schemas import CompanyCreate, CompanyOut

router = APIRouter(prefix="/companies", tags=["companies"])


@router.post("", response_model=CompanyOut, status_code=201)
def create_company(
    body: CompanyCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    company = Company(name=body.name)
    db.add(company)
    db.flush()

    db.add(CompanyMember(company_id=company.id, user_id=current_user.id, role="owner"))
    db.commit()
    db.refresh(company)
    return company


@router.get("/mine", response_model=list[CompanyOut])
def list_my_companies(
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    memberships = db.query(CompanyMember).filter(CompanyMember.user_id == current_user.id).all()
    company_ids = [m.company_id for m in memberships]
    if not company_ids:
        return []
    return db.query(Company).filter(Company.id.in_(company_ids)).all()
