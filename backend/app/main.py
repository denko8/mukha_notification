"""Self-hosted API foundation. Clients retain their local offline store."""
import hashlib
import json
import os
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field
from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, create_engine, delete, func, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from .limits import RequestLimits


def now():
    return datetime.now(timezone.utc)


def digest(token: str):
    return hashlib.sha256(token.encode()).hexdigest()


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    name: Mapped[str] = mapped_column(String(80))
    password_hash: Mapped[str] = mapped_column(String(255))


class AuthSession(Base):
    __tablename__ = 'sessions'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    expires: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Family(Base):
    __tablename__ = 'families'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    owner_id: Mapped[str] = mapped_column(ForeignKey('users.id'))


class Member(Base):
    __tablename__ = 'members'
    family_id: Mapped[str] = mapped_column(ForeignKey('families.id'), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)


class Invite(Base):
    __tablename__ = 'invites'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    family_id: Mapped[str] = mapped_column(ForeignKey('families.id'))
    expires: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used: Mapped[int] = mapped_column(Integer, default=0)


class Note(Base):
    __tablename__ = 'notes'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    family_id: Mapped[str | None] = mapped_column(ForeignKey('families.id'), nullable=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    deleted: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    payload: Mapped[dict] = mapped_column(JSON)


class MutationReceipt(Base):
    __tablename__ = 'mutation_receipts'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    operation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    request_hash: Mapped[str] = mapped_column(String(64))
    note_id: Mapped[str] = mapped_column(String(36))
    result: Mapped[dict] = mapped_column(JSON)


class SyncSnapshot(Base):
    __tablename__ = 'sync_snapshots'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    expires: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    family_ids: Mapped[list] = mapped_column(JSON)
    notes: Mapped[list] = mapped_column(JSON)


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Credentials(Input):
    email: str = Field(min_length=3, max_length=254, pattern=r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
    password: str = Field(min_length=12, max_length=128)


class Registration(Credentials):
    name: str = Field(min_length=1, max_length=80)


class FamilyInput(Input):
    name: str = Field(min_length=1, max_length=80)


class JoinInput(Input):
    token: str = Field(min_length=20, max_length=100)


class NoteInput(Input):
    # Client generates UUID before storing offline. Scope/author cannot be changed.
    family_id: uuid.UUID | None = None
    expected_version: int = Field(ge=0)
    text: str = Field(min_length=1, max_length=20000)
    reminder_at: AwareDatetime | None = None
    done: bool = False
    category: str = Field(default='general', min_length=1, max_length=100)


class DeleteInput(Input):
    expected_version: int = Field(ge=1)


def aware(value):
    # SQLite test driver returns naive datetimes; production PostgreSQL retains tz.
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def create_app(database_url: str | None = None):
    database_url = database_url or os.environ.get('DATABASE_URL')
    if not database_url:
        raise RuntimeError('DATABASE_URL must be configured')
    engine = create_engine(database_url, pool_pre_ping=True)
    sessions = sessionmaker(engine, expire_on_commit=False)
    app = FastAPI(title='Smart Notes API', version='0.3.0')
    app.add_middleware(RequestLimits)
    app.state.engine = engine
    password_hash = PasswordHash.recommended()
    # Avoid skipping the expensive password check for unknown accounts.
    dummy_hash = password_hash.hash(secrets.token_urlsafe(32))
    bearer = HTTPBearer(auto_error=False)

    def db():
        with sessions() as session:
            yield session

    DB = Annotated[Session, Depends(db)]

    def auth(db: DB, credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if credentials is None:
            raise HTTPException(401, 'Authentication required')
        session = db.get(AuthSession, digest(credentials.credentials))
        if session is None or aware(session.expires) <= now():
            raise HTTPException(401, 'Session expired or invalid')
        return db.get(User, session.user_id)

    Current = Annotated[User, Depends(auth)]

    def family_access(db, family_id, user):
        if db.get(Member, (family_id, user.id)) is None:
            raise HTTPException(404, 'Family not found')

    def note_access(db, note, user):
        if note is None:
            raise HTTPException(404, 'Note not found')
        if note.family_id:
            family_access(db, note.family_id, user)
        elif note.owner_id != user.id:
            raise HTTPException(404, 'Note not found')

    def public_note(note):
        return dict(id=note.id, author_id=note.owner_id, family_id=note.family_id,
                    version=note.version, deleted=bool(note.deleted),
                    updated_at=aware(note.updated_at).isoformat(), **note.payload)

    def issue_session(db, user):
        token = secrets.token_urlsafe(32)
        expires = now() + timedelta(days=30)
        db.add(AuthSession(token_hash=digest(token), user_id=user.id, expires=expires))
        db.commit()
        return dict(access_token=token, token_type='bearer', expires_at=expires.isoformat(),
                    user=dict(id=user.id, name=user.name, email=user.email))

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.get('/ready')
    def ready(db: DB):
        # Liveness is separate: readiness requires a reachable, initialized DB.
        try:
            db.execute(select(User.id).limit(1))
        except Exception:
            raise HTTPException(503, 'Database not ready')
        return {'status': 'ready'}

    @app.post('/auth/register', status_code=201)
    def register(data: Registration, db: DB):
        from sqlalchemy.exc import IntegrityError
        user = User(id=str(uuid.uuid4()), email=data.email.strip().lower(),
                    name=data.name, password_hash=password_hash.hash(data.password))
        db.add(user)
        try:
            db.flush()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'Registration unavailable for this email')
        return issue_session(db, user)

    @app.post('/auth/login')
    def login(data: Credentials, db: DB):
        user = db.scalar(select(User).where(User.email == data.email.strip().lower()))
        valid = password_hash.verify(data.password, user.password_hash if user else dummy_hash)
        if user is None or not valid:
            raise HTTPException(401, 'Invalid credentials')
        return issue_session(db, user)

    @app.post('/auth/logout', status_code=204)
    def logout(db: DB, user: Current, credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer)]):
        db.delete(db.get(AuthSession, digest(credentials.credentials)))
        db.commit()
        return Response(status_code=204)

    @app.get('/me')
    def me(user: Current):
        return dict(id=user.id, name=user.name, email=user.email)

    @app.post('/families', status_code=201)
    def create_family(data: FamilyInput, db: DB, user: Current):
        family = Family(id=str(uuid.uuid4()), name=data.name, owner_id=user.id)
        db.add(family)
        db.flush()
        db.add(Member(family_id=family.id, user_id=user.id))
        db.commit()
        return dict(id=family.id, name=family.name, owner_id=family.owner_id)

    @app.get('/families')
    def families(db: DB, user: Current):
        return [dict(id=f.id, name=f.name, owner_id=f.owner_id) for f in
                db.scalars(select(Family).join(Member).where(Member.user_id == user.id))]

    @app.get('/families/{family_id}/members')
    def members(family_id: uuid.UUID, db: DB, user: Current):
        family_access(db, str(family_id), user)
        return [dict(id=u.id, name=u.name) for u in db.scalars(
            select(User).join(Member).where(Member.family_id == str(family_id)))]

    @app.post('/families/{family_id}/invites', status_code=201)
    def invite(family_id: uuid.UUID, db: DB, user: Current):
        family_access(db, str(family_id), user)
        if db.get(Family, str(family_id)).owner_id != user.id:
            raise HTTPException(403, 'Only the family owner may invite')
        token = secrets.token_urlsafe(32)
        expires = now() + timedelta(days=2)
        db.add(Invite(token_hash=digest(token), family_id=str(family_id), expires=expires))
        db.commit()
        return dict(token=token, expires_at=expires.isoformat())

    @app.post('/families/join')
    def join(data: JoinInput, db: DB, user: Current):
        invitation = db.scalar(select(Invite).where(Invite.token_hash == digest(data.token)))
        if invitation is None or invitation.used or aware(invitation.expires) <= now():
            raise HTTPException(404, 'Invite invalid or expired')
        lock_family(db, invitation.family_id)
        if db.get(Member, (invitation.family_id, user.id)):
            raise HTTPException(409, 'Already a member')
        # Conditional update makes consumption single-use even for concurrent requests.
        changed = db.execute(update(Invite).where(
            Invite.token_hash == invitation.token_hash, Invite.used == 0,
            Invite.expires > now()).values(used=1).execution_options(synchronize_session=False))
        if changed.rowcount != 1:
            raise HTTPException(409, 'Invite already consumed')
        db.add(Member(family_id=invitation.family_id, user_id=user.id))
        db.commit()
        return dict(family_id=invitation.family_id)

    def lock_family(db, family_id):
        return db.scalar(select(Family).where(Family.id == family_id).with_for_update())

    @app.delete('/families/{family_id}/invites', status_code=204)
    def revoke_invites(family_id: uuid.UUID, db: DB, user: Current):
        family = lock_family(db, str(family_id))
        if family is None or family.owner_id != user.id:
            raise HTTPException(404, 'Family not found')
        db.execute(update(Invite).where(Invite.family_id == str(family_id)).values(used=1))
        db.commit()
        return Response(status_code=204)

    @app.delete('/families/{family_id}/members/{member_id}', status_code=204)
    def remove_member(family_id: uuid.UUID, member_id: uuid.UUID, db: DB, user: Current):
        family = lock_family(db, str(family_id))
        family_access(db, str(family_id), user)
        target = str(member_id)
        if family.owner_id == target:
            raise HTTPException(409, 'Owner cannot leave; ownership transfer is not implemented yet')
        if target != user.id and family.owner_id != user.id:
            raise HTTPException(403, 'Only owner can remove other members')
        member = db.get(Member, (str(family_id), target))
        if member is None:
            raise HTTPException(404, 'Member not found')
        db.delete(member)
        db.commit()
        return Response(status_code=204)

    @app.get('/notes')
    def notes(db: DB, user: Current, offset: int = 0, limit: int = 100):
        if offset < 0 or not 1 <= limit <= 200:
            raise HTTPException(422, 'Invalid pagination')
        family_ids = select(Member.family_id).where(Member.user_id == user.id)
        accessible = ((Note.owner_id == user.id) & Note.family_id.is_(None)) | Note.family_id.in_(family_ids)
        # Tombstones are included, so an offline device can apply deletions.
        return [public_note(n) for n in db.scalars(select(Note).where(accessible)
                .order_by(Note.id).offset(offset).limit(limit))]

    def begin_mutation(db, user, key, method, note_id, data):
        # Serialize this user's writes/receipts. PG locks are held until commit.
        db.execute(select(User.id).where(User.id == user.id).with_for_update())
        fingerprint = digest(json.dumps([method, str(note_id), data.model_dump(mode='json')],
                                        sort_keys=True, separators=(',', ':')))
        if key is None:
            return fingerprint, None
        receipt = db.get(MutationReceipt, (user.id, str(key)))
        if receipt is not None:
            if receipt.request_hash != fingerprint:
                raise HTTPException(409, 'Idempotency key reused for a different request')
            # A receipt must never bypass revoked family access.
            note_access(db, db.get(Note, receipt.note_id), user)
            return fingerprint, receipt.result
        if db.scalar(select(func.count()).select_from(MutationReceipt).where(
                MutationReceipt.user_id == user.id)) >= 10000:
            raise HTTPException(429, 'Mutation receipt quota reached; contact administrator')
        return fingerprint, None

    def finish_mutation(db, user, key, fingerprint, note):
        result = public_note(note)
        if key is not None:
            db.add(MutationReceipt(user_id=user.id, operation_id=str(key),
                request_hash=fingerprint, note_id=note.id, result=result))
        # Receipt and note change are committed atomically, before replying.
        db.commit()
        return result

    @app.get('/notes/{note_id}')
    def get_note(note_id: uuid.UUID, db: DB, user: Current):
        note = db.get(Note, str(note_id))
        note_access(db, note, user)
        return public_note(note)

    @app.post('/sync/snapshots', status_code=201)
    def snapshot(db: DB, user: Current):
        db.execute(select(User.id).where(User.id == user.id).with_for_update())
        db.execute(delete(SyncSnapshot).where(SyncSnapshot.expires <= now()))
        count = db.scalar(select(func.count()).select_from(SyncSnapshot).where(
            SyncSnapshot.user_id == user.id))
        if count >= 3:
            raise HTTPException(429, 'Too many active snapshots; release one or wait 10 minutes')
        scopes = sorted(db.scalars(select(Member.family_id).where(Member.user_id == user.id)))
        accessible = ((Note.owner_id == user.id) & Note.family_id.is_(None)) | Note.family_id.in_(scopes)
        # One SELECT freezes a consistent set of rows; no offset over live data.
        rows = list(db.scalars(select(Note).where(accessible).order_by(Note.id).limit(1001)))
        if len(rows) > 1000:
            raise HTTPException(413, 'Snapshot note limit reached; incremental sync is required')
        frozen = [public_note(n) for n in rows]
        if len(json.dumps(frozen).encode()) > 8 * 1024 * 1024:
            raise HTTPException(413, 'Snapshot byte limit reached')
        snap = SyncSnapshot(id=str(uuid.uuid4()), user_id=user.id,
            expires=now() + timedelta(minutes=10), family_ids=scopes, notes=frozen)
        db.add(snap)
        db.commit()
        return dict(snapshot_id=snap.id, expires_at=snap.expires.isoformat(),
                    total=len(frozen), family_ids=scopes)

    def own_snapshot(db, user, snapshot_id):
        snap = db.get(SyncSnapshot, str(snapshot_id))
        if snap is None or snap.user_id != user.id:
            raise HTTPException(404, 'Snapshot not found')
        if aware(snap.expires) <= now():
            raise HTTPException(410, 'Snapshot expired; restart download')
        scopes = sorted(db.scalars(select(Member.family_id).where(Member.user_id == user.id)))
        if scopes != snap.family_ids:
            raise HTTPException(409, 'Family access changed; discard snapshot and restart')
        return snap

    @app.get('/sync/snapshots/{snapshot_id}')
    def snapshot_page(snapshot_id: uuid.UUID, db: DB, user: Current,
                      offset: int = 0, limit: int = 100):
        snap = own_snapshot(db, user, snapshot_id)
        if offset < 0 or offset > len(snap.notes) or not 1 <= limit <= 200:
            raise HTTPException(422, 'Invalid snapshot pagination')
        end = min(offset + limit, len(snap.notes))
        return dict(snapshot_id=snap.id, notes=snap.notes[offset:end],
                    next_offset=end if end < len(snap.notes) else None,
                    total=len(snap.notes), family_ids=snap.family_ids)

    @app.delete('/sync/snapshots/{snapshot_id}', status_code=204)
    def release_snapshot(snapshot_id: uuid.UUID, db: DB, user: Current):
        # Release must work even if the snapshot expired or access changed.
        snap = db.get(SyncSnapshot, str(snapshot_id))
        if snap is None or snap.user_id != user.id:
            raise HTTPException(404, 'Snapshot not found')
        db.delete(snap)
        db.commit()
        return Response(status_code=204)

    @app.put('/notes/{note_id}')
    def put_note(note_id: uuid.UUID, data: NoteInput, db: DB, user: Current,
                 idempotency_key: Annotated[uuid.UUID | None, Header()] = None):
        from sqlalchemy.exc import IntegrityError
        fingerprint, replay = begin_mutation(db, user, idempotency_key, 'PUT', note_id, data)
        if replay is not None:
            return replay
        note = db.get(Note, str(note_id))
        payload = data.model_dump(mode='json', exclude={'expected_version', 'family_id'})
        family_id = str(data.family_id) if data.family_id else None
        if note is None:
            if data.expected_version != 0:
                raise HTTPException(409, 'Note missing; fetch remote state')
            if family_id:
                lock_family(db, family_id)
                family_access(db, family_id, user)
            note = Note(id=str(note_id), owner_id=user.id, family_id=family_id,
                        payload=payload, version=1, deleted=0, updated_at=now())
            db.add(note)
            try:
                db.flush()
            except IntegrityError:
                db.rollback()
                raise HTTPException(409, 'Concurrent creation; fetch remote state')
        else:
            if note.family_id:
                lock_family(db, note.family_id)
            note_access(db, note, user)
            if family_id != note.family_id:
                raise HTTPException(422, 'Moving notes between scopes is not supported yet')
            changed = db.execute(update(Note).where(Note.id == note.id,
                Note.version == data.expected_version, Note.deleted == 0).values(
                payload=payload, version=Note.version + 1, updated_at=now()))
            if changed.rowcount != 1:
                raise HTTPException(409, 'Version conflict; fetch remote state')
            db.refresh(note)
        return finish_mutation(db, user, idempotency_key, fingerprint, note)

    @app.delete('/notes/{note_id}')
    def delete_note(note_id: uuid.UUID, data: DeleteInput, db: DB, user: Current,
                    idempotency_key: Annotated[uuid.UUID | None, Header()] = None):
        fingerprint, replay = begin_mutation(db, user, idempotency_key, 'DELETE', note_id, data)
        if replay is not None:
            return replay
        note = db.get(Note, str(note_id))
        if note is not None and note.family_id:
            lock_family(db, note.family_id)
        note_access(db, note, user)
        changed = db.execute(update(Note).where(Note.id == note.id,
            Note.version == data.expected_version, Note.deleted == 0).values(
            deleted=1, payload={}, version=Note.version + 1, updated_at=now()))
        if changed.rowcount != 1:
            raise HTTPException(409, 'Version conflict; fetch remote state')
        db.refresh(note)
        return finish_mutation(db, user, idempotency_key, fingerprint, note)

    return app
