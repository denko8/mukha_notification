"""Durable write receipts and immutable, expiring full-sync snapshots."""
from alembic import op
import sqlalchemy as sa

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('mutation_receipts',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('operation_id', sa.String(36), primary_key=True),
        sa.Column('request_hash', sa.String(64), nullable=False),
        sa.Column('note_id', sa.String(36), nullable=False),
        sa.Column('result', sa.JSON(), nullable=False))
    op.create_table('sync_snapshots',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('expires', sa.DateTime(timezone=True), nullable=False),
        sa.Column('family_ids', sa.JSON(), nullable=False),
        sa.Column('notes', sa.JSON(), nullable=False))
    op.create_index('ix_sync_snapshots_user_id', 'sync_snapshots', ['user_id'])
    op.create_index('ix_sync_snapshots_expires', 'sync_snapshots', ['expires'])


def downgrade():
    op.drop_table('sync_snapshots')
    op.drop_table('mutation_receipts')
