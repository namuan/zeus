"""Zeus Resources - Icons, styles, and themes."""

from pathlib import Path

RESOURCES_DIR = Path(__file__).parent
ICONS_DIR = RESOURCES_DIR / "icons"
STYLES_DIR = RESOURCES_DIR / "styles"
THEMES_DIR = RESOURCES_DIR / "themes"


def get_icon_path(name: str) -> Path:
    """Get the path to an icon file."""
    return ICONS_DIR / name


def get_style_path(name: str) -> Path:
    """Get the path to a style file."""
    return STYLES_DIR / name


def get_theme_path(name: str) -> Path:
    """Get the path to a theme file."""
    return THEMES_DIR / name
