"""Indexes for access checks, listing and token cleanup."""
from alembic import op

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None

INDEXES = [
    ('ix_sessions_user', 'sessions', ['user_id']),
    ('ix_sessions_expires', 'sessions', ['expires']),
    ('ix_members_user', 'members', ['user_id']),
    ('ix_invites_family', 'invites', ['family_id']),
    ('ix_invites_expires', 'invites', ['expires']),
    ('ix_notes_owner_id', 'notes', ['owner_id', 'id']),
    ('ix_notes_family_id', 'notes', ['family_id', 'id']),
]


def upgrade():
    for name, table, columns in INDEXES:
        op.create_index(name, table, columns)


def downgrade():
    for name, table, _ in reversed(INDEXES):
        op.drop_index(name, table_name=table)
