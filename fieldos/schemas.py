from datetime import date, datetime
from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


# Auth
class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=100)
    name: str = Field(min_length=1, max_length=200)
    password: str = Field(min_length=8, max_length=200)


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    username: str
    name: str


class SessionOut(BaseModel):
    token: str
    user: UserOut


# Companies
class CompanyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)


class CompanyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    name: str
    created_at: datetime


# Projects
class ProjectCreate(BaseModel):
    company_id: str
    name: str
    client_name: Optional[str] = None
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    geofence_radius_m: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class ProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    company_id: str
    name: str
    client_name: Optional[str]
    location_lat: Optional[float]
    location_lng: Optional[float]
    geofence_radius_m: Optional[int]
    start_date: Optional[date]
    end_date: Optional[date]
    status: str
    created_at: datetime


class ProjectMemberAdd(BaseModel):
    user_id: str
    role: Literal["owner", "project_manager", "site_engineer"]


class ProjectMemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    user_id: str
    role: str


# Tasks
class TaskCreate(BaseModel):
    title: str
    assignee_id: Optional[str] = None
    due_date: Optional[date] = None


class TaskStatusUpdate(BaseModel):
    status: Literal["todo", "in_progress", "done", "blocked"]


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    title: str
    assignee_id: Optional[str]
    due_date: Optional[date]
    status: str
    created_at: datetime
    updated_at: datetime


# DPR
class DPREntryCreate(BaseModel):
    entry_date: date
    work_summary: str
    manpower_count: int = 0
    weather: Optional[str] = None


class DPREntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    created_by: str
    entry_date: date
    work_summary: str
    manpower_count: int
    weather: Optional[str]
    status: str
    source: str
    created_at: datetime


class DPRPhotoCreate(BaseModel):
    photo_url: str
    caption: Optional[str] = None


class DPRPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    dpr_entry_id: str
    photo_url: str
    caption: Optional[str]
    created_at: datetime


class DPRVoiceDraft(BaseModel):
    """A draft, not a saved DPREntry -- the engineer reviews/edits this
    before it becomes a real record. See fieldos/sarvam.py."""

    transcript: str
    work_summary: str
    manpower_count: int
    weather: Optional[str] = None


# Issues
class IssueCreate(BaseModel):
    description: str
    severity: Literal["low", "medium", "high", "critical"] = "medium"
    dpr_entry_id: Optional[str] = None


class IssueOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    dpr_entry_id: Optional[str]
    description: str
    severity: str
    status: str
    created_at: datetime
    resolved_at: Optional[datetime]


# Dashboard / feed
class DashboardOut(BaseModel):
    percent_tasks_complete: float
    dpr_streak_days: int
    open_issue_count: int


class FeedItemOut(BaseModel):
    type: str
    id: str
    occurred_at: datetime
    summary: str


# Estimation / BOQ
class EstimationCreate(BaseModel):
    name: str
    contractor_profit_percent: Optional[Decimal] = None


class EstimationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    name: str
    status: str
    contractor_profit_percent: Optional[Decimal]
    created_by: str
    created_at: datetime


class CostHeadCreate(BaseModel):
    name: str
    calculation_type: str
    raw_unit: str
    billing_unit: str
    # max_digits/decimal_places mirror the Numeric(precision, scale) columns
    # in fieldos/models.py exactly -- without this, a value the DB layer
    # would silently truncate/accept (SQLite doesn't enforce NUMERIC
    # precision) can instead blow up decimal.Decimal.quantize() far
    # downstream in BOQ calculation with an unhandled InvalidOperation (500).
    # Reject it here at the API boundary instead, with a clean 422.
    conversion_factor: Decimal = Field(default=Decimal("1"), max_digits=18, decimal_places=10)
    rate_per_unit: Optional[Decimal] = Field(default=None, max_digits=14, decimal_places=2)


class CostHeadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    estimation_id: str
    name: str
    calculation_type: str
    raw_unit: str
    billing_unit: str
    conversion_factor: Decimal
    rate_per_unit: Optional[Decimal]
    sort_order: int


class MeasurementEntryCreate(BaseModel):
    description: str
    # Bounds mirror Numeric(14, 6) on MeasurementEntry -- see the comment on
    # CostHeadCreate.conversion_factor for why this matters.
    length: Optional[Decimal] = Field(default=None, max_digits=14, decimal_places=6)
    width: Optional[Decimal] = Field(default=None, max_digits=14, decimal_places=6)
    depth: Optional[Decimal] = Field(default=None, max_digits=14, decimal_places=6)
    nos: Decimal = Field(default=Decimal("1"), max_digits=14, decimal_places=6)
    is_deduction: bool = False


class MeasurementEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    cost_head_id: str
    description: str
    length: Optional[Decimal]
    width: Optional[Decimal]
    depth: Optional[Decimal]
    nos: Decimal
    is_deduction: bool


class SteelEntryCreate(BaseModel):
    description: str
    # Bounds mirror Numeric(6, 2) / Numeric(14, 6) on SteelEntry.
    bar_dia_mm: Decimal = Field(max_digits=6, decimal_places=2)
    nos: Decimal = Field(max_digits=14, decimal_places=6)
    length_ft: Decimal = Field(max_digits=14, decimal_places=6)


class SteelEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    cost_head_id: str
    description: str
    bar_dia_mm: Decimal
    nos: Decimal
    length_ft: Decimal


class BOQLineOut(BaseModel):
    cost_head_id: str
    name: str
    billing_unit: str
    raw_quantity: Decimal
    billing_quantity: Decimal
    rate_per_unit: Optional[Decimal]
    amount: Optional[Decimal]


class BOQOut(BaseModel):
    lines: list[BOQLineOut]
    subtotal: Decimal
    contractor_profit_percent: Optional[Decimal]
    contractor_profit_amount: Decimal
    grand_total: Decimal


# Material tracking
MATERIAL_CATEGORY = Literal[
    "cement", "sand", "aggregate", "steel", "brick", "timber",
    "pipe", "electrical", "plumbing", "paint", "other",
]


class MaterialEntryCreate(BaseModel):
    entry_date: date
    item_name: str = Field(min_length=1, max_length=200)
    category: MATERIAL_CATEGORY = "other"
    quantity: Decimal
    unit: str = Field(min_length=1, max_length=20)
    supplier: Optional[str] = None
    cost: Optional[Decimal] = None
    notes: Optional[str] = None


class MaterialEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    entry_date: date
    item_name: str
    category: str
    quantity: Decimal
    unit: str
    supplier: Optional[str]
    cost: Optional[Decimal]
    notes: Optional[str]
    created_by: str
    created_at: datetime
    photos: list["MaterialPhotoOut"] = []


class MaterialPhotoCreate(BaseModel):
    photo_url: str
    caption: Optional[str] = None


class MaterialPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    material_entry_id: str
    photo_url: str
    caption: Optional[str]
    created_at: datetime


# Labour / workforce tracking
WORKER_STATUS = Literal["active", "inactive"]
ATTENDANCE_STATUS = Literal["present", "absent", "half_day"]


class WorkerCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    role: str = Field(min_length=1, max_length=100)
    phone: Optional[str] = None
    daily_wage: Optional[Decimal] = None


class WorkerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    name: str
    role: str
    phone: Optional[str]
    daily_wage: Optional[Decimal]
    status: str
    created_at: datetime


class AttendanceCreate(BaseModel):
    worker_id: str
    attendance_date: date
    status: ATTENDANCE_STATUS = "present"
    notes: Optional[str] = None


class AttendanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    worker_id: str
    attendance_date: date
    status: str
    notes: Optional[str]
    created_at: datetime


class AttendanceBulkCreate(BaseModel):
    """Mark attendance for multiple workers on a single date."""
    attendance_date: date
    entries: list[AttendanceCreate]


# Project export/import -- for moving one project's full data between two
# separate local installs (e.g. site laptop -> office laptop). User accounts
# and company membership are NOT part of this: the receiving machine has its
# own local accounts, so created_by/assignee_id are reattributed to whoever
# performs the import rather than carried across.
EXPORT_FORMAT = "fieldos.project_export.v1"


class TaskExport(BaseModel):
    title: str
    due_date: Optional[date] = None
    status: str


class DPRPhotoExport(BaseModel):
    photo_url: str
    caption: Optional[str] = None


class DPREntryExport(BaseModel):
    local_id: int
    entry_date: date
    work_summary: str
    manpower_count: int
    weather: Optional[str] = None
    status: str
    source: str
    photos: list[DPRPhotoExport] = []


class IssueExport(BaseModel):
    dpr_entry_local_id: Optional[int] = None
    description: str
    severity: str
    status: str
    resolved_at: Optional[datetime] = None


class MeasurementEntryExport(BaseModel):
    description: str
    length: Optional[Decimal] = None
    width: Optional[Decimal] = None
    depth: Optional[Decimal] = None
    nos: Decimal
    is_deduction: bool


class SteelEntryExport(BaseModel):
    description: str
    bar_dia_mm: Decimal
    nos: Decimal
    length_ft: Decimal


class CostHeadExport(BaseModel):
    name: str
    calculation_type: str
    raw_unit: str
    billing_unit: str
    conversion_factor: Decimal
    rate_per_unit: Optional[Decimal] = None
    sort_order: int
    measurement_entries: list[MeasurementEntryExport] = []
    steel_entries: list[SteelEntryExport] = []


class EstimationExport(BaseModel):
    name: str
    status: str
    contractor_profit_percent: Optional[Decimal] = None
    cost_heads: list[CostHeadExport] = []


class ProjectExportPayload(BaseModel):
    name: str
    client_name: Optional[str] = None
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    geofence_radius_m: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    status: str


class ProjectExport(BaseModel):
    format: str = EXPORT_FORMAT
    project: ProjectExportPayload
    tasks: list[TaskExport] = []
    dpr_entries: list[DPREntryExport] = []
    issues: list[IssueExport] = []
    estimations: list[EstimationExport] = []


# Settings -- installation-wide config, currently just the Sarvam key.
# Never echo the actual key value back; "configured" is all the UI needs.
class SarvamKeyUpdate(BaseModel):
    api_key: str = Field(min_length=1)


class SarvamStatusOut(BaseModel):
    configured: bool


# Document Management
DOC_CATEGORY = Literal[
    "drawing", "specification", "contract", "permit", "report",
    "photo", "correspondence", "safety", "other",
]


class DocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    name: str
    category: str
    version: int
    file_path: str
    file_size: Optional[int]
    mime_type: Optional[str]
    notes: Optional[str]
    uploaded_by: str
    created_at: datetime


# Procurement
class VendorCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    contact_person: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    gst_number: Optional[str] = None
    category: Optional[str] = None
    notes: Optional[str] = None


class VendorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    company_id: str
    name: str
    contact_person: Optional[str]
    phone: Optional[str]
    email: Optional[str]
    address: Optional[str]
    gst_number: Optional[str]
    category: Optional[str]
    notes: Optional[str]
    created_at: datetime


class PurchaseRequisitionCreate(BaseModel):
    item_name: str = Field(min_length=1, max_length=200)
    quantity: Decimal
    unit: str = Field(min_length=1, max_length=20)
    estimated_cost: Optional[Decimal] = None
    urgency: Literal["low", "normal", "high", "critical"] = "normal"
    notes: Optional[str] = None


class PurchaseRequisitionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    item_name: str
    quantity: Decimal
    unit: str
    estimated_cost: Optional[Decimal]
    urgency: str
    status: str
    requested_by: str
    approved_by: Optional[str]
    approved_at: Optional[datetime]
    notes: Optional[str]
    created_at: datetime


class RFQCreate(BaseModel):
    requisition_id: Optional[str] = None
    title: str = Field(min_length=1, max_length=200)
    deadline: Optional[date] = None
    vendor_ids: list[str] = []


class RFQOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    requisition_id: Optional[str]
    title: str
    deadline: Optional[date]
    status: str
    created_by: str
    created_at: datetime


class QuoteCreate(BaseModel):
    vendor_id: str
    total_amount: Decimal
    delivery_days: Optional[int] = None
    payment_terms: Optional[str] = None
    notes: Optional[str] = None


class QuoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    rfq_id: str
    vendor_id: str
    total_amount: Decimal
    delivery_days: Optional[int]
    payment_terms: Optional[str]
    notes: Optional[str]
    status: str
    created_at: datetime


class PurchaseOrderCreate(BaseModel):
    quote_id: Optional[str] = None
    vendor_id: str
    po_number: str = Field(min_length=1, max_length=50)
    total_amount: Decimal
    delivery_date: Optional[date] = None
    notes: Optional[str] = None


class PurchaseOrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    quote_id: Optional[str]
    vendor_id: str
    po_number: str
    total_amount: Decimal
    delivery_date: Optional[date]
    status: str
    notes: Optional[str]
    created_by: str
    created_at: datetime


class GRNCreate(BaseModel):
    received_date: date
    item_description: str = Field(min_length=1, max_length=300)
    ordered_qty: Decimal
    received_qty: Decimal
    unit: str = Field(min_length=1, max_length=20)
    condition: Literal["good", "damaged", "partial"] = "good"
    notes: Optional[str] = None


class GRNOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    purchase_order_id: str
    received_date: date
    item_description: str
    ordered_qty: Decimal
    received_qty: Decimal
    unit: str
    condition: str
    received_by: str
    notes: Optional[str]
    created_at: datetime


# Equipment & Machinery
EQUIPMENT_STATUS = Literal["available", "in_use", "maintenance", "breakdown"]


class EquipmentCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    equipment_type: str = Field(min_length=1, max_length=100)
    model: Optional[str] = None
    registration_number: Optional[str] = None
    daily_rate: Optional[Decimal] = None
    notes: Optional[str] = None


class EquipmentUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    equipment_type: Optional[str] = Field(None, min_length=1, max_length=100)
    model: Optional[str] = None
    registration_number: Optional[str] = None
    status: Optional[EQUIPMENT_STATUS] = None
    daily_rate: Optional[Decimal] = None
    notes: Optional[str] = None


class EquipmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    name: str
    equipment_type: str
    model: Optional[str]
    registration_number: Optional[str]
    status: str
    daily_rate: Optional[Decimal]
    notes: Optional[str]
    created_at: datetime


class EquipmentLogCreate(BaseModel):
    log_date: date
    log_type: Literal["usage", "maintenance", "repair", "fuel", "inspection"]
    hours_used: Optional[Decimal] = None
    description: Optional[str] = None
    cost: Optional[Decimal] = None


class EquipmentLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    equipment_id: str
    log_date: date
    log_type: str
    hours_used: Optional[Decimal]
    description: Optional[str]
    cost: Optional[Decimal]
    created_by: str
    created_at: datetime


# Site Inspection / Quality
class InspectionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    inspection_type: Literal["safety", "quality", "environmental", "progress", "fire", "electrical", "other"] = "quality"
    scheduled_date: Optional[date] = None
    notes: Optional[str] = None


class InspectionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    title: str
    inspection_type: str
    status: str
    inspector_id: str
    scheduled_date: Optional[date]
    completed_date: Optional[date]
    overall_result: Optional[str]
    notes: Optional[str]
    created_at: datetime


class InspectionItemCreate(BaseModel):
    item_description: str = Field(min_length=1, max_length=300)
    status: Literal["pending", "pass", "fail", "na"] = "pending"
    notes: Optional[str] = None


class InspectionItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    inspection_id: str
    item_description: str
    status: str
    notes: Optional[str]
    sort_order: int


class InspectionPhotoCreate(BaseModel):
    photo_url: str
    caption: Optional[str] = None


class InspectionPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    inspection_id: str
    photo_url: str
    caption: Optional[str]
    uploaded_by: str
    created_at: datetime


# Billing / Subscriptions
class SubscriptionPlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    name: str
    monthly_price_usd: int
    max_projects: int
    max_users_per_project: int
    features: Optional[str]
    is_active: bool


class CompanySubscriptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    company_id: str
    plan_id: Optional[str]
    status: str
    trial_ends_at: Optional[datetime]
    current_period_end: Optional[datetime]
    cancel_at_period_end: bool


class BillingEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    company_id: str
    event_type: str
    amount_usd: Optional[int]
    currency: str
    description: Optional[str]
    event_metadata: Optional[str]
    created_at: datetime


class CreateCheckoutSessionRequest(BaseModel):
    plan_id: str
    success_url: str
    cancel_url: str
