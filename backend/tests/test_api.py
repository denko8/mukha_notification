import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client(tmp_path, monkeypatch):
    import os
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, text
    from sqlalchemy.engine import make_url
    from pathlib import Path

    postgres = os.environ.get('TEST_POSTGRES_URL')
    admin = None
    if postgres:
        database = 'test_' + uuid.uuid4().hex
        url = make_url(postgres)
        admin = create_engine(url.set(database='postgres'), isolation_level='AUTOCOMMIT')
        with admin.connect() as conn:
            conn.execute(text(f'CREATE DATABASE "{database}"'))
        database_url = url.set(database=database).render_as_string(hide_password=False)
    else:
        database_url = f'sqlite:///{tmp_path}/test.db'
    monkeypatch.setenv('DATABASE_URL', database_url)
    config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
    command.upgrade(config, 'head')
    app = create_app(database_url)
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.state.engine.dispose()
        if admin is not None:
            with admin.connect() as conn:
                conn.execute(text(f'DROP DATABASE "{database}"'))
            admin.dispose()


def account(client, email):
    response = client.post('/auth/register', json={
        'email': email, 'password': 'long-test-password-123', 'name': 'Тест',
    })
    assert response.status_code == 201, response.text
    return {'Authorization': 'Bearer ' + response.json()['access_token']}


def put(client, headers, note_id, version=0, family_id=None, text='Завтра в 14:00'):
    return client.put('/notes/' + note_id, headers=headers, json={
        'text': text, 'expected_version': version, 'family_id': family_id,
    })


def test_auth_and_logout(client):
    headers = account(client, 'a@example.com')
    assert client.get('/me').status_code == 401
    assert client.get('/me', headers=headers).status_code == 200
    assert client.post('/auth/login', json={
        'email': 'a@example.com', 'password': 'wrong-long-password',
    }).status_code == 401
    assert client.post('/auth/logout', headers=headers).status_code == 204
    assert client.get('/me', headers=headers).status_code == 401


def test_private_isolation_conflicts_and_tombstones(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    nid = str(uuid.uuid4())
    assert put(client, alice, nid).json()['version'] == 1
    assert client.get('/notes', headers=bob).json() == []
    assert put(client, bob, nid, 1).status_code == 404
    assert put(client, alice, nid, 0).status_code == 409
    assert put(client, alice, nid, 1).json()['version'] == 2
    assert client.request('DELETE', '/notes/' + nid, headers=alice,
                          json={'expected_version': 1}).status_code == 409
    assert client.request('DELETE', '/notes/' + nid, headers=alice,
                          json={'expected_version': 2}).json()['deleted'] is True
    assert client.get('/notes', headers=alice).json()[0]['deleted'] is True
    assert put(client, alice, nid, 3).status_code == 409  # no resurrection


def test_family_invite_and_access(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    eve = account(client, 'e@example.com')
    fid = client.post('/families', headers=alice, json={'name': 'Семья'}).json()['id']
    assert client.get(f'/families/{fid}/members', headers=bob).status_code == 404
    nid = str(uuid.uuid4())
    assert put(client, bob, nid, family_id=fid).status_code == 404
    assert put(client, alice, nid, family_id=fid).status_code == 200
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    assert client.post('/families/join', headers=bob, json={'token': token}).status_code == 200
    assert client.post('/families/join', headers=eve, json={'token': token}).status_code == 404
    assert len(client.get('/notes', headers=bob).json()) == 1
    assert client.get('/notes', headers=eve).json() == []
    assert client.post(f'/families/{fid}/invites', headers=bob).status_code == 403
    assert put(client, bob, nid, 1, fid, 'Изменено семьёй').status_code == 200
    assert put(client, alice, nid, 1, fid).status_code == 409
    assert put(client, bob, nid, 2).status_code == 422  # cannot steal scope


def test_validation(client):
    alice = account(client, 'a@example.com')
    assert put(client, alice, str(uuid.uuid4()), text='').status_code == 422
    assert client.get('/notes?limit=10000', headers=alice).status_code == 422
    assert client.post('/auth/register', json={
        'email': 'bad', 'password': 'short', 'name': 'Тест',
    }).status_code == 422


def test_expired_sessions_and_invites(client):
    from datetime import timedelta
    from sqlalchemy import update
    from sqlalchemy.orm import Session
    from app.main import AuthSession, Invite, now

    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    with Session(client.app.state.engine) as db:
        db.execute(update(Invite).values(expires=now() - timedelta(days=1)))
        db.commit()
    assert client.post('/families/join', headers=bob, json={'token': token}).status_code == 404
    with Session(client.app.state.engine) as db:
        db.execute(update(AuthSession).values(expires=now() - timedelta(days=1)))
        db.commit()
    assert client.get('/notes', headers=alice).status_code == 401


def test_cannot_supply_author_or_other_unrecognized_fields(client):
    alice = account(client, 'a@example.com')
    response = client.put('/notes/' + str(uuid.uuid4()), headers=alice, json={
        'text': 'Заметка', 'expected_version': 0, 'author_id': 'someone-else',
    })
    assert response.status_code == 422


def test_member_removal_and_revoked_invites(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    eve = account(client, 'e@example.com')
    aid = client.get('/me', headers=alice).json()['id']
    bid = client.get('/me', headers=bob).json()['id']
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    client.post('/families/join', headers=bob, json={'token': token})
    nid = str(uuid.uuid4())
    put(client, alice, nid, family_id=fid)
    assert client.delete(f'/families/{fid}/members/{aid}', headers=alice).status_code == 409
    assert client.delete(f'/families/{fid}/members/{aid}', headers=bob).status_code == 409
    assert client.delete(f'/families/{fid}/members/{bid}', headers=alice).status_code == 204
    assert client.get('/notes', headers=bob).json() == []
    assert put(client, bob, nid, 1, fid).status_code == 404
    assert client.get(f'/families/{fid}/members', headers=bob).status_code == 404
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    assert client.delete(f'/families/{fid}/invites', headers=alice).status_code == 204
    assert client.post('/families/join', headers=eve, json={'token': token}).status_code == 404


def test_member_can_leave_without_owner_removal(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    bid = client.get('/me', headers=bob).json()['id']
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    client.post('/families/join', headers=bob, json={'token': token})
    assert client.delete(f'/families/{fid}/members/{bid}', headers=bob).status_code == 204
    assert client.get('/families', headers=bob).json() == []


def test_body_and_rate_limits(client):
    assert client.post('/auth/login', content=b'x' * 131073).status_code == 413
    responses = [client.post('/auth/login', json={
        'email': 'invalid@example.com', 'password': 'long-test-password-123',
    }).status_code for _ in range(21)]
    assert 429 in responses
    assert client.get('/health').status_code == 200


def test_ready_requires_schema(tmp_path):
    app = create_app(f'sqlite:///{tmp_path}/empty.db')
    with TestClient(app) as client:
        assert client.get('/health').status_code == 200
        assert client.get('/ready').status_code == 503
    app.state.engine.dispose()


def test_concurrent_note_updates_have_one_winner(client):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    alice = account(client, 'a@example.com')
    nid = str(uuid.uuid4())
    put(client, alice, nid)
    barrier = Barrier(2)

    def change(text):
        barrier.wait(timeout=10)
        return put(client, alice, nid, 1, text=text).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(change, ['Первое устройство', 'Второе устройство']))
    assert sorted(results) == [200, 409]
    assert client.get('/notes', headers=alice).json()[0]['version'] == 2


def test_concurrent_invite_acceptance_is_single_use(client):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    eve = account(client, 'e@example.com')
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    barrier = Barrier(2)

    def join(headers):
        barrier.wait(timeout=10)
        return client.post('/families/join', headers=headers, json={'token': token}).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(join, [bob, eve]))
    assert results.count(200) == 1
    assert all(code in (200, 404, 409) for code in results)
    assert len(client.get(f'/families/{fid}/members', headers=alice).json()) == 2
