from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
import datetime
import json
import logging
import os

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Company, CompanySubscription, SubscriptionPlan, BillingEvent
from fieldos.permissions import require_company_role, ROLE_OWNER
from fieldos.schemas import (
    SubscriptionPlanOut,
    CompanySubscriptionOut,
    BillingEventOut,
    CreateCheckoutSessionRequest,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/billing", tags=["billing"])


def _stripe_metadata_dict(obj) -> dict:
    """event.data.object (and its nested fields like .metadata) are
    stripe.StripeObject, not dicts -- newer stripe-python versions
    deliberately raise AttributeError on dict method names like .get() to
    force explicit .to_dict() conversion. Normalize to a plain dict here so
    every call site can just use .get()."""
    metadata = getattr(obj, "metadata", None) or {}
    return metadata.to_dict() if hasattr(metadata, "to_dict") else dict(metadata)

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY")


@router.get("/plans", response_model=list[SubscriptionPlanOut])
def list_plans(
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return db.query(SubscriptionPlan).filter(SubscriptionPlan.is_active == True).order_by(SubscriptionPlan.monthly_price_usd).all()


@router.get("/subscription", response_model=CompanySubscriptionOut)
def get_subscription(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER})
    sub = db.query(CompanySubscription).filter(CompanySubscription.company_id == company_id).first()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found")
    return sub


@router.post("/checkout-session")
async def create_checkout_session(
    company_id: str,
    body: CreateCheckoutSessionRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER})

    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=503, detail="Billing not configured")

    import stripe
    stripe.api_key = STRIPE_SECRET_KEY

    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Company not found")

    plan = db.get(SubscriptionPlan, body.plan_id)
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    # Get or create Stripe customer
    sub = db.query(CompanySubscription).filter(CompanySubscription.company_id == company_id).first()
    if not sub:
        sub = CompanySubscription(company_id=company_id)
        db.add(sub)
        db.commit()
        db.refresh(sub)

    customer_id = sub.stripe_customer_id
    if not customer_id:
        customer = stripe.Customer.create(
            email=current_user.username,
            name=company.name,
            metadata={"company_id": company_id},
        )
        customer_id = customer.id
        sub.stripe_customer_id = customer_id
        db.commit()

    # Create checkout session
    session = stripe.checkout.Session.create(
        customer=customer_id,
        payment_method_types=["card"],
        line_items=[{
            "price": plan.stripe_price_id,
            "quantity": 1,
        }],
        mode="subscription",
        success_url=body.success_url,
        cancel_url=body.cancel_url,
        metadata={"company_id": company_id, "plan_id": plan.id},
    )

    return {"url": session.url}


@router.post("/portal-session")
async def create_portal_session(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER})

    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=503, detail="Billing not configured")

    import stripe
    stripe.api_key = STRIPE_SECRET_KEY

    sub = db.query(CompanySubscription).filter(CompanySubscription.company_id == company_id).first()
    if not sub or not sub.stripe_customer_id:
        raise HTTPException(status_code=404, detail="No billing account found")

    session = stripe.billing_portal.Session.create(
        customer=sub.stripe_customer_id,
        return_url=f"{os.getenv('FRONTEND_URL', 'http://localhost:3000')}/settings?companyId={company_id}",
    )

    return {"url": session.url}


@router.get("/events", response_model=list[BillingEventOut])
def list_billing_events(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_company_role(db, company_id, current_user.id, {ROLE_OWNER})
    return db.query(BillingEvent).filter(BillingEvent.company_id == company_id).order_by(BillingEvent.created_at.desc()).limit(50).all()


# Stripe webhook endpoint (no auth, verified by signature)
@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    db: Session = Depends(get_db),
):
    import stripe

    webhook_secret = os.getenv("STRIPE_WEBHOOK_SECRET")
    if not STRIPE_SECRET_KEY or not webhook_secret:
        # Fail closed: without the signing secret we cannot distinguish a
        # genuine Stripe call from a forged one, and a 400 here would bait
        # callers into retrying forever. 503 says "not configured".
        logger.error("Stripe webhook called but STRIPE_SECRET_KEY/STRIPE_WEBHOOK_SECRET is not configured")
        raise HTTPException(status_code=503, detail="Billing not configured")

    if stripe.api_key != STRIPE_SECRET_KEY:
        stripe.api_key = STRIPE_SECRET_KEY

    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")
    if not sig_header:
        raise HTTPException(status_code=400, detail="Missing stripe-signature header")

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, webhook_secret)
    except stripe.error.SignatureVerificationError:
        # Forged or replayed request -- client gets a flat 400 with no
        # verifier internals leaked.
        logger.warning("Stripe webhook signature verification failed")
        raise HTTPException(status_code=400, detail="Invalid signature")
    except Exception:
        # Malformed payload / JSON -- same generic response, real cause logged.
        logger.exception("Stripe webhook payload could not be parsed/verified")
        raise HTTPException(status_code=400, detail="Invalid webhook payload")

    # Idempotency: skip if we've already processed this Stripe event
    existing = db.query(BillingEvent).filter(BillingEvent.stripe_event_id == event.id).first()
    if existing:
        return {"received": True}

    obj = event.data.object
    metadata_dict = _stripe_metadata_dict(obj)

    billing_event = BillingEvent(
        company_id=metadata_dict.get("company_id", "unknown"),
        event_type=event.type,
        stripe_event_id=event.id,
        amount_usd=getattr(obj, "amount", None),
        currency=getattr(obj, "currency", "usd"),
        description=event.type,
        event_metadata=json.dumps(metadata_dict),
    )
    db.add(billing_event)

    # amount is stored in cents (Stripe's native minor unit), NOT whole dollars -- do not divide by 100, the Integer column can't hold fractional dollars anyway

    # Handle subscription events
    if event.type == "checkout.session.completed":
        session = event.data.object
        session_metadata = _stripe_metadata_dict(session)
        company_id = session_metadata.get("company_id")
        plan_id = session_metadata.get("plan_id")
        if company_id and plan_id:
            sub = db.query(CompanySubscription).filter(CompanySubscription.company_id == company_id).first()
            if sub:
                sub.plan_id = plan_id
                sub.stripe_subscription_id = session.subscription
                sub.status = "active"
                db.commit()

    elif event.type in ("customer.subscription.updated", "customer.subscription.deleted"):
        subscription = event.data.object
        customer_id = subscription.customer
        sub = db.query(CompanySubscription).filter(CompanySubscription.stripe_customer_id == customer_id).first()
        if sub:
            if event.type == "customer.subscription.deleted":
                sub.status = "canceled"
                sub.plan_id = None
                sub.stripe_subscription_id = None
            else:
                sub.status = subscription.status
                sub.current_period_end = datetime.datetime.fromtimestamp(
                    subscription.current_period_end, tz=datetime.timezone.utc
                ).replace(tzinfo=None)
                sub.cancel_at_period_end = subscription.cancel_at_period_end
            db.commit()

    elif event.type == "invoice.payment_failed":
        subscription = event.data.object
        customer_id = subscription.customer
        sub = db.query(CompanySubscription).filter(CompanySubscription.stripe_customer_id == customer_id).first()
        if sub:
            sub.status = "past_due"
            db.commit()

    db.commit()
    return {"received": True}