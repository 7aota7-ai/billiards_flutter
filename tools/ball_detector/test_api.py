#!/usr/bin/env python3
"""Quick POST test for /detect."""
import json
import os
import sys
import urllib.request
from pathlib import Path


def main() -> int:
    image_path = Path(sys.argv[1] if len(sys.argv) > 1 else "samples/user_blue_table2.png")
    corners_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    base_url = (
        sys.argv[3]
        if len(sys.argv) > 3
        else os.environ.get("DETECT_API_URL", "http://127.0.0.1:8765")
    ).rstrip("/")
    if corners_path:
        corners = json.loads(corners_path.read_text(encoding="utf-8"))
    else:
        corners = [
        [200 / 968, 130 / 846],
        [780 / 968, 130 / 846],
        [880 / 968, 720 / 846],
        [90 / 968, 720 / 846],
    ]

    img = image_path.read_bytes()
    corners_json = json.dumps(corners)
    ref_w = "968"
    ref_h = "846"
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"

    body = bytearray()
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="corners"\r\n\r\n')
    body.extend(corners_json.encode())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="ref_width"\r\n\r\n')
    body.extend(ref_w.encode())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="ref_height"\r\n\r\n')
    body.extend(ref_h.encode())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(
        b'Content-Disposition: form-data; name="image"; filename="photo.jpg"\r\n'
    )
    body.extend(b"Content-Type: image/jpeg\r\n\r\n")
    body.extend(img)
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())

    req = urllib.request.Request(
        f"{base_url}/detect",
        data=bytes(body),
        method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
    print(json.dumps(data, ensure_ascii=False, indent=2))
    print(f"ball_count={data['meta']['ball_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
