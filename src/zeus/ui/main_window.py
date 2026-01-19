"""Main application window for Zeus."""

from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QMenuBar, QMenu, QToolBar, QStatusBar, QSplitter,
    QMessageBox, QFileDialog, QApplication
)
from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QAction, QKeySequence, QIcon

from zeus.core.state import AppState
from zeus.core.project import Project
from zeus.ui.canvas import DesignCanvas
from zeus.ui.palette import ComponentPalette
from zeus.ui.properties import PropertiesPanel
from zeus.ui.explorer import ProjectExplorer
from zeus.ui.output import OutputPanel


class MainWindow(QMainWindow):
    """Main application window with menu bar, toolbars, and panel layout."""
    
    def __init__(self):
        super().__init__()
        self.state = AppState()
        self._setup_window()
        self._create_actions()
        self._create_menus()
        self._create_toolbars()
        self._create_panels()
        self._create_status_bar()
        self._apply_theme()
        
        # Create initial project
        self._new_project()
    
    def _setup_window(self) -> None:
        """Configure main window properties."""
        self.setWindowTitle("Zeus - Visual Application Designer")
        self.setMinimumSize(1200, 800)
        self.resize(1400, 900)
        
        # Center window on screen
        screen = QApplication.primaryScreen().geometry()
        x = (screen.width() - self.width()) // 2
        y = (screen.height() - self.height()) // 2
        self.move(x, y)
    
    def _create_actions(self) -> None:
        """Create all menu and toolbar actions."""
        # File actions
        self.action_new = QAction("&New Project", self)
        self.action_new.setShortcut(QKeySequence.StandardKey.New)
        self.action_new.triggered.connect(self._new_project)
        
        self.action_open = QAction("&Open Project...", self)
        self.action_open.setShortcut(QKeySequence.StandardKey.Open)
        self.action_open.triggered.connect(self._open_project)
        
        self.action_save = QAction("&Save", self)
        self.action_save.setShortcut(QKeySequence.StandardKey.Save)
        self.action_save.triggered.connect(self._save_project)
        
        self.action_save_as = QAction("Save &As...", self)
        self.action_save_as.setShortcut(QKeySequence("Ctrl+Shift+S"))
        self.action_save_as.triggered.connect(self._save_project_as)
        
        self.action_exit = QAction("E&xit", self)
        self.action_exit.setShortcut(QKeySequence.StandardKey.Quit)
        self.action_exit.triggered.connect(self.close)
        
        # Edit actions
        self.action_undo = QAction("&Undo", self)
        self.action_undo.setShortcut(QKeySequence.StandardKey.Undo)
        self.action_undo.triggered.connect(self._undo)
        
        self.action_redo = QAction("&Redo", self)
        self.action_redo.setShortcut(QKeySequence.StandardKey.Redo)
        self.action_redo.triggered.connect(self._redo)
        
        self.action_cut = QAction("Cu&t", self)
        self.action_cut.setShortcut(QKeySequence.StandardKey.Cut)
        
        self.action_copy = QAction("&Copy", self)
        self.action_copy.setShortcut(QKeySequence.StandardKey.Copy)
        
        self.action_paste = QAction("&Paste", self)
        self.action_paste.setShortcut(QKeySequence.StandardKey.Paste)
        
        self.action_delete = QAction("&Delete", self)
        self.action_delete.setShortcut(QKeySequence.StandardKey.Delete)
        self.action_delete.triggered.connect(self._delete_selected)
        
        self.action_select_all = QAction("Select &All", self)
        self.action_select_all.setShortcut(QKeySequence.StandardKey.SelectAll)
        
        # View actions
        self.action_zoom_in = QAction("Zoom &In", self)
        self.action_zoom_in.setShortcut(QKeySequence.StandardKey.ZoomIn)
        self.action_zoom_in.triggered.connect(self._zoom_in)
        
        self.action_zoom_out = QAction("Zoom &Out", self)
        self.action_zoom_out.setShortcut(QKeySequence.StandardKey.ZoomOut)
        self.action_zoom_out.triggered.connect(self._zoom_out)
        
        self.action_zoom_fit = QAction("&Fit to Screen", self)
        self.action_zoom_fit.setShortcut(QKeySequence("Ctrl+0"))
        self.action_zoom_fit.triggered.connect(self._zoom_fit)
        
        self.action_toggle_grid = QAction("Show &Grid", self)
        self.action_toggle_grid.setCheckable(True)
        self.action_toggle_grid.setChecked(True)
        self.action_toggle_grid.triggered.connect(self._toggle_grid)
        
        self.action_toggle_snap = QAction("&Snap to Grid", self)
        self.action_toggle_snap.setCheckable(True)
        self.action_toggle_snap.setChecked(True)
        self.action_toggle_snap.triggered.connect(self._toggle_snap)
        
        # Project actions
        self.action_run = QAction("&Run", self)
        self.action_run.setShortcut(QKeySequence("F5"))
        self.action_run.triggered.connect(self._run_preview)
        
        self.action_settings = QAction("Project &Settings...", self)
        
        # Help actions
        self.action_about = QAction("&About Zeus", self)
        self.action_about.triggered.connect(self._show_about)
    
    def _create_menus(self) -> None:
        """Create the menu bar and menus."""
        menubar = self.menuBar()
        
        # File menu
        file_menu = menubar.addMenu("&File")
        file_menu.addAction(self.action_new)
        file_menu.addAction(self.action_open)
        file_menu.addSeparator()
        file_menu.addAction(self.action_save)
        file_menu.addAction(self.action_save_as)
        file_menu.addSeparator()
        file_menu.addAction(self.action_exit)
        
        # Edit menu
        edit_menu = menubar.addMenu("&Edit")
        edit_menu.addAction(self.action_undo)
        edit_menu.addAction(self.action_redo)
        edit_menu.addSeparator()
        edit_menu.addAction(self.action_cut)
        edit_menu.addAction(self.action_copy)
        edit_menu.addAction(self.action_paste)
        edit_menu.addAction(self.action_delete)
        edit_menu.addSeparator()
        edit_menu.addAction(self.action_select_all)
        
        # View menu
        view_menu = menubar.addMenu("&View")
        view_menu.addAction(self.action_zoom_in)
        view_menu.addAction(self.action_zoom_out)
        view_menu.addAction(self.action_zoom_fit)
        view_menu.addSeparator()
        view_menu.addAction(self.action_toggle_grid)
        view_menu.addAction(self.action_toggle_snap)
        
        # Project menu
        project_menu = menubar.addMenu("&Project")
        project_menu.addAction(self.action_run)
        project_menu.addSeparator()
        project_menu.addAction(self.action_settings)
        
        # Help menu
        help_menu = menubar.addMenu("&Help")
        help_menu.addAction(self.action_about)
    
    def _create_toolbars(self) -> None:
        """Create the main toolbar."""
        toolbar = QToolBar("Main Toolbar")
        toolbar.setMovable(False)
        toolbar.setIconSize(QSize(24, 24))
        self.addToolBar(toolbar)
        
        toolbar.addAction(self.action_new)
        toolbar.addAction(self.action_open)
        toolbar.addAction(self.action_save)
        toolbar.addSeparator()
        toolbar.addAction(self.action_undo)
        toolbar.addAction(self.action_redo)
        toolbar.addSeparator()
        toolbar.addAction(self.action_run)
    
    def _create_panels(self) -> None:
        """Create the main panel layout."""
        # Main widget and layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # Vertical splitter for main area and bottom panel
        self.v_splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(self.v_splitter)
        
        # Horizontal splitter for left, center, right panels
        self.h_splitter = QSplitter(Qt.Orientation.Horizontal)
        self.v_splitter.addWidget(self.h_splitter)
        
        # Left panel - Component Palette and Project Explorer
        left_container = QWidget()
        left_layout = QVBoxLayout(left_container)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(0)
        
        self.project_explorer = ProjectExplorer()
        self.component_palette = ComponentPalette()
        
        left_splitter = QSplitter(Qt.Orientation.Vertical)
        left_splitter.addWidget(self.project_explorer)
        left_splitter.addWidget(self.component_palette)
        left_splitter.setSizes([200, 400])
        
        left_layout.addWidget(left_splitter)
        self.h_splitter.addWidget(left_container)
        
        # Center panel - Design Canvas
        self.canvas = DesignCanvas()
        self.h_splitter.addWidget(self.canvas)
        
        # Right panel - Properties Inspector
        self.properties_panel = PropertiesPanel()
        self.h_splitter.addWidget(self.properties_panel)
        
        # Bottom panel - Output
        self.output_panel = OutputPanel()
        self.v_splitter.addWidget(self.output_panel)
        
        # Set splitter sizes
        self.h_splitter.setSizes([250, 700, 300])
        self.v_splitter.setSizes([600, 150])
    
    def _create_status_bar(self) -> None:
        """Create the status bar."""
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("Ready")
    
    def _apply_theme(self) -> None:
        """Apply the application theme."""
        dark_theme = """
            QMainWindow {
                background-color: #1e1e1e;
            }
            QWidget {
                background-color: #252526;
                color: #cccccc;
                font-size: 13px;
            }
            QMenuBar {
                background-color: #3c3c3c;
                color: #cccccc;
                padding: 2px;
            }
            QMenuBar::item {
                padding: 4px 8px;
                background-color: transparent;
            }
            QMenuBar::item:selected {
                background-color: #505050;
            }
            QMenu {
                background-color: #252526;
                border: 1px solid #454545;
            }
            QMenu::item {
                padding: 6px 30px 6px 20px;
            }
            QMenu::item:selected {
                background-color: #094771;
            }
            QMenu::separator {
                height: 1px;
                background-color: #454545;
                margin: 4px 10px;
            }
            QToolBar {
                background-color: #3c3c3c;
                border: none;
                spacing: 4px;
                padding: 4px;
            }
            QToolButton {
                background-color: transparent;
                border: none;
                padding: 4px;
                border-radius: 3px;
            }
            QToolButton:hover {
                background-color: #505050;
            }
            QToolButton:pressed {
                background-color: #094771;
            }
            QStatusBar {
                background-color: #007acc;
                color: white;
            }
            QSplitter::handle {
                background-color: #3c3c3c;
            }
            QSplitter::handle:horizontal {
                width: 2px;
            }
            QSplitter::handle:vertical {
                height: 2px;
            }
            QScrollBar:vertical {
                background-color: #1e1e1e;
                width: 12px;
                margin: 0;
            }
            QScrollBar::handle:vertical {
                background-color: #5a5a5a;
                min-height: 30px;
                border-radius: 6px;
                margin: 2px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #787878;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
            QScrollBar:horizontal {
                background-color: #1e1e1e;
                height: 12px;
                margin: 0;
            }
            QScrollBar::handle:horizontal {
                background-color: #5a5a5a;
                min-width: 30px;
                border-radius: 6px;
                margin: 2px;
            }
            QScrollBar::handle:horizontal:hover {
                background-color: #787878;
            }
            QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
                width: 0px;
            }
            QTabWidget::pane {
                border: 1px solid #3c3c3c;
                background-color: #252526;
            }
            QTabBar::tab {
                background-color: #2d2d2d;
                color: #969696;
                padding: 8px 16px;
                border: none;
            }
            QTabBar::tab:selected {
                background-color: #1e1e1e;
                color: #ffffff;
                border-bottom: 2px solid #007acc;
            }
            QTabBar::tab:hover:!selected {
                background-color: #383838;
            }
            QLineEdit, QTextEdit, QPlainTextEdit {
                background-color: #3c3c3c;
                border: 1px solid #545454;
                border-radius: 3px;
                padding: 4px 8px;
                color: #cccccc;
            }
            QLineEdit:focus, QTextEdit:focus, QPlainTextEdit:focus {
                border-color: #007acc;
            }
            QPushButton {
                background-color: #0e639c;
                color: white;
                border: none;
                padding: 6px 14px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #1177bb;
            }
            QPushButton:pressed {
                background-color: #094771;
            }
            QPushButton:disabled {
                background-color: #3c3c3c;
                color: #666666;
            }
            QTreeView, QListView {
                background-color: #252526;
                border: none;
                outline: none;
            }
            QTreeView::item, QListView::item {
                padding: 4px;
            }
            QTreeView::item:selected, QListView::item:selected {
                background-color: #094771;
            }
            QTreeView::item:hover, QListView::item:hover {
                background-color: #2a2d2e;
            }
            QHeaderView::section {
                background-color: #3c3c3c;
                color: #cccccc;
                padding: 6px;
                border: none;
                border-right: 1px solid #454545;
            }
            QLabel {
                color: #cccccc;
                background-color: transparent;
            }
            QGroupBox {
                border: 1px solid #3c3c3c;
                border-radius: 4px;
                margin-top: 8px;
                padding-top: 8px;
            }
            QGroupBox::title {
                color: #cccccc;
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 3px;
            }
            QComboBox {
                background-color: #3c3c3c;
                border: 1px solid #545454;
                border-radius: 3px;
                padding: 4px 8px;
                color: #cccccc;
            }
            QComboBox:hover {
                border-color: #007acc;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
            }
            QComboBox QAbstractItemView {
                background-color: #252526;
                border: 1px solid #454545;
                selection-background-color: #094771;
            }
            QSpinBox, QDoubleSpinBox {
                background-color: #3c3c3c;
                border: 1px solid #545454;
                border-radius: 3px;
                padding: 4px;
                color: #cccccc;
            }
            QCheckBox {
                spacing: 8px;
            }
            QCheckBox::indicator {
                width: 16px;
                height: 16px;
                border: 1px solid #545454;
                border-radius: 3px;
                background-color: #3c3c3c;
            }
            QCheckBox::indicator:checked {
                background-color: #007acc;
                border-color: #007acc;
            }
        """
        self.setStyleSheet(dark_theme)
    
    # Action handlers
    def _new_project(self) -> None:
        """Create a new project."""
        self.state.project = Project.create_new()
        self.status_bar.showMessage("New project created")
        self._update_title()
        self.output_panel.log("New project created")
        self.canvas.refresh()
        self.project_explorer.refresh()
    
    def _open_project(self) -> None:
        """Open an existing project."""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Open Project", "", "Zeus Project (*.zeus);;All Files (*)"
        )
        if file_path:
            try:
                from pathlib import Path
                self.state.project = Project.load(Path(file_path))
                self.status_bar.showMessage(f"Opened: {file_path}")
                self._update_title()
                self.output_panel.log(f"Opened project: {file_path}")
                self.canvas.refresh()
                self.project_explorer.refresh()
            except Exception as e:
                QMessageBox.critical(self, "Error", f"Failed to open project: {e}")
    
    def _save_project(self) -> None:
        """Save the current project."""
        if self.state.project is None:
            return
        
        if self.state.project.file_path is None:
            self._save_project_as()
        else:
            try:
                self.state.project.save()
                self.status_bar.showMessage("Project saved")
                self._update_title()
                self.output_panel.log("Project saved")
            except Exception as e:
                QMessageBox.critical(self, "Error", f"Failed to save project: {e}")
    
    def _save_project_as(self) -> None:
        """Save the project with a new name."""
        if self.state.project is None:
            return
        
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Save Project As", "", "Zeus Project (*.zeus);;All Files (*)"
        )
        if file_path:
            try:
                from pathlib import Path
                if not file_path.endswith('.zeus'):
                    file_path += '.zeus'
                self.state.project.save(Path(file_path))
                self.status_bar.showMessage(f"Saved: {file_path}")
                self._update_title()
                self.output_panel.log(f"Project saved as: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "Error", f"Failed to save project: {e}")
    
    def _update_title(self) -> None:
        """Update the window title with project name."""
        if self.state.project:
            name = self.state.project.name
            if self.state.project.file_path:
                name = self.state.project.file_path.stem
            self.setWindowTitle(f"{name} - Zeus")
        else:
            self.setWindowTitle("Zeus - Visual Application Designer")
    
    def _undo(self) -> None:
        """Undo the last action."""
        if self.state.command_stack.undo():
            self.status_bar.showMessage("Undo")
            self.canvas.refresh()
    
    def _redo(self) -> None:
        """Redo the last undone action."""
        if self.state.command_stack.redo():
            self.status_bar.showMessage("Redo")
            self.canvas.refresh()
    
    def _delete_selected(self) -> None:
        """Delete selected components."""
        self.canvas.delete_selected()
    
    def _zoom_in(self) -> None:
        """Zoom in on the canvas."""
        self.state.zoom_level = self.state.zoom_level * 1.2
        self.canvas.update_zoom()
    
    def _zoom_out(self) -> None:
        """Zoom out on the canvas."""
        self.state.zoom_level = self.state.zoom_level / 1.2
        self.canvas.update_zoom()
    
    def _zoom_fit(self) -> None:
        """Reset zoom to fit the canvas."""
        self.state.zoom_level = 1.0
        self.canvas.update_zoom()
    
    def _toggle_grid(self) -> None:
        """Toggle grid visibility."""
        self.state.grid_visible = self.action_toggle_grid.isChecked()
        self.canvas.update()
    
    def _toggle_snap(self) -> None:
        """Toggle snap to grid."""
        self.state.grid_snap = self.action_toggle_snap.isChecked()
    
    def _run_preview(self) -> None:
        """Run the project in preview mode."""
        self.output_panel.log("Running preview...")
        self.status_bar.showMessage("Preview mode")
        # TODO: Implement preview functionality
    
    def _show_about(self) -> None:
        """Show the about dialog."""
        QMessageBox.about(
            self,
            "About Zeus",
            "<h2>Zeus</h2>"
            "<p>Visual Application Designer</p>"
            "<p>Version 0.1.0</p>"
            "<p>A low-code platform for building desktop applications.</p>"
        )
    
    def closeEvent(self, event) -> None:
        """Handle window close event."""
        # TODO: Check for unsaved changes
        event.accept()
