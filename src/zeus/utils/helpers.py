"""Utility helper functions."""

from uuid import uuid4
from typing import Tuple


def generate_id() -> str:
    """Generate a unique identifier."""
    return str(uuid4())


def clamp(value: float, min_val: float, max_val: float) -> float:
    """Clamp a value between min and max."""
    return max(min_val, min(max_val, value))


def snap_to_grid(value: int, grid_size: int) -> int:
    """Snap a value to the nearest grid point."""
    return round(value / grid_size) * grid_size


def color_to_rgba(hex_color: str) -> Tuple[int, int, int, int]:
    """Convert a hex color string to RGBA tuple.
    
    Args:
        hex_color: Color in format '#RRGGBB' or '#RRGGBBAA'
    
    Returns:
        Tuple of (red, green, blue, alpha) values 0-255
    """
    hex_color = hex_color.lstrip('#')
    
    if len(hex_color) == 6:
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        a = 255
    elif len(hex_color) == 8:
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        a = int(hex_color[6:8], 16)
    else:
        return (0, 0, 0, 255)
    
    return (r, g, b, a)


def rgba_to_color(r: int, g: int, b: int, a: int = 255) -> str:
    """Convert RGBA values to hex color string.
    
    Args:
        r, g, b: Color values 0-255
        a: Alpha value 0-255
    
    Returns:
        Hex color string in format '#RRGGBB' or '#RRGGBBAA'
    """
    if a == 255:
        return f"#{r:02x}{g:02x}{b:02x}"
    return f"#{r:02x}{g:02x}{b:02x}{a:02x}"


def lerp(start: float, end: float, t: float) -> float:
    """Linear interpolation between two values.
    
    Args:
        start: Start value
        end: End value
        t: Interpolation factor (0-1)
    
    Returns:
        Interpolated value
    """
    return start + (end - start) * clamp(t, 0.0, 1.0)


def distance(x1: float, y1: float, x2: float, y2: float) -> float:
    """Calculate distance between two points."""
    import math
    return math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)


def rect_contains(rect_x: int, rect_y: int, rect_w: int, rect_h: int,
                  point_x: int, point_y: int) -> bool:
    """Check if a point is inside a rectangle."""
    return (rect_x <= point_x <= rect_x + rect_w and
            rect_y <= point_y <= rect_y + rect_h)


def rects_intersect(r1_x: int, r1_y: int, r1_w: int, r1_h: int,
                    r2_x: int, r2_y: int, r2_w: int, r2_h: int) -> bool:
    """Check if two rectangles intersect."""
    return (r1_x < r2_x + r2_w and r1_x + r1_w > r2_x and
            r1_y < r2_y + r2_h and r1_y + r1_h > r2_y)
