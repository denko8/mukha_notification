"""Reproducible logical traffic benchmark, NOT a hosting-price/load benchmark.
Run from backend: python -m scripts.measure_cloud --notes 100 --chars 1000
"""
import argparse
import json
import os
import tempfile
import uuid
from pathlib import Path

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from app.main import NoteChange, create_app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--notes', type=int, default=100)
    parser.add_argument('--chars', type=int, default=1000)
    args = parser.parse_args()
    if not 1 <= args.notes <= 200 or not 1 <= args.chars <= 10000:
        parser.error('notes: 1..200, chars: 1..10000 (keeps test below request limits)')
    with tempfile.TemporaryDirectory() as tmp:
        url = f'sqlite:///{Path(tmp) / "measure.db"}'
        os.environ['DATABASE_URL'] = url
        cfg = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
        command.upgrade(cfg, 'head')
        app = create_app(url)
        try:
            with TestClient(app) as client:
                registered = client.post('/auth/register', json={
                    'email': 'benchmark@example.test', 'password': 'benchmark-test-password-123', 'name': 'Benchmark'})
                registered.raise_for_status()
                headers = {'Authorization': 'Bearer ' + registered.json()['access_token']}
                ids = [str(uuid.uuid4()) for _ in range(args.notes)]
                text = 'Я' * args.chars
                for nid in ids:
                    client.put('/notes/' + nid, headers=headers,
                        json={'expected_version': 0, 'text': text}).raise_for_status()
                baseline = client.get('/notes?limit=200', headers=headers)
                baseline.raise_for_status()
                initial_bytes = 0
                cursor = None
                while True:
                    page = client.get('/sync/changes', headers=headers,
                        params={'cursor': cursor, 'limit': 200} if cursor else {'limit': 200})
                    page.raise_for_status()
                    initial_bytes += len(page.content)
                    cursor = page.json()['cursor']
                    if not page.json()['has_more']: break
                client.put('/notes/' + ids[0], headers=headers,
                    json={'expected_version': 1, 'text': text + '!'}).raise_for_status()
                delta = client.get('/sync/changes', headers=headers, params={'cursor': cursor})
                delta.raise_for_status()
                idle = client.get('/sync/changes', headers=headers, params={'cursor': delta.json()['cursor']})
                idle.raise_for_status()
                with Session(app.state.engine) as db:
                    index_rows = db.scalar(select(func.count()).select_from(NoteChange))
                print(json.dumps(dict(notes=args.notes, characters_per_note=args.chars,
                    text_utf8_bytes=len(text.encode()) * args.notes,
                    full_list_json_bytes=len(baseline.content), bootstrap_json_bytes=initial_bytes,
                    one_edit_delta_json_bytes=len(delta.content), idle_delta_json_bytes=len(idle.content),
                    file_download_requests=0, compact_change_index_rows=index_rows,
                    saving_one_edit_percent=round((1-len(delta.content)/len(baseline.content))*100, 2),
                    scope='JSON response bodies only; excludes TLS/HTTP, latency, DB pages, backups and S3 billing'),
                    ensure_ascii=False, indent=2))
        finally:
            app.state.engine.dispose()


if __name__ == '__main__': main()
