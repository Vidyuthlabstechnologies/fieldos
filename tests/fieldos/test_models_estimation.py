from decimal import Decimal

from fieldos.estimation_calc import CALC_STEEL_WEIGHT, CALC_VOLUME
from fieldos.models import Company, CostHead, Estimation, MeasurementEntry, Project, SteelEntry


def _seed_project(db_session):
    company = Company(name="Protek Consult")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Narapally Residential (S+5)", status="active")
    db_session.add(project)
    db_session.commit()
    return project


def test_creating_an_estimation_under_a_project(db_session):
    project = _seed_project(db_session)
    estimation = Estimation(
        project_id=project.id,
        name="Narapally BOQ v1",
        created_by="owner-1",
        contractor_profit_percent=Decimal("10.00"),
    )
    db_session.add(estimation)
    db_session.commit()

    fetched = db_session.query(Estimation).filter_by(name="Narapally BOQ v1").one()
    assert fetched.project_id == project.id
    assert fetched.status == "draft"
    assert fetched.contractor_profit_percent == Decimal("10.00")


def test_cost_head_belongs_to_an_estimation(db_session):
    project = _seed_project(db_session)
    estimation = Estimation(project_id=project.id, name="Test Estimation", created_by="owner-1")
    db_session.add(estimation)
    db_session.flush()

    cost_head = CostHead(
        estimation_id=estimation.id,
        name='Brick Work - 9" Walls',
        calculation_type=CALC_VOLUME,
        raw_unit="CFT",
        billing_unit="CFT",
        conversion_factor=Decimal("1"),
        rate_per_unit=Decimal("150.00"),
    )
    db_session.add(cost_head)
    db_session.commit()

    fetched = db_session.query(CostHead).filter_by(name='Brick Work - 9" Walls').one()
    assert fetched.estimation_id == estimation.id
    assert fetched.calculation_type == CALC_VOLUME
    assert fetched.rate_per_unit == Decimal("150.00")


def test_measurement_entry_preserves_decimal_precision(db_session):
    project = _seed_project(db_session)
    estimation = Estimation(project_id=project.id, name="Test Estimation", created_by="owner-1")
    db_session.add(estimation)
    db_session.flush()
    cost_head = CostHead(
        estimation_id=estimation.id,
        name="Brick Work",
        calculation_type=CALC_VOLUME,
        raw_unit="CFT",
        billing_unit="CFT",
    )
    db_session.add(cost_head)
    db_session.flush()

    entry = MeasurementEntry(
        cost_head_id=cost_head.id,
        description='WALL(9")',
        length=Decimal("108.25"),
        width=Decimal("0.75"),
        depth=Decimal("8.85"),
        nos=Decimal("1"),
    )
    db_session.add(entry)
    db_session.commit()

    fetched = db_session.query(MeasurementEntry).filter_by(description='WALL(9")').one()
    assert fetched.length == Decimal("108.25")
    assert fetched.width == Decimal("0.75")
    assert fetched.depth == Decimal("8.85")
    assert fetched.is_deduction is False


def test_steel_entry_preserves_decimal_precision(db_session):
    project = _seed_project(db_session)
    estimation = Estimation(project_id=project.id, name="Test Estimation", created_by="owner-1")
    db_session.add(estimation)
    db_session.flush()
    cost_head = CostHead(
        estimation_id=estimation.id,
        name="Column Reinforcement",
        calculation_type=CALC_STEEL_WEIGHT,
        raw_unit="KG",
        billing_unit="TONNES",
        conversion_factor=Decimal("0.001"),
    )
    db_session.add(cost_head)
    db_session.flush()

    entry = SteelEntry(
        cost_head_id=cost_head.id,
        description="C1",
        bar_dia_mm=Decimal("25"),
        nos=Decimal("16"),
        length_ft=Decimal("10.5"),
    )
    db_session.add(entry)
    db_session.commit()

    fetched = db_session.query(SteelEntry).filter_by(description="C1").one()
    assert fetched.bar_dia_mm == Decimal("25")
    assert fetched.nos == Decimal("16")
    assert fetched.length_ft == Decimal("10.5")
