"""Output Panel - Console and logs display."""

from datetime import datetime
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPlainTextEdit,
    QFrame, QTabWidget, QToolButton
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QTextCharFormat, QColor, QFont


class ConsoleOutput(QPlainTextEdit):
    """Console output widget with colored text support."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setReadOnly(True)
        self.setFont(QFont("Consolas", 11))
        self.setStyleSheet("""
            QPlainTextEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: none;
                padding: 8px;
            }
        """)
    
    def log(self, message: str, level: str = "info") -> None:
        """Log a message with color based on level."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Create format based on level
        fmt = QTextCharFormat()
        if level == "error":
            fmt.setForeground(QColor("#f14c4c"))
        elif level == "warning":
            fmt.setForeground(QColor("#cca700"))
        elif level == "success":
            fmt.setForeground(QColor("#89d185"))
        else:
            fmt.setForeground(QColor("#cccccc"))
        
        cursor = self.textCursor()
        cursor.movePosition(cursor.MoveOperation.End)
        
        # Add timestamp
        time_fmt = QTextCharFormat()
        time_fmt.setForeground(QColor("#888888"))
        cursor.insertText(f"[{timestamp}] ", time_fmt)
        
        # Add message
        cursor.insertText(f"{message}\n", fmt)
        
        # Scroll to bottom
        self.setTextCursor(cursor)
        self.ensureCursorVisible()
    
    def clear_log(self) -> None:
        """Clear all log messages."""
        self.clear()


class ProblemsOutput(QWidget):
    """Problems/errors display widget."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the problems widget."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        
        self.text = QPlainTextEdit()
        self.text.setReadOnly(True)
        self.text.setFont(QFont("Consolas", 11))
        self.text.setStyleSheet("""
            QPlainTextEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: none;
                padding: 8px;
            }
        """)
        self.text.setPlainText("No problems detected")
        layout.addWidget(self.text)
    
    def add_problem(self, message: str, severity: str = "error") -> None:
        """Add a problem to the list."""
        icon = "❌" if severity == "error" else "⚠️"
        self.text.appendPlainText(f"{icon} {message}")
    
    def clear_problems(self) -> None:
        """Clear all problems."""
        self.text.setPlainText("No problems detected")


class OutputPanel(QWidget):
    """Bottom panel containing console output, problems, and terminal tabs."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the output panel UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        # Header with tabs
        self.tabs = QTabWidget()
        self.tabs.setTabPosition(QTabWidget.TabPosition.South)
        
        # Console tab
        console_widget = QWidget()
        console_layout = QVBoxLayout(console_widget)
        console_layout.setContentsMargins(0, 0, 0, 0)
        
        # Console header
        console_header = QFrame()
        console_header.setFixedHeight(28)
        console_header.setStyleSheet("""
            QFrame {
                background-color: #2d2d2d;
                border-bottom: 1px solid #3c3c3c;
            }
        """)
        header_layout = QHBoxLayout(console_header)
        header_layout.setContentsMargins(8, 0, 8, 0)
        
        console_title = QLabel("Output")
        console_title.setStyleSheet("color: #cccccc; font-size: 11px;")
        header_layout.addWidget(console_title)
        header_layout.addStretch()
        
        clear_btn = QToolButton()
        clear_btn.setText("🗑")
        clear_btn.setAutoRaise(True)
        clear_btn.setToolTip("Clear Output")
        clear_btn.clicked.connect(self._clear_console)
        header_layout.addWidget(clear_btn)
        
        console_layout.addWidget(console_header)
        
        self.console = ConsoleOutput()
        console_layout.addWidget(self.console)
        
        self.tabs.addTab(console_widget, "Console")
        
        # Problems tab
        self.problems = ProblemsOutput()
        self.tabs.addTab(self.problems, "Problems")
        
        layout.addWidget(self.tabs)
    
    def log(self, message: str, level: str = "info") -> None:
        """Log a message to the console."""
        self.console.log(message, level)
    
    def log_error(self, message: str) -> None:
        """Log an error message."""
        self.console.log(message, "error")
        self.problems.add_problem(message, "error")
    
    def log_warning(self, message: str) -> None:
        """Log a warning message."""
        self.console.log(message, "warning")
        self.problems.add_problem(message, "warning")
    
    def log_success(self, message: str) -> None:
        """Log a success message."""
        self.console.log(message, "success")
    
    def _clear_console(self) -> None:
        """Clear the console output."""
        self.console.clear_log()
