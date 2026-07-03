#!/usr/bin/env python3
"""Billiard ball detection: 4-point homography + Hough circles + color hints."""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

# Standard pool table playing surface aspect ratio (length : width = 2 : 1).
WARP_WIDTH = 2000
WARP_HEIGHT = 1000

# Post-filter defaults (felt interior, dedupe, cap).
FILTER_EDGE_MARGIN = 0.05
FILTER_MAX_BALLS = 15
FILTER_MIN_SEP_FACTOR = 2.0
MIN_BALL_SCORE = 2.2
EXPECTED_BALL_RADIUS_RATIO = 0.0225  # ~57 mm dia on 127 cm playing width
DETECTOR_VERSION = "0.1.6"

CORNER_LABELS = ("top-left", "top-right", "bottom-right", "bottom-left")


@dataclass
class DetectedBall:
    id: int | None
    x: float
    y: float
    color: str
    radius_px: float
    score: float = 0.0

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "x": round(self.x, 4),
            "y": round(self.y, 4),
            "color": self.color,
        }


def _order_corners(pts: list[list[float]]) -> np.ndarray:
    """Order 4 points as TL, TR, BR, BL regardless of input order."""
    arr = np.array(pts, dtype=np.float32)
    if arr.shape != (4, 2):
        raise ValueError("corners must be 4 (x, y) pairs")
    s = arr.sum(axis=1)
    diff = np.diff(arr, axis=1).reshape(-1)
    tl = arr[np.argmin(s)]
    br = arr[np.argmax(s)]
    tr = arr[np.argmin(diff)]
    bl = arr[np.argmax(diff)]
    return np.array([tl, tr, br, bl], dtype=np.float32)


def warp_felt(image: np.ndarray, corners: list[list[float]]) -> tuple[np.ndarray, np.ndarray]:
    src = _order_corners(corners)
    dst = np.float32(
        [
            [0, 0],
            [WARP_WIDTH - 1, 0],
            [WARP_WIDTH - 1, WARP_HEIGHT - 1],
            [0, WARP_HEIGHT - 1],
        ]
    )
    matrix = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(image, matrix, (WARP_WIDTH, WARP_HEIGHT))
    return warped, matrix


def _sample_annulus_hsv(
    hsv: np.ndarray,
    x: int,
    y: int,
    r: int,
    *,
    sample_radius: float = 0.55,
) -> np.ndarray:
    """Sample HSV on a ball surface ring (avoids center glare)."""
    h, w = hsv.shape[:2]
    rr = max(2, int(r * sample_radius))
    samples: list[np.ndarray] = []
    for angle in range(0, 360, 30):
        rad = math.radians(angle)
        sx = int(x + math.cos(rad) * rr)
        sy = int(y + math.sin(rad) * rr)
        if 0 <= sx < w and 0 <= sy < h:
            samples.append(hsv[sy, sx])
    if not samples:
        inner = max(2, int(r * 0.35))
        x0, x1 = max(0, x - inner), min(w, x + inner)
        y0, y1 = max(0, y - inner), min(h, y + inner)
        patch = hsv[y0:y1, x0:x1].reshape(-1, 3)
        return patch
    return np.array(samples, dtype=np.uint8)


def _patch_gray_std(bgr: np.ndarray, x: int, y: int, r: int) -> float:
    h, w = bgr.shape[:2]
    inner = max(3, int(r * 0.65))
    x0, x1 = max(0, x - inner), min(w, x + inner)
    y0, y1 = max(0, y - inner), min(h, y + inner)
    patch = bgr[y0:y1, x0:x1]
    if patch.size == 0:
        return 0.0
    gray = cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY)
    return float(np.std(gray))


def _is_glare_patch(pixels: np.ndarray, *, texture_std: float = 0.0) -> bool:
    """Specular highlight on bare felt — bright, low sat, low texture."""
    if pixels.size == 0:
        return False
    s_med = float(np.median(pixels[:, 1]))
    v_med = float(np.median(pixels[:, 2]))
    if v_med <= 205 or s_med >= 45:
        return False
    # White balls also look bright/low-sat but have edge texture.
    if texture_std > 14.0:
        return False
    return True


def _edge_ring_score(gray: np.ndarray, cx: int, cy: int, r: int) -> float:
    """Circular edge strength — works for same-hue balls on felt (e.g. blue on blue)."""
    h, w = gray.shape[:2]
    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    mag = cv2.magnitude(gx, gy)
    hits = 0.0
    total = 0
    for angle in range(0, 360, 20):
        rad = math.radians(angle)
        sx = int(cx + math.cos(rad) * r * 0.85)
        sy = int(cy + math.sin(rad) * r * 0.85)
        if 0 <= sx < w and 0 <= sy < h:
            total += 1
            hits += float(mag[sy, sx])
    if total == 0:
        return 0.0
    return hits / total


def _hue_to_color(hue: float, sat: float, val: float) -> str:
    if val < 55:
        return "black"
    if sat < 40 and val > 150:
        return "white"
    if sat < 50 and val > 115:
        return "white"
    if hue < 12 or hue >= 168:
        return "red" if val > 90 else "maroon"
    if hue < 22:
        return "orange"
    if hue < 38:
        return "yellow"
    if hue < 78:
        return "green"
    if hue < 105:
        return "blue"
    if hue < 135:
        return "purple"
    if hue < 168:
        return "red"
    return "unknown"


def _classify_color(bgr: np.ndarray, x: int, y: int, r: int) -> str:
    """HSV color label from annular samples (robust to center glare)."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    pixels = _sample_annulus_hsv(hsv, x, y, r)
    if pixels.size == 0:
        return "unknown"

    usable = pixels[(pixels[:, 2] > 35) & ~((pixels[:, 2] > 220) & (pixels[:, 1] < 35))]
    if len(usable) == 0:
        return "unknown"

    hues = usable[:, 0].astype(np.float32)
    s_med = float(np.median(usable[:, 1]))
    v_med = float(np.median(usable[:, 2]))
    h_med = float(np.median(hues))

    # Stripe balls: hue jumps around the ring (white + colored stripe).
    if len(hues) >= 4 and float(np.std(hues)) > 22 and s_med > 35:
        low_sat = usable[usable[:, 1] < 55]
        high_sat = usable[usable[:, 1] >= 55]
        if len(low_sat) >= 2 and len(high_sat) >= 2:
            return _hue_to_color(float(np.median(high_sat[:, 0])), s_med, v_med)

    return _hue_to_color(h_med, s_med, v_med)


def _cloth_masks(hsv: np.ndarray) -> tuple[np.ndarray, np.ndarray, bool]:
    """Build felt/non-felt masks and detect blue vs green cloth."""
    blue_felt = cv2.inRange(hsv, np.array([85, 35, 25]), np.array([145, 255, 255]))
    green_felt = cv2.inRange(hsv, np.array([35, 30, 25]), np.array([90, 255, 255]))

    h, w = hsv.shape[:2]
    y0, y1 = h // 4, (3 * h) // 4
    x0, x1 = w // 4, (3 * w) // 4
    blue_ratio = float(np.mean(blue_felt[y0:y1, x0:x1] > 0))
    green_ratio = float(np.mean(green_felt[y0:y1, x0:x1] > 0))
    is_blue_cloth = blue_ratio > 0.5 and blue_ratio > green_ratio
    is_green_cloth = green_ratio > 0.45 and green_ratio > blue_ratio

    if is_blue_cloth:
        felt = blue_felt
    elif is_green_cloth:
        felt = green_felt
    else:
        felt = cv2.bitwise_or(blue_felt, green_felt)

    felt = cv2.morphologyEx(felt, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    non_felt = cv2.bitwise_not(felt)
    non_felt = cv2.morphologyEx(non_felt, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    non_felt = cv2.morphologyEx(non_felt, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    return felt, non_felt, is_blue_cloth


def _expected_ball_radius(w: int) -> float:
    return max(12.0, w * EXPECTED_BALL_RADIUS_RATIO)


def _ring_non_felt_ratio(
    non_felt: np.ndarray,
    cx: int,
    cy: int,
    r: int,
) -> float:
    h, w = non_felt.shape[:2]
    hits = 0
    total = 0
    for angle in range(0, 360, 30):
        rad = math.radians(angle)
        sx = int(cx + math.cos(rad) * r * 0.65)
        sy = int(cy + math.sin(rad) * r * 0.65)
        if 0 <= sx < w and 0 <= sy < h:
            total += 1
            if non_felt[sy, sx] != 0:
                hits += 1
    return hits / total if total else 0.0


def _score_ball_candidate(
    warped_bgr: np.ndarray,
    felt: np.ndarray,
    non_felt: np.ndarray,
    cx: int,
    cy: int,
    r: int,
    *,
    gray: np.ndarray | None = None,
) -> float:
    h, w = warped_bgr.shape[:2]
    if cx < 0 or cy < 0 or cx >= w or cy >= h:
        return 0.0

    if gray is None:
        gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)

    hsv = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2HSV)
    annulus = _sample_annulus_hsv(hsv, cx, cy, r)
    texture_std = _patch_gray_std(warped_bgr, cx, cy, r)
    if _is_glare_patch(annulus, texture_std=texture_std):
        return 0.0

    expected_r = _expected_ball_radius(w)
    size_score = max(0.0, 1.0 - abs(r - expected_r) / max(expected_r, 1.0))

    usable = annulus[annulus[:, 2] > 35]
    sat_med = float(np.median(usable[:, 1])) if len(usable) else 0.0
    sat_score = min(1.0, sat_med / 130.0)

    ring_ratio = _ring_non_felt_ratio(non_felt, cx, cy, r)
    ring_score = min(1.0, ring_ratio / 0.45)

    edge_strength = _edge_ring_score(gray, cx, cy, r)
    edge_score = min(1.0, edge_strength / 55.0)

    # Same-hue ball on felt (blue on blue): weak non-felt ring but strong circular edge.
    if ring_score < 0.35 and edge_score < 0.35:
        return 0.0

    color = _classify_color(warped_bgr, cx, cy, r)
    color_score = 0.2 if color == "unknown" else 0.45

    edge = min(cx / w, 1.0 - cx / w, cy / h, 1.0 - cy / h)
    edge_margin_score = min(1.0, edge / 0.06)

    combined_ring = max(ring_score, edge_score * 0.95)

    return (
        size_score * 1.6
        + sat_score * 1.0
        + combined_ring * 2.4
        + color_score
        + edge_margin_score * 0.35
        + min(0.5, texture_std / 40.0)
    )


def _hough_circle_candidates(
    source: np.ndarray,
    *,
    min_radius: int,
    max_radius: int,
    min_dist: int,
    param2_values: list[int],
    param1: int = 100,
) -> list[tuple[int, int, int]]:
    candidates: list[tuple[int, int, int]] = []
    for p2 in param2_values:
        circles = cv2.HoughCircles(
            source,
            cv2.HOUGH_GRADIENT,
            dp=1.2,
            minDist=min_dist,
            param1=param1,
            param2=p2,
            minRadius=min_radius,
            maxRadius=max_radius,
        )
        if circles is not None:
            candidates.extend(np.round(circles[0]).astype(int).tolist())
    return candidates


def _balls_from_candidates(
    warped_bgr: np.ndarray,
    felt: np.ndarray,
    non_felt: np.ndarray,
    gray: np.ndarray,
    candidates: list[tuple[int, int, int]],
    *,
    w: int,
    h: int,
    min_radius: int,
    max_radius: int,
    edge_margin: float,
    min_score: float,
) -> list[DetectedBall]:
    margin = max_radius + 6
    detected: list[DetectedBall] = []
    seen: set[tuple[int, int, int]] = set()
    for cx, cy, r in candidates:
        key = (cx // 4, cy // 4, r // 3)
        if key in seen:
            continue
        seen.add(key)

        if cx < margin or cy < margin or cx > w - margin or cy > h - margin:
            continue
        if cy < 0 or cy >= h or cx < 0 or cx >= w:
            continue

        nx, ny = cx / w, cy / h
        if nx < edge_margin or nx > 1.0 - edge_margin or ny < edge_margin or ny > 1.0 - edge_margin:
            continue

        score = _score_ball_candidate(
            warped_bgr, felt, non_felt, cx, cy, r, gray=gray
        )
        if score < min_score:
            continue

        color = _classify_color(warped_bgr, cx, cy, r)
        detected.append(
            DetectedBall(
                id=None,
                x=float(nx),
                y=float(ny),
                color=color,
                radius_px=float(r),
                score=score,
            )
        )
    return detected


def detect_balls(
    warped_bgr: np.ndarray,
    *,
    min_radius: int | None = None,
    max_radius: int | None = None,
    hough_param2: int = 26,
    edge_margin: float = 0.06,
    min_score: float = MIN_BALL_SCORE,
) -> list[DetectedBall]:
    """Detect balls on a top-down warped felt image."""
    h, w = warped_bgr.shape[:2]
    expected_r = _expected_ball_radius(w)
    if min_radius is None:
        min_radius = max(8, int(expected_r * 0.65))
    if max_radius is None:
        max_radius = max(min_radius + 6, int(expected_r * 1.45))

    gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(gray)
    gray = cv2.GaussianBlur(gray, (7, 7), 1.5)

    hsv = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2HSV)
    sat = hsv[:, :, 1]
    sat = cv2.GaussianBlur(sat, (7, 7), 1.5)
    felt, non_felt, _is_blue_cloth = _cloth_masks(hsv)

    masked = cv2.bitwise_and(gray, gray, mask=non_felt)
    masked_sat = cv2.bitwise_and(sat, sat, mask=non_felt)

    param2_values = sorted(
        {hough_param2, max(16, hough_param2 - 4), max(12, hough_param2 - 8), max(10, hough_param2 - 12)},
        reverse=True,
    )
    candidates: list[tuple[int, int, int]] = []
    candidates.extend(
        _hough_circle_candidates(
            masked,
            min_radius=min_radius,
            max_radius=max_radius,
            min_dist=int(min_radius * 1.8),
            param2_values=param2_values[:3],
        )
    )
    candidates.extend(
        _hough_circle_candidates(
            masked_sat,
            min_radius=min_radius,
            max_radius=max_radius,
            min_dist=int(min_radius * 1.8),
            param2_values=param2_values[1:],
        )
    )
    # Color-agnostic pass — catches blue-on-blue and white balls missed by felt mask.
    candidates.extend(
        _hough_circle_candidates(
            gray,
            min_radius=min_radius,
            max_radius=max_radius,
            min_dist=int(min_radius * 1.6),
            param2_values=param2_values,
            param1=80,
        )
    )

    # Contour fallback: only near-circular blobs on non-felt mask.
    contours, _ = cv2.findContours(non_felt, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for cnt in contours:
        area = cv2.contourArea(cnt)
        r_min = math.pi * min_radius * min_radius * 0.65
        r_max = math.pi * max_radius * max_radius * 1.35
        if area < r_min or area > r_max:
            continue
        perimeter = cv2.arcLength(cnt, True)
        if perimeter <= 0:
            continue
        circularity = 4.0 * math.pi * area / (perimeter * perimeter)
        if circularity < 0.68:
            continue
        (cx, cy), radius = cv2.minEnclosingCircle(cnt)
        if min_radius <= radius <= max_radius:
            candidates.append((int(cx), int(cy), int(radius)))

    margin = max_radius + 6
    detected = _balls_from_candidates(
        warped_bgr,
        felt,
        non_felt,
        gray,
        candidates,
        w=w,
        h=h,
        min_radius=min_radius,
        max_radius=max_radius,
        edge_margin=edge_margin,
        min_score=min_score,
    )

    return _dedupe_balls(detected, min_dist=min_radius * 1.8)


def _ball_quality(ball: DetectedBall) -> float:
    """Higher = more likely a real ball (score + size + distance from cushion)."""
    if ball.score > 0:
        return ball.score
    edge = min(ball.x, 1.0 - ball.x, ball.y, 1.0 - ball.y)
    return ball.radius_px * (0.35 + edge * 4.0)


def filter_detected_balls(
    balls: list[DetectedBall],
    warped_bgr: np.ndarray | None = None,
    *,
    edge_margin: float = FILTER_EDGE_MARGIN,
    max_balls: int = FILTER_MAX_BALLS,
    min_sep_factor: float = FILTER_MIN_SEP_FACTOR,
) -> tuple[list[DetectedBall], dict[str, Any]]:
    """
    Keep felt-interior detections, drop cushion clutter, dedupe by distance, cap count.
    """
    if not balls:
        return balls, {"raw_count": 0, "filter_reasons": {}}

    h, w = (
        warped_bgr.shape[:2]
        if warped_bgr is not None
        else (WARP_HEIGHT, WARP_WIDTH)
    )
    non_felt: np.ndarray | None = None
    gray: np.ndarray | None = None
    if warped_bgr is not None:
        hsv = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2HSV)
        _, non_felt, _ = _cloth_masks(hsv)
        gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)

    reasons: dict[str, int] = {"edge": 0, "felt": 0, "dedupe": 0, "cap": 0}
    interior: list[DetectedBall] = []

    for ball in balls:
        if (
            ball.x < edge_margin
            or ball.x > 1.0 - edge_margin
            or ball.y < edge_margin
            or ball.y > 1.0 - edge_margin
        ):
            reasons["edge"] += 1
            continue

        if non_felt is not None and gray is not None:
            cx, cy = int(ball.x * w), int(ball.y * h)
            if not (0 <= cx < w and 0 <= cy < h):
                reasons["felt"] += 1
                continue
            r_px = max(2, int(ball.radius_px))
            ring_hits = 0
            ring_total = 0
            for angle in range(0, 360, 45):
                rad = math.radians(angle)
                sx = int(cx + math.cos(rad) * r_px * 0.65)
                sy = int(cy + math.sin(rad) * r_px * 0.65)
                if 0 <= sx < w and 0 <= sy < h:
                    ring_total += 1
                    if non_felt[sy, sx] != 0:
                        ring_hits += 1
            ring_ratio = ring_hits / ring_total if ring_total else 0.0
            edge_strength = _edge_ring_score(gray, cx, cy, r_px)
            if ring_ratio < 0.30 and edge_strength < 28.0:
                reasons["felt"] += 1
                continue

        interior.append(ball)

    raw_count = len(interior)
    avg_r = sum(b.radius_px for b in interior) / raw_count if interior else 18.0
    min_dist = max(14.0, avg_r * min_sep_factor)

    kept: list[DetectedBall] = []
    for ball in sorted(interior, key=_ball_quality, reverse=True):
        bx, by = ball.x * w, ball.y * h
        if any(
            (bx - k.x * w) ** 2 + (by - k.y * h) ** 2 < min_dist**2 for k in kept
        ):
            reasons["dedupe"] += 1
            continue
        kept.append(ball)

    if len(kept) > max_balls:
        reasons["cap"] = len(kept) - max_balls
        kept = sorted(kept, key=_ball_quality, reverse=True)[:max_balls]

    return kept, {
        "raw_count": len(balls),
        "after_interior": raw_count,
        "filter_reasons": reasons,
        "max_balls": max_balls,
        "edge_margin": edge_margin,
    }


def _dedupe_balls(balls: list[DetectedBall], min_dist: float) -> list[DetectedBall]:
    if not balls:
        return balls
    kept: list[DetectedBall] = []
    for ball in sorted(balls, key=_ball_quality, reverse=True):
        bx = ball.x * WARP_WIDTH
        by = ball.y * WARP_HEIGHT
        if all((bx - k.x * WARP_WIDTH) ** 2 + (by - k.y * WARP_HEIGHT) ** 2 >= min_dist**2 for k in kept):
            kept.append(ball)
    return kept


def _pixel_corners(
    corners: list[list[float]],
    width: int,
    height: int,
    *,
    ref_width: float | None = None,
    ref_height: float | None = None,
) -> list[list[float]]:
    """Map normalized or pixel corners to OpenCV image pixels."""
    vals = [v for pt in corners for v in pt]
    if not vals:
        return corners

    if max(vals) <= 1.0 and min(vals) >= 0.0:
        rw = ref_width if ref_width and ref_width > 0 else width
        rh = ref_height if ref_height and ref_height > 0 else height
        flutter_px = [[pt[0] * rw, pt[1] * rh] for pt in corners]
        if abs(rw - width) < 1.5 and abs(rh - height) < 1.5:
            return flutter_px
        sx = width / rw
        sy = height / rh
        return [[p[0] * sx, p[1] * sy] for p in flutter_px]

    if ref_width and ref_height and ref_width > 0 and ref_height > 0:
        if abs(ref_width - width) > 1.5 or abs(ref_height - height) > 1.5:
            sx = width / ref_width
            sy = height / ref_height
            return [[pt[0] * sx, pt[1] * sy] for pt in corners]

    return corners


def _corner_span_ok(pixel_corners: list[list[float]], width: int, height: int) -> bool:
    xs = [p[0] for p in pixel_corners]
    ys = [p[1] for p in pixel_corners]
    span_x = max(xs) - min(xs)
    span_y = max(ys) - min(ys)
    return span_x > width * 0.15 and span_y > height * 0.15


def detect_balls_bare(warped_bgr: np.ndarray) -> list[DetectedBall]:
    """Last-resort Hough on full grayscale (no felt mask)."""
    h, w = warped_bgr.shape[:2]
    expected_r = _expected_ball_radius(w)
    min_radius = max(8, int(expected_r * 0.6))
    max_radius = max(min_radius + 6, int(expected_r * 1.5))
    gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(gray)
    gray = cv2.GaussianBlur(gray, (5, 5), 1.2)
    hsv = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2HSV)
    felt, non_felt, _ = _cloth_masks(hsv)

    candidates: list[tuple[int, int, int]] = []
    for p2 in (32, 26, 20, 16):
        circles = cv2.HoughCircles(
            gray,
            cv2.HOUGH_GRADIENT,
            dp=1.2,
            minDist=int(min_radius * 1.8),
            param1=80,
            param2=p2,
            minRadius=min_radius,
            maxRadius=max_radius,
        )
        if circles is not None:
            candidates.extend(np.round(circles[0]).astype(int).tolist())

    margin = max_radius + 4
    detected: list[DetectedBall] = []
    seen: set[tuple[int, int, int]] = set()
    for cx, cy, r in candidates:
        key = (cx // 4, cy // 4, r // 3)
        if key in seen:
            continue
        seen.add(key)
        if cx < margin or cy < margin or cx > w - margin or cy > h - margin:
            continue
        nx, ny = cx / w, cy / h
        if nx < 0.05 or nx > 0.95 or ny < 0.05 or ny > 0.95:
            continue
        score = _score_ball_candidate(warped_bgr, felt, non_felt, cx, cy, r, gray=gray)
        if score < MIN_BALL_SCORE - 0.8:
            continue
        color = _classify_color(warped_bgr, cx, cy, r)
        detected.append(
            DetectedBall(
                id=None,
                x=float(nx),
                y=float(ny),
                color=color,
                radius_px=float(r),
                score=score,
            )
        )
    return _dedupe_balls(detected, min_dist=min_radius * 1.8)


def _merge_detected_balls(*groups: list[DetectedBall]) -> list[DetectedBall]:
    merged: list[DetectedBall] = []
    for group in groups:
        for ball in group:
            bx, by = ball.x * WARP_WIDTH, ball.y * WARP_HEIGHT
            duplicate = False
            for i, kept in enumerate(merged):
                kx, ky = kept.x * WARP_WIDTH, kept.y * WARP_HEIGHT
                dist = math.hypot(bx - kx, by - ky)
                min_r = max(12.0, min(ball.radius_px, kept.radius_px) * 1.6)
                if dist < min_r:
                    duplicate = True
                    if ball.score > kept.score:
                        merged[i] = ball
                    break
            if not duplicate:
                merged.append(ball)
    return merged


def detect_from_array(
    image: np.ndarray,
    corners: list[list[float]],
    *,
    source_name: str = "upload",
    debug_dir: Path | None = None,
    ref_width: float | None = None,
    ref_height: float | None = None,
    upload_bytes: int | None = None,
) -> dict[str, Any]:
    if image is None or image.size == 0:
        raise FileNotFoundError("cannot decode image")

    h, w = image.shape[:2]
    pixel_corners = _pixel_corners(
        corners,
        w,
        h,
        ref_width=ref_width,
        ref_height=ref_height,
    )
    corners_ok = _corner_span_ok(pixel_corners, w, h)
    warped, _ = warp_felt(image, pixel_corners)
    strict = detect_balls(warped)
    relaxed = detect_balls(
        warped,
        hough_param2=18,
        edge_margin=0.04,
        min_score=MIN_BALL_SCORE - 0.5,
    )
    bare = detect_balls_bare(warped)
    balls = _merge_detected_balls(strict, relaxed, bare)
    detect_mode = "ensemble"
    if len(strict) >= len(balls):
        detect_mode = "felt_mask"
    elif len(relaxed) >= len(bare):
        detect_mode = "relaxed"
    else:
        detect_mode = "bare_hough"

    raw_count = len(balls)
    balls, filter_meta = filter_detected_balls(balls, warped)

    hsv = cv2.cvtColor(warped, cv2.COLOR_BGR2HSV)
    _, _, is_blue_cloth = _cloth_masks(hsv)

    if debug_dir is not None:
        debug_dir.mkdir(parents=True, exist_ok=True)
        overlay = warped.copy()
        for ball in balls:
            cx = int(ball.x * WARP_WIDTH)
            cy = int(ball.y * WARP_HEIGHT)
            r = int(ball.radius_px)
            cv2.circle(overlay, (cx, cy), r, (0, 255, 0), 2)
            cv2.putText(
                overlay,
                ball.color,
                (cx - r, cy - r - 4),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.45,
                (255, 255, 255),
                1,
                cv2.LINE_AA,
            )
        cv2.imwrite(str(debug_dir / "warped_overlay.png"), overlay)

    return {
        "balls": [b.to_json() for b in balls],
        "meta": {
            "source_image": source_name,
            "upload_bytes": upload_bytes,
            "image_size": [w, h],
            "ref_size": [ref_width, ref_height] if ref_width and ref_height else None,
            "warp_size": [WARP_WIDTH, WARP_HEIGHT],
            "corners": corners,
            "corners_px": pixel_corners,
            "corners_ok": corners_ok,
            "corner_order": list(CORNER_LABELS),
            "ball_count": len(balls),
            "ball_count_raw": raw_count,
            "filter": filter_meta,
            "detect_mode": detect_mode,
            "is_blue_cloth": is_blue_cloth,
            "detector_version": DETECTOR_VERSION,
        },
    }


def detect_from_image(
    image_path: str | Path,
    corners: list[list[float]],
    *,
    debug_dir: Path | None = None,
) -> dict[str, Any]:
    image = cv2.imread(str(image_path))
    if image is None:
        raise FileNotFoundError(f"cannot read image: {image_path}")

    result = detect_from_array(
        image,
        corners,
        source_name=str(Path(image_path).name),
        debug_dir=debug_dir,
    )
    return result


def pick_corners_interactive(image_path: str | Path) -> list[list[float]]:
    """Click 4 felt inner corners: TL → TR → BR → BL."""
    image = cv2.imread(str(image_path))
    if image is None:
        raise FileNotFoundError(f"cannot read image: {image_path}")

    points: list[tuple[int, int]] = []
    window = "Pick 4 felt corners (TL, TR, BR, BL) — ESC when done, R to reset"

    def on_mouse(event: int, x: int, y: int, _flags: int, _param: Any) -> None:
        if event != cv2.EVENT_LBUTTONDOWN or len(points) >= 4:
            return
        points.append((x, y))

    cv2.namedWindow(window, cv2.WINDOW_NORMAL)
    cv2.setMouseCallback(window, on_mouse)

    while True:
        canvas = image.copy()
        for i, (x, y) in enumerate(points):
            cv2.circle(canvas, (x, y), 8, (0, 255, 0), -1)
            cv2.putText(
                canvas,
                CORNER_LABELS[i],
                (x + 10, y - 10),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 0),
                2,
            )
        if len(points) == 4:
            pts = np.array(points, dtype=np.int32)
            cv2.polylines(canvas, [pts], True, (0, 255, 255), 2)
        cv2.imshow(window, canvas)
        key = cv2.waitKey(30) & 0xFF
        if key == 27 and len(points) == 4:
            break
        if key == ord("r"):
            points.clear()

    cv2.destroyAllWindows()
    if len(points) != 4:
        raise RuntimeError("need exactly 4 corner points")
    return [[float(x), float(y)] for x, y in points]


def _load_corners(path: Path) -> list[list[float]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "corners" in data:
        data = data["corners"]
    corners = [[float(p[0]), float(p[1])] for p in data]
    if len(corners) != 4:
        raise ValueError("corners JSON must contain exactly 4 points")
    return corners


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Detect billiard balls from a table photo.")
    parser.add_argument("--image", "-i", required=True, help="Input photo path")
    parser.add_argument("--corners", "-c", help="JSON file with 4 corner points [[x,y], ...]")
    parser.add_argument("--pick-corners", action="store_true", help="Interactive corner picker (OpenCV window)")
    parser.add_argument("--output", "-o", help="Write detection JSON here")
    parser.add_argument("--debug-dir", help="Save warped overlay PNG for inspection")
    args = parser.parse_args(argv)

    image_path = Path(args.image)
    if args.pick_corners:
        corners = pick_corners_interactive(image_path)
    elif args.corners:
        corners = _load_corners(Path(args.corners))
    else:
        parser.error("provide --corners or --pick-corners")

    result = detect_from_image(
        image_path,
        corners,
        debug_dir=Path(args.debug_dir) if args.debug_dir else None,
    )

    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
        print(f"Wrote {args.output} ({result['meta']['ball_count']} balls)")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
