"""Ingest the KJV Bible into pgvector on Cloud SQL.

Creates the pgvector extension and the verses table, downloads all 66 books,
chunks them into verses and overlapping passages, embeds each with the same
model the service uses at query time, and bulk-inserts the rows.

Run once against the target database (DATABASE_URL / DB_* env vars):
    python ingest.py
"""

import requests
from sqlalchemy import text

from rag import Base, SessionLocal, Verse, _get_model, engine

BIBLE_REPO_URL = "https://raw.githubusercontent.com/aruljohn/Bible-kjv/master"
PASSAGE_CHUNK_SIZE = 5  # verses per passage chunk
PASSAGE_OVERLAP = 2     # overlapping verses between chunks
BATCH_SIZE = 500

BOOKS = [
    "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
    "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
    "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
    "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
    "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
    "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah",
    "Haggai", "Zechariah", "Malachi",
    "Matthew", "Mark", "Luke", "John", "Acts",
    "Romans", "1 Corinthians", "2 Corinthians", "Galatians",
    "Ephesians", "Philippians", "Colossians",
    "1 Thessalonians", "2 Thessalonians",
    "1 Timothy", "2 Timothy", "Titus", "Philemon",
    "Hebrews", "James", "1 Peter", "2 Peter",
    "1 John", "2 John", "3 John", "Jude", "Revelation",
]
OT_BOOKS = set(BOOKS[:39])


def download_book(book: str) -> dict:
    url = f"{BIBLE_REPO_URL}/{book.replace(' ', '')}.json"
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    return resp.json()


def testament_of(book: str) -> str:
    return "OT" if book in OT_BOOKS else "NT"


def records_for_book(book_data: dict, book: str) -> list[dict]:
    """Build verse and overlapping-passage records for one book."""
    records = []
    for chapter in book_data.get("chapters", []):
        chapter_num = int(chapter["chapter"])
        verses = [
            {"verse": int(v["verse"]), "text": v["text"].strip()}
            for v in chapter["verses"]
        ]
        # Individual verses
        for v in verses:
            ref = f"{book} {chapter_num}:{v['verse']}"
            records.append({
                "reference": ref, "book": book, "testament": testament_of(book),
                "type": "verse", "text": v["text"],
            })
        # Overlapping passage chunks
        step = PASSAGE_CHUNK_SIZE - PASSAGE_OVERLAP
        for i in range(0, len(verses), step):
            chunk = verses[i : i + PASSAGE_CHUNK_SIZE]
            if not chunk:
                break
            ref = f"{book} {chapter_num}:{chunk[0]['verse']}-{chunk[-1]['verse']}"
            records.append({
                "reference": ref, "book": book, "testament": testament_of(book),
                "type": "passage", "text": " ".join(v["text"] for v in chunk),
            })
    return records


def ingest() -> None:
    print("Ensuring pgvector extension and schema...")
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    Base.metadata.drop_all(engine)   # fresh ingest
    Base.metadata.create_all(engine)

    print("Loading embedding model...")
    model = _get_model()

    all_records = []
    for i, book in enumerate(BOOKS, 1):
        print(f"[{i}/{len(BOOKS)}] Downloading {book}...")
        try:
            all_records.extend(records_for_book(download_book(book), book))
        except requests.RequestException as e:
            print(f"  ERROR downloading {book}: {e}")

    total = len(all_records)
    print(f"\nEmbedding and inserting {total} records...")
    for start in range(0, total, BATCH_SIZE):
        batch = all_records[start : start + BATCH_SIZE]
        embeddings = model.encode([r["text"] for r in batch], show_progress_bar=False)
        with SessionLocal() as db:
            db.add_all([
                Verse(
                    reference=r["reference"], book=r["book"], testament=r["testament"],
                    type=r["type"], text=r["text"], embedding=emb.tolist(),
                )
                for r, emb in zip(batch, embeddings)
            ])
            db.commit()
        print(f"  Inserted {min(start + BATCH_SIZE, total)}/{total}")

    print(f"\nDone. {total} records in pgvector.")


if __name__ == "__main__":
    ingest()
