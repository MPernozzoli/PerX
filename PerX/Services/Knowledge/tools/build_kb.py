#!/usr/bin/env python3
"""
Costruisce il database vettoriale kb.sqlite a partire da file .txt/.md/.rtf.
Supporta chunking per heading in stile:

#TITOLO_CON_UNDERSCORE
corpo del chunk

#ALTRO_TITOLO
corpo successivo

Usa OpenAI embeddings (model default: text-embedding-3-small).

Esempio:
  OPENAI_API_KEY=sk-... python build_kb.py ./docs --output kb.sqlite
"""

import argparse
import json
import os
import sqlite3
import re
import struct
import sys
import time
import urllib.request

SUPPORTED_EXT = {".txt", ".md", ".rtf"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Genera kb.sqlite da file .txt/.md usando OpenAI embeddings.")
    p.add_argument("inputs", nargs="+", help="File o directory contenenti .txt/.md")
    p.add_argument("--output", default="kb.sqlite", help="Percorso output SQLite (default: kb.sqlite)")
    p.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", ""), help="API key OpenAI (altrimenti usa env OPENAI_API_KEY)")
    p.add_argument("--base-url", default=os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"), help="Base URL OpenAI (default: https://api.openai.com/v1)")
    p.add_argument("--model", default=os.environ.get("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"), help="Modello embedding (default: text-embedding-3-small)")
    p.add_argument("--chunk-size", type=int, default=1500, help="Dimensione chunk in caratteri (default: 1500)")
    p.add_argument("--chunk-overlap", type=int, default=200, help="Overlap tra chunk in caratteri (default: 200)")
    p.add_argument("--drop-existing", action="store_true", help="Droppa tabella esistente kb_chunks se presente")
    return p.parse_args()


def iter_files(inputs):
    for path in inputs:
        if os.path.isdir(path):
            for root, _, files in os.walk(path):
                for name in files:
                    if os.path.splitext(name)[1].lower() in SUPPORTED_EXT:
                        yield os.path.join(root, name)
        else:
            if os.path.splitext(path)[1].lower() in SUPPORTED_EXT:
                yield path


def read_text(path: str) -> str:
    # RTF: convert a testo semplice
    ext = os.path.splitext(path)[1].lower()
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        raw = f.read()
    if ext == ".rtf":
        return rtf_to_text(raw)
    return raw


def rtf_to_text(raw: str) -> str:
    # Conversione minima: rimuove comandi \control, gruppi { } e codici esadecimali \'hh
    text = re.sub(r"\\'[0-9a-fA-F]{2}", lambda m: bytes.fromhex(m.group(0)[2:]).decode("latin-1", errors="ignore"), raw)
    text = re.sub(r"\\[a-zA-Z]+\d*", "", text)
    text = text.replace("{", "").replace("}", "")
    return text


def chunk_text(text: str, size: int, overlap: int):
    chunks = []
    start = 0
    n = len(text)
    while start < n:
        end = min(start + size, n)
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= n:
            break
        start = max(end - overlap, start + 1)
    return chunks


def chunk_by_headings(text: str):
    lines = text.splitlines()
    chunks = []
    current_title = None
    buffer = []
    for line in lines:
        if line.startswith("#"):
            # salva chunk precedente
            if current_title is not None and buffer:
                body = "\n".join(buffer).strip()
                if body:
                    chunks.append((current_title, body))
            current_title = line.lstrip("#").strip()
            buffer = []
        else:
            buffer.append(line)
    if current_title is not None and buffer:
        body = "\n".join(buffer).strip()
        if body:
            chunks.append((current_title, body))
    return chunks


def fetch_embedding(text: str, api_key: str, base_url: str, model: str):
    url = f"{base_url.rstrip('/')}/embeddings"
    payload = {"model": model, "input": text}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
        parsed = json.loads(body)
        emb = parsed["data"][0]["embedding"]
        return [float(x) for x in emb]


def ensure_table(conn: sqlite3.Connection, drop_existing: bool):
    cur = conn.cursor()
    if drop_existing:
        cur.execute("DROP TABLE IF EXISTS kb_chunks")
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS kb_chunks (
            id INTEGER PRIMARY KEY,
            document_id TEXT NOT NULL,
            section TEXT,
            chunk_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            embedding BLOB NOT NULL
        );
        """
    )
    conn.commit()


def embedding_to_blob(embedding):
    return struct.pack(f"<{len(embedding)}f", *embedding)


def main():
    args = parse_args()
    if not args.api_key:
        print("Errore: API key mancante (usa --api-key o env OPENAI_API_KEY)", file=sys.stderr)
        sys.exit(1)

    files = list(iter_files(args.inputs))
    if not files:
        print("Nessun file .txt/.md trovato.", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(args.output)
    ensure_table(conn, args.drop_existing)
    cur = conn.cursor()

    chunk_id = 1
    total_chunks = 0
    start_time = time.time()

    for file_path in files:
        doc_id = os.path.splitext(os.path.basename(file_path))[0]
        text = read_text(file_path)
        heading_parts = chunk_by_headings(text)
        if heading_parts:
            parts = [body for _, body in heading_parts]
            sections = [title for title, _ in heading_parts]
            print(f"[+] {file_path} -> {len(parts)} chunk (headings)")
        else:
            parts = chunk_text(text, args.chunk_size, args.chunk_overlap)
            sections = [None] * len(parts)
            print(f"[+] {file_path} -> {len(parts)} chunk (auto)")

        for idx, (chunk, section) in enumerate(zip(parts, sections)):
            emb = fetch_embedding(chunk, args.api_key, args.base_url, args.model)
            blob = embedding_to_blob(emb)
            cur.execute(
                "INSERT INTO kb_chunks (id, document_id, section, chunk_index, text, embedding) VALUES (?, ?, ?, ?, ?, ?)",
                (chunk_id, doc_id, section, idx, chunk, blob),
            )
            chunk_id += 1
            total_chunks += 1

        conn.commit()

    elapsed = time.time() - start_time
    print(f"Completato. Chunk inseriti: {total_chunks}. Output: {args.output}. Tempo: {elapsed:.1f}s")


if __name__ == "__main__":
    main()

