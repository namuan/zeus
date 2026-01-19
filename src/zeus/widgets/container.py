"""Container widget component."""

from PyQt6.QtWidgets import QFrame, QWidget, QVBoxLayout
from PyQt6.QtCore import Qt

from zeus.core.component import BaseComponent, ComponentProperty
from zeus.widgets.registry import register_component


@register_component
class ContainerComponent(BaseComponent):
    """A container for grouping other components."""
    
    component_type = "container"
    display_name = "Container"
    category = "Layout"
    icon = "container.png"
    description = "A container for grouping and organizing components"
    
    default_width = 300
    default_height = 200
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="background_color",
                display_name="Background",
                property_type="color",
                default_value="#2d2d2d",
                description="Container background color"
            ),
            ComponentProperty(
                name="border_width",
                display_name="Border Width",
                property_type="int",
                default_value=1,
                description="Border width in pixels"
            ),
            ComponentProperty(
                name="border_color",
                display_name="Border Color",
                property_type="color",
                default_value="#3c3c3c",
                description="Border color"
            ),
            ComponentProperty(
                name="border_radius",
                display_name="Border Radius",
                property_type="int",
                default_value=4,
                description="Border corner radius"
            ),
            ComponentProperty(
                name="padding",
                display_name="Padding",
                property_type="int",
                default_value=10,
                description="Inner padding in pixels"
            ),
            ComponentProperty(
                name="layout",
                display_name="Layout",
                property_type="enum",
                default_value="vertical",
                description="Child layout direction",
                options=["vertical", "horizontal", "none"]
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render container for design canvas."""
        return self._create_container()
    
    def render_runtime(self) -> QWidget:
        """Render container for runtime execution."""
        return self._create_container()
    
    def _create_container(self) -> QFrame:
        """Create the container widget."""
        container = QFrame()
        container.setFrameShape(QFrame.Shape.StyledPanel)
        
        bg_color = self.get_property("background_color") or "#2d2d2d"
        border_width = self.get_property("border_width") or 1
        border_color = self.get_property("border_color") or "#3c3c3c"
        border_radius = self.get_property("border_radius") or 4
        padding = self.get_property("padding") or 10
        
        container.setStyleSheet(f"""
            QFrame {{
                background-color: {bg_color};
                border: {border_width}px solid {border_color};
                border-radius: {border_radius}px;
            }}
        """)
        
        # Set up layout
        layout_type = self.get_property("layout") or "vertical"
        if layout_type != "none":
            layout = QVBoxLayout(container)
            layout.setContentsMargins(padding, padding, padding, padding)
        
        return container
