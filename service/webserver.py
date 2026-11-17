import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer


class WebHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        connection = http.client.HTTPConnection("127.0.0.1", 38081)
        connection.request("POST", "/increment", body, {"Content-Type": "application/json"})
        response = connection.getresponse()
        status, body = response.status, response.read()
        connection.close()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 38080), WebHandler).serve_forever()
