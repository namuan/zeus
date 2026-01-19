"""Checkbox widget component."""

from PyQt6.QtWidgets import QCheckBox, QWidget
from PyQt6.QtCore import Qt

from zeus.core.component import BaseComponent, ComponentProperty, ComponentEvent
from zeus.widgets.registry import register_component


@register_component
class CheckboxComponent(BaseComponent):
    """A checkbox component for boolean values."""
    
    component_type = "checkbox"
    display_name = "Checkbox"
    category = "Form Controls"
    icon = "checkbox.png"
    description = "A checkbox for boolean selections"
    
    default_width = 150
    default_height = 30
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="label",
                display_name="Label",
                property_type="string",
                default_value="Checkbox",
                description="The label text next to the checkbox"
            ),
            ComponentProperty(
                name="checked",
                display_name="Checked",
                property_type="bool",
                default_value=False,
                description="Whether the checkbox is checked"
            ),
            ComponentProperty(
                name="enabled",
                display_name="Enabled",
                property_type="bool",
                default_value=True,
                description="Whether the checkbox is interactive"
            ),
            ComponentProperty(
                name="text_color",
                display_name="Text Color",
                property_type="color",
                default_value="#cccccc",
                description="Label text color"
            ),
        ]
    
    @classmethod
    def get_events(cls) -> list[ComponentEvent]:
        return [
            ComponentEvent(
                name="onChange",
                display_name="On Change",
                description="Triggered when the checkbox state changes"
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render checkbox for design canvas."""
        checkbox = self._create_checkbox()
        checkbox.setEnabled(False)
        return checkbox
    
    def render_runtime(self) -> QWidget:
        """Render checkbox for runtime execution."""
        checkbox = self._create_checkbox()
        checkbox.setEnabled(self.get_property("enabled") or True)
        checkbox.stateChanged.connect(
            lambda state: self.emit_event("onChange", state == Qt.CheckState.Checked.value)
        )
        return checkbox
    
    def _create_checkbox(self) -> QCheckBox:
        """Create the checkbox widget."""
        checkbox = QCheckBox(self.get_property("label") or "Checkbox")
        checkbox.setChecked(self.get_property("checked") or False)
        
        text_color = self.get_property("text_color") or "#cccccc"
        
        checkbox.setStyleSheet(f"""
            QCheckBox {{
                color: {text_color};
                spacing: 8px;
                font-size: 13px;
            }}
            QCheckBox::indicator {{
                width: 18px;
                height: 18px;
                border: 1px solid #545454;
                border-radius: 3px;
                background-color: #3c3c3c;
            }}
            QCheckBox::indicator:checked {{
                background-color: #007acc;
                border-color: #007acc;
            }}
            QCheckBox::indicator:hover {{
                border-color: #007acc;
            }}
        """)
        
        return checkbox
