"""Small immutable attachment objects inside the transactional PostgreSQL backup."""
from alembic import op
import sqlalchemy as sa
revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('attachments',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('note_id', sa.String(36), sa.ForeignKey('notes.id'), nullable=False),
        sa.Column('uploader_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('name', sa.String(120), nullable=False),
        sa.Column('mime', sa.String(80), nullable=False),
        sa.Column('size', sa.Integer(), nullable=False),
        sa.Column('sha256', sa.String(64), nullable=False),
        sa.Column('data', sa.LargeBinary(), nullable=False))
    op.create_index('ix_attachments_note_id', 'attachments', ['note_id'])
    op.create_index('ix_attachments_uploader_id', 'attachments', ['uploader_id'])


def downgrade():
    op.drop_table('attachments')
