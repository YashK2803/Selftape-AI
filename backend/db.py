# db.py
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool
from sqlalchemy.orm import sessionmaker, declarative_base

# Replace with your actual PostgreSQL credentials
DATABASE_URL = "postgresql://postgres.fhdmktfofvqoayihpuyk:ok123@aws-1-ap-southeast-2.pooler.supabase.com:5432/postgres"

engine = create_engine(
    DATABASE_URL,
    # 1. Disable SQLAlchemy pooling (let Supabase handle it)
    poolclass=NullPool,
    # 2. Disable prepared statements (incompatible with some poolers)
    connect_args={'prepare_threshold': None}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()