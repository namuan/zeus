"""Project Explorer - Tree view of project structure."""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QTreeWidget,
    QTreeWidgetItem, QFrame, QToolButton, QMenu
)
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QAction

from zeus.core.state import AppState


class ProjectExplorer(QWidget):
    """Left panel showing project structure."""
    
    page_selected = pyqtSignal(str)  # Emits page ID
    page_added = pyqtSignal(str)  # Emits page name
    page_removed = pyqtSignal(str)  # Emits page ID
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.state = AppState()
        self._setup_ui()
        
        # Subscribe to state changes
        self.state.subscribe("project_changed", self._on_project_changed)
    
    def _setup_ui(self) -> None:
        """Set up the explorer UI."""
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
        header_layout.setContentsMargins(12, 0, 8, 0)
        
        title = QLabel("Explorer")
        title.setStyleSheet("font-weight: bold; font-size: 13px; color: #cccccc;")
        header_layout.addWidget(title)
        header_layout.addStretch()
        
        # Add page button
        add_btn = QToolButton()
        add_btn.setText("+")
        add_btn.setAutoRaise(True)
        add_btn.setFixedSize(24, 24)
        add_btn.setToolTip("Add Page")
        add_btn.clicked.connect(self._add_page)
        add_btn.setStyleSheet("""
            QToolButton {
                color: #cccccc;
                font-size: 16px;
                font-weight: bold;
            }
            QToolButton:hover {
                background-color: #3c3c3c;
            }
        """)
        header_layout.addWidget(add_btn)
        
        layout.addWidget(header)
        
        # Tree widget
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setIndentation(16)
        self.tree.setStyleSheet("""
            QTreeWidget {
                background-color: #252526;
                border: none;
            }
            QTreeWidget::item {
                padding: 4px;
            }
            QTreeWidget::item:selected {
                background-color: #094771;
            }
            QTreeWidget::item:hover {
                background-color: #2a2d2e;
            }
        """)
        self.tree.itemClicked.connect(self._on_item_clicked)
        self.tree.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self._show_context_menu)
        
        layout.addWidget(self.tree)
    
    def refresh(self) -> None:
        """Refresh the project tree."""
        self.tree.clear()
        
        if self.state.project is None:
            return
        
        # Project root
        project_item = QTreeWidgetItem(self.tree)
        project_item.setText(0, self.state.project.name)
        project_item.setExpanded(True)
        
        # Pages folder
        pages_item = QTreeWidgetItem(project_item)
        pages_item.setText(0, "Pages")
        pages_item.setExpanded(True)
        
        for page in self.state.project.pages:
            page_item = QTreeWidgetItem(pages_item)
            page_item.setText(0, page.name)
            page_item.setData(0, Qt.ItemDataRole.UserRole, page.id)
            
            # Highlight current page
            if page.id == self.state.current_page_id:
                font = page_item.font(0)
                font.setBold(True)
                page_item.setFont(0, font)
        
        # Assets folder
        assets_item = QTreeWidgetItem(project_item)
        assets_item.setText(0, "Assets")
    
    def _on_project_changed(self, project) -> None:
        """Handle project change."""
        self.refresh()
    
    def _on_item_clicked(self, item: QTreeWidgetItem, column: int) -> None:
        """Handle item click."""
        page_id = item.data(0, Qt.ItemDataRole.UserRole)
        if page_id:
            self.state.current_page_id = page_id
            self.page_selected.emit(page_id)
            self.refresh()
    
    def _add_page(self) -> None:
        """Add a new page."""
        if self.state.project:
            page_count = len(self.state.project.pages)
            page = self.state.project.add_page(f"Page {page_count + 1}")
            self.state.current_page_id = page.id
            self.page_added.emit(page.name)
            self.refresh()
    
    def _show_context_menu(self, position) -> None:
        """Show context menu for tree items."""
        item = self.tree.itemAt(position)
        if item is None:
            return
        
        page_id = item.data(0, Qt.ItemDataRole.UserRole)
        if page_id:
            menu = QMenu(self)
            
            rename_action = QAction("Rename", self)
            rename_action.triggered.connect(lambda: self._rename_page(page_id))
            menu.addAction(rename_action)
            
            delete_action = QAction("Delete", self)
            delete_action.triggered.connect(lambda: self._delete_page(page_id))
            menu.addAction(delete_action)
            
            menu.exec(self.tree.mapToGlobal(position))
    
    def _rename_page(self, page_id: str) -> None:
        """Rename a page."""
        # TODO: Implement page rename dialog
        pass
    
    def _delete_page(self, page_id: str) -> None:
        """Delete a page."""
        if self.state.project and len(self.state.project.pages) > 1:
            self.state.project.remove_page(page_id)
            if self.state.current_page_id == page_id:
                self.state.current_page_id = self.state.project.pages[0].id
            self.page_removed.emit(page_id)
            self.refresh()
