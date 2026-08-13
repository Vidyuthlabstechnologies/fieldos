from datetime import date

from fieldos.models import Company, DPREntry, DPRPhoto, Issue, Project


def _seed_project(db_session):
    company = Company(name="Onsite AI Test Co")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Test Site", status="active")
    db_session.add(project)
    db_session.commit()
    return project


def test_dpr_entry_defaults_to_confirmed_manual(db_session):
    project = _seed_project(db_session)
    entry = DPREntry(
        project_id=project.id,
        created_by="engineer-1",
        entry_date=date(2026, 8, 11),
        work_summary="Poured 50 cum concrete on footing F12",
        manpower_count=8,
    )
    db_session.add(entry)
    db_session.commit()

    fetched = db_session.query(DPREntry).one()
    assert fetched.status == "confirmed"
    assert fetched.source == "manual"


def test_dpr_photo_links_to_a_dpr_entry(db_session):
    project = _seed_project(db_session)
    entry = DPREntry(
        project_id=project.id,
        created_by="engineer-1",
        entry_date=date(2026, 8, 11),
        work_summary="Steel fixing at column C4",
        manpower_count=5,
    )
    db_session.add(entry)
    db_session.flush()

    photo = DPRPhoto(dpr_entry_id=entry.id, photo_url="https://example.com/photo.jpg")
    db_session.add(photo)
    db_session.commit()

    fetched = db_session.query(DPRPhoto).one()
    assert fetched.dpr_entry_id == entry.id


def test_issue_defaults_to_open_medium_severity(db_session):
    project = _seed_project(db_session)
    issue = Issue(project_id=project.id, description="Cement delivery delayed by 2 days")
    db_session.add(issue)
    db_session.commit()

    fetched = db_session.query(Issue).one()
    assert fetched.status == "open"
    assert fetched.severity == "medium"
    assert fetched.resolved_at is None
