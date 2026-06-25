"""FastAPI server for ball detection from Flutter."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from detect_balls import detect_from_array

app = FastAPI(title="Billiards Ball Detector", version="0.1.3")

LOG_PATH = Path(__file__).resolve().parent / "samples" / "out" / "last_detect.json"

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
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


def _log_result(payload: dict) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOG_PATH.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except OSError:
        pass


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "version": "0.1.3"}


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
    try:
        corner_points = json.loads(corners)
        if len(corner_points) != 4:
            raise ValueError("need 4 corners")
    except (json.JSONDecodeError, TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"invalid corners: {exc}") from exc

    raw = await image.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty image upload")

    arr = np.frombuffer(raw, dtype=np.uint8)
    bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if bgr is None:
        raise HTTPException(status_code=400, detail="cannot decode image bytes")

    rw = _parse_ref(ref_width)
    rh = _parse_ref(ref_height)

    try:
        result = detect_from_array(
            bgr,
            corner_points,
            source_name=Path(image.filename or "photo.jpg").name,
            ref_width=rw,
            ref_height=rh,
            upload_bytes=len(raw),
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    _log_result(result)
    return result
