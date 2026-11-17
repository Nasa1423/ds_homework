import json
import logging
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer

MAX_NUMBER = 1_000_000
logging.basicConfig(filename="application.log", level=logging.ERROR)


def process_number(number):
    with database:
        duplicate = database.execute(
            "SELECT 1 FROM history WHERE number = ? LIMIT 1", (number,)
        ).fetchone()
        predecessor = database.execute(
            "SELECT 1 FROM history WHERE number = ? AND outcome = 'OK' LIMIT 1",
            (number + 1,),
        ).fetchone()
        if duplicate:
            outcome = "DUPLICATE_NUMBER"
        elif predecessor:
            outcome = "PREDECESSOR_OF_PROCESSED"
        else:
            outcome = "OK"
        database.execute("INSERT INTO history VALUES (?, ?)", (number, outcome))
    if outcome != "OK":
        logging.error("number=%s error=%s", number, outcome)
        return 409, {"error": outcome}
    return 200, {"result": number + 1}


class ApplicationHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length))
            number = data["number"]
            if type(number) is not int or not 0 <= number <= MAX_NUMBER:
                raise ValueError
        except (ValueError, KeyError, TypeError, UnicodeDecodeError):
            status, payload = 400, {"error": "INVALID_NUMBER"}
        else:
            status, payload = process_number(number)
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    database = sqlite3.connect("history.db")
    database.execute(
        "CREATE TABLE IF NOT EXISTS history (number INTEGER NOT NULL, outcome TEXT NOT NULL)"
    )
    try:
        HTTPServer(("127.0.0.1", 38081), ApplicationHandler).serve_forever()
    finally:
        database.close()
