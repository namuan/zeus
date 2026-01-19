"""Text input widget component."""

from PyQt6.QtWidgets import QLineEdit, QWidget
from PyQt6.QtCore import Qt

from zeus.core.component import BaseComponent, ComponentProperty, ComponentEvent
from zeus.widgets.registry import register_component


@register_component
class TextInputComponent(BaseComponent):
    """A text input field component."""
    
    component_type = "text_input"
    display_name = "Text Input"
    category = "Form Controls"
    icon = "input.png"
    description = "A single-line text input field"
    
    default_width = 200
    default_height = 36
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="placeholder",
                display_name="Placeholder",
                property_type="string",
                default_value="Enter text...",
                description="Placeholder text when empty"
            ),
            ComponentProperty(
                name="value",
                display_name="Value",
                property_type="string",
                default_value="",
                description="The current text value"
            ),
            ComponentProperty(
                name="enabled",
                display_name="Enabled",
                property_type="bool",
                default_value=True,
                description="Whether the input is editable"
            ),
            ComponentProperty(
                name="password",
                display_name="Password Mode",
                property_type="bool",
                default_value=False,
                description="Hide input as password"
            ),
            ComponentProperty(
                name="max_length",
                display_name="Max Length",
                property_type="int",
                default_value=100,
                description="Maximum character length"
            ),
            ComponentProperty(
                name="background_color",
                display_name="Background",
                property_type="color",
                default_value="#3c3c3c",
                description="Input background color"
            ),
            ComponentProperty(
                name="text_color",
                display_name="Text Color",
                property_type="color",
                default_value="#cccccc",
                description="Input text color"
            ),
        ]
    
    @classmethod
    def get_events(cls) -> list[ComponentEvent]:
        return [
            ComponentEvent(
                name="onChange",
                display_name="On Change",
                description="Triggered when the text changes"
            ),
            ComponentEvent(
                name="onSubmit",
                display_name="On Submit",
                description="Triggered when Enter is pressed"
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render input for design canvas."""
        input_field = self._create_input()
        input_field.setEnabled(False)
        return input_field
    
    def render_runtime(self) -> QWidget:
        """Render input for runtime execution."""
        input_field = self._create_input()
        input_field.setEnabled(self.get_property("enabled") or True)
        input_field.textChanged.connect(lambda t: self.emit_event("onChange", t))
        input_field.returnPressed.connect(lambda: self.emit_event("onSubmit"))
        return input_field
    
    def _create_input(self) -> QLineEdit:
        """Create the input widget."""
        input_field = QLineEdit()
        input_field.setPlaceholderText(self.get_property("placeholder") or "Enter text...")
        input_field.setText(self.get_property("value") or "")
        input_field.setMaxLength(self.get_property("max_length") or 100)
        
        if self.get_property("password"):
            input_field.setEchoMode(QLineEdit.EchoMode.Password)
        
        bg_color = self.get_property("background_color") or "#3c3c3c"
        text_color = self.get_property("text_color") or "#cccccc"
        
        input_field.setStyleSheet(f"""
            QLineEdit {{
                background-color: {bg_color};
                color: {text_color};
                border: 1px solid #545454;
                border-radius: 4px;
                padding: 6px 10px;
                font-size: 13px;
            }}
            QLineEdit:focus {{
                border-color: #007acc;
            }}
            QLineEdit:disabled {{
                background-color: #2d2d2d;
                color: #666666;
            }}
        """)
        
        return input_field
