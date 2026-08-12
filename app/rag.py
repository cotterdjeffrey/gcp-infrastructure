"""Retrieval layer: embedding model + pgvector similarity search over Cloud SQL.

The vector index lives in the same Cloud SQL Postgres instance the platform
provisions (via the pgvector extension) — no separate vector database. The
embedding model is baked into the container image at build time so the pod needs
no network egress to load it.
"""

import os

from sentence_transformers import SentenceTransformer
from sqlalchemy import Column, Integer, String, Text, create_engine, select
from sqlalchemy.orm import declarative_base, sessionmaker
from pgvector.sqlalchemy import Vector

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
EMBEDDING_DIM = 384  # all-MiniLM-L6-v2 output dimension
TOP_K = int(os.getenv("TOP_K", "8"))


def _build_database_url() -> str:
    """Assemble the connection string from parts.

    In-cluster, DB_PASSWORD is synced from GCP Secret Manager by the Secrets
    Store CSI driver (Workload Identity) — never baked into the image or manifest.
    An explicit DATABASE_URL still wins for local development.
    """
    explicit = os.getenv("DATABASE_URL")
    if explicit:
        return explicit
    user = os.getenv("DB_USER", "app")
    password = os.getenv("DB_PASSWORD", "")
    host = os.getenv("DB_HOST", "localhost")
    port = os.getenv("DB_PORT", "5432")
    name = os.getenv("DB_NAME", "app")
    return f"postgresql://{user}:{password}@{host}:{port}/{name}"


engine = create_engine(_build_database_url())
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

_model: SentenceTransformer | None = None


def _get_model() -> SentenceTransformer:
    global _model
    if _model is None:
        _model = SentenceTransformer(EMBEDDING_MODEL)
    return _model


class Verse(Base):
    """One Bible verse or passage plus its embedding, stored in pgvector."""

    __tablename__ = "verses"

    id = Column(Integer, primary_key=True)
    reference = Column(String(64), index=True)
    book = Column(String(48), index=True)
    testament = Column(String(2))
    type = Column(String(16))  # "verse" or "passage"
    text = Column(Text, nullable=False)
    embedding = Column(Vector(EMBEDDING_DIM), nullable=False)


def embed(text: str) -> list[float]:
    """Embed a query into the same vector space as the stored verses."""
    return _get_model().encode(text).tolist()


def search(query: str, top_k: int = TOP_K) -> list[dict]:
    """Return the top_k most similar passages by cosine distance (lower = closer)."""
    qvec = embed(query)
    with SessionLocal() as db:
        rows = db.execute(
            select(Verse, Verse.embedding.cosine_distance(qvec).label("distance"))
            .order_by("distance")
            .limit(top_k)
        ).all()
    return [
        {
            "reference": v.reference,
            "book": v.book,
            "testament": v.testament,
            "type": v.type,
            "text": v.text,
            "distance": float(distance),
        }
        for v, distance in rows
    ]
