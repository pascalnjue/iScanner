#!/usr/bin/env python3
"""
Scanner Companion — Listens for scanned text from the iOS Scanner app
and types it into whatever field is focused on your Mac.

Usage: python3 scanner_companion.py [--port PORT]

The iOS app sends a POST to http://<mac-ip>:9876/type
with JSON body: {"text": "scanned content"}

The companion uses AppleScript to simulate keystrokes.
"""

import json
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

DEFAULT_PORT = 9876


def type_text(text: str) -> None:
    """Type text into the currently focused input using AppleScript."""
    # Escape backslashes and double quotes for AppleScript string
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')

    script = f'''
    tell application "System Events"
        keystroke "{escaped}"
    end tell
    '''

    try:
        subprocess.run(
            ["osascript", "-e", script],
            check=True,
            capture_output=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Failed to type text: {e.stderr.decode().strip()}", file=sys.stderr)
        raise


class ScannerHandler(BaseHTTPRequestHandler):
    """HTTP handler for receiving scanned text."""

    def do_POST(self) -> None:
        if self.path != "/type":
            self.send_error(404, "Not found — use POST /type")
            return

        # Read the full body
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
            text = data.get("text", "")
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        if not text:
            self.send_error(400, "Missing 'text' field")
            return

        try:
            type_text(text)
            print(f"[OK] Typed: {text[:80]}{'...' if len(text) > 80 else ''}")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        except Exception as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            self.send_error(500, str(e))

    def do_GET(self) -> None:
        """Health check endpoint."""
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "running"}).encode())
        else:
            self.send_error(404)

    def log_message(self, format, *args) -> None:
        """Suppress default log noise; we print our own."""
        pass


def get_local_ip() -> str:
    """Get the primary local IP address."""
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def main() -> None:
    port = DEFAULT_PORT
    if len(sys.argv) > 2 and sys.argv[1] == "--port":
        port = int(sys.argv[2])

    ip = get_local_ip()

    server = HTTPServer(("0.0.0.0", port), ScannerHandler)
    print(f"  Scanner Companion")
    print(f"  Listening on http://{ip}:{port}")
    print(f"  POST scanned text to http://{ip}:{port}/type")
    print(f"  Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()


if __name__ == "__main__":
    main()
