"""Self-hosted API foundation. Clients retain their local offline store."""
import hashlib
import os
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, create_engine, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


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
    reminder_at: datetime | None = None
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
    app = FastAPI(title='Smart Notes API', version='0.1.0')
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

    @app.get('/notes')
    def notes(db: DB, user: Current, offset: int = 0, limit: int = 100):
        if offset < 0 or not 1 <= limit <= 200:
            raise HTTPException(422, 'Invalid pagination')
        family_ids = select(Member.family_id).where(Member.user_id == user.id)
        accessible = ((Note.owner_id == user.id) & Note.family_id.is_(None)) | Note.family_id.in_(family_ids)
        # Tombstones are included, so an offline device can apply deletions.
        return [public_note(n) for n in db.scalars(select(Note).where(accessible)
                .order_by(Note.id).offset(offset).limit(limit))]

    @app.put('/notes/{note_id}')
    def put_note(note_id: uuid.UUID, data: NoteInput, db: DB, user: Current):
        from sqlalchemy.exc import IntegrityError
        note = db.get(Note, str(note_id))
        payload = data.model_dump(mode='json', exclude={'expected_version', 'family_id'})
        family_id = str(data.family_id) if data.family_id else None
        if note is None:
            if data.expected_version != 0:
                raise HTTPException(409, 'Note missing; fetch remote state')
            if family_id:
                family_access(db, family_id, user)
            note = Note(id=str(note_id), owner_id=user.id, family_id=family_id,
                        payload=payload, version=1, deleted=0, updated_at=now())
            db.add(note)
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                raise HTTPException(409, 'Concurrent creation; fetch remote state')
        else:
            note_access(db, note, user)
            if family_id != note.family_id:
                raise HTTPException(422, 'Moving notes between scopes is not supported yet')
            changed = db.execute(update(Note).where(Note.id == note.id,
                Note.version == data.expected_version, Note.deleted == 0).values(
                payload=payload, version=Note.version + 1, updated_at=now()))
            if changed.rowcount != 1:
                raise HTTPException(409, 'Version conflict; fetch remote state')
            db.commit()
            db.refresh(note)
        return public_note(note)

    @app.delete('/notes/{note_id}')
    def delete_note(note_id: uuid.UUID, data: DeleteInput, db: DB, user: Current):
        note = db.get(Note, str(note_id))
        note_access(db, note, user)
        changed = db.execute(update(Note).where(Note.id == note.id,
            Note.version == data.expected_version, Note.deleted == 0).values(
            deleted=1, payload={}, version=Note.version + 1, updated_at=now()))
        if changed.rowcount != 1:
            raise HTTPException(409, 'Version conflict; fetch remote state')
        db.commit()
        db.refresh(note)
        return public_note(note)

    return app
