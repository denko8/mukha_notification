import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import Base, create_app


@pytest.fixture
def client(tmp_path):
    app = create_app(f'sqlite:///{tmp_path}/test.db')
    Base.metadata.create_all(app.state.engine)
    with TestClient(app) as client:
        yield client
    app.state.engine.dispose()


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
