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
