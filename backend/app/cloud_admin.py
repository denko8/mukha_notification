"""Server-only entitlement grant, migration and retryable object GC. No client PRO trust."""
import argparse
import json
import hashlib
import os
from datetime import timedelta
from sqlalchemy import create_engine, select, func, text
from sqlalchemy.orm import Session
from .main import Attachment, CloudPlan, ObjectGarbage, User, now
from .objects import configured_objects


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    grant = sub.add_parser('plan')
    grant.add_argument('--email', required=True)
    grant.add_argument('--tier', choices=['free', 'cloud'], required=True)
    grant.add_argument('--days', type=int, default=30)
    sub.add_parser('migrate-blobs')
    sub.add_parser('collect-objects')
    sub.add_parser('measure-storage')
    args = parser.parse_args()
    engine = create_engine(os.environ['DATABASE_URL'])
    with Session(engine) as db:
        if args.command == 'plan':
            if not 1 <= args.days <= 366:
                parser.error('--days must be between 1 and 366')
            user = db.scalar(select(User).where(User.email == args.email.strip().lower()).with_for_update())
            if user is None:
                parser.error('Account not found')
            plan = db.get(CloudPlan, user.id)
            if plan is None:
                plan = CloudPlan(user_id=user.id, tier=args.tier)
                db.add(plan)
            plan.tier, plan.expires = args.tier, now() + timedelta(days=args.days)
            db.commit()
            print(f'Entitlement updated: user={user.id}, tier={plan.tier}, expires={plan.expires}')
            return
        objects = configured_objects()
        if args.command == 'measure-storage':
            physical = None
            if db.get_bind().dialect.name == 'postgresql':
                tables = ['notes', 'attachments', 'note_changes', 'mutation_receipts', 'sync_snapshots']
                physical = {table: db.scalar(text('SELECT pg_total_relation_size(:name)'), {'name': table}) for table in tables}
            print(json.dumps(dict(
                active_attachment_bytes=db.scalar(select(func.coalesce(func.sum(Attachment.size), 0))),
                legacy_bytea_payload_bytes=db.scalar(select(func.coalesce(func.sum(func.length(Attachment.data)), 0))),
                postgres_table_and_index_bytes=physical,
                current_s3_objects=objects.inventory() if objects else None,
                note='S3 inventory excludes noncurrent versions, replicas and billing overhead; no object body downloaded'), indent=2))
            return
        if objects is None:
            parser.error('Configure private S3 storage first')
        if args.command == 'migrate-blobs':
            # One object + one DB transaction per row. Safe to restart; never drop
            # legacy bytes until a complete read-back/hash check has succeeded.
            ids = list(db.scalars(select(Attachment.id).where(Attachment.data.is_not(None))))
            for attachment_id in ids:
                item = db.scalar(select(Attachment).where(Attachment.id == attachment_id).with_for_update())
                if item is None or item.data is None:
                    db.rollback()
                    continue
                key = f'attachments/{item.uploader_id}/{item.id}/{item.sha256}'
                objects.put(key, item.data, item.mime)
                if hashlib.sha256(objects.get(key)).hexdigest() != item.sha256:
                    raise RuntimeError('Object read-back check failed; original DB bytes retained')
                item.object_key, item.data = key, None
                db.commit()
            print('Legacy blob migration complete')
        else:
            for key in list(db.scalars(select(ObjectGarbage.key))):
                objects.delete(key)  # idempotent; failure leaves the DB retry record
                item = db.get(ObjectGarbage, key)
                if item is not None:
                    db.delete(item)
                db.commit()
            print('Retired object collection complete')


if __name__ == '__main__':
    main()
