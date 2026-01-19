"""Component Palette - Drag-and-drop source for components."""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QScrollArea, QFrame, QToolButton, QGridLayout, QSizePolicy
)
from PyQt6.QtCore import Qt, QMimeData, QByteArray, pyqtSignal
from PyQt6.QtGui import QDrag, QPixmap, QPainter, QColor, QFont

from zeus.widgets import COMPONENT_REGISTRY


class ComponentItem(QFrame):
    """A draggable component item in the palette."""
    
    def __init__(self, component_class, parent=None):
        super().__init__(parent)
        self.component_class = component_class
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the component item UI."""
        self.setObjectName("componentItem")
        self.setFixedSize(80, 80)
        self.setCursor(Qt.CursorShape.OpenHandCursor)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 8, 4, 4)
        layout.setSpacing(4)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        
        # Icon placeholder
        icon_label = QLabel()
        icon_label.setFixedSize(32, 32)
        icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        icon_label.setStyleSheet("""
            background-color: #3c3c3c;
            border-radius: 4px;
            color: #007acc;
            font-size: 18px;
            font-weight: bold;
        """)
        icon_label.setText(self.component_class.display_name[0].upper())
        layout.addWidget(icon_label, alignment=Qt.AlignmentFlag.AlignCenter)
        
        # Component name
        name_label = QLabel(self.component_class.display_name)
        name_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        name_label.setWordWrap(True)
        name_label.setStyleSheet("font-size: 11px; color: #cccccc;")
        layout.addWidget(name_label)
        
        self.setStyleSheet("""
            #componentItem {
                background-color: #2d2d2d;
                border: 1px solid #3c3c3c;
                border-radius: 6px;
            }
            #componentItem:hover {
                background-color: #383838;
                border-color: #007acc;
            }
        """)
    
    def mousePressEvent(self, event) -> None:
        """Handle mouse press to start drag."""
        if event.button() == Qt.MouseButton.LeftButton:
            self.setCursor(Qt.CursorShape.ClosedHandCursor)
        super().mousePressEvent(event)
    
    def mouseReleaseEvent(self, event) -> None:
        """Handle mouse release."""
        self.setCursor(Qt.CursorShape.OpenHandCursor)
        super().mouseReleaseEvent(event)
    
    def mouseMoveEvent(self, event) -> None:
        """Handle mouse move to perform drag."""
        if event.buttons() & Qt.MouseButton.LeftButton:
            drag = QDrag(self)
            mime_data = QMimeData()
            
            # Store component type in mime data
            mime_data.setData(
                "application/x-zeus-component",
                QByteArray(self.component_class.component_type.encode())
            )
            drag.setMimeData(mime_data)
            
            # Create drag pixmap
            pixmap = QPixmap(80, 40)
            pixmap.fill(QColor("#094771"))
            painter = QPainter(pixmap)
            painter.setPen(QColor("#ffffff"))
            painter.setFont(QFont("Segoe UI", 10))
            painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, 
                           self.component_class.display_name)
            painter.end()
            
            drag.setPixmap(pixmap)
            drag.setHotSpot(event.position().toPoint())
            
            drag.exec(Qt.DropAction.CopyAction)


class CategorySection(QFrame):
    """A collapsible category section in the palette."""
    
    def __init__(self, title: str, parent=None):
        super().__init__(parent)
        self.title = title
        self._expanded = True
        self._components: list[type] = []
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the category section UI."""
        self.setObjectName("categorySection")
        
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # Header
        header = QFrame()
        header.setFixedHeight(32)
        header.setStyleSheet("""
            QFrame {
                background-color: #2d2d2d;
                border-bottom: 1px solid #3c3c3c;
            }
        """)
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(8, 0, 8, 0)
        
        self.toggle_btn = QToolButton()
        self.toggle_btn.setText("▼")
        self.toggle_btn.setAutoRaise(True)
        self.toggle_btn.setFixedSize(20, 20)
        self.toggle_btn.clicked.connect(self._toggle)
        self.toggle_btn.setStyleSheet("color: #888888; border: none;")
        header_layout.addWidget(self.toggle_btn)
        
        title_label = QLabel(self.title)
        title_label.setStyleSheet("font-weight: bold; color: #cccccc;")
        header_layout.addWidget(title_label)
        header_layout.addStretch()
        
        main_layout.addWidget(header)
        
        # Content area
        self.content = QWidget()
        self.content_layout = QGridLayout(self.content)
        self.content_layout.setContentsMargins(8, 8, 8, 8)
        self.content_layout.setSpacing(8)
        main_layout.addWidget(self.content)
    
    def add_component(self, component_class: type) -> None:
        """Add a component to this category."""
        self._components.append(component_class)
        item = ComponentItem(component_class)
        row = len(self._components) // 3
        col = (len(self._components) - 1) % 3
        self.content_layout.addWidget(item, row, col)
    
    def _toggle(self) -> None:
        """Toggle the category expansion."""
        self._expanded = not self._expanded
        self.content.setVisible(self._expanded)
        self.toggle_btn.setText("▼" if self._expanded else "▶")
    
    def filter_components(self, search_text: str) -> bool:
        """Filter components by search text. Returns True if any visible."""
        has_visible = False
        search_lower = search_text.lower()
        
        for i in range(self.content_layout.count()):
            item = self.content_layout.itemAt(i)
            if item and item.widget():
                widget = item.widget()
                if isinstance(widget, ComponentItem):
                    visible = search_lower in widget.component_class.display_name.lower()
                    widget.setVisible(visible)
                    if visible:
                        has_visible = True
        
        self.setVisible(has_visible or not search_text)
        return has_visible


class ComponentPalette(QWidget):
    """Left panel containing draggable components organized by category."""
    
    component_selected = pyqtSignal(str)  # Emits component type
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._categories: dict[str, CategorySection] = {}
        self._setup_ui()
        self._load_components()
    
    def _setup_ui(self) -> None:
        """Set up the palette UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        # Header
        header = QFrame()
        header.setFixedHeight(36)
        header.setStyleSheet("""
            QFrame {
                background-color: #252526;
                border-bottom: 1px solid #3c3c3c;
            }
        """)
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(12, 0, 12, 0)
        
        title = QLabel("Components")
        title.setStyleSheet("font-weight: bold; font-size: 13px; color: #cccccc;")
        header_layout.addWidget(title)
        layout.addWidget(header)
        
        # Search box
        search_container = QFrame()
        search_container.setStyleSheet("background-color: #252526;")
        search_layout = QHBoxLayout(search_container)
        search_layout.setContentsMargins(8, 8, 8, 8)
        
        self.search_box = QLineEdit()
        self.search_box.setPlaceholderText("Search components...")
        self.search_box.textChanged.connect(self._filter_components)
        search_layout.addWidget(self.search_box)
        layout.addWidget(search_container)
        
        # Scrollable content
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setStyleSheet("QScrollArea { border: none; }")
        
        self.content = QWidget()
        self.content_layout = QVBoxLayout(self.content)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(0)
        self.content_layout.addStretch()
        
        scroll.setWidget(self.content)
        layout.addWidget(scroll)
    
    def _load_components(self) -> None:
        """Load all registered components into the palette."""
        # Group components by category
        categories = {}
        for comp_type, comp_class in COMPONENT_REGISTRY.items():
            category = comp_class.category
            if category not in categories:
                categories[category] = []
            categories[category].append(comp_class)
        
        # Create category sections
        for category_name in sorted(categories.keys()):
            section = CategorySection(category_name)
            for comp_class in categories[category_name]:
                section.add_component(comp_class)
            
            self._categories[category_name] = section
            # Insert before stretch
            self.content_layout.insertWidget(
                self.content_layout.count() - 1, section
            )
    
    def _filter_components(self, text: str) -> None:
        """Filter components based on search text."""
        for section in self._categories.values():
            section.filter_components(text)
