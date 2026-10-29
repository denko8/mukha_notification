"""Initial versioned schema. Frozen here, independent of future ORM changes."""
from alembic import op
import sqlalchemy as sa

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('users',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('email', sa.String(254), nullable=False, unique=True),
        sa.Column('name', sa.String(80), nullable=False),
        sa.Column('password_hash', sa.String(255), nullable=False))
    op.create_table('sessions',
        sa.Column('token_hash', sa.String(64), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('expires', sa.DateTime(timezone=True), nullable=False))
    op.create_table('families',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(80), nullable=False),
        sa.Column('owner_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False))
    op.create_table('members',
        sa.Column('family_id', sa.String(36), sa.ForeignKey('families.id'), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True))
    op.create_table('invites',
        sa.Column('token_hash', sa.String(64), primary_key=True),
        sa.Column('family_id', sa.String(36), sa.ForeignKey('families.id'), nullable=False),
        sa.Column('expires', sa.DateTime(timezone=True), nullable=False),
        sa.Column('used', sa.Integer(), nullable=False))
    op.create_table('notes',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('owner_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('family_id', sa.String(36), sa.ForeignKey('families.id'), nullable=True),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('deleted', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False))


def downgrade():
    for name in ['notes', 'invites', 'members', 'families', 'sessions', 'users']:
        op.drop_table(name)
