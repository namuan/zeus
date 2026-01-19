"""Design Canvas - Main editing area for visual design."""

from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QFrame,
    QScrollArea, QRubberBand, QMenu, QApplication
)
from PyQt6.QtCore import Qt, QPoint, QRect, QSize, pyqtSignal, QMimeData
from PyQt6.QtGui import (
    QPainter, QColor, QPen, QBrush, QMouseEvent, QWheelEvent,
    QKeyEvent, QDragEnterEvent, QDropEvent, QPaintEvent
)

from zeus.core.state import AppState
from zeus.core.commands import (
    AddComponentCommand, RemoveComponentCommand, 
    MoveComponentCommand, CommandStack
)
from zeus.widgets import COMPONENT_REGISTRY, create_component


class ComponentWrapper(QFrame):
    """Wrapper widget for components on the canvas with selection handles."""
    
    selected = pyqtSignal(str)  # Emits component ID
    moved = pyqtSignal(str, int, int)  # Emits component ID, new x, new y
    resized = pyqtSignal(str, int, int)  # Emits component ID, new width, new height
    
    HANDLE_SIZE = 8
    
    def __init__(self, component, parent=None):
        super().__init__(parent)
        self.component = component
        self._is_selected = False
        self._resize_handle = None
        self._drag_start = None
        self._original_pos = None
        self._original_size = None
        
        self._setup_ui()
        self._update_geometry()
    
    def _setup_ui(self) -> None:
        """Set up the wrapper UI."""
        self.setObjectName("componentWrapper")
        self.setMouseTracking(True)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        
        # Render the component's preview
        preview = self.component.render_preview()
        if preview:
            layout.addWidget(preview)
        
        self._update_style()
    
    def _update_geometry(self) -> None:
        """Update the wrapper geometry from component."""
        self.setGeometry(
            self.component.x,
            self.component.y,
            self.component.width,
            self.component.height
        )
    
    def _update_style(self) -> None:
        """Update the wrapper style based on selection state."""
        if self._is_selected:
            self.setStyleSheet("""
                #componentWrapper {
                    border: 2px solid #007acc;
                    background-color: transparent;
                }
            """)
        else:
            self.setStyleSheet("""
                #componentWrapper {
                    border: 1px solid transparent;
                    background-color: transparent;
                }
                #componentWrapper:hover {
                    border: 1px dashed #555555;
                }
            """)
    
    def set_selected(self, selected: bool) -> None:
        """Set the selection state."""
        self._is_selected = selected
        self._update_style()
        self.update()
    
    def paintEvent(self, event: QPaintEvent) -> None:
        """Paint selection handles."""
        super().paintEvent(event)
        
        if self._is_selected:
            painter = QPainter(self)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            
            # Draw resize handles
            handle_color = QColor("#007acc")
            painter.setBrush(QBrush(handle_color))
            painter.setPen(QPen(Qt.GlobalColor.white, 1))
            
            for rect in self._get_handle_rects():
                painter.drawRect(rect)
            
            painter.end()
    
    def _get_handle_rects(self) -> list[QRect]:
        """Get the rectangles for resize handles."""
        w, h = self.width(), self.height()
        s = self.HANDLE_SIZE
        half = s // 2
        
        return [
            QRect(-half, -half, s, s),  # top-left
            QRect(w // 2 - half, -half, s, s),  # top-center
            QRect(w - half, -half, s, s),  # top-right
            QRect(-half, h // 2 - half, s, s),  # middle-left
            QRect(w - half, h // 2 - half, s, s),  # middle-right
            QRect(-half, h - half, s, s),  # bottom-left
            QRect(w // 2 - half, h - half, s, s),  # bottom-center
            QRect(w - half, h - half, s, s),  # bottom-right
        ]
    
    def _get_handle_at(self, pos: QPoint) -> int | None:
        """Get the handle index at the given position."""
        if not self._is_selected:
            return None
        
        for i, rect in enumerate(self._get_handle_rects()):
            if rect.adjusted(-2, -2, 2, 2).contains(pos):
                return i
        return None
    
    def mousePressEvent(self, event: QMouseEvent) -> None:
        """Handle mouse press for selection and dragging."""
        if event.button() == Qt.MouseButton.LeftButton:
            handle = self._get_handle_at(event.position().toPoint())
            if handle is not None:
                self._resize_handle = handle
                self._original_size = (self.width(), self.height())
                self._original_pos = (self.x(), self.y())
            else:
                self._drag_start = event.position().toPoint()
                self._original_pos = (self.x(), self.y())
            
            # Emit selection signal
            modifiers = QApplication.keyboardModifiers()
            self.selected.emit(self.component.id)
        
        super().mousePressEvent(event)
    
    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        """Handle mouse move for dragging and resizing."""
        pos = event.position().toPoint()
        
        # Update cursor based on handle position
        if self._is_selected:
            handle = self._get_handle_at(pos)
            if handle is not None:
                cursors = [
                    Qt.CursorShape.SizeFDiagCursor,  # top-left
                    Qt.CursorShape.SizeVerCursor,    # top-center
                    Qt.CursorShape.SizeBDiagCursor,  # top-right
                    Qt.CursorShape.SizeHorCursor,    # middle-left
                    Qt.CursorShape.SizeHorCursor,    # middle-right
                    Qt.CursorShape.SizeBDiagCursor,  # bottom-left
                    Qt.CursorShape.SizeVerCursor,    # bottom-center
                    Qt.CursorShape.SizeFDiagCursor,  # bottom-right
                ]
                self.setCursor(cursors[handle])
            else:
                self.setCursor(Qt.CursorShape.SizeAllCursor)
        
        # Handle resizing
        if self._resize_handle is not None and self._original_size:
            delta = event.position().toPoint() - self._drag_start if self._drag_start else pos
            # Simplified resize - just handle bottom-right for now
            if self._resize_handle == 7:  # bottom-right
                new_width = max(50, self._original_size[0] + delta.x())
                new_height = max(30, self._original_size[1] + delta.y())
                self.resize(new_width, new_height)
                self.component.width = new_width
                self.component.height = new_height
        
        # Handle dragging
        elif self._drag_start is not None and self._original_pos:
            delta = pos - self._drag_start
            new_x = self._original_pos[0] + delta.x()
            new_y = self._original_pos[1] + delta.y()
            
            # Snap to grid
            state = AppState()
            if state.grid_snap:
                grid = state.grid_size
                new_x = round(new_x / grid) * grid
                new_y = round(new_y / grid) * grid
            
            self.move(new_x, new_y)
        
        super().mouseMoveEvent(event)
    
    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        """Handle mouse release to finish dragging/resizing."""
        if event.button() == Qt.MouseButton.LeftButton:
            if self._original_pos and (self.x() != self._original_pos[0] or 
                                       self.y() != self._original_pos[1]):
                self.component.x = self.x()
                self.component.y = self.y()
                self.moved.emit(self.component.id, self.x(), self.y())
            
            if self._resize_handle is not None:
                self.resized.emit(self.component.id, self.width(), self.height())
            
            self._drag_start = None
            self._original_pos = None
            self._original_size = None
            self._resize_handle = None
        
        super().mouseReleaseEvent(event)


class CanvasArea(QWidget):
    """The actual canvas drawing area."""
    
    component_selected = pyqtSignal(str)
    selection_cleared = pyqtSignal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.state = AppState()
        self._components: dict[str, ComponentWrapper] = {}
        self._rubber_band = None
        self._rubber_band_origin = None
        
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the canvas area."""
        self.setAcceptDrops(True)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        
        # Set canvas size
        self.setMinimumSize(2000, 2000)
        self.setStyleSheet("background-color: #1e1e1e;")
    
    def paintEvent(self, event: QPaintEvent) -> None:
        """Paint the canvas background and grid."""
        super().paintEvent(event)
        
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        # Draw grid if visible
        if self.state.grid_visible:
            self._draw_grid(painter)
        
        # Draw artboard/page bounds
        self._draw_artboard(painter)
        
        painter.end()
    
    def _draw_grid(self, painter: QPainter) -> None:
        """Draw the grid pattern."""
        grid_size = self.state.grid_size
        zoom = self.state.zoom_level
        
        painter.setPen(QPen(QColor("#2a2a2a"), 1))
        
        # Draw vertical lines
        x = 0
        while x < self.width():
            painter.drawLine(int(x), 0, int(x), self.height())
            x += grid_size * zoom
        
        # Draw horizontal lines
        y = 0
        while y < self.height():
            painter.drawLine(0, int(y), self.width(), int(y))
            y += grid_size * zoom
    
    def _draw_artboard(self, painter: QPainter) -> None:
        """Draw the artboard/page bounds."""
        if self.state.project and self.state.current_page_id:
            page = self.state.project.get_page(self.state.current_page_id)
            if page:
                zoom = self.state.zoom_level
                width = int(page.width * zoom)
                height = int(page.height * zoom)
                
                # Draw artboard background
                painter.fillRect(50, 50, width, height, QColor("#252526"))
                
                # Draw artboard border
                painter.setPen(QPen(QColor("#3c3c3c"), 2))
                painter.drawRect(50, 50, width, height)
    
    def add_component(self, component) -> None:
        """Add a component to the canvas."""
        wrapper = ComponentWrapper(component, self)
        wrapper.selected.connect(self._on_component_selected)
        wrapper.moved.connect(self._on_component_moved)
        wrapper.resized.connect(self._on_component_resized)
        wrapper.show()
        
        self._components[component.id] = wrapper
    
    def remove_component(self, component_id: str) -> None:
        """Remove a component from the canvas."""
        if component_id in self._components:
            wrapper = self._components.pop(component_id)
            wrapper.deleteLater()
    
    def get_component(self, component_id: str):
        """Get a component by ID."""
        wrapper = self._components.get(component_id)
        return wrapper.component if wrapper else None
    
    def _on_component_selected(self, component_id: str) -> None:
        """Handle component selection."""
        modifiers = QApplication.keyboardModifiers()
        add_to_selection = modifiers & Qt.KeyboardModifier.ShiftModifier
        
        if not add_to_selection:
            # Deselect all other components
            for cid, wrapper in self._components.items():
                wrapper.set_selected(cid == component_id)
        else:
            # Toggle selection
            if component_id in self._components:
                wrapper = self._components[component_id]
                wrapper.set_selected(not wrapper._is_selected)
        
        self.state.select_component(component_id, add_to_selection)
        self.component_selected.emit(component_id)
    
    def _on_component_moved(self, component_id: str, x: int, y: int) -> None:
        """Handle component move."""
        pass  # TODO: Add undo command
    
    def _on_component_resized(self, component_id: str, width: int, height: int) -> None:
        """Handle component resize."""
        pass  # TODO: Add undo command
    
    def clear_selection(self) -> None:
        """Clear all component selections."""
        for wrapper in self._components.values():
            wrapper.set_selected(False)
        self.state.clear_selection()
        self.selection_cleared.emit()
    
    def delete_selected(self) -> None:
        """Delete selected components."""
        selected = self.state.selection.selected_ids.copy()
        for component_id in selected:
            self.remove_component(component_id)
        self.state.clear_selection()
    
    def mousePressEvent(self, event: QMouseEvent) -> None:
        """Handle mouse press on empty canvas."""
        if event.button() == Qt.MouseButton.LeftButton:
            # Check if clicked on empty area
            child = self.childAt(event.position().toPoint())
            if child is None:
                self.clear_selection()
                # Start rubber band selection
                self._rubber_band_origin = event.position().toPoint()
                if not self._rubber_band:
                    self._rubber_band = QRubberBand(QRubberBand.Shape.Rectangle, self)
                self._rubber_band.setGeometry(QRect(self._rubber_band_origin, QSize()))
                self._rubber_band.show()
        
        super().mousePressEvent(event)
    
    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        """Handle mouse move for rubber band selection."""
        if self._rubber_band and self._rubber_band_origin:
            self._rubber_band.setGeometry(
                QRect(self._rubber_band_origin, event.position().toPoint()).normalized()
            )
        super().mouseMoveEvent(event)
    
    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        """Handle mouse release to finish rubber band selection."""
        if self._rubber_band:
            # Select components within rubber band
            rect = self._rubber_band.geometry()
            for component_id, wrapper in self._components.items():
                if rect.intersects(wrapper.geometry()):
                    wrapper.set_selected(True)
                    self.state.select_component(component_id, True)
            
            self._rubber_band.hide()
            self._rubber_band_origin = None
        
        super().mouseReleaseEvent(event)
    
    def keyPressEvent(self, event: QKeyEvent) -> None:
        """Handle keyboard shortcuts."""
        if event.key() == Qt.Key.Key_Delete or event.key() == Qt.Key.Key_Backspace:
            self.delete_selected()
        elif event.key() == Qt.Key.Key_Escape:
            self.clear_selection()
        super().keyPressEvent(event)
    
    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        """Handle drag enter for component drops."""
        if event.mimeData().hasFormat("application/x-zeus-component"):
            event.acceptProposedAction()
        else:
            event.ignore()
    
    def dragMoveEvent(self, event) -> None:
        """Handle drag move."""
        if event.mimeData().hasFormat("application/x-zeus-component"):
            event.acceptProposedAction()
    
    def dropEvent(self, event: QDropEvent) -> None:
        """Handle component drop on canvas."""
        if event.mimeData().hasFormat("application/x-zeus-component"):
            data = event.mimeData().data("application/x-zeus-component")
            component_type = bytes(data).decode()
            
            # Get drop position
            pos = event.position().toPoint()
            
            # Snap to grid if enabled
            if self.state.grid_snap:
                grid = self.state.grid_size
                pos.setX(round(pos.x() / grid) * grid)
                pos.setY(round(pos.y() / grid) * grid)
            
            # Create the component
            component = create_component(component_type, pos.x(), pos.y())
            if component:
                self.add_component(component)
                self._on_component_selected(component.id)
            
            event.acceptProposedAction()


class DesignCanvas(QWidget):
    """Main design canvas widget with scroll and zoom support."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.state = AppState()
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the canvas UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        # Header/toolbar
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
        
        # Page name
        self.page_label = QLabel("Main Page")
        self.page_label.setStyleSheet("font-weight: bold; color: #cccccc;")
        header_layout.addWidget(self.page_label)
        
        header_layout.addStretch()
        
        # Zoom indicator
        self.zoom_label = QLabel("100%")
        self.zoom_label.setStyleSheet("color: #888888;")
        header_layout.addWidget(self.zoom_label)
        
        layout.addWidget(header)
        
        # Scroll area for canvas
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(False)
        self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.scroll_area.setStyleSheet("QScrollArea { border: none; }")
        
        # Canvas area
        self.canvas = CanvasArea()
        self.scroll_area.setWidget(self.canvas)
        
        layout.addWidget(self.scroll_area)
        
        # Subscribe to state changes
        self.state.subscribe("zoom_changed", self._on_zoom_changed)
    
    def refresh(self) -> None:
        """Refresh the canvas display."""
        if self.state.project and self.state.current_page_id:
            page = self.state.project.get_page(self.state.current_page_id)
            if page:
                self.page_label.setText(page.name)
        self.canvas.update()
    
    def update_zoom(self) -> None:
        """Update the zoom display."""
        zoom_percent = int(self.state.zoom_level * 100)
        self.zoom_label.setText(f"{zoom_percent}%")
        self.canvas.update()
    
    def _on_zoom_changed(self, zoom: float) -> None:
        """Handle zoom level change."""
        self.update_zoom()
    
    def delete_selected(self) -> None:
        """Delete selected components."""
        self.canvas.delete_selected()
    
    def wheelEvent(self, event: QWheelEvent) -> None:
        """Handle mouse wheel for zooming."""
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            if delta > 0:
                self.state.zoom_level *= 1.1
            else:
                self.state.zoom_level /= 1.1
            event.accept()
        else:
            super().wheelEvent(event)
