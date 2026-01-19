"""Application state management."""

from typing import Any, Optional, Callable
from dataclasses import dataclass, field
from enum import Enum

from zeus.core.project import Project
from zeus.core.commands import CommandStack


class EditorMode(Enum):
    """Editor interaction modes."""
    SELECT = "select"
    PAN = "pan"
    ZOOM = "zoom"


@dataclass
class SelectionState:
    """Tracks the current selection in the editor."""
    selected_ids: list[str] = field(default_factory=list)
    
    def clear(self) -> None:
        self.selected_ids.clear()
    
    def select(self, component_id: str) -> None:
        self.selected_ids = [component_id]
    
    def add_to_selection(self, component_id: str) -> None:
        if component_id not in self.selected_ids:
            self.selected_ids.append(component_id)
    
    def remove_from_selection(self, component_id: str) -> None:
        if component_id in self.selected_ids:
            self.selected_ids.remove(component_id)
    
    def is_selected(self, component_id: str) -> bool:
        return component_id in self.selected_ids
    
    def has_selection(self) -> bool:
        return len(self.selected_ids) > 0
    
    def is_multi_select(self) -> bool:
        return len(self.selected_ids) > 1


class AppState:
    """Global application state container."""
    
    _instance: Optional["AppState"] = None
    
    def __new__(cls) -> "AppState":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        
        self._initialized = True
        self._project: Optional[Project] = None
        self._current_page_id: Optional[str] = None
        self._selection = SelectionState()
        self._command_stack = CommandStack()
        self._editor_mode = EditorMode.SELECT
        self._zoom_level: float = 1.0
        self._grid_visible: bool = True
        self._grid_snap: bool = True
        self._grid_size: int = 10
        self._theme: str = "dark"
        self._listeners: dict[str, list[Callable]] = {}
    
    @property
    def project(self) -> Optional[Project]:
        return self._project
    
    @project.setter
    def project(self, value: Optional[Project]) -> None:
        self._project = value
        if value and value.pages:
            self._current_page_id = value.pages[0].id
        else:
            self._current_page_id = None
        self._notify("project_changed", value)
    
    @property
    def current_page_id(self) -> Optional[str]:
        return self._current_page_id
    
    @current_page_id.setter
    def current_page_id(self, value: Optional[str]) -> None:
        self._current_page_id = value
        self._selection.clear()
        self._notify("page_changed", value)
    
    @property
    def selection(self) -> SelectionState:
        return self._selection
    
    @property
    def command_stack(self) -> CommandStack:
        return self._command_stack
    
    @property
    def editor_mode(self) -> EditorMode:
        return self._editor_mode
    
    @editor_mode.setter
    def editor_mode(self, value: EditorMode) -> None:
        self._editor_mode = value
        self._notify("editor_mode_changed", value)
    
    @property
    def zoom_level(self) -> float:
        return self._zoom_level
    
    @zoom_level.setter
    def zoom_level(self, value: float) -> None:
        self._zoom_level = max(0.1, min(5.0, value))
        self._notify("zoom_changed", self._zoom_level)
    
    @property
    def grid_visible(self) -> bool:
        return self._grid_visible
    
    @grid_visible.setter
    def grid_visible(self, value: bool) -> None:
        self._grid_visible = value
        self._notify("grid_visibility_changed", value)
    
    @property
    def grid_snap(self) -> bool:
        return self._grid_snap
    
    @grid_snap.setter
    def grid_snap(self, value: bool) -> None:
        self._grid_snap = value
        self._notify("grid_snap_changed", value)
    
    @property
    def grid_size(self) -> int:
        return self._grid_size
    
    @grid_size.setter
    def grid_size(self, value: int) -> None:
        self._grid_size = max(5, min(50, value))
        self._notify("grid_size_changed", self._grid_size)
    
    @property
    def theme(self) -> str:
        return self._theme
    
    @theme.setter
    def theme(self, value: str) -> None:
        self._theme = value
        self._notify("theme_changed", value)
    
    def subscribe(self, event: str, callback: Callable) -> None:
        """Subscribe to state change events."""
        if event not in self._listeners:
            self._listeners[event] = []
        self._listeners[event].append(callback)
    
    def unsubscribe(self, event: str, callback: Callable) -> None:
        """Unsubscribe from state change events."""
        if event in self._listeners:
            self._listeners[event].remove(callback)
    
    def _notify(self, event: str, data: Any = None) -> None:
        """Notify all listeners of a state change."""
        for callback in self._listeners.get(event, []):
            callback(data)
    
    def select_component(self, component_id: str, add_to_selection: bool = False) -> None:
        """Select a component."""
        if add_to_selection:
            self._selection.add_to_selection(component_id)
        else:
            self._selection.select(component_id)
        self._notify("selection_changed", self._selection.selected_ids)
    
    def clear_selection(self) -> None:
        """Clear the current selection."""
        self._selection.clear()
        self._notify("selection_changed", [])
    
    def reset(self) -> None:
        """Reset state to initial values."""
        self._project = None
        self._current_page_id = None
        self._selection.clear()
        self._command_stack.clear()
        self._editor_mode = EditorMode.SELECT
        self._zoom_level = 1.0
