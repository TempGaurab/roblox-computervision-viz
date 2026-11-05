"""Reference stroke preprocessing and wire format. NeuralCore must match this; see claude.md."""

import math
import struct
from collections.abc import Sequence

import numpy as np

from training import config

COORD_MAX = 65535.0

Strokes = tuple[list[int], list[int], list[int]]


def _stamp_segment(
    image: np.ndarray, ax: float, ay: float, bx: float, by: float, inner: float, outer: float, grid: int
) -> None:
    """Max-combine one segment (or a dot, when both ends match) into the image."""
    first_col = max(0, math.floor(min(ax, bx) - outer))
    last_col = min(grid - 1, math.floor(max(ax, bx) + outer))
    first_row = max(0, math.floor(min(ay, by) - outer))
    last_row = min(grid - 1, math.floor(max(ay, by) + outer))

    dx = bx - ax
    dy = by - ay
    length_squared = dx * dx + dy * dy

    for row in range(first_row, last_row + 1):
        center_y = row + 0.5
        for col in range(first_col, last_col + 1):
            center_x = col + 0.5
            t = 0.0
            if length_squared > 0.0:
                t = ((center_x - ax) * dx + (center_y - ay) * dy) / length_squared
                t = min(1.0, max(0.0, t))
            offset_x = center_x - (ax + t * dx)
            offset_y = center_y - (ay + t * dy)
            distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)
            intensity = min(1.0, max(0.0, (outer - distance) / (outer - inner)))
            if intensity > image[row, col]:
                image[row, col] = intensity


def _rasterize(
    xs: Sequence[float], ys: Sequence[float], stroke_ends: Sequence[int], inner: float, outer: float, grid: int
) -> np.ndarray:
    image = np.zeros((grid, grid), dtype=np.float64)
    start = 0
    for end in stroke_ends:
        if end - start == 1:
            _stamp_segment(image, xs[start], ys[start], xs[start], ys[start], inner, outer, grid)
        else:
            for i in range(start, end - 1):
                _stamp_segment(image, xs[i], ys[i], xs[i + 1], ys[i + 1], inner, outer, grid)
        start = end
    return image


def preprocess(
    xs: Sequence[int],
    ys: Sequence[int],
    stroke_ends: Sequence[int],
    inner: float = config.BRUSH_INNER,
    outer: float = config.BRUSH_OUTER,
) -> np.ndarray | None:
    """Turn u16 strokes into 784 floats in [0, 1], or None when empty or too small to read."""
    if len(xs) == 0:
        return None

    grid = config.GRID
    unit_x = [x / COORD_MAX for x in xs]
    unit_y = [y / COORD_MAX for y in ys]

    min_x = min(unit_x)
    min_y = min(unit_y)
    width = max(unit_x) - min_x
    height = max(unit_y) - min_y
    extent = max(width, height)
    if extent < config.MIN_EXTENT:
        return None

    scale = config.BOX / extent
    offset_x = (grid - width * scale) / 2
    offset_y = (grid - height * scale) / 2
    grid_x = [(x - min_x) * scale + offset_x for x in unit_x]
    grid_y = [(y - min_y) * scale + offset_y for y in unit_y]

    image = _rasterize(grid_x, grid_y, stroke_ends, inner, outer, grid)

    total = 0.0
    moment_x = 0.0
    moment_y = 0.0
    for row in range(grid):
        for col in range(grid):
            intensity = float(image[row, col])
            total += intensity
            moment_x += intensity * (col + 0.5)
            moment_y += intensity * (row + 0.5)
    if total <= 0.0:
        return None

    shift_x = grid / 2 - moment_x / total
    shift_y = grid / 2 - moment_y / total
    shifted_x = [x + shift_x for x in grid_x]
    shifted_y = [y + shift_y for y in grid_y]

    return _rasterize(shifted_x, shifted_y, stroke_ends, inner, outer, grid).reshape(-1)


def encode_strokes(xs: Sequence[int], ys: Sequence[int], stroke_ends: Sequence[int]) -> bytes:
    """Encode strokes in the wire format: u16 strokeCount, then per stroke u16 pointCount and u16 x, y pairs."""
    parts = [struct.pack("<H", len(stroke_ends))]
    start = 0
    for end in stroke_ends:
        parts.append(struct.pack("<H", end - start))
        for i in range(start, end):
            parts.append(struct.pack("<HH", xs[i], ys[i]))
        start = end
    return b"".join(parts)


def decode_strokes(payload: bytes) -> Strokes:
    """Decode the wire format, raising ValueError on anything malformed or over the limits."""
    if len(payload) < 2:
        raise ValueError("payload too short")
    stroke_count = struct.unpack_from("<H", payload, 0)[0]
    if stroke_count > config.MAX_STROKES:
        raise ValueError("too many strokes")

    xs: list[int] = []
    ys: list[int] = []
    stroke_ends: list[int] = []
    cursor = 2
    for _ in range(stroke_count):
        if cursor + 2 > len(payload):
            raise ValueError("truncated stroke header")
        point_count = struct.unpack_from("<H", payload, cursor)[0]
        cursor += 2
        if point_count == 0:
            raise ValueError("empty stroke")
        if len(xs) + point_count > config.MAX_POINTS:
            raise ValueError("too many points")
        if cursor + point_count * 4 > len(payload):
            raise ValueError("truncated stroke points")
        for _ in range(point_count):
            x, y = struct.unpack_from("<HH", payload, cursor)
            cursor += 4
            xs.append(x)
            ys.append(y)
        stroke_ends.append(len(xs))
    if cursor != len(payload):
        raise ValueError("trailing bytes")
    return xs, ys, stroke_ends
