"""Command pattern implementation for undo/redo functionality."""

from abc import ABC, abstractmethod
from typing import Any, Optional
from dataclasses import dataclass


class Command(ABC):
    """Abstract base class for undoable commands."""
    
    @property
    @abstractmethod
    def description(self) -> str:
        """Human-readable description of the command."""
        pass
    
    @abstractmethod
    def execute(self) -> None:
        """Execute the command."""
        pass
    
    @abstractmethod
    def undo(self) -> None:
        """Undo the command."""
        pass
    
    def redo(self) -> None:
        """Redo the command. By default, just execute again."""
        self.execute()


class CommandStack:
    """Manages undo/redo history."""
    
    def __init__(self, max_size: int = 100):
        self._undo_stack: list[Command] = []
        self._redo_stack: list[Command] = []
        self._max_size = max_size
        self._is_executing = False
    
    def execute(self, command: Command) -> None:
        """Execute a command and add it to the undo stack."""
        if self._is_executing:
            return
        
        self._is_executing = True
        try:
            command.execute()
            self._undo_stack.append(command)
            self._redo_stack.clear()  # Clear redo stack on new command
            
            # Limit stack size
            while len(self._undo_stack) > self._max_size:
                self._undo_stack.pop(0)
        finally:
            self._is_executing = False
    
    def undo(self) -> Optional[Command]:
        """Undo the last command."""
        if not self._undo_stack:
            return None
        
        command = self._undo_stack.pop()
        command.undo()
        self._redo_stack.append(command)
        return command
    
    def redo(self) -> Optional[Command]:
        """Redo the last undone command."""
        if not self._redo_stack:
            return None
        
        command = self._redo_stack.pop()
        command.redo()
        self._undo_stack.append(command)
        return command
    
    def can_undo(self) -> bool:
        """Check if there are commands to undo."""
        return len(self._undo_stack) > 0
    
    def can_redo(self) -> bool:
        """Check if there are commands to redo."""
        return len(self._redo_stack) > 0
    
    def clear(self) -> None:
        """Clear all command history."""
        self._undo_stack.clear()
        self._redo_stack.clear()
    
    def get_undo_description(self) -> Optional[str]:
        """Get description of the command that would be undone."""
        if self._undo_stack:
            return self._undo_stack[-1].description
        return None
    
    def get_redo_description(self) -> Optional[str]:
        """Get description of the command that would be redone."""
        if self._redo_stack:
            return self._redo_stack[-1].description
        return None


# Common Commands

@dataclass
class AddComponentCommand(Command):
    """Command to add a component to the canvas."""
    canvas: Any  # Reference to canvas
    component: Any  # Component to add
    
    @property
    def description(self) -> str:
        return f"Add {self.component.display_name}"
    
    def execute(self) -> None:
        self.canvas.add_component(self.component)
    
    def undo(self) -> None:
        self.canvas.remove_component(self.component.id)


@dataclass
class RemoveComponentCommand(Command):
    """Command to remove a component from the canvas."""
    canvas: Any
    component: Any
    
    @property
    def description(self) -> str:
        return f"Remove {self.component.display_name}"
    
    def execute(self) -> None:
        self.canvas.remove_component(self.component.id)
    
    def undo(self) -> None:
        self.canvas.add_component(self.component)


@dataclass
class MoveComponentCommand(Command):
    """Command to move a component."""
    component: Any
    old_x: int
    old_y: int
    new_x: int
    new_y: int
    
    @property
    def description(self) -> str:
        return f"Move {self.component.display_name}"
    
    def execute(self) -> None:
        self.component.x = self.new_x
        self.component.y = self.new_y
    
    def undo(self) -> None:
        self.component.x = self.old_x
        self.component.y = self.old_y


@dataclass
class ResizeComponentCommand(Command):
    """Command to resize a component."""
    component: Any
    old_width: int
    old_height: int
    new_width: int
    new_height: int
    
    @property
    def description(self) -> str:
        return f"Resize {self.component.display_name}"
    
    def execute(self) -> None:
        self.component.width = self.new_width
        self.component.height = self.new_height
    
    def undo(self) -> None:
        self.component.width = self.old_width
        self.component.height = self.old_height


@dataclass
class ChangePropertyCommand(Command):
    """Command to change a component property."""
    component: Any
    property_name: str
    old_value: Any
    new_value: Any
    
    @property
    def description(self) -> str:
        return f"Change {self.property_name}"
    
    def execute(self) -> None:
        self.component.set_property(self.property_name, self.new_value)
    
    def undo(self) -> None:
        self.component.set_property(self.property_name, self.old_value)
