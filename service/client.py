import http.client
import json
import sys

number = int(sys.argv[1])
connection = http.client.HTTPConnection("127.0.0.1", 38080)
connection.request("POST", "/increment", json.dumps({"number": number}),
                   {"Content-Type": "application/json"})
response = connection.getresponse()
print(response.read().decode())
connection.close()
