"""Serves the check page and appends each result to results.jsonl."""
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

os.chdir(Path(__file__).parent)


class Handler(SimpleHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        with open("results.jsonl", "ab") as f:
            f.write(body + b"\n")
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", 8130), Handler).serve_forever()
