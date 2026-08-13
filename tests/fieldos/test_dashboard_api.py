from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_dashboard_reports_percent_complete_streak_and_open_issues(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    t1 = client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 1"}).json()
    client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 2"})
    client.patch(f"/projects/{project['id']}/tasks/{t1['id']}", json={"status": "done"})

    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1", "manpower_count": 5},
    )
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Day 2", "manpower_count": 5},
    )

    client.post(f"/projects/{project['id']}/issues", json={"description": "Open issue"})

    response = client.get(f"/projects/{project['id']}/dashboard")

    assert response.status_code == 200
    body = response.json()
    assert body["percent_tasks_complete"] == 50.0
    assert body["dpr_streak_days"] == 2
    assert body["open_issue_count"] == 1


def test_site_feed_merges_dpr_and_issues_newest_first(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1 work", "manpower_count": 5},
    )
    client.post(f"/projects/{project['id']}/issues", json={"description": "Cement delay"})

    response = client.get(f"/projects/{project['id']}/feed")

    assert response.status_code == 200
    types = {item["type"] for item in response.json()}
    assert types == {"dpr", "issue"}
