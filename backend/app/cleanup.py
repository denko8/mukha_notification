"""Delete expired sessions/invites. Deliberately never remove note tombstones."""
import os
from sqlalchemy import create_engine, delete
from sqlalchemy.orm import Session
from .main import AuthSession, Invite, now

if __name__ == '__main__':
    with Session(create_engine(os.environ['DATABASE_URL'])) as db:
        sessions = db.execute(delete(AuthSession).where(AuthSession.expires <= now())).rowcount
        invites = db.execute(delete(Invite).where(Invite.expires <= now())).rowcount
        db.commit()
        print(f'Deleted expired sessions: {sessions}; invites: {invites}')
