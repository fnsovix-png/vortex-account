import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
HEALTH_URL = "http://127.0.0.1:8000/health"
APP_URL = "http://127.0.0.1:8000"
NATIVE_EXE = BASE_DIR / "app" / "build" / "windows" / "x64" / "runner" / "Release" / "Vortex.exe"
EDGE_PATHS = [
    Path(os.environ.get("ProgramFiles(x86)", "")) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
    Path(os.environ.get("ProgramFiles", "")) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
]
STARTUP_TIMEOUT = 30


def backend_running() -> bool:
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=1) as res:
            return res.status == 200
    except OSError:
        return False


def start_backend():
    subprocess.Popen(
        [sys.executable, str(BASE_DIR / "main.py")],
        cwd=BASE_DIR,
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def wait_for_backend():
    deadline = time.time() + STARTUP_TIMEOUT
    while time.time() < deadline:
        if backend_running():
            return
        time.sleep(0.25)


def open_app():
    if NATIVE_EXE.exists():
        subprocess.Popen([str(NATIVE_EXE)], cwd=NATIVE_EXE.parent)
        return
    for edge in EDGE_PATHS:
        if edge.exists():
            subprocess.Popen([str(edge), f"--app={APP_URL}"])
            return
    os.startfile(APP_URL)


if __name__ == "__main__":
    if not backend_running():
        start_backend()
        wait_for_backend()
    open_app()
