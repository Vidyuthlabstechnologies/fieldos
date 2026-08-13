def test_db_session_fixture_provides_a_working_session(db_session):
    assert db_session.is_active
