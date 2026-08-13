from datetime import date

from fieldos.models import Company, Project, ProjectMember


def test_creating_a_project_under_a_company(db_session):
    company = Company(name="Cfolios Design & Construction")
    db_session.add(company)
    db_session.flush()

    project = Project(
        company_id=company.id,
        name="Skyline Towers",
        client_name="Acme Developers",
        location_lat=12.9716,
        location_lng=77.5946,
        geofence_radius_m=200,
        start_date=date(2026, 1, 1),
        end_date=date(2026, 12, 31),
        status="planning",
    )
    db_session.add(project)
    db_session.commit()

    fetched = db_session.query(Project).filter_by(name="Skyline Towers").one()
    assert fetched.company_id == company.id
    assert fetched.status == "planning"


def test_project_member_links_a_user_to_a_project_with_a_role(db_session):
    company = Company(name="HEM Engineers")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Transmission Line 4", status="active")
    db_session.add(project)
    db_session.flush()

    member = ProjectMember(project_id=project.id, user_id="user-2", role="site_engineer")
    db_session.add(member)
    db_session.commit()

    fetched = db_session.query(ProjectMember).filter_by(user_id="user-2").one()
    assert fetched.project_id == project.id
    assert fetched.role == "site_engineer"
