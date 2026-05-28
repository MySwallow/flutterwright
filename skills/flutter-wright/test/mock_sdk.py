#!/usr/bin/env python3
"""Minimal mock of the flutter_wright_sdk control plane for flutter-wright script tests.

  GET  /health             -> 200 "ok"
  POST /navigate, /reset    -> status from env FW_MOCK_STATUS (default 501) + the
                               SDK's real "navigation not configured" body
Usage: mock_sdk.py [port]   # omit or pass 0 => OS picks a free port (no TOCTOU race)
On startup prints the actual bound port (one line) to stdout, then serves forever.
"""
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATUS = int(os.environ.get("FW_MOCK_STATUS", "501"))
NAV_BODY = (
    "navigation not configured — pass navigatorKey or navigationAdapter "
    "to FlutterWright.start() to enable goto/reset"
)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body):
        b = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, "ok")
        if self.path == "/snapshot" or self.path == "/wait_for" or self.path.startswith("/wait_for?"):
            return self._send(200, '- text "mock" [ref=s1]\n')
        return self._send(404, "not found")

    def do_POST(self):
        if self.path in ("/navigate", "/reset", "/tap", "/type", "/scroll", "/long_press"):
            return self._send(STATUS, NAV_BODY)
        return self._send(404, "not found")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = HTTPServer(("127.0.0.1", port), H)
    print(server.server_address[1], flush=True)  # tell the caller the real port
    server.serve_forever()
