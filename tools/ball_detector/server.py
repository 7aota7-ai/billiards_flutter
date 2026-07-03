"""FastAPI server for ball detection from Flutter."""

from __future__ import annotations

import json
import logging
import os
import time
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from detect_balls import detect_from_array

APP_VERSION = "0.1.7"

# --- Config (env overrides for Cloud Run) ---
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))
RATE_LIMIT_REQUESTS = int(os.getenv("RATE_LIMIT_REQUESTS", "30"))
RATE_LIMIT_WINDOW_SEC = int(os.getenv("RATE_LIMIT_WINDOW_SEC", "60"))
LOG_DETECT_RESULTS = os.getenv("LOG_DETECT_RESULTS", "false").lower() in (
    "1",
    "true",
    "yes",
)

_DEFAULT_CORS = (
    "https://7aota7-ai.github.io,"
    "http://localhost:8080,"
    "http://127.0.0.1:8080,"
    "http://localhost:8765,"
    "http://127.0.0.1:8765"
)
CORS_ORIGINS = [
    o.strip()
    for o in os.getenv("CORS_ORIGINS", _DEFAULT_CORS).split(",")
    if o.strip()
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("ball_detector")

app = FastAPI(title="Billiards Ball Detector", version=APP_VERSION)


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Per-IP sliding window (per instance; see README for scale-out notes)."""

    def __init__(self, app, max_requests: int, window_sec: int) -> None:
        super().__init__(app)
        self.max_requests = max_requests
        self.window_sec = window_sec
        self._hits: dict[str, list[float]] = defaultdict(list)

    async def dispatch(self, request: Request, call_next):
        if request.url.path not in ("/detect",):
            return await call_next(request)

        client = request.client.host if request.client else "unknown"
        now = time.monotonic()
        window_start = now - self.window_sec
        hits = [t for t in self._hits[client] if t > window_start]
        if len(hits) >= self.max_requests:
            logger.warning("rate_limit client=%s path=%s", client, request.url.path)
            return JSONResponse(
                status_code=429,
                content={"detail": "rate limit exceeded; retry later"},
            )
        hits.append(now)
        self._hits[client] = hits
        return await call_next(request)


app.add_middleware(RateLimitMiddleware, max_requests=RATE_LIMIT_REQUESTS, window_sec=RATE_LIMIT_WINDOW_SEC)
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    # flutter run -d chrome uses a random localhost port (not only :8080).
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


def _parse_ref(value: str | None) -> float | None:
    if value is None or value.strip() == "":
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    return parsed if parsed > 0 else None


def _log_detect_summary(
    *,
    upload_bytes: int,
    ball_count: int,
    duration_ms: float,
    source_name: str,
) -> None:
    """Log metadata only — never image bytes or full detection payload."""
    logger.info(
        "detect ok source=%s upload_bytes=%d ball_count=%d duration_ms=%.0f",
        source_name,
        upload_bytes,
        ball_count,
        duration_ms,
    )
    if LOG_DETECT_RESULTS:
        logger.debug(
            "detect debug ball_count=%d (set LOG_DETECT_RESULTS=false in prod)",
            ball_count,
        )


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "version": APP_VERSION,
        "git_sha": os.getenv("GIT_SHA", "unknown"),
    }


@app.post("/detect")
async def detect(
    image: UploadFile = File(...),
    corners: str = Form(...),
    ref_width: str | None = Form(None),
    ref_height: str | None = Form(None),
) -> dict:
    """
    Detect balls from a table photo.

    `corners`: JSON [[x,y], ...] normalized 0–1 (Flutter display coords) or pixels.
    `ref_width` / `ref_height`: Flutter decode size (optional, for EXIF/rescale fix).
    """
    started = time.perf_counter()

    try:
        corner_points = json.loads(corners)
        if len(corner_points) != 4:
            raise ValueError("need 4 corners")
    except (json.JSONDecodeError, TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"invalid corners: {exc}") from exc

    raw = await image.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty image upload")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"image too large (max {MAX_UPLOAD_BYTES} bytes)",
        )

    arr = np.frombuffer(raw, dtype=np.uint8)
    bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if bgr is None:
        raise HTTPException(status_code=400, detail="cannot decode image bytes")

    rw = _parse_ref(ref_width)
    rh = _parse_ref(ref_height)
    source_name = Path(image.filename or "photo.jpg").name

    try:
        result = detect_from_array(
            bgr,
            corner_points,
            source_name=source_name,
            ref_width=rw,
            ref_height=rh,
            upload_bytes=len(raw),
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    ball_count = int(result.get("meta", {}).get("ball_count", 0))
    duration_ms = (time.perf_counter() - started) * 1000
    _log_detect_summary(
        upload_bytes=len(raw),
        ball_count=ball_count,
        duration_ms=duration_ms,
        source_name=source_name,
    )
    return result
