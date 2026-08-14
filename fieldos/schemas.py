from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


# Auth
class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=100)
    name: str = Field(min_length=1, max_length=200)
    password: str = Field(min_length=8, max_length=200)


class LoginRequest(BaseModel):
    username: str
    password: str


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
    name: str


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
    role: str


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
    status: str


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


# Issues
class IssueCreate(BaseModel):
    description: str
    severity: str = "medium"
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
    conversion_factor: Decimal = Decimal("1")
    rate_per_unit: Optional[Decimal] = None


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
    length: Optional[Decimal] = None
    width: Optional[Decimal] = None
    depth: Optional[Decimal] = None
    nos: Decimal = Decimal("1")
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
    bar_dia_mm: Decimal
    nos: Decimal
    length_ft: Decimal


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
