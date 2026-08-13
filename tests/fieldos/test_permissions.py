import pytest
from fastapi import HTTPException

from fieldos.models import Company, CompanyMember, Project, ProjectMember
from fieldos.permissions import (
    ROLE_OWNER,
    ROLE_PM,
    ROLE_SITE_ENGINEER,
    get_company_role,
    require_company_role,
    require_project_access,
)


def _seed_company_and_project(db_session, owner_id="owner-1"):
    company = Company(name="Dfine Homes")
    db_session.add(company)
    db_session.flush()
    db_session.add(CompanyMember(company_id=company.id, user_id=owner_id, role=ROLE_OWNER))
    project = Project(company_id=company.id, name="Villa 12", status="active")
    db_session.add(project)
    db_session.commit()
    return company, project


def test_get_company_role_returns_none_for_non_member(db_session):
    company, _ = _seed_company_and_project(db_session)
    assert get_company_role(db_session, company.id, "stranger") is None


def test_require_company_role_raises_403_when_role_not_allowed(db_session):
    company, _ = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="engineer-1", role=ROLE_SITE_ENGINEER))
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        require_company_role(db_session, company.id, "engineer-1", {ROLE_OWNER, ROLE_PM})

    assert exc_info.value.status_code == 403


def test_require_project_access_allows_company_owner_without_explicit_membership(db_session):
    company, project = _seed_company_and_project(db_session)
    result = require_project_access(db_session, project.id, "owner-1")
    assert result.id == project.id


def test_require_project_access_denies_non_member_non_owner(db_session):
    company, project = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="pm-1", role=ROLE_PM))
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        require_project_access(db_session, project.id, "pm-1")

    assert exc_info.value.status_code == 403


def test_require_project_access_allows_explicit_project_member(db_session):
    company, project = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="pm-1", role=ROLE_PM))
    db_session.add(ProjectMember(project_id=project.id, user_id="pm-1", role=ROLE_PM))
    db_session.commit()

    result = require_project_access(db_session, project.id, "pm-1")
    assert result.id == project.id


def test_require_project_access_raises_404_for_missing_project(db_session):
    with pytest.raises(HTTPException) as exc_info:
        require_project_access(db_session, "does-not-exist", "owner-1")
    assert exc_info.value.status_code == 404
