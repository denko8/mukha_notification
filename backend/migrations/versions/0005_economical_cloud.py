"""Compact change index, object references and server-owned cloud entitlement."""
import secrets
from alembic import op
import sqlalchemy as sa

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('attachments') as batch:
        batch.alter_column('data', existing_type=sa.LargeBinary(), nullable=True)
        batch.add_column(sa.Column('object_key', sa.String(240), nullable=True))
    op.create_table('sync_clock', sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('position', sa.BigInteger(), nullable=False), sa.Column('secret', sa.String(64), nullable=False))
    op.create_table('note_changes',
        sa.Column('note_id', sa.String(36), sa.ForeignKey('notes.id'), primary_key=True),
        sa.Column('position', sa.BigInteger(), nullable=False),
        sa.Column('owner_id', sa.String(36), nullable=False), sa.Column('family_id', sa.String(36), nullable=True))
    op.create_index('ix_note_changes_position', 'note_changes', ['position'], unique=True)
    op.create_index('ix_changes_owner_scope', 'note_changes', ['owner_id', 'family_id', 'position'])
    op.create_index('ix_changes_family_scope', 'note_changes', ['family_id', 'position'])
    op.create_table('cloud_plans', sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('tier', sa.String(20), nullable=False), sa.Column('expires', sa.DateTime(timezone=True), nullable=True))
    op.create_table('object_garbage', sa.Column('key', sa.String(240), primary_key=True))
    op.create_table('cloud_usage', sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('uploaded_bytes', sa.BigInteger(), nullable=False),
        sa.Column('download_granted_bytes', sa.BigInteger(), nullable=False),
        sa.Column('sync_response_bytes', sa.BigInteger(), nullable=False))
    bind = op.get_bind()
    rows = bind.execute(sa.text('SELECT id, owner_id, family_id FROM notes ORDER BY id'))
    position = 0
    for row in rows:
        position += 1
        bind.execute(sa.text('INSERT INTO note_changes (note_id,position,owner_id,family_id) VALUES (:id,:p,:owner,:family)'),
            dict(id=row.id, p=position, owner=row.owner_id, family=row.family_id))
    bind.execute(sa.text('INSERT INTO sync_clock (id,position,secret) VALUES (1,:p,:secret)'),
                 dict(p=position, secret=secrets.token_hex(32)))


def downgrade():
    # Never silently discard external object references or lose data on rollback.
    bind = op.get_bind()
    if bind.scalar(sa.text('SELECT count(*) FROM attachments WHERE data IS NULL')):
        raise RuntimeError('Restore object bytes to DB before downgrading attachment schema')
    for name in ['cloud_usage', 'object_garbage', 'cloud_plans', 'note_changes', 'sync_clock']:
        op.drop_table(name)
    with op.batch_alter_table('attachments') as batch:
        batch.drop_column('object_key')
        batch.alter_column('data', existing_type=sa.LargeBinary(), nullable=False)
