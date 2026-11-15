"""Upload the local account data once, so the hosted server starts with it.

Run with VORTEX_REDIS_URL set (and optionally a data dir as argv[1]).
Prints what it packed so a wrong path is obvious.
"""
from __future__ import annotations

import sys
from pathlib import Path

import durable

data_dir = Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\VortexServerData")
if not data_dir.is_dir():
    raise SystemExit(f"no such data dir: {data_dir}")
if not (data_dir / "vortex.db").is_file():
    raise SystemExit(f"{data_dir} has no vortex.db, wrong folder?")

store = durable.Store(data_dir)
if not store.enabled:
    raise SystemExit("VORTEX_REDIS_URL is not set (or unreadable)")

files = [p for p in data_dir.rglob("*") if p.is_file()]
print(f"packing {len(files)} files from {data_dir}")
size = sum(p.stat().st_size for p in files)
print(f"total {size / 1024:.0f} KB -> {durable.SNAPSHOT_KEY}")
store.backup_once()
if store.last_error:
    raise SystemExit(f"upload failed: {store.last_error}")
print("done: snapshot uploaded")
