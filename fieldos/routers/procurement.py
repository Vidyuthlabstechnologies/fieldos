from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import (
    GRN,
    PurchaseOrder,
    PurchaseRequisition,
    Quote,
    RFQ,
    Vendor,
)
from fieldos.permissions import get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import (
    GRNCreate,
    GRNOut,
    PurchaseOrderCreate,
    PurchaseOrderOut,
    PurchaseRequisitionCreate,
    PurchaseRequisitionOut,
    QuoteCreate,
    QuoteOut,
    RFQCreate,
    RFQOut,
    VendorCreate,
    VendorOut,
)

router = APIRouter(tags=["procurement"])


# ---------------------------------------------------------------------------
# Vendors
# ---------------------------------------------------------------------------

@router.post("/companies/{company_id}/vendors", response_model=VendorOut, status_code=201)
def create_vendor(
    company_id: str,
    body: VendorCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    vendor = Vendor(company_id=company_id, **body.model_dump())
    db.add(vendor)
    db.commit()
    db.refresh(vendor)
    return vendor


@router.get("/companies/{company_id}/vendors", response_model=list[VendorOut])
def list_vendors(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM, ROLE_SITE_ENGINEER
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER, ROLE_PM, ROLE_SITE_ENGINEER})
    return db.query(Vendor).filter(Vendor.company_id == company_id).order_by(Vendor.name).all()


# ---------------------------------------------------------------------------
# Purchase Requisitions (site engineer requests)
# ---------------------------------------------------------------------------

@router.post("/projects/{project_id}/requisitions", response_model=PurchaseRequisitionOut, status_code=201)
def create_requisition(
    project_id: str,
    body: PurchaseRequisitionCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    req = PurchaseRequisition(
        project_id=project_id,
        requested_by=current_user.id,
        **body.model_dump(),
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return req


@router.get("/projects/{project_id}/requisitions", response_model=list[PurchaseRequisitionOut])
def list_requisitions(
    project_id: str,
    status: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    query = db.query(PurchaseRequisition).filter(PurchaseRequisition.project_id == project_id)
    if status:
        query = query.filter(PurchaseRequisition.status == status)
    return query.order_by(PurchaseRequisition.created_at.desc()).all()


@router.patch("/projects/{project_id}/requisitions/{req_id}/approve", response_model=PurchaseRequisitionOut)
def approve_requisition(
    project_id: str,
    req_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.models import Project
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    req = db.get(PurchaseRequisition, req_id)
    if req is None or req.project_id != project_id:
        raise HTTPException(status_code=404, detail="Requisition not found")

    from datetime import datetime, timezone

    req.status = "approved"
    req.approved_by = current_user.id
    req.approved_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(req)
    return req


# ---------------------------------------------------------------------------
# RFQ
# ---------------------------------------------------------------------------

@router.post("/projects/{project_id}/rfqs", response_model=RFQOut, status_code=201)
def create_rfq(
    project_id: str,
    body: RFQCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    rfq = RFQ(
        project_id=project_id,
        requisition_id=body.requisition_id,
        title=body.title,
        deadline=body.deadline,
        created_by=current_user.id,
    )
    db.add(rfq)
    db.commit()
    db.refresh(rfq)
    return rfq


@router.get("/projects/{project_id}/rfqs", response_model=list[RFQOut])
def list_rfqs(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(RFQ).filter(RFQ.project_id == project_id).order_by(RFQ.created_at.desc()).all()


# ---------------------------------------------------------------------------
# Quotes
# ---------------------------------------------------------------------------

@router.post("/rfqs/{rfq_id}/quotes", response_model=QuoteOut, status_code=201)
def create_quote(
    rfq_id: str,
    body: QuoteCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rfq = db.get(RFQ, rfq_id)
    if rfq is None:
        raise HTTPException(status_code=404, detail="RFQ not found")
    require_project_access(db, rfq.project_id, current_user.id)

    quote = Quote(rfq_id=rfq_id, **body.model_dump())
    db.add(quote)
    db.commit()
    db.refresh(quote)
    return quote


@router.get("/rfqs/{rfq_id}/quotes", response_model=list[QuoteOut])
def list_quotes(
    rfq_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rfq = db.get(RFQ, rfq_id)
    if rfq is None:
        raise HTTPException(status_code=404, detail="RFQ not found")
    require_project_access(db, rfq.project_id, current_user.id)
    return db.query(Quote).filter(Quote.rfq_id == rfq_id).order_by(Quote.total_amount).all()


# ---------------------------------------------------------------------------
# Purchase Orders
# ---------------------------------------------------------------------------

@router.post("/projects/{project_id}/purchase-orders", response_model=PurchaseOrderOut, status_code=201)
def create_purchase_order(
    project_id: str,
    body: PurchaseOrderCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    po = PurchaseOrder(
        project_id=project_id,
        created_by=current_user.id,
        **body.model_dump(),
    )
    db.add(po)
    db.commit()
    db.refresh(po)
    return po


@router.get("/projects/{project_id}/purchase-orders", response_model=list[PurchaseOrderOut])
def list_purchase_orders(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(PurchaseOrder).filter(PurchaseOrder.project_id == project_id).order_by(PurchaseOrder.created_at.desc()).all()


# ---------------------------------------------------------------------------
# GRN (Goods Receipt Notes)
# ---------------------------------------------------------------------------

@router.post("/purchase-orders/{po_id}/grn", response_model=GRNOut, status_code=201)
def create_grn(
    po_id: str,
    body: GRNCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    po = db.get(PurchaseOrder, po_id)
    if po is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    require_project_access(db, po.project_id, current_user.id)

    grn = GRN(
        purchase_order_id=po_id,
        received_by=current_user.id,
        **body.model_dump(),
    )
    db.add(grn)
    db.commit()
    db.refresh(grn)
    return grn


@router.get("/purchase-orders/{po_id}/grn", response_model=list[GRNOut])
def list_grns(
    po_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    po = db.get(PurchaseOrder, po_id)
    if po is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    require_project_access(db, po.project_id, current_user.id)
    return db.query(GRN).filter(GRN.purchase_order_id == po_id).order_by(GRN.received_date.desc()).all()
