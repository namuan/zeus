"""Component registry for managing available components."""

from typing import Type, Optional

# Global component registry
COMPONENT_REGISTRY: dict[str, Type] = {}


def register_component(component_class: Type) -> Type:
    """Decorator to register a component class."""
    COMPONENT_REGISTRY[component_class.component_type] = component_class
    return component_class


def create_component(component_type: str, x: int = 0, y: int = 0, 
                     width: int = None, height: int = None):
    """Factory function to create a component instance."""
    if component_type not in COMPONENT_REGISTRY:
        return None
    
    component_class = COMPONENT_REGISTRY[component_type]
    
    # Get default size from class
    if width is None:
        width = getattr(component_class, 'default_width', 100)
    if height is None:
        height = getattr(component_class, 'default_height', 40)
    
    return component_class(x=x, y=y, width=width, height=height)


def get_component_class(component_type: str) -> Optional[Type]:
    """Get a component class by type."""
    return COMPONENT_REGISTRY.get(component_type)
