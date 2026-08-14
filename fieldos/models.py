import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from fieldos.db import Base


def gen_uuid() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    username: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Session(Base):
    __tablename__ = "sessions"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class AppSetting(Base):
    """Installation-wide config (currently just the Sarvam API key) --
    lets a non-technical user configure integrations from the app itself
    instead of needing to set an environment variable. See fieldos/sarvam.py."""

    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[str] = mapped_column(Text, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class Company(Base):
    __tablename__ = "companies"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    members: Mapped[list["CompanyMember"]] = relationship(back_populates="company")


class CompanyMember(Base):
    __tablename__ = "company_members"
    __table_args__ = (UniqueConstraint("company_id", "user_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    company_id: Mapped[str] = mapped_column(String(36), ForeignKey("companies.id"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    role: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    company: Mapped["Company"] = relationship(back_populates="members")


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    company_id: Mapped[str] = mapped_column(String(36), ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    client_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    location_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    location_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    geofence_radius_m: Mapped[int | None] = mapped_column(Integer, nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="planning")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class ProjectMember(Base):
    __tablename__ = "project_members"
    __table_args__ = (UniqueConstraint("project_id", "user_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    role: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    assignee_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="todo")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )


class DPREntry(Base):
    __tablename__ = "dpr_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False, index=True)
    created_by: Mapped[str] = mapped_column(String(64), nullable=False)
    entry_date: Mapped[date] = mapped_column(Date, nullable=False)
    work_summary: Mapped[str] = mapped_column(Text, nullable=False)
    manpower_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    weather: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="confirmed")
    source: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class DPRPhoto(Base):
    __tablename__ = "dpr_photos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    dpr_entry_id: Mapped[str] = mapped_column(String(36), ForeignKey("dpr_entries.id"), nullable=False, index=True)
    photo_url: Mapped[str] = mapped_column(String(500), nullable=False)
    caption: Mapped[str | None] = mapped_column(String(200), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Issue(Base):
    __tablename__ = "issues"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False, index=True)
    dpr_entry_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("dpr_entries.id"), nullable=True
    )
    description: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[str] = mapped_column(String(20), nullable=False, default="medium")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Estimation(Base):
    __tablename__ = "estimations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft")
    contractor_profit_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    created_by: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class CostHead(Base):
    __tablename__ = "cost_heads"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    estimation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("estimations.id"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    calculation_type: Mapped[str] = mapped_column(String(20), nullable=False)
    raw_unit: Mapped[str] = mapped_column(String(20), nullable=False)
    billing_unit: Mapped[str] = mapped_column(String(20), nullable=False)
    conversion_factor: Mapped[Decimal] = mapped_column(Numeric(18, 10), nullable=False, default=Decimal("1"))
    rate_per_unit: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class MeasurementEntry(Base):
    __tablename__ = "measurement_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    cost_head_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("cost_heads.id"), nullable=False, index=True
    )
    description: Mapped[str] = mapped_column(String(200), nullable=False)
    length: Mapped[Decimal | None] = mapped_column(Numeric(14, 6), nullable=True)
    width: Mapped[Decimal | None] = mapped_column(Numeric(14, 6), nullable=True)
    depth: Mapped[Decimal | None] = mapped_column(Numeric(14, 6), nullable=True)
    nos: Mapped[Decimal] = mapped_column(Numeric(14, 6), nullable=False, default=Decimal("1"))
    is_deduction: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)


class SteelEntry(Base):
    __tablename__ = "steel_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    cost_head_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("cost_heads.id"), nullable=False, index=True
    )
    description: Mapped[str] = mapped_column(String(200), nullable=False)
    bar_dia_mm: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)
    nos: Mapped[Decimal] = mapped_column(Numeric(14, 6), nullable=False)
    length_ft: Mapped[Decimal] = mapped_column(Numeric(14, 6), nullable=False)
