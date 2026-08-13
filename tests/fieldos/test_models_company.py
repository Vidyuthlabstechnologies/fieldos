from fieldos.models import Company, CompanyMember


def test_creating_a_company_persists_it(db_session):
    company = Company(name="Bhavya Developers")
    db_session.add(company)
    db_session.commit()

    fetched = db_session.query(Company).filter_by(name="Bhavya Developers").one()
    assert fetched.id == company.id
    assert fetched.created_at is not None


def test_company_member_links_a_user_to_a_company_with_a_role(db_session):
    company = Company(name="Reidus Infra")
    db_session.add(company)
    db_session.flush()

    membership = CompanyMember(company_id=company.id, user_id="user-1", role="owner")
    db_session.add(membership)
    db_session.commit()

    fetched = db_session.query(CompanyMember).filter_by(user_id="user-1").one()
    assert fetched.company_id == company.id
    assert fetched.role == "owner"
