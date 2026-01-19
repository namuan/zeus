# Zeus Development Plan

## Overview

Zeus is a low-code/no-code desktop platform for developers, built with PyQt6. It provides a visual designer interface to build powerful, scalable applications through drag-and-drop components and visual workflows.

---

## Phase 1: Foundation & Core Architecture

### 1.1 Project Structure Setup
- [ ] Create proper module structure under `src/zeus/`
  - `core/` - Core application logic and state management
  - `ui/` - UI components and widgets
  - `widgets/` - Custom reusable widgets
  - `models/` - Data models and schemas
  - `utils/` - Utility functions and helpers
  - `resources/` - Icons, styles, and assets

### 1.2 Main Window Framework
- [ ] Implement `MainWindow` class extending `QMainWindow`
- [ ] Set up application icon and title
- [ ] Configure window size and positioning
- [ ] Implement dark/light theme support
- [ ] Create application-wide stylesheet (QSS)

### 1.3 Menu Bar & Toolbars
- [ ] File menu (New, Open, Save, Save As, Export, Recent Files, Exit)
- [ ] Edit menu (Undo, Redo, Cut, Copy, Paste, Delete, Select All)
- [ ] View menu (Toggle panels, Zoom, Layout options)
- [ ] Project menu (Run, Debug, Build, Settings)
- [ ] Help menu (Documentation, About, Check for Updates)
- [ ] Quick access toolbar with common actions

---

## Phase 2: UI Layout & Panels

### 2.1 Left Panel - Component Palette
- [ ] Create collapsible/expandable panel widget
- [ ] Implement component categories (Forms, Layout, Data, Navigation, etc.)
- [ ] Add drag-and-drop source functionality for components
- [ ] Create component icons and thumbnails
- [ ] Implement search/filter functionality for components
- [ ] Categories to include:
  - **Form Controls**: Button, TextInput, Checkbox, Radio, Dropdown, Slider
  - **Layout**: Container, Grid, Stack, Tabs, Accordion
  - **Data**: Table, List, Card, Chart, TreeView
  - **Navigation**: Menu, Breadcrumb, Pagination, Sidebar
  - **Media**: Image, Video, Icon, Avatar
  - **Feedback**: Alert, Modal, Toast, Progress, Spinner

### 2.2 Center Panel - Canvas/Designer Area
- [ ] Implement scrollable canvas widget
- [ ] Create grid/snap-to-grid functionality
- [ ] Add zoom controls (zoom in, zoom out, fit to screen)
- [ ] Implement drop target for components
- [ ] Create visual guides and rulers
- [ ] Support multiple artboards/pages
- [ ] Implement selection highlighting
- [ ] Add resize handles for selected components
- [ ] Create alignment guides (smart guides)

### 2.3 Right Panel - Properties Inspector
- [ ] Create tabbed property editor
- [ ] **Properties Tab**: Component-specific property fields
- [ ] **Styles Tab**: Visual styling options (colors, fonts, spacing)
- [ ] **Events Tab**: Event handlers and actions
- [ ] **Data Tab**: Data bindings and expressions
- [ ] Implement property validation
- [ ] Add inline editing for quick changes

### 2.4 Bottom Panel - Output & Logs
- [ ] Create tabbed output area
- [ ] Console/Log output tab
- [ ] Problems/Errors tab
- [ ] Terminal integration tab
- [ ] Search results tab

---

## Phase 3: Component System

### 3.1 Base Component Architecture
- [ ] Create `BaseComponent` abstract class
- [ ] Define component interface (properties, events, methods)
- [ ] Implement component serialization/deserialization
- [ ] Create component factory for instantiation
- [ ] Support component versioning

### 3.2 Component Rendering
- [ ] Implement design-time rendering (preview mode)
- [ ] Implement runtime rendering
- [ ] Support component nesting and hierarchy
- [ ] Create component wrapper for canvas manipulation

### 3.3 Built-in Components
- [ ] Implement core form components
- [ ] Implement layout components
- [ ] Implement data display components
- [ ] Add component documentation/tooltips

---

## Phase 4: Visual Designer Features

### 4.1 Drag & Drop System
- [ ] Implement drag source (from palette)
- [ ] Implement drop target (on canvas)
- [ ] Support reordering via drag & drop
- [ ] Visual feedback during drag operations
- [ ] Support multi-select drag

### 4.2 Selection & Manipulation
- [ ] Single selection with click
- [ ] Multi-selection with Shift+Click or lasso
- [ ] Move components with arrow keys
- [ ] Resize with handles
- [ ] Rotate support (if applicable)
- [ ] Copy/paste components

### 4.3 Undo/Redo System
- [ ] Implement command pattern for actions
- [ ] Create undo/redo stack
- [ ] Support action grouping
- [ ] Persist undo history per session

### 4.4 Layout Tools
- [ ] Align left, center, right
- [ ] Align top, middle, bottom
- [ ] Distribute horizontally/vertically
- [ ] Match width/height
- [ ] Grouping components

---

## Phase 5: Project Management

### 5.1 Project Structure
- [ ] Define project file format (JSON/YAML)
- [ ] Create project templates
- [ ] Support multiple pages/screens
- [ ] Asset management (images, fonts, etc.)

### 5.2 File Operations
- [ ] New project wizard
- [ ] Open project
- [ ] Save/Save As functionality
- [ ] Auto-save feature
- [ ] Recent projects list

### 5.3 Project Explorer (Left Sidebar)
- [ ] Tree view of project files
- [ ] Pages/screens list
- [ ] Components hierarchy view
- [ ] Assets browser

---

## Phase 6: Data & Logic

### 6.1 Data Binding
- [ ] Property binding expressions
- [ ] Two-way data binding
- [ ] Computed properties
- [ ] Data context inheritance

### 6.2 Event System
- [ ] Define standard events (onClick, onChange, onLoad, etc.)
- [ ] Event handler editor
- [ ] Action builder (visual scripting)
- [ ] Custom event support

### 6.3 State Management
- [ ] Application state store
- [ ] Local component state
- [ ] State persistence options

---

## Phase 7: Code Generation & Export

### 7.1 Code Generation
- [ ] Generate Python/PyQt6 code
- [ ] Generate HTML/CSS/JS (web export)
- [ ] Code preview panel
- [ ] Configurable code style

### 7.2 Export Options
- [ ] Export as standalone Python application
- [ ] Export as web application
- [ ] Export project as package
- [ ] Export assets only

---

## Phase 8: Advanced Features

### 8.1 Preview & Testing
- [ ] Live preview mode
- [ ] Responsive preview (different screen sizes)
- [ ] Debug mode with component inspection

### 8.2 Plugin System
- [ ] Plugin architecture design
- [ ] Plugin API definition
- [ ] Custom component plugins
- [ ] Theme plugins

### 8.3 Collaboration (Future)
- [ ] Project sharing
- [ ] Version control integration
- [ ] Cloud sync

---

## Technical Specifications

### Technology Stack
- **Language**: Python 3.12+
- **UI Framework**: PyQt6
- **Project Format**: JSON with schema validation
- **Styling**: QSS (Qt Style Sheets)
- **Build Tool**: uv (package manager)

### Architecture Patterns
- **MVC/MVVM** for UI separation
- **Command Pattern** for undo/redo
- **Factory Pattern** for component creation
- **Observer Pattern** for data binding
- **Composite Pattern** for component hierarchy

### File Structure (Target)
```
src/zeus/
├── __init__.py
├── __main__.py
├── app.py                 # Application entry point
├── core/
│   ├── __init__.py
│   ├── component.py       # Base component class
│   ├── project.py         # Project management
│   ├── commands.py        # Undo/redo commands
│   └── state.py           # State management
├── ui/
│   ├── __init__.py
│   ├── main_window.py     # Main window
│   ├── canvas.py          # Design canvas
│   ├── palette.py         # Component palette
│   ├── properties.py      # Properties panel
│   └── explorer.py        # Project explorer
├── widgets/
│   ├── __init__.py
│   ├── button.py
│   ├── input.py
│   └── ...                # Built-in widgets
├── models/
│   ├── __init__.py
│   └── schema.py          # Data schemas
├── utils/
│   ├── __init__.py
│   └── helpers.py
└── resources/
    ├── icons/
    ├── styles/
    └── themes/
```

---

## Development Milestones

| Milestone | Description | Target |
|-----------|-------------|--------|
| M1 | Basic window with menu bar and empty panels | Week 1-2 |
| M2 | Component palette with drag support | Week 3-4 |
| M3 | Canvas with drop and selection | Week 5-6 |
| M4 | Properties panel with editing | Week 7-8 |
| M5 | Core components (Button, Input, Label) | Week 9-10 |
| M6 | Project save/load functionality | Week 11-12 |
| M7 | Undo/redo and advanced editing | Week 13-14 |
| M8 | Code generation and export | Week 15-16 |
| M9 | Polish, testing, and documentation | Week 17-18 |

---

## Next Steps

1. **Immediate**: Set up the module structure and create basic `MainWindow`
2. **Short-term**: Implement the three-panel layout (palette, canvas, properties)
3. **Medium-term**: Build the component system and drag-drop functionality
4. **Long-term**: Add code generation and export capabilities

---

## References

- [PyQt6 Documentation](https://www.riverbankcomputing.com/static/Docs/PyQt6/)
- [Qt Designer Manual](https://doc.qt.io/qt-6/qtdesigner-manual.html)
- [Low-Code Platform Design Patterns](https://www.outsystems.com/low-code-platforms/)
