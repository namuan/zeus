"""Properties Panel - Inspector for component properties."""

from typing import Any, Optional
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QSpinBox, QDoubleSpinBox, QCheckBox, QComboBox, QColorDialog,
    QFrame, QScrollArea, QFormLayout, QTabWidget, QPushButton,
    QGroupBox
)
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QColor

from zeus.core.state import AppState
from zeus.core.component import ComponentProperty


class ColorButton(QPushButton):
    """A button that displays and edits a color."""
    
    color_changed = pyqtSignal(str)
    
    def __init__(self, color: str = "#ffffff", parent=None):
        super().__init__(parent)
        self._color = color
        self.setFixedSize(60, 24)
        self._update_style()
        self.clicked.connect(self._pick_color)
    
    def _update_style(self) -> None:
        """Update the button style with current color."""
        self.setStyleSheet(f"""
            QPushButton {{
                background-color: {self._color};
                border: 1px solid #545454;
                border-radius: 3px;
            }}
            QPushButton:hover {{
                border-color: #007acc;
            }}
        """)
    
    def _pick_color(self) -> None:
        """Open color picker dialog."""
        color = QColorDialog.getColor(QColor(self._color), self, "Pick Color")
        if color.isValid():
            self._color = color.name()
            self._update_style()
            self.color_changed.emit(self._color)
    
    def get_color(self) -> str:
        return self._color
    
    def set_color(self, color: str) -> None:
        self._color = color
        self._update_style()


class PropertyEditor(QWidget):
    """Widget for editing a single property."""
    
    value_changed = pyqtSignal(str, object)  # property name, new value
    
    def __init__(self, prop: ComponentProperty, value: Any = None, parent=None):
        super().__init__(parent)
        self.prop = prop
        self._setup_ui(value)
    
    def _setup_ui(self, value: Any) -> None:
        """Create the appropriate editor widget."""
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        
        if self.prop.property_type == "string":
            self.editor = QLineEdit()
            self.editor.setText(str(value) if value else self.prop.default_value or "")
            self.editor.textChanged.connect(
                lambda v: self.value_changed.emit(self.prop.name, v)
            )
        
        elif self.prop.property_type == "int":
            self.editor = QSpinBox()
            self.editor.setRange(-10000, 10000)
            self.editor.setValue(value if value is not None else self.prop.default_value or 0)
            self.editor.valueChanged.connect(
                lambda v: self.value_changed.emit(self.prop.name, v)
            )
        
        elif self.prop.property_type == "float":
            self.editor = QDoubleSpinBox()
            self.editor.setRange(-10000.0, 10000.0)
            self.editor.setDecimals(2)
            self.editor.setValue(value if value is not None else self.prop.default_value or 0.0)
            self.editor.valueChanged.connect(
                lambda v: self.value_changed.emit(self.prop.name, v)
            )
        
        elif self.prop.property_type == "bool":
            self.editor = QCheckBox()
            self.editor.setChecked(value if value is not None else self.prop.default_value or False)
            self.editor.stateChanged.connect(
                lambda v: self.value_changed.emit(self.prop.name, v == Qt.CheckState.Checked.value)
            )
        
        elif self.prop.property_type == "color":
            self.editor = ColorButton(value or self.prop.default_value or "#ffffff")
            self.editor.color_changed.connect(
                lambda v: self.value_changed.emit(self.prop.name, v)
            )
        
        elif self.prop.property_type == "enum":
            self.editor = QComboBox()
            self.editor.addItems(self.prop.options)
            if value:
                index = self.editor.findText(str(value))
                if index >= 0:
                    self.editor.setCurrentIndex(index)
            self.editor.currentTextChanged.connect(
                lambda v: self.value_changed.emit(self.prop.name, v)
            )
        
        else:
            self.editor = QLabel("Unknown type")
        
        layout.addWidget(self.editor)
    
    def get_value(self) -> Any:
        """Get the current value."""
        if self.prop.property_type == "string":
            return self.editor.text()
        elif self.prop.property_type in ("int", "float"):
            return self.editor.value()
        elif self.prop.property_type == "bool":
            return self.editor.isChecked()
        elif self.prop.property_type == "color":
            return self.editor.get_color()
        elif self.prop.property_type == "enum":
            return self.editor.currentText()
        return None
    
    def set_value(self, value: Any) -> None:
        """Set the current value."""
        if self.prop.property_type == "string":
            self.editor.setText(str(value) if value else "")
        elif self.prop.property_type == "int":
            self.editor.setValue(int(value) if value else 0)
        elif self.prop.property_type == "float":
            self.editor.setValue(float(value) if value else 0.0)
        elif self.prop.property_type == "bool":
            self.editor.setChecked(bool(value))
        elif self.prop.property_type == "color":
            self.editor.set_color(value or "#ffffff")
        elif self.prop.property_type == "enum":
            index = self.editor.findText(str(value))
            if index >= 0:
                self.editor.setCurrentIndex(index)


class PropertiesTab(QWidget):
    """Tab for editing component properties."""
    
    property_changed = pyqtSignal(str, object)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._editors: dict[str, PropertyEditor] = {}
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the properties tab UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        
        # Scroll area for properties
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setStyleSheet("QScrollArea { border: none; }")
        
        self.content = QWidget()
        self.form_layout = QFormLayout(self.content)
        self.form_layout.setContentsMargins(12, 12, 12, 12)
        self.form_layout.setSpacing(8)
        self.form_layout.setLabelAlignment(Qt.AlignmentFlag.AlignLeft)
        
        scroll.setWidget(self.content)
        layout.addWidget(scroll)
    
    def clear(self) -> None:
        """Clear all property editors."""
        while self.form_layout.count():
            item = self.form_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self._editors.clear()
    
    def set_component(self, component) -> None:
        """Set the component to edit."""
        self.clear()
        
        if component is None:
            return
        
        # Add position/size properties
        common_props = [
            ComponentProperty("x", "X", "int", component.x),
            ComponentProperty("y", "Y", "int", component.y),
            ComponentProperty("width", "Width", "int", component.width),
            ComponentProperty("height", "Height", "int", component.height),
        ]
        
        # Add common properties group
        for prop in common_props:
            value = getattr(component, prop.name, prop.default_value)
            editor = PropertyEditor(prop, value)
            editor.value_changed.connect(self._on_property_changed)
            self.form_layout.addRow(f"{prop.display_name}:", editor)
            self._editors[prop.name] = editor
        
        # Add separator
        separator = QFrame()
        separator.setFrameShape(QFrame.Shape.HLine)
        separator.setStyleSheet("background-color: #3c3c3c;")
        self.form_layout.addRow(separator)
        
        # Add component-specific properties
        for prop in component.get_properties():
            value = component.get_property(prop.name)
            editor = PropertyEditor(prop, value)
            editor.value_changed.connect(self._on_property_changed)
            self.form_layout.addRow(f"{prop.display_name}:", editor)
            self._editors[prop.name] = editor
    
    def _on_property_changed(self, name: str, value: Any) -> None:
        """Handle property value change."""
        self.property_changed.emit(name, value)


class StylesTab(QWidget):
    """Tab for editing component styles."""
    
    style_changed = pyqtSignal(str, object)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the styles tab UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)
        
        # Background group
        bg_group = QGroupBox("Background")
        bg_layout = QFormLayout(bg_group)
        
        self.bg_color = ColorButton("#ffffff")
        self.bg_color.color_changed.connect(
            lambda v: self.style_changed.emit("background_color", v)
        )
        bg_layout.addRow("Color:", self.bg_color)
        
        layout.addWidget(bg_group)
        
        # Border group
        border_group = QGroupBox("Border")
        border_layout = QFormLayout(border_group)
        
        self.border_width = QSpinBox()
        self.border_width.setRange(0, 20)
        self.border_width.valueChanged.connect(
            lambda v: self.style_changed.emit("border_width", v)
        )
        border_layout.addRow("Width:", self.border_width)
        
        self.border_color = ColorButton("#000000")
        self.border_color.color_changed.connect(
            lambda v: self.style_changed.emit("border_color", v)
        )
        border_layout.addRow("Color:", self.border_color)
        
        self.border_radius = QSpinBox()
        self.border_radius.setRange(0, 100)
        self.border_radius.valueChanged.connect(
            lambda v: self.style_changed.emit("border_radius", v)
        )
        border_layout.addRow("Radius:", self.border_radius)
        
        layout.addWidget(border_group)
        
        # Typography group
        text_group = QGroupBox("Typography")
        text_layout = QFormLayout(text_group)
        
        self.font_size = QSpinBox()
        self.font_size.setRange(8, 72)
        self.font_size.setValue(14)
        self.font_size.valueChanged.connect(
            lambda v: self.style_changed.emit("font_size", v)
        )
        text_layout.addRow("Size:", self.font_size)
        
        self.text_color = ColorButton("#000000")
        self.text_color.color_changed.connect(
            lambda v: self.style_changed.emit("text_color", v)
        )
        text_layout.addRow("Color:", self.text_color)
        
        layout.addWidget(text_group)
        
        layout.addStretch()
    
    def set_component(self, component) -> None:
        """Set the component to edit styles for."""
        # Load component styles if available
        if component and hasattr(component, '_properties'):
            props = component._properties
            if 'background_color' in props:
                self.bg_color.set_color(props['background_color'])
            if 'border_width' in props:
                self.border_width.setValue(props['border_width'])
            if 'border_color' in props:
                self.border_color.set_color(props['border_color'])
            if 'border_radius' in props:
                self.border_radius.setValue(props['border_radius'])
            if 'font_size' in props:
                self.font_size.setValue(props['font_size'])
            if 'text_color' in props:
                self.text_color.set_color(props['text_color'])


class EventsTab(QWidget):
    """Tab for editing component events."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Set up the events tab UI."""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        
        placeholder = QLabel("No events configured")
        placeholder.setAlignment(Qt.AlignmentFlag.AlignCenter)
        placeholder.setStyleSheet("color: #888888;")
        layout.addWidget(placeholder)
        
        layout.addStretch()
    
    def set_component(self, component) -> None:
        """Set the component to edit events for."""
        pass  # TODO: Implement event editing


class PropertiesPanel(QWidget):
    """Right panel for editing component properties, styles, and events."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.state = AppState()
        self._current_component = None
        self._setup_ui()
        
        # Subscribe to selection changes
        self.state.subscribe("selection_changed", self._on_selection_changed)
    
    def _setup_ui(self) -> None:
        """Set up the panel UI."""
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
        
        self.title_label = QLabel("Properties")
        self.title_label.setStyleSheet("font-weight: bold; color: #cccccc;")
        header_layout.addWidget(self.title_label)
        layout.addWidget(header)
        
        # Component info
        self.component_info = QLabel("No component selected")
        self.component_info.setStyleSheet("""
            padding: 12px;
            color: #888888;
            background-color: #2d2d2d;
            border-bottom: 1px solid #3c3c3c;
        """)
        layout.addWidget(self.component_info)
        
        # Tabs
        self.tabs = QTabWidget()
        
        self.properties_tab = PropertiesTab()
        self.properties_tab.property_changed.connect(self._on_property_changed)
        self.tabs.addTab(self.properties_tab, "Properties")
        
        self.styles_tab = StylesTab()
        self.styles_tab.style_changed.connect(self._on_style_changed)
        self.tabs.addTab(self.styles_tab, "Styles")
        
        self.events_tab = EventsTab()
        self.tabs.addTab(self.events_tab, "Events")
        
        layout.addWidget(self.tabs)
    
    def _on_selection_changed(self, selected_ids: list[str]) -> None:
        """Handle selection change."""
        if not selected_ids:
            self._set_component(None)
        else:
            # For now, just edit the first selected component
            # TODO: Get component from canvas
            pass
    
    def _set_component(self, component) -> None:
        """Set the component to edit."""
        self._current_component = component
        
        if component is None:
            self.component_info.setText("No component selected")
            self.properties_tab.clear()
            self.styles_tab.set_component(None)
            self.events_tab.set_component(None)
        else:
            self.component_info.setText(f"{component.display_name}")
            self.properties_tab.set_component(component)
            self.styles_tab.set_component(component)
            self.events_tab.set_component(component)
    
    def set_component(self, component) -> None:
        """Public method to set the component to edit."""
        self._set_component(component)
    
    def _on_property_changed(self, name: str, value: Any) -> None:
        """Handle property change."""
        if self._current_component:
            if name in ('x', 'y', 'width', 'height'):
                setattr(self._current_component, name, value)
            else:
                self._current_component.set_property(name, value)
    
    def _on_style_changed(self, name: str, value: Any) -> None:
        """Handle style change."""
        if self._current_component:
            self._current_component.set_property(name, value)
