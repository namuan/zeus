"""Image widget component."""

from PyQt6.QtWidgets import QLabel, QWidget
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QPixmap

from zeus.core.component import BaseComponent, ComponentProperty
from zeus.widgets.registry import register_component


@register_component
class ImageComponent(BaseComponent):
    """An image display component."""
    
    component_type = "image"
    display_name = "Image"
    category = "Media"
    icon = "image.png"
    description = "Displays an image from file or URL"
    
    default_width = 200
    default_height = 150
    
    @classmethod
    def get_properties(cls) -> list[ComponentProperty]:
        return [
            ComponentProperty(
                name="source",
                display_name="Source",
                property_type="string",
                default_value="",
                description="Image file path or URL"
            ),
            ComponentProperty(
                name="alt_text",
                display_name="Alt Text",
                property_type="string",
                default_value="Image",
                description="Alternative text for accessibility"
            ),
            ComponentProperty(
                name="fit",
                display_name="Fit",
                property_type="enum",
                default_value="contain",
                description="How the image fits in the container",
                options=["contain", "cover", "fill", "none"]
            ),
            ComponentProperty(
                name="border_radius",
                display_name="Border Radius",
                property_type="int",
                default_value=0,
                description="Corner radius for rounded images"
            ),
        ]
    
    def render_preview(self) -> QWidget:
        """Render image placeholder for design canvas."""
        return self._create_image_widget(preview=True)
    
    def render_runtime(self) -> QWidget:
        """Render image for runtime execution."""
        return self._create_image_widget(preview=False)
    
    def _create_image_widget(self, preview: bool = False) -> QLabel:
        """Create the image widget."""
        label = QLabel()
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        
        source = self.get_property("source")
        alt_text = self.get_property("alt_text") or "Image"
        border_radius = self.get_property("border_radius") or 0
        
        # Try to load the image
        if source and not preview:
            pixmap = QPixmap(source)
            if not pixmap.isNull():
                fit = self.get_property("fit") or "contain"
                if fit == "contain":
                    scaled = pixmap.scaled(
                        self.width, self.height,
                        Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation
                    )
                elif fit == "cover":
                    scaled = pixmap.scaled(
                        self.width, self.height,
                        Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                        Qt.TransformationMode.SmoothTransformation
                    )
                elif fit == "fill":
                    scaled = pixmap.scaled(
                        self.width, self.height,
                        Qt.AspectRatioMode.IgnoreAspectRatio,
                        Qt.TransformationMode.SmoothTransformation
                    )
                else:
                    scaled = pixmap
                
                label.setPixmap(scaled)
            else:
                label.setText(f"[{alt_text}]")
        else:
            # Show placeholder
            label.setText(f"🖼 {alt_text}")
        
        label.setStyleSheet(f"""
            QLabel {{
                background-color: #2d2d2d;
                border: 1px dashed #555555;
                border-radius: {border_radius}px;
                color: #888888;
                font-size: 12px;
            }}
        """)
        
        return label
