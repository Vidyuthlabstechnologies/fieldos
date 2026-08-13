from datetime import date

from fieldos.models import Company, Project, Task


def test_creating_a_task_defaults_to_todo_status(db_session):
    company = Company(name="Shivam Developers")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Highway Segment 7", status="active")
    db_session.add(project)
    db_session.flush()

    task = Task(project_id=project.id, title="Pour footing F12", due_date=date(2026, 9, 1))
    db_session.add(task)
    db_session.commit()

    fetched = db_session.query(Task).filter_by(title="Pour footing F12").one()
    assert fetched.status == "todo"
    assert fetched.assignee_id is None
