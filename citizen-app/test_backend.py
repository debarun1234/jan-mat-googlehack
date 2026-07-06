import requests, sys

BASE = "https://janmat-backend-w2w3osjaua-el.a.run.app"

tests = [
    ("Health", "GET", f"{BASE}/health", None),
    (
        "Intake text",
        "POST",
        f"{BASE}/intake/text",
        {"text": "Test connection from citizen app"},
    ),
]

for name, method, url, body in tests:
    try:
        if method == "GET":
            r = requests.get(url, timeout=10)
        else:
            r = requests.post(url, json=body, timeout=10)
        print(f"  {name}: {r.status_code} — {r.text[:80]}")
    except Exception as e:
        print(f"  {name}: FAILED — {e}")
