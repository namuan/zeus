"""Project management for Zeus applications."""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
from datetime import datetime


@dataclass
class Page:
    """Represents a single page/screen in the project."""
    id: str
    name: str
    components: list[dict] = field(default_factory=list)
    width: int = 800
    height: int = 600
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "components": self.components,
            "width": self.width,
            "height": self.height
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "Page":
        return cls(
            id=data["id"],
            name=data["name"],
            components=data.get("components", []),
            width=data.get("width", 800),
            height=data.get("height", 600)
        )


@dataclass
class Project:
    """Represents a Zeus project."""
    name: str = "Untitled Project"
    description: str = ""
    version: str = "1.0.0"
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    modified_at: str = field(default_factory=lambda: datetime.now().isoformat())
    pages: list[Page] = field(default_factory=list)
    assets: list[str] = field(default_factory=list)
    settings: dict = field(default_factory=dict)
    file_path: Optional[Path] = None
    
    def __post_init__(self):
        # Ensure there's at least one page
        if not self.pages:
            from uuid import uuid4
            self.pages.append(Page(id=str(uuid4()), name="Main Page"))
    
    def add_page(self, name: str) -> Page:
        """Add a new page to the project."""
        from uuid import uuid4
        page = Page(id=str(uuid4()), name=name)
        self.pages.append(page)
        self.mark_modified()
        return page
    
    def remove_page(self, page_id: str) -> bool:
        """Remove a page from the project."""
        for i, page in enumerate(self.pages):
            if page.id == page_id:
                self.pages.pop(i)
                self.mark_modified()
                return True
        return False
    
    def get_page(self, page_id: str) -> Optional[Page]:
        """Get a page by ID."""
        for page in self.pages:
            if page.id == page_id:
                return page
        return None
    
    def mark_modified(self) -> None:
        """Update the modified timestamp."""
        self.modified_at = datetime.now().isoformat()
    
    def to_dict(self) -> dict:
        """Serialize project to dictionary."""
        return {
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "created_at": self.created_at,
            "modified_at": self.modified_at,
            "pages": [page.to_dict() for page in self.pages],
            "assets": self.assets,
            "settings": self.settings
        }
    
    @classmethod
    def from_dict(cls, data: dict, file_path: Optional[Path] = None) -> "Project":
        """Deserialize project from dictionary."""
        pages = [Page.from_dict(p) for p in data.get("pages", [])]
        return cls(
            name=data.get("name", "Untitled Project"),
            description=data.get("description", ""),
            version=data.get("version", "1.0.0"),
            created_at=data.get("created_at", datetime.now().isoformat()),
            modified_at=data.get("modified_at", datetime.now().isoformat()),
            pages=pages,
            assets=data.get("assets", []),
            settings=data.get("settings", {}),
            file_path=file_path
        )
    
    def save(self, file_path: Optional[Path] = None) -> None:
        """Save project to file."""
        path = file_path or self.file_path
        if path is None:
            raise ValueError("No file path specified for saving")
        
        self.file_path = path
        self.mark_modified()
        
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(self.to_dict(), f, indent=2)
    
    @classmethod
    def load(cls, file_path: Path) -> "Project":
        """Load project from file."""
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return cls.from_dict(data, file_path)
    
    @classmethod
    def create_new(cls, name: str = "Untitled Project") -> "Project":
        """Create a new empty project."""
        return cls(name=name)
