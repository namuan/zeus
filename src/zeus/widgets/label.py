"""Label widget component."""

from PyQt6.QtWidgets import QLabel, QWidget
from PyQt6.QtCore import Qt

from zeus.core.component import BaseComponent, ComponentProperty
from zeus.widgets.registry import register_component


@register_component
class LabelComponent(BaseComponent):
    """A text label component."""
    
    component_type = "label"
    display_name = "Label"
    category = "Form Controls"
    icon = "label.png"
    description = "A text label for displaying static text"
    
    default_width = 100
    default_height = 30
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="text",
                display_name="Text",
                property_type="string",
                default_value="Label",
                description="The text content of the label"
            ),
            ComponentProperty(
                name="font_size",
                display_name="Font Size",
                property_type="int",
                default_value=14,
                description="Font size in pixels"
            ),
            ComponentProperty(
                name="text_color",
                display_name="Text Color",
                property_type="color",
                default_value="#cccccc",
                description="Text color"
            ),
            ComponentProperty(
                name="alignment",
                display_name="Alignment",
                property_type="enum",
                default_value="left",
                description="Text alignment",
                options=["left", "center", "right"]
            ),
            ComponentProperty(
                name="bold",
                display_name="Bold",
                property_type="bool",
                default_value=False,
                description="Whether the text is bold"
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render label for design canvas."""
        return self._create_label()
    
    def render_runtime(self) -> QWidget:
        """Render label for runtime execution."""
        return self._create_label()
    
    def _create_label(self) -> QLabel:
        """Create the label widget."""
        label = QLabel(self.get_property("text") or "Label")
        
        font_size = self.get_property("font_size") or 14
        text_color = self.get_property("text_color") or "#cccccc"
        bold = "bold" if self.get_property("bold") else "normal"
        
        alignment_map = {
            "left": Qt.AlignmentFlag.AlignLeft,
            "center": Qt.AlignmentFlag.AlignCenter,
            "right": Qt.AlignmentFlag.AlignRight,
        }
        alignment = alignment_map.get(self.get_property("alignment") or "left", 
                                      Qt.AlignmentFlag.AlignLeft)
        
        label.setAlignment(alignment | Qt.AlignmentFlag.AlignVCenter)
        label.setStyleSheet(f"""
            QLabel {{
                color: {text_color};
                font-size: {font_size}px;
                font-weight: {bold};
                background-color: transparent;
            }}
        """)
        
        return label
