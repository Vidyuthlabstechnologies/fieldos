from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


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
