"""Compatibility entrypoint: apply versioned migrations, never create_all."""
from alembic import command
from alembic.config import Config

if __name__ == '__main__':
    command.upgrade(Config('alembic.ini'), 'head')
