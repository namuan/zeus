"""Zeus Application - Main entry point."""

import sys
import platform
from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont

from zeus.ui.main_window import MainWindow


def get_system_font() -> str:
    """Get the appropriate system font for the current platform."""
    system = platform.system()
    if system == "Darwin":  # macOS
        return "SF Pro Text"
    elif system == "Windows":
        return "Segoe UI"
    else:  # Linux and others
        return "Ubuntu"


def create_application() -> QApplication:
    """Create and configure the Qt application."""
    # Enable high DPI scaling
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    
    app = QApplication(sys.argv)
    app.setApplicationName("Zeus")
    app.setApplicationVersion("0.1.0")
    app.setOrganizationName("Zeus")
    
    # Set default font - use system-appropriate font
    font_family = get_system_font()
    font = QFont(font_family, 10)
    app.setFont(font)
    
    return app


def main() -> int:
    """Main entry point for Zeus application."""
    app = create_application()
    
    # Create and show main window
    window = MainWindow()
    window.show()
    
    # Run the application
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
