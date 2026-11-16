import asyncio
import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import socket
import sqlite3
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import yt_dlp
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from ytmusicapi import YTMusic

BASE_DIR = Path(__file__).resolve().parent
WEB_DIR = BASE_DIR / "app" / "build" / "web"
FROZEN = getattr(sys, "frozen", False)
DATA_DIR = Path(os.environ.get("VORTEX_DATA") or Path(os.environ.get("LOCALAPPDATA", BASE_DIR)) / "Vortex")
DB_FILE = DATA_DIR / "vortex.db"
USERS_DIR = DATA_DIR / "users"
INVITE_FILE = DATA_DIR / "invite_code"
INVITE_CODE = os.environ.get("VORTEX_INVITE") or (INVITE_FILE.read_text().strip() if INVITE_FILE.exists() else "")
DOWNLOAD_DIR = Path(sys.executable).resolve().parent.parent if FROZEN else BASE_DIR / "dist"
DOWNLOADS = {
    "Vortex.apk": "application/vnd.android.package-archive",
    "Vortex-Phone.apk": "application/vnd.android.package-archive",
    "Vortex-Windows.zip": "application/zip",
    "VortexAnime.apk": "application/vnd.android.package-archive",
    "VortexAnime-Windows.zip": "application/zip",
    "VortexAnimeApp.apk": "application/vnd.android.package-archive",
    "VortexAnimeApp-Windows.zip": "application/zip",
    "VortexLauncher-Windows.zip": "application/zip",
    "VortexAI-Setup.exe": "application/vnd.microsoft.portable-executable",
    "VortexAI.apk": "application/vnd.android.package-archive",
}
MAX_PLAYLISTS = 200
MAX_PLAYLIST_TRACKS = 2000
PLAYLIST_ID = re.compile(r"^[a-f0-9]{16}$")
LEGACY_FILES = ("profile.json", "history.json", "liked.json", "recommendations.json", "images")
BROWSE_ID = re.compile(r"^[\w-]{5,80}$")
BROWSE_TTL = 3600
ARTIST_SONG_LIMIT = 200
IMAGE_KINDS = ("avatar", "banner", "wallpaper")
PUBLIC_IMAGES = ("avatar", "banner")
MAX_IMAGE_BYTES = 10 * 1024 * 1024
IMAGE_SIGNATURES = (
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"RIFF", "image/webp"),
    (b"GIF8", "image/gif"),
)
DEFAULT_PROFILE = {"theme": "auto", "images": {}, "pronouns": "", "bio": "", "quote": "", "status": "online"}
PROFILE_STATUSES = ("online", "dnd", "sleep", "invisible")
MAX_PRONOUNS = 30
MAX_BIO = 300
MAX_QUOTE = 120
MAX_UTC_OFFSET_MINUTES = 14 * 60
ALBUM_TRACK_TYPE = "MUSIC_VIDEO_TYPE_ATV"
MAX_RADIO_SWAPS = 6
MAX_SONG_VERSIONS = 2000
ANIME_DIR = BASE_DIR / "anime_app" / "build" / "web"
ANIME_STATUSES = ("watching", "completed", "planning", "paused", "dropped")
MAX_ANIME_ENTRIES = 5000
VIDEO_STILL_HOST = "ytimg.com"
ARTIST_PHOTOS_FILE = DATA_DIR / "artist_photos.json"
ARTIST_PHOTO_SIZE = "=w544-h544-p-l90-rj"
ARTIST_PHOTO_LOOKUPS = 5
ARTIST_PHOTO_RETRY_SECONDS = 6 * 3600
MAX_HISTORY = 1000
HISTORY_HALF_LIFE = 14 * 24 * 3600
RECENT_EXCLUDE = 30
MAX_SEEDS = 3
RADIO_SIZE = 25
SHELF_SIZE = 16
MIX_LEAD = 10
MIN_SHELF = 4
MAX_TOP_ARTISTS = 10
RECOMMENDATION_TTL = 1800
RECOMMENDATION_PLAYS = 3
PORT = int(os.environ.get("PORT", 8000))
EMAIL_PATTERN = re.compile(r"^[^@\s]{1,64}@[^@\s]+\.[^@\s]{2,}$")
USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_.]{2,30}$")
SESSION_DAYS = 90
LOGIN_WINDOW = 900
LOGIN_ATTEMPTS = 10
HELPER_SECRET = os.environ.get("VORTEX_HELPER_SECRET", "")
HELPER_DOWNLOAD_TOKEN = os.environ.get("VORTEX_HELPER_DOWNLOAD", "")
HELPER_ZIP = DATA_DIR / "helper" / "VortexHelper.zip"
HELPER_ADDRESS_FILE = DATA_DIR / "helper" / "address.json"
HELPER_PROBE_SECONDS = 8
HELPER_URL = re.compile(r"^https://[a-z0-9-]+\.trycloudflare\.com$")
WHOLE_FILE_RANGE = "bytes=0-"
MIN_PASSWORD = 8
MAX_PASSWORD = 200
ONLINE_SECONDS = 60
MAX_MESSAGE_FETCH = 200
MAX_SIGNIN_TRACK = 60

LOOPBACK_HOSTS = {"127.0.0.1", "::1"}
PROXY_HEADERS = ("cf-connecting-ip", "cf-ray", "x-forwarded-for", "forwarded")
VIDEO_ID = re.compile(r"^[\w-]{6,20}$")
ART_HOSTS = ("googleusercontent.com", "ggpht.com", "ytimg.com")
URL_SAFETY_MARGIN = 300
URL_FALLBACK_TTL = 3600
MAX_CACHED_URLS = 200
LYRICS_API = "https://lrclib.net/api"
LYRICS_USER_AGENT = "Vortex/1.0"


class _SilentLogger:
    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        pass


# YouTube refuses a plain datacenter IP with "sign in to confirm you're not a
# bot". A browser cookie export in VORTEX_YT_COOKIES (path or raw contents)
# gives yt-dlp a signed-in session that passes the check.
def _cookie_file() -> str | None:
    """Finds a cookie file from the shipped copy, base64 env, or a path.

    YouTube refuses a datacenter IP with "sign in to confirm you are not a
    bot". Every candidate is validated, so a truncated env var falls through
    to the shipped file instead of failing the whole lookup.
    """
    candidates: list[str] = []
    encoded = os.environ.get("VORTEX_YT_COOKIES_B64", "").strip()
    if encoded:
        try:
            candidates.append(base64.b64decode(encoded).decode("utf-8", "ignore"))
        except Exception:
            pass
    raw = os.environ.get("VORTEX_YT_COOKIES", "").strip()
    if raw:
        candidates.append(raw)
    shipped = DOWNLOAD_DIR / "yt-cookies.txt"
    if shipped.is_file():
        candidates.append(shipped.read_text(encoding="utf-8", errors="ignore"))

    for text in candidates:
        if not text:
            continue
        if "Netscape" in text or "\t" in text:
            path = DATA_DIR / "yt-cookies.txt"
            if not path.exists() or path.read_text(encoding="utf-8", errors="ignore") != text:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            return str(path)
        if Path(text).is_file():
            return text
    return None

YDL_BASE = {
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "logger": _SilentLogger(),
    "extractor_args": {"youtube": {"player_client": ["tv_embedded", "android", "android_vr"]}},
}
# The cookie file is kept for diagnostics only: passing it makes YouTube answer
# with storyboards only, while anonymous requests still return real audio.
if False and (cookie := _cookie_file()):
    YDL_BASE["cookiefile"] = cookie

app = FastAPI(title="Vortex Backend")
client = httpx.AsyncClient(timeout=httpx.Timeout(20, read=None), follow_redirects=True)
_ytmusic: YTMusic | None = None

_url_cache: dict[str, tuple[str, dict, str, float]] = {}
_in_flight: dict[str, asyncio.Task] = {}
_lyrics_cache: dict[tuple[str, str], dict] = {}
_browse_cache: dict[str, tuple[float, object]] = {}
_helper = {"url": ""}
_song_versions: dict[str, str | None] = {}
_audio_choice: dict[str, str] = {}
_artist_photos: dict[str, str] = {}
_artist_photo_misses: dict[str, float] = {}


def _is_local(request: Request) -> bool:
    if any(header in request.headers for header in PROXY_HEADERS):
        return False
    return request.client is not None and request.client.host in LOOPBACK_HOSTS


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("cf-connecting-ip") or request.headers.get("x-forwarded-for", "").split(",")[0].strip()
    return forwarded or (request.client.host if request.client else "unknown")


DATA_DIR.mkdir(parents=True, exist_ok=True)

# The free host has no persistent disk, so the last snapshot is restored before
# the connection opens and every write is pushed back to durable storage.
import durable  # noqa: E402

_store = durable.Store(DATA_DIR)
RESTORE_STATUS = _store.restore()
print(f"[storage] {RESTORE_STATUS}", flush=True)
print(f"[yt-dlp] {yt_dlp.version.__version__} cookies={bool(_cookie_file())}", flush=True)

_db = sqlite3.connect(DB_FILE, check_same_thread=False)
_db.row_factory = sqlite3.Row
_store.start()
_db.executescript(
    """
    PRAGMA journal_mode=WAL;
    PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_salt BLOB NOT NULL,
        password_hash BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        listening_seconds INTEGER NOT NULL DEFAULT 0,
        now_playing TEXT,
        is_playing INTEGER NOT NULL DEFAULT 0,
        last_seen INTEGER NOT NULL DEFAULT 0,
        plays_override INTEGER NOT NULL DEFAULT 0,
        best_streak INTEGER NOT NULL DEFAULT 0,
        crown INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS friendships (
        low_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        high_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        requested_by INTEGER NOT NULL,
        accepted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (low_id, high_id)
    );
    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY,
        sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        recipient_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        body TEXT NOT NULL,
        track TEXT,
        sent_at INTEGER NOT NULL,
        read_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS messages_pair ON messages(sender_id, recipient_id, id);
    """
)
# Older databases predate the vanity columns; add them in place.
for _col, _decl in (("plays_override", "INTEGER NOT NULL DEFAULT 0"), ("best_streak", "INTEGER NOT NULL DEFAULT 0"), ("crown", "INTEGER NOT NULL DEFAULT 0")):
    try:
        _db.execute(f"ALTER TABLE users ADD COLUMN {_col} {_decl}")
    except sqlite3.OperationalError:
        pass
_db.commit()
_login_failures: dict[str, list[float]] = {}


def _hash_password(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _new_session(user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    _db.execute("INSERT INTO sessions VALUES (?, ?, ?)", (_token_hash(token), user_id, int(time.time()) + SESSION_DAYS * 86400))
    _db.commit()
    _store.touch()
    return token


async def require_key(key: str = Query("")) -> sqlite3.Row:
    row = _db.execute(
        "SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id WHERE token_hash = ? AND expires_at > ?",
        (_token_hash(key), int(time.time())),
    ).fetchone()
    if row is None:
        raise HTTPException(401, "Please sign in")
    return row

def _lan_ip() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def _yt() -> YTMusic:
    global _ytmusic
    if _ytmusic is None:
        _ytmusic = YTMusic()
    return _ytmusic


def _search(q: str, limit: int):
    results = _yt().search(q, filter="songs", limit=limit)
    tracks = []
    for r in results:
        if not r.get("videoId"):
            continue
        if r.get("videoType") == ALBUM_TRACK_TYPE:
            _audio_choice[r["videoId"]] = r["videoId"]
        thumbs = r.get("thumbnails") or []
        thumb = thumbs[-1]["url"] if thumbs else f"https://i.ytimg.com/vi/{r['videoId']}/hqdefault.jpg"
        tracks.append(
            {
                "id": r["videoId"],
                "title": r.get("title"),
                "artist": ", ".join(a["name"] for a in r.get("artists") or [] if a.get("name")),
                "artist_id": next((a.get("id") for a in r.get("artists") or [] if a.get("id")), None),
                "album": (r.get("album") or {}).get("name"),
                "duration": r.get("duration_seconds"),
                "thumbnail": thumb,
            }
        )
    return tracks[:limit]


def _audio_info(video_id: str):
    """Resolve a playable audio URL.

    Cookies get past YouTube's datacenter bot check but suppress the audio
    formats, so both contexts are tried and whichever yields a stream wins.
    """
    base = {**YDL_BASE, "format": "bestaudio[ext=m4a]/bestaudio/best[acodec!=none]/best/18"}
    attempts = []
    if base.get("cookiefile"):
        attempts.append({k: v for k, v in base.items() if k != "cookiefile"})
        attempts.append(base)
    else:
        attempts.append(base)

    last: Exception | None = None
    for opts in attempts:
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            url = info.get("url")
            if not url:
                continue
            expire = parse_qs(urlparse(url).query).get("expire", [None])[0]
            expires_at = int(expire) - URL_SAFETY_MARGIN if expire else time.time() + URL_FALLBACK_TTL
            return url, info.get("http_headers", {}), info.get("ext", "m4a"), expires_at
        except Exception as exc:
            last = exc
    raise last if last else RuntimeError("no stream")

async def _resolve(video_id: str, fresh: bool = False):
    cached = _url_cache.get(video_id)
    if cached and not fresh and cached[3] > time.time():
        return cached

    task = _in_flight.get(video_id)
    if task is None:
        task = asyncio.create_task(asyncio.to_thread(_audio_info, video_id))
        _in_flight[video_id] = task
        task.add_done_callback(lambda _: _in_flight.pop(video_id, None))

    entry = await asyncio.shield(task)
    _url_cache[video_id] = entry
    if len(_url_cache) > MAX_CACHED_URLS:
        _url_cache.pop(min(_url_cache, key=lambda k: _url_cache[k][3]))
    return entry


def _check_id(video_id: str):
    if not VIDEO_ID.match(video_id):
        raise HTTPException(400, "Invalid track id")


async def _open_upstream(video_id: str, range_header: str | None, fresh: bool = False):
    url, headers, ext, _ = await _resolve(video_id, fresh)
    upstream_headers = dict(headers)
    if range_header:
        upstream_headers["Range"] = range_header
    upstream = await client.send(client.build_request("GET", url, headers=upstream_headers), stream=True)
    return upstream, ext


@app.get("/health")
async def health():
    return {"status": "ok", "app": "vortex", "yt_dlp": yt_dlp.version.__version__, "audio_helper": await _helper_answers(), "cookies": bool(_cookie_file()), "cookie_path": str(DOWNLOAD_DIR / "yt-cookies.txt"), "cookie_shipped": (DOWNLOAD_DIR / "yt-cookies.txt").is_file()}


@app.get("/pairing")
async def pairing(request: Request):
    if not _is_local(request):
        raise HTTPException(403, "Only available on this PC")
    return {"url": f"http://{_lan_ip()}:{PORT}"}


DOWNLOAD_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Get Vortex</title><style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;color:#fff;
font-family:"Segoe UI",Roboto,system-ui,sans-serif;background:#0c0c10;
background-image:radial-gradient(60% 50% at 15% 5%,#2f8f63,transparent),radial-gradient(50% 45% at 90% 15%,#6a3fa0,transparent),radial-gradient(50% 45% at 85% 95%,#2f6f8f,transparent)}
main{width:100%;max-width:440px;padding:32px;border-radius:28px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.15);backdrop-filter:blur(26px)}
h1{margin:0;font-size:52px;font-weight:900;font-style:italic;letter-spacing:-1px;background:linear-gradient(90deg,#fff 40%,#5cf08f);-webkit-background-clip:text;background-clip:text;color:transparent}
p{color:#c9c9d2;line-height:1.45}a.b{display:block;margin-top:12px;padding:16px 20px;border-radius:18px;background:rgba(255,255,255,.1);color:#fff;text-decoration:none;font-weight:800}
a.b small{display:block;margin-top:2px;font-weight:500;opacity:.75}a.b.main{background:#5cf08f;color:#000}.none{margin-top:12px;color:#ff9c9c}
</style></head><body><main><h1>VORTEX</h1><p>Your private music player. Pick your device.</p>__LINKS__
<p style="font-size:13px;margin-top:20px">Sign in with your Vortex account after you install.</p></main>
<script>if(/android/i.test(navigator.userAgent)){var a=document.querySelector('a[href$=".apk"]');if(a)a.classList.add('main')}else{var w=document.querySelector('a[href$=".zip"]');if(w)w.classList.add('main')}</script>
</body></html>"""


def _download_link(name: str, label: str) -> str:
    path = DOWNLOAD_DIR / name
    if not path.is_file():
        return ""
    size = path.stat().st_size / (1024 * 1024)
    return f'<a class="b" href="/download/{name}">{label}<small>{name}, {size:.0f} MB</small></a>'


@app.get("/download", response_class=HTMLResponse)
async def download_page():
    links = _download_link("Vortex.apk", "Android phone") + _download_link("Vortex-Windows.zip", "Windows PC")
    return DOWNLOAD_PAGE.replace("__LINKS__", links or '<p class="none">No downloads are ready on this PC.</p>')


@app.get("/download/{name}")
async def download_file(name: str):
    path = DOWNLOAD_DIR / name
    if name not in DOWNLOADS or not path.is_file():
        raise HTTPException(404, "Not available")
    return FileResponse(path, media_type=DOWNLOADS[name], filename=name)


def _read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _write_json(path: Path, value):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value), encoding="utf-8")
    temp.replace(path)


def _local_day(timestamp: float, offset_minutes: int) -> date:
    return datetime.fromtimestamp(timestamp + offset_minutes * 60, timezone.utc).date()


def _seed_streak(history: list[dict], offset_minutes: int) -> dict | None:
    days = {_local_day(play["at"], offset_minutes) for play in history if play.get("at")}
    if not days:
        return None
    latest = day = max(days)
    count = 0
    best = 0
    run = 0
    previous = None
    for played in sorted(days):
        run = run + 1 if previous == played - timedelta(days=1) else 1
        best = max(best, run)
        previous = played
    while day in days:
        count += 1
        day -= timedelta(days=1)
    return {"count": count, "best": best, "last": latest.isoformat(), "offset": offset_minutes}


def _advance_streak(streak: dict | None, today: date, offset_minutes: int) -> dict:
    count = streak["count"] if streak else 0
    best = streak["best"] if streak else 0
    last = date.fromisoformat(streak["last"]) if streak else None
    if last != today and (last is None or last < today):
        count = count + 1 if last == today - timedelta(days=1) else 1
        last = today
    return {"count": count, "best": max(best, count), "last": last.isoformat(), "offset": offset_minutes}


def _streak_fields(profile: dict, now: float | None = None) -> dict:
    streak = profile.get("streak")
    if not streak:
        return {"streak": 0, "best_streak": 0}
    today = _local_day(time.time() if now is None else now, streak.get("offset", 0))
    alive = (today - date.fromisoformat(streak["last"])).days <= 1
    return {"streak": streak["count"] if alive else 0, "best_streak": streak["best"]}


class UserData:
    def __init__(self, user_id: int):
        self.dir = USERS_DIR / str(user_id)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.profile = {**DEFAULT_PROFILE, **_read_json(self.dir / "profile.json", {})}
        self.history: list[dict] = _read_json(self.dir / "history.json", [])
        self.recommendations = {"at": 0.0, "plays": -1, "value": None}

    @property
    def images(self) -> Path:
        return self.dir / "images"

    def save_profile(self):
        _write_json(self.dir / "profile.json", self.profile)

    def public(self, user: sqlite3.Row) -> dict:
        return {
            **self.profile,
            **_streak_fields(self.profile),
            "id": user["id"],
            "username": user["username"],
            "email": user["email"],
            "plays": max(len(self.history), user["plays_override"]),
            "listening_seconds": user["listening_seconds"],
            "crown": bool(user["crown"]),
            "best_streak": max(_streak_fields(self.profile)["best_streak"], user["best_streak"]),
        }


_user_data: dict[int, UserData] = {}


def _data_for(user_id: int) -> UserData:
    data = _user_data.get(user_id)
    if data is None:
        data = _user_data[user_id] = UserData(user_id)
    return data

def _image_type(data: bytes) -> str | None:
    for signature, media_type in IMAGE_SIGNATURES:
        if data.startswith(signature):
            if media_type == "image/webp" and data[8:12] != b"WEBP":
                continue
            return media_type
    return None


class ProfileUpdate(BaseModel):
    username: str | None = Field(None, max_length=30)
    theme: str | None = Field(None, max_length=20)
    pronouns: str | None = Field(None, max_length=MAX_PRONOUNS)
    bio: str | None = Field(None, max_length=MAX_BIO)
    quote: str | None = Field(None, max_length=MAX_QUOTE)
    status: str | None = None


class Play(BaseModel):
    id: str
    title: str | None = None
    artist: str | None = None
    album: str | None = None
    duration: int | None = None
    thumbnail: str | None = None
    artist_id: str | None = None


class Credentials(BaseModel):
    email: str
    password: str
    username: str | None = None
    invite: str | None = None


class PasswordChange(BaseModel):
    current: str
    new: str


class Presence(BaseModel):
    track: Play | None = None
    playing: bool = False
    seconds: int = Field(0, ge=0, le=3600)


class MessageIn(BaseModel):
    body: str = Field("", max_length=2000)
    track: Play | None = None
    gift: bool = False


def _claim_legacy_data(user_id: int):
    target = USERS_DIR / str(user_id)
    target.mkdir(parents=True, exist_ok=True)
    for name in LEGACY_FILES:
        source = DATA_DIR / name
        if source.exists():
            shutil.move(str(source), str(target / name))


@app.post("/auth/register")
async def register(body: Credentials, request: Request):
    email = body.email.strip()
    username = (body.username or "").strip()
    if INVITE_CODE and not secrets.compare_digest(body.invite or "", INVITE_CODE):
        raise HTTPException(403, "That invite code isn't right.")
    if not EMAIL_PATTERN.match(email):
        raise HTTPException(400, "Enter a valid email address.")
    if not USERNAME_PATTERN.match(username):
        raise HTTPException(400, "Usernames are 2 to 30 letters, numbers, dots or underscores.")
    if len(body.password) < MIN_PASSWORD:
        raise HTTPException(400, f"Your password needs at least {MIN_PASSWORD} characters.")
    if len(body.password) > MAX_PASSWORD:
        raise HTTPException(400, f"Your password can't be longer than {MAX_PASSWORD} characters.")
    salt = secrets.token_bytes(16)
    first_user = _db.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0
    try:
        cursor = _db.execute(
            "INSERT INTO users (email, username, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)",
            (email, username, salt, _hash_password(body.password, salt), int(time.time())),
        )
    except sqlite3.IntegrityError:
        raise HTTPException(409, "That email or username is already taken.")
    _db.commit()
    _store.touch()
    if first_user:
        _claim_legacy_data(cursor.lastrowid)
    return {"token": _new_session(cursor.lastrowid)}


@app.post("/auth/login")
async def login(body: Credentials, request: Request):
    email = body.email.strip().lower()
    attempt_key = f"{_client_ip(request)}|{email}"
    now = time.time()
    recent = [t for t in _login_failures.get(attempt_key, []) if now - t < LOGIN_WINDOW]
    if len(recent) >= LOGIN_ATTEMPTS:
        raise HTTPException(429, "Too many tries. Wait a few minutes.")
    if len(body.password) > MAX_PASSWORD:
        raise HTTPException(401, "Wrong email or password.")
    row = _db.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    salt = row["password_salt"] if row else b"\0" * 16
    expected = row["password_hash"] if row else b"\0" * 32
    if not secrets.compare_digest(_hash_password(body.password, salt), expected) or row is None:
        _login_failures[attempt_key] = recent + [now]
        raise HTTPException(401, "Wrong email or password.")
    _login_failures.pop(attempt_key, None)
    return {"token": _new_session(row["id"])}


@app.post("/auth/logout")
async def logout(key: str = Query("")):
    _db.execute("DELETE FROM sessions WHERE token_hash = ?", (_token_hash(key),))
    _db.commit()
    _store.touch()
    return {"status": "signed out"}


@app.post("/auth/password")
async def change_password(body: PasswordChange, key: str = Query(""), user: sqlite3.Row = Depends(require_key)):
    if len(body.current) > MAX_PASSWORD or not secrets.compare_digest(_hash_password(body.current, user["password_salt"]), user["password_hash"]):
        raise HTTPException(401, "Your current password isn't right.")
    if not MIN_PASSWORD <= len(body.new) <= MAX_PASSWORD:
        raise HTTPException(400, f"Your new password needs {MIN_PASSWORD} to {MAX_PASSWORD} characters.")
    salt = secrets.token_bytes(16)
    _db.execute("UPDATE users SET password_salt = ?, password_hash = ? WHERE id = ?", (salt, _hash_password(body.new, salt), user["id"]))
    _db.execute("DELETE FROM sessions WHERE user_id = ? AND token_hash != ?", (user["id"], _token_hash(key)))
    _db.commit()
    _store.touch()
    return {"status": "changed"}


@app.delete("/account")
async def delete_account(user: sqlite3.Row = Depends(require_key)):
    _db.execute("DELETE FROM users WHERE id = ?", (user["id"],))
    _db.commit()
    _store.touch()
    _user_data.pop(user["id"], None)
    shutil.rmtree(USERS_DIR / str(user["id"]), ignore_errors=True)
    return {"status": "deleted"}


@app.get("/profile")
async def get_profile(user: sqlite3.Row = Depends(require_key)):
    return _data_for(user["id"]).public(user)


@app.post("/profile")
async def update_profile(update: ProfileUpdate, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    if update.username is not None:
        username = update.username.strip()
        if not USERNAME_PATTERN.match(username):
            raise HTTPException(400, "Usernames are 2 to 30 letters, numbers, dots or underscores.")
        try:
            _db.execute("UPDATE users SET username = ? WHERE id = ?", (username, user["id"]))
            _db.commit()
            _store.touch()
        except sqlite3.IntegrityError:
            raise HTTPException(409, "That username is already taken.")
        user = _db.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()
    if update.theme is not None:
        data.profile["theme"] = update.theme
    if update.status is not None:
        if update.status not in PROFILE_STATUSES:
            raise HTTPException(400, "Pick a status from the list.")
        data.profile["status"] = update.status
    if update.pronouns is not None:
        data.profile["pronouns"] = " ".join(update.pronouns.split())
    if update.quote is not None:
        data.profile["quote"] = " ".join(update.quote.split())
    if update.bio is not None:
        data.profile["bio"] = update.bio.strip()
    data.save_profile()
    return data.public(user)


def _check_image_kind(kind: str):
    if kind not in IMAGE_KINDS:
        raise HTTPException(404, "Unknown image")


def _serve_image(path: Path) -> Response:
    if not path.is_file():
        raise HTTPException(404, "No image")
    data = path.read_bytes()
    return Response(data, media_type=_image_type(data) or "application/octet-stream", headers={"Cache-Control": "private, max-age=31536000"})


@app.put("/profile/image/{kind}")
async def upload_image(kind: str, request: Request, user: sqlite3.Row = Depends(require_key)):
    _check_image_kind(kind)
    data = await request.body()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Image is larger than 10 MB")
    if _image_type(data) is None:
        raise HTTPException(415, "Use a PNG, JPEG, WebP or GIF image")
    store = _data_for(user["id"])
    store.images.mkdir(parents=True, exist_ok=True)
    (store.images / kind).write_bytes(data)
    store.profile["images"] = {**store.profile["images"], kind: int(time.time())}
    store.save_profile()
    return store.public(user)


@app.delete("/profile/image/{kind}")
async def delete_image(kind: str, user: sqlite3.Row = Depends(require_key)):
    _check_image_kind(kind)
    store = _data_for(user["id"])
    (store.images / kind).unlink(missing_ok=True)
    store.profile["images"] = {k: v for k, v in store.profile["images"].items() if k != kind}
    store.save_profile()
    return store.public(user)


@app.get("/profile/image/{kind}")
async def get_image(kind: str, user: sqlite3.Row = Depends(require_key)):
    _check_image_kind(kind)
    return _serve_image(_data_for(user["id"]).images / kind)


@app.post("/history")
async def log_play(play: Play, tz: int | None = Query(None, ge=-MAX_UTC_OFFSET_MINUTES, le=MAX_UTC_OFFSET_MINUTES), user: sqlite3.Row = Depends(require_key)):
    _check_id(play.id)
    data = _data_for(user["id"])
    now = time.time()
    saved = data.profile.get("streak") or _seed_streak(data.history, tz or 0)
    offset = tz if tz is not None else (saved or {}).get("offset", 0)
    data.history.append({**play.model_dump(), "at": int(now)})
    del data.history[:-MAX_HISTORY]
    _write_json(data.dir / "history.json", data.history)
    data.profile["streak"] = _advance_streak(saved, _local_day(now, offset), offset)
    data.save_profile()
    return {"plays": len(data.history), **_streak_fields(data.profile, now)}


@app.delete("/history")
async def clear_history(user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    data.history.clear()
    _write_json(data.dir / "history.json", data.history)
    data.recommendations["value"] = None
    (data.dir / "recommendations.json").unlink(missing_ok=True)
    return {"plays": 0}


def _pair(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _friend_state(me: int, other: int) -> str:
    if me == other:
        return "self"
    row = _db.execute("SELECT * FROM friendships WHERE low_id = ? AND high_id = ?", _pair(me, other)).fetchone()
    if row is None:
        return "none"
    if row["accepted"]:
        return "friends"
    return "outgoing" if row["requested_by"] == me else "incoming"


def _other_user(user_id: int) -> sqlite3.Row:
    row = _db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "That person doesn't exist")
    return row


def _artist_photo(name: str) -> str | None:
    """The artist's own picture, only when the name matches exactly."""
    if not _artist_photos:
        _artist_photos.update(_read_json(ARTIST_PHOTOS_FILE, {}))
    key = _normal_title(name)
    if key in _artist_photos:
        return _artist_photos[key]
    if time.time() - _artist_photo_misses.get(key, 0) < ARTIST_PHOTO_RETRY_SECONDS:
        return None
    photo = None
    try:
        for hit in _yt().search(name, filter="artists", limit=5):
            if _normal_title(hit.get("artist") or hit.get("title")) == key and hit.get("thumbnails"):
                photo = re.sub(r"=[swh]\d+.*$", ARTIST_PHOTO_SIZE, hit["thumbnails"][-1]["url"])
                break
    except Exception:
        pass
    if photo is None:
        _artist_photo_misses[key] = time.time()
        return None
    _artist_photos[key] = photo
    _write_json(ARTIST_PHOTOS_FILE, _artist_photos)
    return photo


def _with_artist_photos(artists: list[dict]) -> list[dict]:
    if not artists:
        return artists
    with ThreadPoolExecutor(ARTIST_PHOTO_LOOKUPS) as pool:
        photos = list(pool.map(lambda a: _artist_photo(a["name"]), artists))
    return [{**a, "thumbnail": photo or a["thumbnail"]} for a, photo in zip(artists, photos)]


def _remember_art(art: dict[str, str], artist: str, thumbnail: str | None):
    # Prefer a real cover. A video still is only used when there's nothing better.
    if thumbnail and (VIDEO_STILL_HOST not in thumbnail or VIDEO_STILL_HOST in art.get(artist, VIDEO_STILL_HOST)):
        art[artist] = thumbnail


def _top_artists(history: list[dict]) -> list[dict]:
    counts: Counter = Counter()
    art: dict[str, str] = {}
    for play in history:
        for artist in (play.get("artist") or "").split(", "):
            if artist:
                counts[artist] += 1
                _remember_art(art, artist, play.get("thumbnail"))
    return [{"name": name, "thumbnail": art.get(name, "")} for name, _ in counts.most_common(MAX_TOP_ARTISTS)]


def _person(me: int, row: sqlite3.Row, full: bool = False) -> dict:
    state = _friend_state(me, row["id"])
    data = _data_for(row["id"])
    person = {
        "id": row["id"],
        "username": row["username"],
        "images": {k: v for k, v in data.profile["images"].items() if k in PUBLIC_IMAGES},
        "friendship": state,
        "pronouns": data.profile["pronouns"],
        "bio": data.profile["bio"],
        "quote": data.profile["quote"],
    }
    if full:
        person["joined"] = row["created_at"]
    if state in ("friends", "self"):
        status = data.profile["status"]
        hidden = status == "invisible" and state == "friends"
        online = time.time() - row["last_seen"] < ONLINE_SECONDS and not hidden
        person |= {
            "online": online,
            "status": "online" if hidden else status,
            **_streak_fields(data.profile),
            "now_playing": json.loads(row["now_playing"]) if online and row["now_playing"] else None,
            "now_gaming": _game_for(row["id"]) if online else None,
            "is_playing": bool(row["is_playing"]) and online,
            "listening_seconds": row["listening_seconds"],
        }
        if full:
            person |= {"plays": len(data.history), "top_artists": _top_artists(data.history)}
    return person


@app.post("/presence")
async def presence(body: Presence, user: sqlite3.Row = Depends(require_key)):
    seconds = min(body.seconds, MAX_SIGNIN_TRACK) if body.playing else 0
    track = json.dumps(body.track.model_dump()) if body.track else None
    _db.execute(
        "UPDATE users SET last_seen = ?, now_playing = ?, is_playing = ?, listening_seconds = listening_seconds + ? WHERE id = ?",
        (int(time.time()), track, int(body.playing), seconds, user["id"]),
    )
    _db.commit()
    _store.touch()
    return {"status": "ok"}


# What each person is playing in VORTEX Launcher. Kept in memory: it only matters while they're online.
_gaming: dict[int, tuple[str, str | None, float]] = {}
GAME_FRESH_SECONDS = 120


class GamePresence(BaseModel):
    title: str | None = Field(default=None, max_length=120)
    appid: str | None = Field(default=None, max_length=12, pattern=r"^\d+$")


def _game_for(user_id: int) -> dict | None:
    hit = _gaming.get(user_id)
    if not hit or time.time() - hit[2] > GAME_FRESH_SECONDS:
        return None
    return {"title": hit[0], "appid": hit[1]}


@app.post("/presence/game")
async def presence_game(body: GamePresence, user: sqlite3.Row = Depends(require_key)):
    """Called by VORTEX Launcher every 30 seconds with the game that's running, or nothing."""
    if body.title:
        _gaming[user["id"]] = (body.title.strip(), body.appid, time.time())
    else:
        _gaming.pop(user["id"], None)
    _db.execute("UPDATE users SET last_seen = ? WHERE id = ?", (int(time.time()), user["id"]))
    _db.commit()
    _store.touch()
    return {"status": "ok"}


@app.get("/release/ai")
async def ai_release():
    """Update card for Vortex AI (desktop and phone). Open to any origin so the phone app can read it."""
    data = _read_json(DOWNLOAD_DIR / "ai_release.json", {"version": "0.0.0", "notes": []})
    return Response(content=json.dumps(data), media_type="application/json", headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"})


@app.get("/release/launcher")
async def launcher_release():
    return _read_json(DOWNLOAD_DIR / "launcher_release.json", {"version": "0.0.0", "notes": []})


@app.post("/presence/ping")
async def presence_ping(user: sqlite3.Row = Depends(require_key)):
    """Marks someone online without touching what their music app says is playing."""
    _db.execute("UPDATE users SET last_seen = ? WHERE id = ?", (int(time.time()), user["id"]))
    _db.commit()
    _store.touch()
    return {"status": "ok"}


@app.get("/people/search")
async def people_search(q: str = Query(..., min_length=1, max_length=30), user: sqlite3.Row = Depends(require_key)):
    escaped = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    rows = _db.execute(
        "SELECT * FROM users WHERE username LIKE ? ESCAPE '\\' AND id != ? ORDER BY username LIMIT 20",
        (f"{escaped}%", user["id"]),
    ).fetchall()
    return [_person(user["id"], r) for r in rows]


@app.get("/people/{user_id}")
async def person_page(user_id: int, user: sqlite3.Row = Depends(require_key)):
    person = _person(user["id"], _other_user(user_id), full=True)
    if person.get("top_artists"):
        person["top_artists"] = await asyncio.to_thread(_with_artist_photos, person["top_artists"])
    return person


@app.get("/people/{user_id}/image/{kind}")
async def person_image(user_id: int, kind: str, user: sqlite3.Row = Depends(require_key)):
    if kind not in PUBLIC_IMAGES:
        raise HTTPException(404, "Unknown image")
    _other_user(user_id)
    return _serve_image(_data_for(user_id).images / kind)


@app.get("/friends")
async def friends(user: sqlite3.Row = Depends(require_key)):
    me = user["id"]
    rows = _db.execute("SELECT * FROM friendships WHERE low_id = ? OR high_id = ?", (me, me)).fetchall()
    out: dict[str, list] = {"friends": [], "incoming": [], "outgoing": []}
    for r in rows:
        other = _other_user(r["high_id"] if r["low_id"] == me else r["low_id"])
        person = _person(me, other)
        unread = _db.execute("SELECT COUNT(*) FROM messages WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL", (other["id"], me)).fetchone()[0]
        person["unread"] = unread
        key = "friends" if r["accepted"] else ("outgoing" if r["requested_by"] == me else "incoming")
        out[key].append(person)
    return out


@app.post("/friends/{user_id}")
async def add_friend(user_id: int, user: sqlite3.Row = Depends(require_key)):
    me = user["id"]
    if user_id == me:
        raise HTTPException(400, "That's you!")
    _other_user(user_id)
    state = _friend_state(me, user_id)
    if state == "none":
        _db.execute("INSERT INTO friendships VALUES (?, ?, ?, 0)", (*_pair(me, user_id), me))
    elif state == "incoming":
        _db.execute("UPDATE friendships SET accepted = 1 WHERE low_id = ? AND high_id = ?", _pair(me, user_id))
    _db.commit()
    _store.touch()
    return {"friendship": _friend_state(me, user_id)}


class AnimeEntry(BaseModel):
    status: str = Field("planning", max_length=20)
    progress: int = Field(0, ge=0, le=100000)
    favorite: bool = False
    title: str = Field("", max_length=300)
    cover: str = Field("", max_length=600)
    format: str = Field("", max_length=30)
    episodes: int | None = Field(None, ge=0, le=100000)


def _anime_file(data: UserData) -> Path:
    return data.dir / "anime.json"


def _load_anime(data: UserData) -> dict:
    return _read_json(_anime_file(data), {})


@app.get("/animelist")
async def anime_list(user: sqlite3.Row = Depends(require_key)):
    return _load_anime(_data_for(user["id"]))


@app.put("/animelist/{media_id}")
async def save_anime(media_id: int, entry: AnimeEntry, user: sqlite3.Row = Depends(require_key)):
    if entry.status not in ANIME_STATUSES:
        raise HTTPException(400, "Pick a status from the list.")
    if entry.cover and not entry.cover.startswith("https://"):
        raise HTTPException(400, "That cover can't be used.")
    data = _data_for(user["id"])
    items = _load_anime(data)
    if str(media_id) not in items and len(items) >= MAX_ANIME_ENTRIES:
        raise HTTPException(400, "That's the most anime your list can hold.")
    items[str(media_id)] = {**entry.model_dump(), "updated": int(time.time())}
    _write_json(_anime_file(data), items)
    return items[str(media_id)]


@app.delete("/animelist/{media_id}")
async def remove_anime(media_id: int, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    items = _load_anime(data)
    items.pop(str(media_id), None)
    _write_json(_anime_file(data), items)
    return {"status": "removed"}


@app.get("/people/{user_id}/animelist")
async def person_anime(user_id: int, user: sqlite3.Row = Depends(require_key)):
    _other_user(user_id)
    if _friend_state(user["id"], user_id) not in ("friends", "self"):
        raise HTTPException(403, "Become friends to see their anime.")
    return _load_anime(_data_for(user_id))


@app.delete("/friends/{user_id}")
async def remove_friend(user_id: int, user: sqlite3.Row = Depends(require_key)):
    _db.execute("DELETE FROM friendships WHERE low_id = ? AND high_id = ?", _pair(user["id"], user_id))
    _db.commit()
    _store.touch()
    return {"friendship": "none"}


class PlaylistIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)


def _playlists_file(data: UserData) -> Path:
    return data.dir / "playlists.json"


def _load_playlists(data: UserData) -> list[dict]:
    return _read_json(_playlists_file(data), [])


def _find_playlist(playlists: list[dict], playlist_id: str) -> dict:
    if PLAYLIST_ID.match(playlist_id):
        for playlist in playlists:
            if playlist["id"] == playlist_id:
                return playlist
    raise HTTPException(404, "Playlist not found")


def _clean_name(name: str) -> str:
    cleaned = name.strip()
    if not cleaned:
        raise HTTPException(400, "Give your playlist a name.")
    return cleaned


@app.get("/playlists")
async def get_playlists(user: sqlite3.Row = Depends(require_key)):
    return _load_playlists(_data_for(user["id"]))


@app.post("/playlists")
async def create_playlist(body: PlaylistIn, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    if len(playlists) >= MAX_PLAYLISTS:
        raise HTTPException(400, "That's the most playlists you can have.")
    playlist = {"id": secrets.token_hex(8), "name": _clean_name(body.name), "cover": None, "tracks": []}
    playlists.insert(0, playlist)
    _write_json(_playlists_file(data), playlists)
    return playlist


@app.patch("/playlists/{playlist_id}")
async def rename_playlist(playlist_id: str, body: PlaylistIn, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    playlist["name"] = _clean_name(body.name)
    _write_json(_playlists_file(data), playlists)
    return playlist


@app.delete("/playlists/{playlist_id}")
async def delete_playlist(playlist_id: str, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    playlists.remove(playlist)
    _write_json(_playlists_file(data), playlists)
    (data.images / f"playlist-{playlist_id}").unlink(missing_ok=True)
    return {"status": "deleted"}


@app.post("/playlists/{playlist_id}/tracks")
async def add_playlist_track(playlist_id: str, track: Play, user: sqlite3.Row = Depends(require_key)):
    _check_id(track.id)
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    if len(playlist["tracks"]) >= MAX_PLAYLIST_TRACKS:
        raise HTTPException(400, "This playlist is full.")
    if not any(t["id"] == track.id for t in playlist["tracks"]):
        playlist["tracks"].append(track.model_dump())
        _write_json(_playlists_file(data), playlists)
    return playlist


@app.delete("/playlists/{playlist_id}/tracks/{track_id}")
async def remove_playlist_track(playlist_id: str, track_id: str, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    playlist["tracks"] = [t for t in playlist["tracks"] if t["id"] != track_id]
    _write_json(_playlists_file(data), playlists)
    return playlist


@app.put("/playlists/{playlist_id}/cover")
async def set_playlist_cover(playlist_id: str, request: Request, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    image = await request.body()
    if len(image) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Image is larger than 10 MB")
    if _image_type(image) is None:
        raise HTTPException(415, "Use a PNG, JPEG, WebP or GIF image")
    data.images.mkdir(parents=True, exist_ok=True)
    (data.images / f"playlist-{playlist_id}").write_bytes(image)
    playlist["cover"] = int(time.time())
    _write_json(_playlists_file(data), playlists)
    return playlist


@app.delete("/playlists/{playlist_id}/cover")
async def delete_playlist_cover(playlist_id: str, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    playlists = _load_playlists(data)
    playlist = _find_playlist(playlists, playlist_id)
    (data.images / f"playlist-{playlist_id}").unlink(missing_ok=True)
    playlist["cover"] = None
    _write_json(_playlists_file(data), playlists)
    return playlist


@app.get("/playlists/{playlist_id}/cover")
async def get_playlist_cover(playlist_id: str, user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    _find_playlist(_load_playlists(data), playlist_id)
    return _serve_image(data.images / f"playlist-{playlist_id}")


@app.get("/release")
async def release():
    return _read_json(DOWNLOAD_DIR / "release.json", {"version": "0.0.0", "notes": []})


@app.get("/release/anime")
async def anime_release():
    return _read_json(DOWNLOAD_DIR / "anime_release.json", {"version": "0.0.0", "notes": []})


@app.get("/release/vortex-anime")
async def vortex_anime_release():
    return _read_json(DOWNLOAD_DIR / "vortex_anime_release.json", {"version": "0.0.0", "notes": []})


def _message_json(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "sender_id": row["sender_id"],
        "body": row["body"],
        "track": json.loads(row["track"]) if row["track"] else None,
        "sent_at": row["sent_at"],
    }


def _fetch_messages(me: int, user_id: int, after: int) -> list[dict]:
    rows = _db.execute(
        """SELECT * FROM (SELECT * FROM messages
           WHERE id > ? AND ((sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?))
           ORDER BY id DESC LIMIT ?) ORDER BY id""",
        (after, me, user_id, user_id, me, MAX_MESSAGE_FETCH),
    ).fetchall()
    if rows:
        _db.execute("UPDATE messages SET read_at = ? WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL", (int(time.time()), user_id, me))
        _db.commit()
        _store.touch()
    return [_message_json(r) for r in rows]


# Open long-poll requests per user. A new message wakes them at once, so chat
# feels instant without a websocket or extra server packages.
_message_waiters: dict[int, set[asyncio.Event]] = {}
MESSAGE_WAIT_SECONDS = 25


def _wake(user_id: int):
    for event in _message_waiters.get(user_id, ()):
        event.set()


@app.get("/messages/{user_id}")
async def get_messages(user_id: int, after: int = Query(0, ge=0), user: sqlite3.Row = Depends(require_key)):
    me = user["id"]
    if _friend_state(me, user_id) != "friends":
        raise HTTPException(403, "You can only chat with friends")
    return _fetch_messages(me, user_id, after)


@app.get("/messages/{user_id}/wait")
async def wait_messages(user_id: int, after: int = Query(0, ge=0), user: sqlite3.Row = Depends(require_key)):
    me = user["id"]
    if _friend_state(me, user_id) != "friends":
        raise HTTPException(403, "You can only chat with friends")
    fresh = _fetch_messages(me, user_id, after)
    if fresh:
        return fresh
    event = asyncio.Event()
    _message_waiters.setdefault(me, set()).add(event)
    try:
        await asyncio.wait_for(event.wait(), MESSAGE_WAIT_SECONDS)
    except asyncio.TimeoutError:
        return []
    finally:
        waiters = _message_waiters.get(me)
        if waiters is not None:
            waiters.discard(event)
            if not waiters:
                _message_waiters.pop(me, None)
    return _fetch_messages(me, user_id, after)


@app.post("/messages/{user_id}")
async def send_message(user_id: int, body: MessageIn, user: sqlite3.Row = Depends(require_key)):
    me = user["id"]
    if _friend_state(me, user_id) != "friends":
        raise HTTPException(403, "You can only chat with friends")
    text = body.body.strip()
    if not text and body.track is None:
        raise HTTPException(400, "Write a message first")
    if body.gift and body.track is None:
        raise HTTPException(400, "Pick a song to gift")
    track = {**body.track.model_dump(), **({"gift": True} if body.gift else {})} if body.track else None
    cursor = _db.execute(
        "INSERT INTO messages (sender_id, recipient_id, body, track, sent_at) VALUES (?, ?, ?, ?, ?)",
        (me, user_id, text, json.dumps(track) if track else None, int(time.time())),
    )
    _db.commit()
    _store.touch()
    _wake(user_id)
    _wake(me)
    return _message_json(_db.execute("SELECT * FROM messages WHERE id = ?", (cursor.lastrowid,)).fetchone())

@app.get("/suggest", dependencies=[Depends(require_key)])
async def suggest(q: str = Query(..., min_length=1, max_length=100)):
    try:
        results = await asyncio.to_thread(lambda: _yt().get_search_suggestions(q))
    except Exception:
        return []
    return results[:6]


def _parse_length(length: str | None) -> int | None:
    if not length:
        return None
    seconds = 0
    for part in length.split(":"):
        if not part.isdigit():
            return None
        seconds = seconds * 60 + int(part)
    return seconds


def _normal_title(text: str | None) -> str:
    without_notes = re.sub(r"[\(\[].*?[\)\]]", " ", (text or "").casefold())
    return " ".join(re.sub(r"[^\w]+", " ", without_notes).split())


def _artist_names(track: dict) -> set[str]:
    return {_normal_title(a.get("name")) for a in track.get("artists") or [] if a.get("name")}


def _song_version(track: dict) -> str | None:
    """Finds the album version of a music video, only when title and artist truly match."""
    video_id = track.get("videoId")
    if video_id in _song_versions:
        return _song_versions[video_id]
    title = _normal_title(track.get("title"))
    artists = _artist_names(track)
    match = None
    if title and artists:
        query = f"{track.get('title')} {' '.join(a['name'] for a in track.get('artists') or [] if a.get('name'))}"
        for hit in _yt().search(query, filter="songs", limit=5):
            if hit.get("videoId") and _normal_title(hit.get("title")) == title and artists & _artist_names(hit):
                match = hit["videoId"]
                break
    if len(_song_versions) >= MAX_SONG_VERSIONS:
        _song_versions.clear()
    _song_versions[video_id] = match
    return match


def _album_audio_id(video_id: str) -> str:
    """Plays the album version instead of a music video, so a 13 minute short film stays a 6 minute song."""
    if video_id in _audio_choice:
        return _audio_choice[video_id]
    try:
        tracks = _yt().get_watch_playlist(videoId=video_id, limit=1).get("tracks", [])
        seed = next((t for t in tracks if t.get("videoId") == video_id), None)
        choice = video_id
        if seed is not None and seed.get("videoType") != ALBUM_TRACK_TYPE:
            choice = _song_version(seed) or video_id
    except Exception:
        return video_id
    if len(_audio_choice) >= MAX_SONG_VERSIONS:
        _audio_choice.clear()
    _audio_choice[video_id] = choice
    return choice


async def _audio_id(video_id: str) -> str:
    return _audio_choice.get(video_id) or await asyncio.to_thread(_album_audio_id, video_id)


def _radio_tracks(seed_id: str) -> list[dict]:
    # A radio started from a music video comes back as all videos with no album
    # covers. Starting from the same song's album version gives real covers.
    tracks = _yt().get_watch_playlist(videoId=seed_id, limit=RADIO_SIZE).get("tracks", [])
    seed = next((t for t in tracks if t.get("videoId") == seed_id), None)
    if seed is None or seed.get("videoType") == ALBUM_TRACK_TYPE:
        return tracks
    try:
        song_id = _song_version(seed)
        if song_id is None:
            return tracks
        songs = _yt().get_watch_playlist(videoId=song_id, limit=RADIO_SIZE).get("tracks", [])
    except Exception:
        return tracks
    return [t for t in songs if t.get("videoId") != song_id] or tracks


def _radio(seed_id: str) -> list[dict]:
    tracks = []
    seen = set()
    swaps = 0
    for r in _radio_tracks(seed_id):
        video_id = r.get("videoId")
        if not video_id:
            continue
        duration = _parse_length(r.get("length"))
        # Up next shouldn't sneak in the long video cut of a song either.
        if r.get("videoType") != ALBUM_TRACK_TYPE and swaps < MAX_RADIO_SWAPS:
            swaps += 1
            try:
                song_id = _song_version(r)
            except Exception:
                song_id = None
            if song_id:
                video_id, duration = song_id, None
        if video_id in seen:
            continue
        seen.add(video_id)
        thumbs = r.get("thumbnail") or []
        tracks.append(
            {
                "id": video_id,
                "title": r.get("title"),
                "artist": ", ".join(a["name"] for a in r.get("artists") or [] if a.get("name")),
                "album": (r.get("album") or {}).get("name"),
                "duration": duration,
                "thumbnail": thumbs[-1]["url"] if thumbs else f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
            }
        )
    return tracks


def _build_recommendations(history: list[dict]) -> dict:
    if not history:
        return {"shelves": [], "top_artists": []}

    now = time.time()
    track_scores: Counter = Counter()
    artist_scores: Counter = Counter()
    latest: dict[str, dict] = {}
    artist_art: dict[str, str] = {}
    for play in history:
        weight = 0.5 ** ((now - play.get("at", now)) / HISTORY_HALF_LIFE)
        track_scores[play["id"]] += weight
        latest[play["id"]] = play
        for artist in (play.get("artist") or "").split(", "):
            if artist:
                artist_scores[artist] += weight
                _remember_art(artist_art, artist, play.get("thumbnail"))

    recent_ids = {p["id"] for p in history[-RECENT_EXCLUDE:]}
    seeds = [track_id for track_id, _ in track_scores.most_common(MAX_SEEDS)]
    candidates: dict[str, dict] = {}
    candidate_scores: Counter = Counter()
    first_radio: list[dict] = []
    first_title = ""
    for index, seed in enumerate(seeds):
        try:
            radio = [t for t in _radio(seed) if t["id"] != seed]
        except Exception:
            continue
        for position, track in enumerate(radio):
            if track["id"] in recent_ids:
                continue
            candidates[track["id"]] = track
            affinity = sum(artist_scores.get(a, 0) for a in (track["artist"] or "").split(", "))
            candidate_scores[track["id"]] += 1 / (position + 2) + 0.2 * min(affinity, 3)
        if index == 0:
            first_radio = radio
            first_title = latest[seed].get("title") or "your last song"

    mix = [candidates[i] for i, _ in candidate_scores.most_common(SHELF_SIZE)]
    mix_lead = {t["id"] for t in mix[:MIX_LEAD]}
    similar = [t for t in first_radio if t["id"] not in recent_ids and t["id"] not in mix_lead][:SHELF_SIZE]
    shelves = []
    if mix:
        shelves.append({"title": "Made for you", "tracks": mix[:MIX_LEAD]})
    if len(similar) >= MIN_SHELF:
        shelves.append({"title": f"Because you played {first_title}", "tracks": similar})
    top_artists = [{"name": name, "thumbnail": artist_art.get(name, "")} for name, _ in artist_scores.most_common(MAX_TOP_ARTISTS)]
    return {"shelves": shelves, "top_artists": _with_artist_photos(top_artists)}


def _best_thumb(thumbs: list | None) -> str:
    return thumbs[-1]["url"] if thumbs else ""


def _check_browse_id(browse_id: str):
    if not BROWSE_ID.match(browse_id):
        raise HTTPException(400, "Invalid id")


def _song_from(r: dict, album: dict | None = None, fallback_art: str = "") -> dict | None:
    video_id = r.get("videoId")
    if not video_id:
        return None
    artists = r.get("artists") or []
    return {
        "id": video_id,
        "title": r.get("title"),
        "artist": ", ".join(a["name"] for a in artists if a.get("name")),
        "artist_id": next((a.get("id") for a in artists if a.get("id")), None),
        "album": album.get("title") if album else (r.get("album") or {}).get("name"),
        "duration": r.get("duration_seconds") or _parse_length(r.get("duration") or r.get("length")),
        "thumbnail": _best_thumb(r.get("thumbnails") or r.get("thumbnail")) or fallback_art or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
    }


def _album_card(r: dict, artist_name: str = "") -> dict | None:
    browse_id = r.get("browseId")
    if not browse_id:
        return None
    artist = artist_name or ", ".join(a["name"] for a in r.get("artists") or [] if a.get("name"))
    return {"id": browse_id, "title": r.get("title"), "artist": artist, "year": r.get("year"), "thumbnail": _best_thumb(r.get("thumbnails"))}


def _browse_search(q: str) -> dict:
    artists = [
        {"id": r["browseId"], "name": r.get("artist") or r.get("title"), "thumbnail": _best_thumb(r.get("thumbnails"))}
        for r in _yt().search(q, filter="artists", limit=10)
        if r.get("browseId")
    ]
    albums = [c for c in (_album_card(r) for r in _yt().search(q, filter="albums", limit=12)) if c]
    return {"artists": artists, "albums": albums}


def _artist_page(browse_id: str) -> dict:
    data = _yt().get_artist(browse_id)
    name = data.get("name") or ""
    section = data.get("songs") or {}
    results = section.get("results") or []
    if section.get("browseId"):
        try:
            results = _yt().get_playlist(section["browseId"], limit=ARTIST_SONG_LIMIT).get("tracks") or results
        except Exception:
            pass
    songs = [s for s in (_song_from(r) for r in results) if s]

    album_section = data.get("albums") or {}
    album_results = album_section.get("results") or []
    if album_section.get("browseId") and album_section.get("params"):
        try:
            album_results = _yt().get_artist_albums(album_section["browseId"], album_section["params"], limit=None) or album_results
        except Exception:
            pass
    albums = [c for c in (_album_card(r, name) for r in album_results) if c]
    return {"id": browse_id, "name": name, "description": data.get("description"), "thumbnail": _best_thumb(data.get("thumbnails")), "songs": songs, "albums": albums}


def _album_page(browse_id: str) -> dict:
    data = _yt().get_album(browse_id)
    art = _best_thumb(data.get("thumbnails"))
    tracks = [s for s in (_song_from(r, data, art) for r in data.get("tracks") or []) if s]
    artists = data.get("artists") or []
    return {
        "id": browse_id,
        "title": data.get("title"),
        "artist": ", ".join(a["name"] for a in artists if a.get("name")),
        "artist_id": next((a.get("id") for a in artists if a.get("id")), None),
        "year": data.get("year"),
        "thumbnail": art,
        "tracks": tracks,
    }


async def _cached_browse(key: str, build):
    entry = _browse_cache.get(key)
    if entry and time.time() - entry[0] < BROWSE_TTL:
        return entry[1]
    try:
        value = await asyncio.to_thread(build)
    except Exception as e:
        raise HTTPException(502, f"Lookup failed: {e}")
    _browse_cache[key] = (time.time(), value)
    return value


@app.get("/browse/search", dependencies=[Depends(require_key)])
async def browse_search(q: str = Query(..., min_length=1, max_length=100)):
    return await _cached_browse(f"search:{q.lower()}", lambda: _browse_search(q))


@app.get("/artist/{browse_id}", dependencies=[Depends(require_key)])
async def artist_page(browse_id: str):
    _check_browse_id(browse_id)
    return await _cached_browse(f"artist:{browse_id}", lambda: _artist_page(browse_id))


@app.get("/album/{browse_id}", dependencies=[Depends(require_key)])
async def album_page(browse_id: str):
    _check_browse_id(browse_id)
    return await _cached_browse(f"album:{browse_id}", lambda: _album_page(browse_id))


@app.get("/radio/{video_id}", dependencies=[Depends(require_key)])
async def radio(video_id: str):
    _check_id(video_id)
    return await _cached_browse(f"radio:{video_id}", lambda: _radio(video_id))


@app.get("/liked")
async def get_liked(user: sqlite3.Row = Depends(require_key)):
    return _read_json(_data_for(user["id"]).dir / "liked.json", [])


@app.put("/liked")
async def put_liked(tracks: list[Play], user: sqlite3.Row = Depends(require_key)):
    _write_json(_data_for(user["id"]).dir / "liked.json", [t.model_dump() for t in tracks][:MAX_HISTORY])
    return {"count": len(tracks)}


@app.get("/recommendations")
async def recommendations(user: sqlite3.Row = Depends(require_key)):
    data = _data_for(user["id"])
    cache = data.recommendations
    history = data.history
    fresh = time.time() - cache["at"] < RECOMMENDATION_TTL and len(history) - cache["plays"] < RECOMMENDATION_PLAYS
    empty_but_has_plays = bool(history) and not (cache["value"] or {}).get("shelves")
    if cache["value"] is not None and fresh and not empty_but_has_plays:
        return cache["value"]
    value = await asyncio.to_thread(_build_recommendations, history)
    saved_file = data.dir / "recommendations.json"
    if history and not value["shelves"]:
        saved = _read_json(saved_file, None)
        if saved:
            return saved
    cache.update(at=time.time(), plays=len(history), value=value)
    _write_json(saved_file, value)
    return value

@app.get("/search", dependencies=[Depends(require_key)])
async def search(q: str = Query(..., min_length=1), limit: int = Query(15, ge=1, le=50)):
    try:
        return await asyncio.to_thread(_search, q, limit)
    except Exception as e:
        raise HTTPException(502, f"Search failed: {e}")


def _helper_url() -> str | None:
    if not _helper["url"]:
        saved = _read_json(HELPER_ADDRESS_FILE, {}).get("url", "")
        if HELPER_URL.match(saved):
            _helper["url"] = saved
    return _helper["url"] or None


async def _helper_answers() -> bool:
    helper = _helper_url()
    if helper is None:
        return False
    try:
        response = await client.get(f"{helper}/prefetch/health-check", timeout=HELPER_PROBE_SECONDS)
    except httpx.HTTPError:
        return False
    return response.status_code == 401


class HelperRegistration(BaseModel):
    url: str


@app.post("/helper/register")
async def helper_register(body: HelperRegistration, x_vortex_helper: str | None = Header(None)):
    if not HELPER_SECRET or not x_vortex_helper or not secrets.compare_digest(x_vortex_helper, HELPER_SECRET):
        raise HTTPException(401, "Not allowed")
    if not HELPER_URL.match(body.url):
        raise HTTPException(400, "Invalid address")
    if body.url != _helper_url():
        HELPER_ADDRESS_FILE.parent.mkdir(parents=True, exist_ok=True)
        _write_json(HELPER_ADDRESS_FILE, {"url": body.url})
        _helper["url"] = body.url
    return {"status": "ok"}


@app.get("/helper/download/{token}")
async def helper_download(token: str):
    if not HELPER_DOWNLOAD_TOKEN or not secrets.compare_digest(token, HELPER_DOWNLOAD_TOKEN) or not HELPER_ZIP.is_file():
        raise HTTPException(404, "Not found")
    return FileResponse(HELPER_ZIP, media_type="application/zip", filename="VortexHelper.zip")


def _relay(upstream: httpx.Response, media_type: str, whole_file: bool) -> StreamingResponse:
    answers_whole_file = whole_file and upstream.status_code == 206
    forwarded = ("content-length", "accept-ranges") if answers_whole_file else ("content-length", "content-range", "accept-ranges")
    passthrough = {k: v for k, v in upstream.headers.items() if k.lower() in forwarded}

    async def body():
        try:
            async for chunk in upstream.aiter_bytes(64 * 1024):
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(body(), status_code=200 if answers_whole_file else upstream.status_code, headers=passthrough, media_type=media_type)


async def _stream_from_helper(video_id: str, range_header: str | None) -> StreamingResponse | None:
    helper = _helper_url()
    if helper is None:
        return None
    headers = {"X-Vortex-Helper": HELPER_SECRET, "Range": range_header or WHOLE_FILE_RANGE}
    try:
        upstream = await client.send(client.build_request("GET", f"{helper}/audio/{video_id}", headers=headers), stream=True)
    except httpx.HTTPError:
        return None
    if upstream.status_code not in (200, 206):
        await upstream.aclose()
        return None
    return _relay(upstream, upstream.headers.get("content-type", "audio/mp4"), whole_file=range_header is None)


@app.get("/prefetch/{video_id}", dependencies=[Depends(require_key)])
async def prefetch(video_id: str):
    _check_id(video_id)
    video_id = await _audio_id(video_id)
    helper = _helper_url()
    if helper is not None:
        try:
            response = await client.get(f"{helper}/prefetch/{video_id}", headers={"X-Vortex-Helper": HELPER_SECRET})
            if response.status_code == 200:
                return {"status": "ready"}
        except httpx.HTTPError:
            pass
    try:
        await _resolve(video_id)
    except Exception as e:
        raise HTTPException(502, f"Extraction failed: {e}")
    return {"status": "ready"}


@app.get("/art", dependencies=[Depends(require_key)])
async def art(url: str = Query(...)):
    parsed = urlparse(url)
    host = parsed.hostname or ""
    if parsed.scheme != "https" or not any(host == h or host.endswith(f".{h}") for h in ART_HOSTS):
        raise HTTPException(400, "Unsupported image host")
    try:
        upstream = await client.get(url)
    except httpx.HTTPError:
        raise HTTPException(502, "Image fetch failed")
    if upstream.status_code != 200:
        raise HTTPException(404, "Image not found")
    return Response(
        upstream.content,
        media_type=upstream.headers.get("content-type", "image/jpeg"),
        headers={"Cache-Control": "private, max-age=86400"},
    )


@app.get("/lyrics", dependencies=[Depends(require_key)])
async def lyrics(title: str = Query(...), artist: str = Query(""), album: str = Query(""), duration: int | None = Query(None)):
    cache_key = (title, artist)
    if cache_key in _lyrics_cache:
        return _lyrics_cache[cache_key]

    headers = {"User-Agent": LYRICS_USER_AGENT}
    best = None
    try:
        if duration:
            params = {"track_name": title, "artist_name": artist, "album_name": album, "duration": duration}
            res = await client.get(f"{LYRICS_API}/get", params=params, headers=headers)
            if res.status_code == 200:
                best = res.json()
        if not best or not (best.get("syncedLyrics") or best.get("plainLyrics")):
            res = await client.get(f"{LYRICS_API}/search", params={"track_name": title, "artist_name": artist}, headers=headers)
            if res.status_code == 200:
                results = res.json()
                best = next((r for r in results if r.get("syncedLyrics")), None) or next((r for r in results if r.get("plainLyrics")), None)
    except httpx.HTTPError:
        raise HTTPException(502, "Lyrics lookup failed")

    payload = {"synced": (best or {}).get("syncedLyrics"), "plain": (best or {}).get("plainLyrics")}
    _lyrics_cache[cache_key] = payload
    return payload


@app.get("/stream/{video_id}", dependencies=[Depends(require_key)])
async def stream(video_id: str, request: Request):
    _check_id(video_id)
    video_id = await _audio_id(video_id)
    range_header = request.headers.get("range")
    relayed = await _stream_from_helper(video_id, range_header)
    if relayed is not None:
        return relayed
    try:
        upstream, ext = await _open_upstream(video_id, range_header or WHOLE_FILE_RANGE)
        if upstream.status_code in (403, 410):
            await upstream.aclose()
            upstream, ext = await _open_upstream(video_id, range_header or WHOLE_FILE_RANGE, fresh=True)
    except Exception as e:
        raise HTTPException(502, f"Extraction failed: {e}")
    return _relay(upstream, "audio/mp4" if ext == "m4a" else "audio/webm", whole_file=range_header is None)


@app.get("/ytdebug")
async def ytdebug(id: str, client: str = ""):
    """Reports what the host can actually extract, formats included."""
    def run():
        opts = {**YDL_BASE}
        if client:
            opts["extractor_args"] = {"youtube": {"player_client": client.split(",")}}
        uses_cookies = bool(opts.get("cookiefile"))
        with yt_dlp.YoutubeDL({**opts, "format": None}) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={id}", download=False)
        formats = [
            f"{f.get('format_id')}|{f.get('ext')}|{f.get('acodec')}"
            for f in (info.get("formats") or [])
            if f.get("acodec") not in (None, "none")
        ]
        return {"ok": True, "cookies": uses_cookies, "n": len(formats), "formats": formats[:10]}
    try:
        return await asyncio.to_thread(run)
    except Exception as exc:
        return {"ok": False, "client": client, "cookies": bool(YDL_BASE.get("cookiefile")), "error": str(exc)[:150]}

@app.get("/storage")
async def storage_status():
    return {"restore": RESTORE_STATUS, **_store.status(), "data_dir": str(DATA_DIR)}


@app.on_event("shutdown")
async def _flush_storage():
    _store.stop()


@app.get("/animesources")
async def anime_sources():
    """Official playlists confirmed playing in the Vortex player, from the last availability check."""
    return _read_json(DOWNLOAD_DIR / "anime_verified.json", {"checked": "", "shows": {}})


@app.get("/anime")
async def anime_home():
    return RedirectResponse("/anime/")


if ANIME_DIR.exists():
    app.mount("/anime", StaticFiles(directory=ANIME_DIR, html=True), name="anime")

if WEB_DIR.exists():
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT, log_config=None, access_log=False)
