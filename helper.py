"""Vortex Helper: fetches song audio over a home internet connection for the Vortex server."""

import asyncio
import ctypes
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import uvicorn
import yt_dlp
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import StreamingResponse

APP_DIR = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
CONFIG = json.loads((APP_DIR / "helper_config.json").read_text(encoding="utf-8"))
SERVER = CONFIG["server"].rstrip("/")
SECRET = CONFIG["secret"]
PORT = 8765
CHECK_SECONDS = 45
REGISTER_EVERY_SECONDS = 6 * 3600
TUNNEL_WAIT_SECONDS = 60
TUNNEL_MAX_FAILURES = 4
URL_SAFETY_MARGIN = 300
URL_FALLBACK_TTL = 3600
MAX_CACHED_URLS = 200
VIDEO_ID = re.compile(r"^[\w-]{6,20}$")
TUNNEL_URL = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
LOG_DIR = Path(os.environ.get("LOCALAPPDATA", tempfile.gettempdir())) / "VortexHelper"
LOG_FILE = LOG_DIR / "helper.log"
NO_WINDOW = 0x08000000
MESSAGE_ICON_INFO = 0x40


def log(message: str):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")


class _SilentLogger:
    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        pass


app = FastAPI(title="Vortex Helper")
client = httpx.AsyncClient(timeout=httpx.Timeout(20, read=None), follow_redirects=True)
_urls: dict[str, tuple[str, dict, str, float]] = {}
_in_flight: dict[str, asyncio.Task] = {}


def _extract(video_id: str):
    options = {"quiet": True, "no_warnings": True, "noplaylist": True, "logger": _SilentLogger(), "format": "bestaudio[ext=m4a]/bestaudio"}
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
    url = info["url"]
    expire = parse_qs(urlparse(url).query).get("expire", [None])[0]
    expires_at = int(expire) - URL_SAFETY_MARGIN if expire else time.time() + URL_FALLBACK_TTL
    return url, info.get("http_headers", {}), info.get("ext", "m4a"), expires_at


async def _resolve(video_id: str, fresh: bool = False):
    cached = _urls.get(video_id)
    if cached and not fresh and cached[3] > time.time():
        return cached
    task = _in_flight.get(video_id)
    if task is None:
        task = asyncio.create_task(asyncio.to_thread(_extract, video_id))
        _in_flight[video_id] = task
        task.add_done_callback(lambda _: _in_flight.pop(video_id, None))
    entry = await asyncio.shield(task)
    _urls[video_id] = entry
    if len(_urls) > MAX_CACHED_URLS:
        _urls.pop(min(_urls, key=lambda k: _urls[k][3]))
    return entry


def _authorize(video_id: str, supplied: str | None):
    if not supplied or not secrets.compare_digest(supplied, SECRET):
        raise HTTPException(401, "Not allowed")
    if not VIDEO_ID.match(video_id):
        raise HTTPException(400, "Invalid track id")


@app.get("/prefetch/{video_id}")
async def prefetch(video_id: str, x_vortex_helper: str | None = Header(None)):
    _authorize(video_id, x_vortex_helper)
    try:
        await _resolve(video_id)
    except Exception as e:
        log(f"prefetch failed {video_id}: {str(e)[:160]}")
        raise HTTPException(502, "Extraction failed")
    return {"status": "ready"}


async def _open(video_id: str, range_header: str | None, fresh: bool = False):
    url, headers, ext, _ = await _resolve(video_id, fresh)
    upstream_headers = dict(headers)
    if range_header:
        upstream_headers["Range"] = range_header
    upstream = await client.send(client.build_request("GET", url, headers=upstream_headers), stream=True)
    return upstream, ext


@app.get("/audio/{video_id}")
async def audio(video_id: str, request: Request, x_vortex_helper: str | None = Header(None)):
    _authorize(video_id, x_vortex_helper)
    range_header = request.headers.get("range")
    try:
        upstream, ext = await _open(video_id, range_header)
        if upstream.status_code in (403, 410):
            await upstream.aclose()
            upstream, ext = await _open(video_id, range_header, fresh=True)
    except Exception as e:
        log(f"audio failed {video_id}: {str(e)[:160]}")
        raise HTTPException(502, "Extraction failed")

    passthrough = {k: v for k, v in upstream.headers.items() if k.lower() in ("content-length", "content-range", "accept-ranges")}

    async def body():
        try:
            async for chunk in upstream.aiter_bytes(64 * 1024):
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(body(), status_code=upstream.status_code, headers=passthrough, media_type="audio/mp4" if ext == "m4a" else "audio/webm")


def _start_tunnel() -> tuple[subprocess.Popen, str | None]:
    tunnel_log = LOG_DIR / "tunnel.log"
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    tunnel_log.unlink(missing_ok=True)
    process = subprocess.Popen(
        [str(APP_DIR / "cloudflared.exe"), "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{PORT}", "--logfile", str(tunnel_log)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=NO_WINDOW,
    )
    deadline = time.time() + TUNNEL_WAIT_SECONDS
    while time.time() < deadline and process.poll() is None:
        if tunnel_log.exists():
            match = TUNNEL_URL.search(tunnel_log.read_text(encoding="utf-8", errors="ignore"))
            if match:
                return process, match.group(0)
        time.sleep(1)
    return process, None


def _register(url: str) -> bool:
    try:
        response = httpx.post(f"{SERVER}/helper/register", json={"url": url}, headers={"X-Vortex-Helper": SECRET}, timeout=20)
        if response.status_code != 200:
            log(f"register refused: {response.status_code}")
        return response.status_code == 200
    except httpx.HTTPError as e:
        log(f"register failed: {e}")
        return False


def _tunnel_answers(url: str) -> bool:
    """Asks for a page through the public address. This helper answers it with 401."""
    try:
        return httpx.get(f"{url}/prefetch/health-check", timeout=20).status_code == 401
    except httpx.HTTPError:
        return False


def _tunnel_loop():
    while True:
        process, url = _start_tunnel()
        if url is None:
            log("tunnel did not start")
            process.terminate()
            time.sleep(CHECK_SECONDS)
            continue
        log(f"tunnel up: {url}")
        register_at = 0.0
        failures = 0
        while process.poll() is None:
            if time.time() >= register_at:
                register_at = time.time() + (REGISTER_EVERY_SECONDS if _register(url) else CHECK_SECONDS)
            time.sleep(CHECK_SECONDS)
            # Cloudflare can delete a temporary address after a connection drop while
            # cloudflared keeps running and retrying it forever. Only a new one fixes that.
            failures = 0 if _tunnel_answers(url) else failures + 1
            if failures >= TUNNEL_MAX_FAILURES:
                log(f"tunnel address stopped answering after {failures} checks, getting a new one")
                process.terminate()
                process.wait()
                break
        log("tunnel stopped, restarting")


def _install_startup():
    startup = Path(os.environ["APPDATA"]) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
    shortcut = startup / "Vortex Helper.lnk"
    if shortcut.exists() or not getattr(sys, "frozen", False):
        return False
    script = (
        "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:VORTEX_LNK);"
        "$s.TargetPath=$env:VORTEX_EXE;$s.WorkingDirectory=$env:VORTEX_DIR;$s.Save()"
    )
    environment = {**os.environ, "VORTEX_LNK": str(shortcut), "VORTEX_EXE": str(Path(sys.executable).resolve()), "VORTEX_DIR": str(APP_DIR)}
    subprocess.run(["powershell", "-NoProfile", "-Command", script], env=environment, creationflags=NO_WINDOW, check=False)
    return True


def _already_running() -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", PORT)) == 0


def main():
    if _already_running():
        ctypes.windll.user32.MessageBoxW(0, "Vortex Helper is already running.", "Vortex Helper", MESSAGE_ICON_INFO)
        return
    first_run = _install_startup()
    log("helper starting")
    threading.Thread(target=_tunnel_loop, daemon=True).start()
    if first_run:
        message = "Vortex Helper is on. It runs quietly in the background and starts with Windows, so you can close this.\n\nKeep this PC on and awake so your family's songs can play."
        threading.Thread(target=ctypes.windll.user32.MessageBoxW, args=(0, message, "Vortex Helper", MESSAGE_ICON_INFO), daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_config=None, access_log=False)


if __name__ == "__main__":
    main()
