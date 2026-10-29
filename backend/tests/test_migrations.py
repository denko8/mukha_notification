from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_upgrade_retains_data_and_downgrade_is_reversible(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/migration.db'
    monkeypatch.setenv('DATABASE_URL', url)
    cfg = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
    command.upgrade(cfg, '0001')
    engine = create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users (id,email,name,password_hash) VALUES ('id','test@example.com','Тест','hash')"))
    command.upgrade(cfg, 'head')
    command.upgrade(cfg, 'head')  # repeated deployment is safe
    with engine.connect() as db:
        assert db.scalar(text('SELECT name FROM users')) == 'Тест'
        assert db.scalar(text('SELECT version_num FROM alembic_version')) == '0005'
    command.downgrade(cfg, '0001')
    with engine.connect() as db:
        assert db.scalar(text('SELECT name FROM users')) == 'Тест'
    command.downgrade(cfg, 'base')  # destructive: tested ONLY against throwaway DB
    assert 'users' not in inspect(engine).get_table_names()
    command.upgrade(cfg, 'head')
    assert 'users' in inspect(engine).get_table_names()
    engine.dispose()
