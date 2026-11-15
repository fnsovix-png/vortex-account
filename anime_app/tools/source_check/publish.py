"""Turns a finished check into dist/anime_verified.json, keeping only playlists that truly played a real episode."""
import json
import re
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path

results = Path(sys.argv[1])
dist = Path(__file__).resolve().parents[3] / "dist" / "anime_verified.json"
EPISODE = re.compile(r"(?:episode|ep|e)\s*0*(\d+)\b|-\s*0*(\d+)\s*-|\b0(\d)\b", re.I)


def lines_up(title):
    """Episode buttons assume the playlist starts at episode 1, and the family watches in English."""
    if re.search("cap[ií]tulo|episodio|epis[oó]dio|oficial", title, re.I):
        return False
    number = EPISODE.search(title)
    return number is None or next(g for g in number.groups() if g) == "1"


shows = defaultdict(list)
audio = {}
rows = [json.loads(line) for line in results.read_text(encoding="utf-8").splitlines() if line.strip()]
for r in rows:
    title = r.get("title") or ""
    # Under 5 minutes is a trailer. Over 2 hours is a whole season in one video, so episode buttons wouldn't line up.
    if r.get("ok") and 300 <= (r.get("seconds") or 0) <= 7200 and lines_up(title):
        shows[str(r["id"])].append(r["list"])
        if re.search(r"multi[- ]?sub", title, re.I):
            audio[str(r["id"])] = "several subtitle languages"
        elif re.search(r"eng(lish)?\.? sub|\(sub\)", title, re.I):
            audio[str(r["id"])] = "English subtitles"
dist.parent.mkdir(exist_ok=True)
dist.write_text(json.dumps({"checked": date.today().strftime("%b %d, %Y"), "shows": shows, "audio": audio}, indent=0), encoding="utf-8")
print(len(rows), "checked,", sum(1 for r in rows if r.get("ok")), "played,", len(shows), "shows published")
