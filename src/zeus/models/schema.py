"""JSON Schema definitions for Zeus projects."""

from typing import Any, Optional
import json

# JSON Schema for Zeus project files
PROJECT_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "title": "Zeus Project",
    "required": ["name", "version", "pages"],
    "properties": {
        "name": {
            "type": "string",
            "description": "Project name"
        },
        "description": {
            "type": "string",
            "description": "Project description"
        },
        "version": {
            "type": "string",
            "description": "Project version"
        },
        "created_at": {
            "type": "string",
            "format": "date-time"
        },
        "modified_at": {
            "type": "string",
            "format": "date-time"
        },
        "pages": {
            "type": "array",
            "items": {"$ref": "#/definitions/page"}
        },
        "assets": {
            "type": "array",
            "items": {"type": "string"}
        },
        "settings": {
            "type": "object"
        }
    },
    "definitions": {
        "page": {
            "type": "object",
            "required": ["id", "name"],
            "properties": {
                "id": {"type": "string"},
                "name": {"type": "string"},
                "width": {"type": "integer", "minimum": 100},
                "height": {"type": "integer", "minimum": 100},
                "components": {
                    "type": "array",
                    "items": {"$ref": "#/definitions/component"}
                }
            }
        },
        "component": {
            "type": "object",
            "required": ["id", "type", "x", "y", "width", "height"],
            "properties": {
                "id": {"type": "string"},
                "type": {"type": "string"},
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer", "minimum": 1},
                "height": {"type": "integer", "minimum": 1},
                "parent_id": {"type": ["string", "null"]},
                "children": {
                    "type": "array",
                    "items": {"type": "string"}
                },
                "properties": {"type": "object"}
            }
        }
    }
}


class ProjectSchema:
    """Schema wrapper for project validation."""
    
    @staticmethod
    def get_schema() -> dict:
        return PROJECT_SCHEMA


class PageSchema:
    """Schema wrapper for page validation."""
    
    @staticmethod
    def get_schema() -> dict:
        return PROJECT_SCHEMA["definitions"]["page"]


class ComponentSchema:
    """Schema wrapper for component validation."""
    
    @staticmethod
    def get_schema() -> dict:
        return PROJECT_SCHEMA["definitions"]["component"]


def validate_project(data: dict) -> tuple[bool, Optional[str]]:
    """Validate project data against schema.
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    # Basic validation without jsonschema dependency
    if not isinstance(data, dict):
        return False, "Project must be a dictionary"
    
    if "name" not in data:
        return False, "Project must have a name"
    
    if "version" not in data:
        return False, "Project must have a version"
    
    if "pages" not in data or not isinstance(data["pages"], list):
        return False, "Project must have a pages array"
    
    for i, page in enumerate(data["pages"]):
        if not isinstance(page, dict):
            return False, f"Page {i} must be a dictionary"
        if "id" not in page:
            return False, f"Page {i} must have an id"
        if "name" not in page:
            return False, f"Page {i} must have a name"
    
    return True, None
