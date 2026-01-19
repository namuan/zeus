"""Built-in widgets and component registry."""

from zeus.widgets.registry import COMPONENT_REGISTRY, register_component, create_component
from zeus.widgets.button import ButtonComponent
from zeus.widgets.label import LabelComponent
from zeus.widgets.input import TextInputComponent
from zeus.widgets.checkbox import CheckboxComponent
from zeus.widgets.container import ContainerComponent
from zeus.widgets.image import ImageComponent

__all__ = [
    "COMPONENT_REGISTRY",
    "register_component",
    "create_component",
    "ButtonComponent",
    "LabelComponent",
    "TextInputComponent",
    "CheckboxComponent",
    "ContainerComponent",
    "ImageComponent",
]
