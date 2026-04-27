#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.error

HA_URL     = "PLACEHOLDER_HA_URL"
HA_TOKEN   = "PLACEHOLDER_HA_TOKEN"
HA_SERVICE = "PLACEHOLDER_HA_SERVICE"

title   = sys.argv[1] if len(sys.argv) > 1 else "Drucker"
message = sys.argv[2] if len(sys.argv) > 2 else ""

payload = json.dumps({"title": title, "message": message}).encode()
req = urllib.request.Request(
    f"{HA_URL}/api/services/notify/{HA_SERVICE}",
    data=payload,
    headers={
        "Authorization": f"Bearer {HA_TOKEN}",
        "Content-Type": "application/json"
    }
)
try:
    urllib.request.urlopen(req, timeout=5)
except urllib.error.URLError as e:
    print(f"HA notify failed: {e}", file=sys.stderr)
    sys.exit(1)
