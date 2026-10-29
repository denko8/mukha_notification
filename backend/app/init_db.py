"""Initial development schema only. Do not use as a migration tool."""
import os
from sqlalchemy import create_engine
from .main import Base

if __name__ == '__main__':
    Base.metadata.create_all(create_engine(os.environ['DATABASE_URL']))
