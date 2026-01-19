"""Button widget component."""

from PyQt6.QtWidgets import QPushButton, QWidget
from PyQt6.QtCore import Qt

from zeus.core.component import BaseComponent, ComponentProperty, ComponentEvent
from zeus.widgets.registry import register_component


@register_component
class ButtonComponent(BaseComponent):
    """A clickable button component."""
    
    component_type = "button"
    display_name = "Button"
    category = "Form Controls"
    icon = "button.png"
    description = "A clickable button that triggers actions"
    
    default_width = 120
    default_height = 40
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="text",
                display_name="Text",
                property_type="string",
                default_value="Button",
                description="The text displayed on the button"
            ),
            ComponentProperty(
                name="enabled",
                display_name="Enabled",
                property_type="bool",
                default_value=True,
                description="Whether the button is interactive"
            ),
            ComponentProperty(
                name="variant",
                display_name="Variant",
                property_type="enum",
                default_value="primary",
                description="Button style variant",
                options=["primary", "secondary", "outline", "text"]
            ),
            ComponentProperty(
                name="background_color",
                display_name="Background",
                property_type="color",
                default_value="#0e639c",
                description="Button background color"
            ),
            ComponentProperty(
                name="text_color",
                display_name="Text Color",
                property_type="color",
                default_value="#ffffff",
                description="Button text color"
            ),
        ]
    
    @classmethod
    def get_events(cls) -> list[ComponentEvent]:
        return [
            ComponentEvent(
                name="onClick",
                display_name="On Click",
                description="Triggered when the button is clicked"
            ),
            ComponentEvent(
                name="onHover",
                display_name="On Hover",
                description="Triggered when the mouse hovers over the button"
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render button for design canvas."""
        button = QPushButton(self.get_property("text") or "Button")
        button.setEnabled(False)  # Disable in preview mode
        
        bg_color = self.get_property("background_color") or "#0e639c"
        text_color = self.get_property("text_color") or "#ffffff"
        
        button.setStyleSheet(f"""
            QPushButton {{
                background-color: {bg_color};
                color: {text_color};
                border: none;
                border-radius: 4px;
                padding: 8px 16px;
                font-size: 13px;
            }}
        """)
        
        return button
    
    def render_runtime(self) -> QWidget:
        """Render button for runtime execution."""
        button = QPushButton(self.get_property("text") or "Button")
        button.setEnabled(self.get_property("enabled") or True)
        
        bg_color = self.get_property("background_color") or "#0e639c"
        text_color = self.get_property("text_color") or "#ffffff"
        
        button.setStyleSheet(f"""
            QPushButton {{
                background-color: {bg_color};
                color: {text_color};
                border: none;
                border-radius: 4px;
                padding: 8px 16px;
                font-size: 13px;
            }}
            QPushButton:hover {{
                background-color: #1177bb;
            }}
            QPushButton:pressed {{
                background-color: #094771;
            }}
        """)
        
        button.clicked.connect(lambda: self.emit_event("onClick"))
        
        return button
