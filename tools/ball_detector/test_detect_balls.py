#!/usr/bin/env python3
"""Regression tests for ball detection heuristics."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from detect_balls import (  # noqa: E402
    MIN_BALL_SCORE,
    _classify_color,
    _cloth_masks,
    _is_glare_patch,
    _sample_annulus_hsv,
    _score_ball_candidate,
    detect_balls,
    detect_from_array,
    warp_felt,
)


class ClothMaskTests(unittest.TestCase):
    def test_green_cloth_uses_green_felt_mask(self) -> None:
        hsv = np.zeros((200, 400, 3), dtype=np.uint8)
        hsv[:, :, 0] = 55
        hsv[:, :, 1] = 120
        hsv[:, :, 2] = 140
        felt, _, is_blue = _cloth_masks(hsv)
        self.assertFalse(is_blue)
        self.assertGreater(float(np.mean(felt > 0)), 0.5)

    def test_blue_cloth_uses_blue_felt_mask(self) -> None:
        hsv = np.zeros((200, 400, 3), dtype=np.uint8)
        hsv[:, :, 0] = 110
        hsv[:, :, 1] = 160
        hsv[:, :, 2] = 150
        _, _, is_blue = _cloth_masks(hsv)
        self.assertTrue(is_blue)


class ColorAndGlareTests(unittest.TestCase):
    def test_glare_patch_detected(self) -> None:
        pixels = np.array(
            [[0, 20, 230], [0, 25, 240], [0, 15, 220]],
            dtype=np.uint8,
        )
        self.assertTrue(_is_glare_patch(pixels))

    def test_colored_ball_not_glare(self) -> None:
        pixels = np.array(
            [[20, 180, 180], [22, 170, 170], [18, 175, 165]],
            dtype=np.uint8,
        )
        self.assertFalse(_is_glare_patch(pixels, texture_std=22.0))

    def test_white_ball_not_glare_with_texture(self) -> None:
        pixels = np.array(
            [[0, 20, 230], [0, 25, 240], [0, 15, 220]],
            dtype=np.uint8,
        )
        self.assertFalse(_is_glare_patch(pixels, texture_std=18.0))

    def test_yellow_ball_color(self) -> None:
        bgr = np.zeros((80, 80, 3), dtype=np.uint8)
        cv2.circle(bgr, (40, 40), 18, (0, 210, 210), -1)
        self.assertEqual(_classify_color(bgr, 40, 40, 18), "yellow")


class SyntheticDetectionTests(unittest.TestCase):
    def _make_blue_table_with_balls(self) -> np.ndarray:
        warped = np.zeros((1000, 2000, 3), dtype=np.uint8)
        warped[:, :] = (180, 80, 40)  # blue felt in BGR
        specs = [
            ((420, 300), (0, 220, 220), "yellow"),
            ((980, 520), (0, 0, 220), "red"),
            ((1500, 700), (240, 240, 240), "white"),
        ]
        for (cx, cy), bgr, _ in specs:
            cv2.circle(warped, (cx, cy), 42, bgr, -1)
            cv2.circle(warped, (cx, cy), 42, (20, 20, 20), 2)
        return warped

    def test_detects_synthetic_balls(self) -> None:
        warped = self._make_blue_table_with_balls()
        balls = detect_balls(warped, min_score=MIN_BALL_SCORE - 0.5)
        self.assertGreaterEqual(len(balls), 2)
        colors = {b.color for b in balls}
        self.assertTrue(colors & {"yellow", "red", "white"})

    def test_score_rejects_felt_glare_blob(self) -> None:
        warped = self._make_blue_table_with_balls()
        hsv = cv2.cvtColor(warped, cv2.COLOR_BGR2HSV)
        felt, non_felt, _ = _cloth_masks(hsv)
        cx, cy, r = 700, 500, 40
        cv2.circle(warped, (cx, cy), r, (245, 245, 245), -1)
        score = _score_ball_candidate(warped, felt, non_felt, cx, cy, r)
        self.assertLess(score, MIN_BALL_SCORE)


class SampleImageSmokeTests(unittest.TestCase):
    def test_table_photo_detects_multiple_balls(self) -> None:
        root = Path(__file__).resolve().parent
        image_path = root / "samples" / "table_photo.png"
        corners_path = root / "samples" / "corners_example.json"
        if not image_path.exists() or not corners_path.exists():
            self.skipTest("sample assets missing")

        image = cv2.imread(str(image_path))
        corners = json.loads(corners_path.read_text(encoding="utf-8"))
        result = detect_from_array(image, corners, source_name="table_photo.png")
        self.assertGreaterEqual(result["meta"]["ball_count"], 5)
        self.assertEqual(result["meta"]["detector_version"], "0.1.6")

    def test_hall_end_view_photo(self) -> None:
        root = Path(__file__).resolve().parent
        image_path = root / "samples" / "S__194953223_0.jpg"
        corners_path = root / "samples" / "hall_end_view_corners.json"
        if not image_path.exists() or not corners_path.exists():
            self.skipTest("hall sample assets missing")

        image = cv2.imread(str(image_path))
        corners = json.loads(corners_path.read_text(encoding="utf-8"))
        result = detect_from_array(image, corners, source_name=image_path.name)
        self.assertGreaterEqual(result["meta"]["ball_count"], 6)
        colors = {b["color"] for b in result["balls"]}
        self.assertTrue(colors - {"unknown"})

    def test_user_end_view_corners_on_hall_photo(self) -> None:
        root = Path(__file__).resolve().parent
        image_path = root / "samples" / "S__194953223_0.jpg"
        corners_path = root / "samples" / "user_end_view_corners.json"
        if not image_path.exists() or not corners_path.exists():
            self.skipTest("user corner fixture missing")

        image = cv2.imread(str(image_path))
        corners = json.loads(corners_path.read_text(encoding="utf-8"))
        result = detect_from_array(
            image,
            corners,
            source_name=image_path.name,
            ref_width=1536,
            ref_height=2048,
        )
        self.assertGreaterEqual(result["meta"]["ball_count"], 7)


if __name__ == "__main__":
    unittest.main()
