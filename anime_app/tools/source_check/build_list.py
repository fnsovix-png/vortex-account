"""Lists AniList shows that have an official YouTube playlist, most popular first."""
import json
import re
import time
from pathlib import Path

import httpx

Q = """query($page:Int){Page(page:$page,perPage:50){pageInfo{hasNextPage}media(type:ANIME,licensedById_in:[13],sort:POPULARITY_DESC,isAdult:false){id episodes format title{english romaji} externalLinks{site url type}}}}"""
out = []
for page in range(1, 13):
    r = httpx.post("https://graphql.anilist.co", json={"query": Q, "variables": {"page": page}}, timeout=30)
    if r.status_code == 429:
        time.sleep(int(r.headers.get("retry-after", 30)))
        r = httpx.post("https://graphql.anilist.co", json={"query": Q, "variables": {"page": page}}, timeout=30)
    data = r.json()["data"]["Page"]
    for m in data["media"]:
        lists = []
        for l in m["externalLinks"]:
            if l["site"] == "YouTube":
                found = re.search(r"[?&]list=([\w-]+)", l["url"])
                if found and found.group(1) not in lists:
                    lists.append(found.group(1))
        if lists:
            out.append({"id": m["id"], "title": m["title"]["english"] or m["title"]["romaji"], "episodes": m["episodes"], "format": m["format"], "lists": lists})
    if not data["pageInfo"]["hasNextPage"]:
        break
    time.sleep(2.2)
Path(__file__).with_name("shows.json").write_text(json.dumps(out))
print(len(out), "shows with playlists,", sum(len(s["lists"]) for s in out), "playlists")
