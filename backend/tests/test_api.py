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


def test_idempotency_survives_lost_response_and_rejects_changed_body(client):
    alice = account(client, 'a@example.com')
    nid = str(uuid.uuid4())
    headers = {**alice, 'Idempotency-Key': str(uuid.uuid4())}
    body = {'expected_version': 0, 'text': 'Не создать дважды'}
    first = client.put('/notes/' + nid, headers=headers, json=body)
    replay = client.put('/notes/' + nid, headers=headers, json=body)
    assert first.status_code == replay.status_code == 200
    assert first.json() == replay.json()
    assert len(client.get('/notes', headers=alice).json()) == 1
    assert client.put('/notes/' + nid, headers=headers,
                      json={**body, 'text': 'Другой запрос'}).status_code == 409
    # A later write must not change the result recorded for the earlier operation.
    assert put(client, alice, nid, 1, text='Новая версия').status_code == 200
    assert client.put('/notes/' + nid, headers=headers, json=body).json() == first.json()
    assert client.get('/notes/' + nid, headers=alice).json()['version'] == 2
    delete_headers = {**alice, 'Idempotency-Key': str(uuid.uuid4())}
    deleted = client.request('DELETE', '/notes/' + nid, headers=delete_headers,
                             json={'expected_version': 2})
    assert deleted.status_code == 200
    assert deleted.json()['deleted'] is True
    assert client.request('DELETE', '/notes/' + nid, headers=delete_headers,
                          json={'expected_version': 2}).json() == deleted.json()


def test_snapshot_pages_are_frozen_not_live_offset(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    ids = [str(uuid.UUID(int=i)) for i in [2, 3]]
    for nid in ids:
        put(client, alice, nid)
    snapshot = client.post('/sync/snapshots', headers=alice)
    assert snapshot.status_code == 201
    sid = snapshot.json()['snapshot_id']
    first = client.get(f'/sync/snapshots/{sid}?limit=1', headers=alice).json()
    assert first['notes'][0]['id'] == ids[0]
    # Live insertion before the page boundary + deletion of next item.
    put(client, alice, str(uuid.UUID(int=1)))
    client.request('DELETE', '/notes/' + ids[1], headers=alice,
                   json={'expected_version': 1})
    second = client.get(f'/sync/snapshots/{sid}?offset=1&limit=1', headers=alice).json()
    assert second['notes'][0]['id'] == ids[1]
    assert second['notes'][0]['deleted'] is False
    assert second['next_offset'] is None
    assert client.get(f'/sync/snapshots/{sid}', headers=bob).status_code == 404
    assert client.delete(f'/sync/snapshots/{sid}', headers=bob).status_code == 404
    assert client.delete(f'/sync/snapshots/{sid}', headers=alice).status_code == 204
    assert client.get(f'/sync/snapshots/{sid}', headers=alice).status_code == 404
    fresh = client.post('/sync/snapshots', headers=alice).json()['snapshot_id']
    rows = client.get(f'/sync/snapshots/{fresh}', headers=alice).json()['notes']
    assert len(rows) == 3
    assert next(n for n in rows if n['id'] == ids[1])['deleted'] is True


def test_snapshot_and_receipt_do_not_bypass_revoked_access(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    bid = client.get('/me', headers=bob).json()['id']
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    client.post('/families/join', headers=bob, json={'token': token})
    nid = str(uuid.uuid4())
    headers = {**bob, 'Idempotency-Key': str(uuid.uuid4())}
    body = dict(expected_version=0, text='Семейная', family_id=fid)
    assert client.put('/notes/' + nid, headers=headers, json=body).status_code == 200
    sid = client.post('/sync/snapshots', headers=bob).json()['snapshot_id']
    assert client.delete(f'/families/{fid}/members/{bid}', headers=alice).status_code == 204
    assert client.get(f'/sync/snapshots/{sid}', headers=bob).status_code == 409
    assert client.put('/notes/' + nid, headers=headers, json=body).status_code == 404
    assert client.get('/notes/' + nid, headers=bob).status_code == 404
    assert client.delete(f'/sync/snapshots/{sid}', headers=bob).status_code == 204


def test_snapshot_quota_expiry_and_release(client):
    from sqlalchemy import update
    from sqlalchemy.orm import Session
    from datetime import timedelta
    from app.main import SyncSnapshot, now

    alice = account(client, 'a@example.com')
    ids = [client.post('/sync/snapshots', headers=alice).json()['snapshot_id'] for _ in range(3)]
    assert client.post('/sync/snapshots', headers=alice).status_code == 429
    assert client.delete('/sync/snapshots/' + ids[0], headers=alice).status_code == 204
    assert client.post('/sync/snapshots', headers=alice).status_code == 201
    with Session(client.app.state.engine) as db:
        db.execute(update(SyncSnapshot).values(expires=now() - timedelta(seconds=1)))
        db.commit()
    assert client.get('/sync/snapshots/' + ids[1], headers=alice).status_code == 410
    assert client.post('/sync/snapshots', headers=alice).status_code == 201


def test_concurrent_idempotent_retries_postgres(client):
    import os
    if not os.environ.get('TEST_POSTGRES_URL'):
        pytest.skip('Requires PostgreSQL row locks; SQLite is not the deployment database')
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    alice = account(client, 'a@example.com')
    headers = {**alice, 'Idempotency-Key': str(uuid.uuid4())}
    nid = str(uuid.uuid4())
    barrier = Barrier(2)

    def send(_):
        barrier.wait(timeout=10)
        response = client.put('/notes/' + nid, headers=headers,
                              json={'expected_version': 0, 'text': 'Один раз'})
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(send, range(2)))
    assert results[0][0] == results[1][0] == 200
    assert results[0][1] == results[1][1]


def test_receipts_and_snapshots_survive_api_restart(client):
    alice = account(client, 'a@example.com')
    headers = {**alice, 'Idempotency-Key': str(uuid.uuid4())}
    nid = str(uuid.uuid4())
    body = {'expected_version': 0, 'text': 'Пережить перезапуск'}
    result = client.put('/notes/' + nid, headers=headers, json=body).json()
    sid = client.post('/sync/snapshots', headers=alice).json()['snapshot_id']
    url = client.app.state.engine.url.render_as_string(hide_password=False)
    restarted = create_app(url)
    try:
        with TestClient(restarted) as second:
            response = second.put('/notes/' + nid, headers=headers, json=body)
            assert response.status_code == 200
            assert response.json() == result
            assert second.get('/sync/snapshots/' + sid, headers=alice).json()['notes'] == [result]
    finally:
        restarted.state.engine.dispose()


def test_attachment_upload_retry_download_and_note_delete(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    nid, aid = str(uuid.uuid4()), str(uuid.uuid4())
    put(client, alice, nid)
    path = f'/notes/{nid}/attachments/{aid}'
    headers = {**alice, 'Content-Type': 'application/octet-stream', 'X-Filename': 'test.pdf'}
    data = b'%PDF-1.7\n test object'
    first = client.put(path, headers=headers, content=data)
    assert first.status_code == 200, first.text
    assert client.put(path, headers=headers, content=data).json() == first.json()
    note = client.get('/notes/' + nid, headers=alice).json()
    assert note['version'] == 2  # retry did not increment again
    assert note['attachments'][0]['id'] == aid
    assert client.get(path, headers=alice).content == data
    assert client.get(path, headers=bob).status_code == 404
    assert client.put(path, headers={**headers, **bob}, content=data).status_code == 404
    assert client.put(path, headers=headers, content=b'%PDF-1.7\n other').status_code == 409
    assert client.request('DELETE', '/notes/' + nid, headers=alice, json={'expected_version': 2}).status_code == 200
    assert client.get(path, headers=alice).status_code == 404
    from sqlalchemy import select, func
    from sqlalchemy.orm import Session
    from app.main import Attachment
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(Attachment)) == 0


def test_attachment_family_revocation(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    bid = client.get('/me', headers=bob).json()['id']
    fid = client.post('/families', headers=alice, json={'name': 'Дом'}).json()['id']
    token = client.post(f'/families/{fid}/invites', headers=alice).json()['token']
    client.post('/families/join', headers=bob, json={'token': token})
    nid, aid = str(uuid.uuid4()), str(uuid.uuid4())
    put(client, alice, nid, family_id=fid)
    path = f'/notes/{nid}/attachments/{aid}'
    data = b'\x89PNG\r\n\x1a\n test'
    assert client.put(path, headers={**bob, 'Content-Type': 'application/octet-stream'}, content=data).status_code == 200
    assert client.get(path, headers=alice).content == data
    client.delete(f'/families/{fid}/members/{bid}', headers=alice)
    assert client.get(path, headers=bob).status_code == 404
    assert client.put(path, headers={**bob, 'Content-Type': 'application/octet-stream'}, content=data).status_code == 404


def test_attachment_type_size_and_count_limits(client):
    alice = account(client, 'a@example.com')
    nid = str(uuid.uuid4())
    put(client, alice, nid)
    headers = {**alice, 'Content-Type': 'application/octet-stream'}
    path = f'/notes/{nid}/attachments/'
    assert client.put(path + str(uuid.uuid4()), headers=headers, content=b'MZ executable').status_code == 415
    assert client.put(path + str(uuid.uuid4()), headers=headers, content=b'%PDF-' + b'x' * (5 * 1024 * 1024)).status_code == 413
    for _ in range(10):
        assert client.put(path + str(uuid.uuid4()), headers=headers, content=b'%PDF-1.7').status_code == 200
    assert client.put(path + str(uuid.uuid4()), headers=headers, content=b'%PDF-1.7').status_code == 413
    # JSON endpoints retain the much smaller body limit.
    assert client.put('/notes/' + nid, headers=alice, content=b'x' * 131073).status_code == 413


def test_attachment_delete_is_idempotent_and_checks_scope(client):
    alice = account(client, 'a@example.com')
    bob = account(client, 'b@example.com')
    nid, aid = str(uuid.uuid4()), str(uuid.uuid4())
    put(client, alice, nid)
    path = f'/notes/{nid}/attachments/{aid}'
    client.put(path, headers={**alice, 'Content-Type': 'application/octet-stream'}, content=b'%PDF-1.7')
    assert client.delete(path, headers=bob).status_code == 404
    assert client.delete(path, headers=alice).status_code == 204
    assert client.delete(path, headers=alice).status_code == 204
    assert client.get('/notes/' + nid, headers=alice).json()['version'] == 3
    assert client.get(path, headers=alice).status_code == 404
