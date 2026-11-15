"""Durable storage on a free host.

The free plan has no persistent disk: the filesystem is wiped on every restart,
and `main.py` opens ONE sqlite connection at import time and holds it forever.
So we put a real database file and the user files on disk locally (instant, no
rewrite of the app) and make them survive:

* On import, restore the last snapshot from Redis BEFORE `main.py` opens it.
* A background thread fingerprints the data directory (path, size, mtime). When
  anything changes it pushes a fresh snapshot, and it keeps re-pushing while the
  data keeps changing, so a burst of writes can never be lost to a restart.
  Fingerprinting rather than per-route hooks means DB commits, JSON files and
  uploaded images are all covered, now and in future code.
* `backup_once()` on shutdown for a clean stop.

Storage comes from VORTEX_REDIS_URL (an Upstash `rediss://` URL) or the REST
pair VORTEX_REDIS_REST_URL / VORTEX_REDIS_REST_TOKEN. Without it the server
still runs, just on the ephemeral disk.
"""
from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import tarfile
import threading
import time
import urllib.request
from pathlib import Path

CHECK_SECONDS = float(os.environ.get("VORTEX_SNAPSHOT_SECONDS", "4"))
SNAPSHOT_KEY = os.environ.get("VORTEX_SNAPSHOT_KEY", "vortex:snapshot:v1")
_REST_URL_ENV = "VORTEX_REDIS_REST_URL"
_REST_TOKEN_ENV = "VORTEX_REDIS_REST_TOKEN"


def _rest_endpoint() -> tuple[str, str] | None:
    """Accept either an Upstash REST pair or a `rediss://` URL."""
    url = os.environ.get(_REST_URL_ENV)
    token = os.environ.get(_REST_TOKEN_ENV)
    if url and token:
        return url.rstrip("/"), token
    redis_url = os.environ.get("VORTEX_REDIS_URL", "")
    if not redis_url:
        return None
    try:
        rest = redis_url.split("://", 1)[1]
        creds, host = rest.rsplit("@", 1)
        password = creds.split(":", 1)[1]
        host = host.split(":", 1)[0]
        return f"https://{host}", password
    except (IndexError, ValueError):
        return None


def _command(*parts: str) -> object:
    endpoint = _rest_endpoint()
    if endpoint is None:
        return None
    url, token = endpoint
    request = urllib.request.Request(
        url,
        data=json.dumps(list(parts)).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        payload = json.loads(response.read() or b"{}")
    if isinstance(payload, dict) and payload.get("error"):
        raise RuntimeError(payload["error"])
    return payload.get("result")


def _archive(data_dir: Path) -> bytes:
    """Every user file plus the database and its WAL, as one tar."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tar:
        for path in sorted(data_dir.rglob("*")):
            if path.is_file():
                tar.add(path, arcname=str(path.relative_to(data_dir)))
    return buffer.getvalue()


def _unarchive(data_dir: Path, blob: bytes) -> int:
    data_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r") as tar:
        tar.extractall(data_dir)
    return sum(1 for p in data_dir.rglob("*") if p.is_file())


class Store:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.enabled = _rest_endpoint() is not None
        self._stop = threading.Event()
        self._saves = 0
        self._last_print = 0.0
        self._fingerprint = ""
        self._thread: threading.Thread | None = None
        self.last_error: str | None = None
        self.last_saved: float | None = None
        self._pending = False

    def fingerprint(self) -> str:
        digest = hashlib.sha256()
        for path in sorted(self.data_dir.rglob("*")):
            if not path.is_file():
                continue
            try:
                stat = path.stat()
            except OSError:
                continue
            digest.update(f"{path.relative_to(self.data_dir)}|{stat.st_size}|{stat.st_mtime_ns}\n".encode())
        return digest.hexdigest()

    def restore(self) -> str:
        if not self.enabled:
            return "storage: off (ephemeral disk)"
        try:
            result = _command("GET", SNAPSHOT_KEY)
        except Exception as exc:  # a bad restore must not stop the server booting
            self.last_error = str(exc)
            return f"restore failed: {exc}"
        if not result:
            return "restore: no snapshot yet (fresh start)"
        try:
            count = _unarchive(self.data_dir, base64.b64decode(result))
            self._fingerprint = self.fingerprint()
            return f"restore: {count} files from snapshot"
        except Exception as exc:
            self.last_error = str(exc)
            return f"restore failed: {exc}"

    def touch(self) -> None:
        """"Kept for call sites; the poll loop compares fingerprints so this
        only nudges it to run on the next tick."""
        self._pending = True

    def backup_once(self) -> None:
        if not self.enabled:
            return
        try:
            current = self.fingerprint()
            if current == self._fingerprint:
                return
            blob = _archive(self.data_dir)
            # 30 day TTL: a long dead project still keeps its snowflake.
            _command("SET", SNAPSHOT_KEY, base64.b64encode(blob).decode(), "EX", "2592000")
            self._fingerprint = current
            self._saves += 1
            self.last_saved = time.time()
            self.last_error = None
        except Exception as exc:
            self.last_error = str(exc)
            print(f"[storage] save failed: {exc}", flush=True)

    def _loop(self) -> None:
        while not self._stop.wait(CHECK_SECONDS):
            self._pending = False
            self.backup_once()

    def start(self) -> None:
        if not self.enabled:
            return
        self._fingerprint = self.fingerprint()
        self._thread = threading.Thread(target=self._loop, name="snapshot", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self.backup_once()

    def status(self) -> dict:
        pending = self.enabled and self.fingerprint() != self._fingerprint
        return {
            "durable": self.enabled,
            "saves": self._saves,
            "last_saved": round(self.last_saved or 0, 1) or None,
            "pending": pending,
            "error": self.last_error,
        }
