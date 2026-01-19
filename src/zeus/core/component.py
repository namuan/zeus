"""Base component class for all visual components."""

from abc import ABC, abstractmethod
from typing import Any, Optional
from dataclasses import dataclass, field
from uuid import uuid4


@dataclass
class ComponentProperty:
    """Defines a property for a component."""
    name: str
    display_name: str
    property_type: str  # 'string', 'int', 'float', 'bool', 'color', 'enum'
    default_value: Any
    description: str = ""
    options: list[str] = field(default_factory=list)  # For enum types


@dataclass
class ComponentEvent:
    """Defines an event that a component can emit."""
    name: str
    display_name: str
    description: str = ""


class BaseComponent(ABC):
    """Abstract base class for all visual components."""
    
    # Component metadata
    component_type: str = "base"
    display_name: str = "Base Component"
    category: str = "General"
    icon: str = "component.png"
    description: str = "Base component"
    
    def __init__(self, x: int = 0, y: int = 0, width: int = 100, height: int = 50):
        self.id = str(uuid4())
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.parent_id: Optional[str] = None
        self.children: list[str] = []
        self._properties: dict[str, Any] = {}
        self._event_handlers: dict[str, list[callable]] = {}
        
        # Initialize with default property values
        for prop in self.get_properties():
            self._properties[prop.name] = prop.default_value
    
    @classmethod
    @abstractmethod
    def get_properties(cls) -> list[ComponentProperty]:
        """Return the list of editable properties for this component."""
        return []
    
    @classmethod
    def get_events(cls) -> list[ComponentEvent]:
        """Return the list of events this component can emit."""
        return []
    
    def get_property(self, name: str) -> Any:
        """Get a property value."""
        return self._properties.get(name)
    
    def set_property(self, name: str, value: Any) -> None:
        """Set a property value."""
        self._properties[name] = value
    
    def add_event_handler(self, event_name: str, handler: callable) -> None:
        """Add an event handler."""
        if event_name not in self._event_handlers:
            self._event_handlers[event_name] = []
        self._event_handlers[event_name].append(handler)
    
    def emit_event(self, event_name: str, *args, **kwargs) -> None:
        """Emit an event to all registered handlers."""
        for handler in self._event_handlers.get(event_name, []):
            handler(*args, **kwargs)
    
    def to_dict(self) -> dict:
        """Serialize component to dictionary."""
        return {
            "id": self.id,
            "type": self.component_type,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
            "parent_id": self.parent_id,
            "children": self.children,
            "properties": self._properties.copy()
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "BaseComponent":
        """Deserialize component from dictionary."""
        component = cls(
            x=data.get("x", 0),
            y=data.get("y", 0),
            width=data.get("width", 100),
            height=data.get("height", 50)
        )
        component.id = data.get("id", component.id)
        component.parent_id = data.get("parent_id")
        component.children = data.get("children", [])
        component._properties.update(data.get("properties", {}))
        return component
    
    @abstractmethod
    def render_preview(self):
        """Render the component for the design canvas (returns QWidget)."""
        pass
    
    @abstractmethod
    def render_runtime(self):
        """Render the component for runtime execution (returns QWidget)."""
        pass
