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

CORNER_LABELS = ("top-left", "top-right", "bottom-right", "bottom-left")


@dataclass
class DetectedBall:
    id: int | None
    x: float
    y: float
    color: str
    radius_px: float

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


def _classify_color(bgr: np.ndarray, x: int, y: int, r: int) -> str:
    """Rough HSV color label for v1 user confirmation."""
    h, w = bgr.shape[:2]
    inner = max(2, int(r * 0.35))
    x0, x1 = max(0, x - inner), min(w, x + inner)
    y0, y1 = max(0, y - inner), min(h, y + inner)
    patch = bgr[y0:y1, x0:x1]
    if patch.size == 0:
        return "unknown"

    hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)
    pixels = hsv.reshape(-1, 3)
    # Ignore very dark shadow pixels under the ball.
    bright = pixels[pixels[:, 2] > 35]
    if len(bright) == 0:
        return "unknown"
    h_med = float(np.median(bright[:, 0]))
    s_med = float(np.median(bright[:, 1]))
    v_med = float(np.median(bright[:, 2]))

    if v_med < 55:
        return "black"
    if s_med < 40 and v_med > 150:
        return "white"
    if s_med < 50 and v_med > 115:
        return "white"

    hue = h_med
    if hue < 12 or hue >= 168:
        return "red" if v_med > 90 else "maroon"
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


def _cloth_masks(hsv: np.ndarray) -> tuple[np.ndarray, np.ndarray, bool]:
    """Build felt/non-felt masks and detect blue vs green cloth."""
    blue_felt = cv2.inRange(hsv, np.array([85, 35, 25]), np.array([145, 255, 255]))
    green_felt = cv2.inRange(hsv, np.array([35, 30, 25]), np.array([90, 255, 255]))

    h, w = hsv.shape[:2]
    y0, y1 = h // 4, (3 * h) // 4
    x0, x1 = w // 4, (3 * w) // 4
    blue_ratio = float(np.mean(blue_felt[y0:y1, x0:x1] > 0))
    green_ratio = float(np.mean(green_felt[y0:y1, x0:x1] > 0))
    # Strong blue cloth: ball centers sit on non-felt pixels.
    # Threshold 0.5 — real blue tables are often ~0.65–0.98 (0.9 was too strict).
    is_blue_cloth = blue_ratio > 0.5 and blue_ratio > green_ratio

    felt = blue_felt
    non_felt = cv2.bitwise_not(felt)
    non_felt = cv2.morphologyEx(non_felt, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    non_felt = cv2.morphologyEx(non_felt, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    return felt, non_felt, is_blue_cloth


def detect_balls(
    warped_bgr: np.ndarray,
    *,
    min_radius: int | None = None,
    max_radius: int | None = None,
    hough_param2: int = 24,
    edge_margin: float = 0.03,
) -> list[DetectedBall]:
    """Detect balls on a top-down warped felt image."""
    h, w = warped_bgr.shape[:2]
    if min_radius is None:
        min_radius = max(10, int(w * 0.009))
    if max_radius is None:
        max_radius = max(min_radius + 6, int(w * 0.028))

    gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (7, 7), 1.5)

    hsv = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2HSV)
    sat = hsv[:, :, 1]
    sat = cv2.GaussianBlur(sat, (7, 7), 1.5)
    felt, non_felt, _is_blue_cloth = _cloth_masks(hsv)

    masked = cv2.bitwise_and(gray, gray, mask=non_felt)
    masked_sat = cv2.bitwise_and(sat, sat, mask=non_felt)

    candidates: list[tuple[int, int, int]] = []
    for source, p2 in ((masked, hough_param2), (masked_sat, max(18, hough_param2 - 2))):
        circles = cv2.HoughCircles(
            source,
            cv2.HOUGH_GRADIENT,
            dp=1.2,
            minDist=int(min_radius * 2.2),
            param1=100,
            param2=p2,
            minRadius=min_radius,
            maxRadius=max_radius,
        )
        if circles is not None:
            candidates.extend(np.round(circles[0]).astype(int).tolist())

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
        if circularity < 0.72:
            continue
        (cx, cy), radius = cv2.minEnclosingCircle(cnt)
        if min_radius <= radius <= max_radius:
            candidates.append((int(cx), int(cy), int(radius)))

    margin = max_radius + 6
    detected: list[DetectedBall] = []
    for cx, cy, r in candidates:
        if cx < margin or cy < margin or cx > w - margin or cy > h - margin:
            continue
        if cy < 0 or cy >= h or cx < 0 or cx >= w:
            continue
        if felt[cy, cx] != 0:
            continue

        # Ignore detections hugging cushion / pocket edges.
        nx, ny = cx / w, cy / h
        if nx < edge_margin or nx > 1.0 - edge_margin or ny < edge_margin or ny > 1.0 - edge_margin:
            continue

        color = _classify_color(warped_bgr, cx, cy, r)
        if color == "unknown":
            color = "white"
        detected.append(
            DetectedBall(
                id=None,
                x=float(cx / w),
                y=float(cy / h),
                color=color,
                radius_px=float(r),
            )
        )

    return _dedupe_balls(detected, min_dist=min_radius * 2.0)


def _dedupe_balls(balls: list[DetectedBall], min_dist: float) -> list[DetectedBall]:
    if not balls:
        return balls
    kept: list[DetectedBall] = []
    for ball in sorted(balls, key=lambda b: b.radius_px, reverse=True):
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
    min_radius = max(8, int(w * 0.008))
    max_radius = max(min_radius + 6, int(w * 0.032))
    gray = cv2.cvtColor(warped_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 1.2)

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
    for cx, cy, r in candidates:
        if cx < margin or cy < margin or cx > w - margin or cy > h - margin:
            continue
        nx, ny = cx / w, cy / h
        if nx < 0.04 or nx > 0.96 or ny < 0.04 or ny > 0.96:
            continue
        color = _classify_color(warped_bgr, cx, cy, r)
        if color == "unknown":
            color = "white"
        detected.append(
            DetectedBall(
                id=None,
                x=float(cx / w),
                y=float(cy / h),
                color=color,
                radius_px=float(r),
            )
        )
    return _dedupe_balls(detected, min_dist=min_radius * 1.8)


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
    balls = detect_balls(warped)
    detect_mode = "felt_mask"
    if not balls:
        balls = detect_balls(warped, hough_param2=18, edge_margin=0.02)
        detect_mode = "relaxed"
    if not balls:
        balls = detect_balls_bare(warped)
        detect_mode = "bare_hough"

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
            "detect_mode": detect_mode,
            "is_blue_cloth": is_blue_cloth,
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
