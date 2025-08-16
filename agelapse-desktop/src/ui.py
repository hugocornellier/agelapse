import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import exifread
from PyQt5 import QtGui
from PyQt5.QtGui import (
  QPixmap, QFont, QDragEnterEvent, QDragLeaveEvent, QDropEvent, QMouseEvent,
  QCursor, QTextCursor, QIcon, QColor, QPainterPath, QRegion
)
from PyQt5.QtCore import Qt, pyqtSignal, QRect, QEvent, QRectF, QUrl
from PyQt5.QtSvg import QSvgWidget
from PyQt5.QtMultimedia import QMediaPlayer, QMediaContent, QMediaPlaylist
from PyQt5.QtMultimediaWidgets import QVideoWidget
from PyQt5.QtWidgets import (
  QMainWindow, QLabel, QVBoxLayout, QWidget, QProgressBar, QPushButton, QGridLayout, QStackedWidget, QHBoxLayout,
  QApplication, QFileDialog, QTextEdit,
  QComboBox, QSizePolicy, QFrame, QGraphicsColorizeEffect, QTableWidgetItem, QTableWidget, QHeaderView,
  QAction, QStackedLayout, QDialog, QListWidget, QLineEdit, QMessageBox
)
from src.video_compile import compile_video
from version import __version__

DROP_AREA_BG_COLOR = "#334155"
DROP_AREA_BORDER_COLOR = "#475569"
DROP_AREA_HOVER_BG_COLOR = "#475569"

common_title_style = """
    QLabel {
        font-size: 24px;
        color: white;
        text-align: center;
    }
"""

button_style = """
    QPushButton {
        background-color: #333333;
        color: white;
        border-radius: 10px;
        padding: 10px;
    }
    QPushButton:hover {
        background-color: #262626;
    }
"""

progress_bar_style = """
    QProgressBar {
        border: none;
        background-color: rgba(51,65,85,0.5);
        height: 6px;
        border-radius: 3px;
        text-indent: -9999px;
    }
    QProgressBar::chunk {
        border-radius: 3px;
        background: qlineargradient(
            x1:0, y1:0, x2:1, y2:0,
            stop:0 #2563EB, stop:1 #7F00FF);
    }
"""

TITLE_BAR_COLOR = "#0C1220"

MAIN_GRADIENT = (
    "QWidget{background: qlineargradient("
    "spread:pad, x1:0, y1:0, x2:0, y2:1,"
    "stop:0 #0f172a, stop:0.5 #080c1c, stop:1 #0f172a); color:white}"
)
GLASS_PANEL = (
    "QFrame{background: rgba(30,41,59,0.5);"
    "border:1px solid rgba(51,65,85,0.5); border-radius:12px;}"
)
APP_STATE_IDLE = "IDLE"
APP_STATE_STABILIZING = "STABILIZING"
APP_STATE_COMPILING = "COMPILING"
APP_STATE_DONE = "DONE"
APP_STATE_ERROR = "ERROR"

def styled_combobox(parent=None):
  cb = QComboBox(parent)
  cb.setStyleSheet("""
      QComboBox {
          background-color: #333333;
          color: white;
          padding: 5px;
      }
      QComboBox:hover {
          background-color: #262626;
      }
  """)
  return cb

def get_path(filename):
  name = os.path.splitext(filename)[0]
  ext = os.path.splitext(filename)[1]

  if platform.system() == "Darwin":
    from AppKit import NSBundle
    file = NSBundle.mainBundle().pathForResource_ofType_(name, ext)
    return file or os.path.realpath(filename)
  else:
    return os.path.realpath(filename)

class ProjectManager:
  @staticmethod
  def base_dir():
    return os.path.join(Path.home(), "AgeLapse", "Projects")

  @staticmethod
  def ensure_base():
    os.makedirs(ProjectManager.base_dir(), exist_ok=True)

  @staticmethod
  def list_projects():
    ProjectManager.ensure_base()
    return sorted([d for d in os.listdir(ProjectManager.base_dir()) if os.path.isdir(os.path.join(ProjectManager.base_dir(), d))])

  @staticmethod
  def create_project(name):
    if not name or any(c in name for c in r'\/:*?"<>|'):
      raise ValueError("Invalid project name")
    pdir = os.path.join(ProjectManager.base_dir(), name)
    if os.path.exists(pdir):
      raise FileExistsError("Project exists")
    os.makedirs(os.path.join(pdir, "Imports"), exist_ok=True)
    os.makedirs(os.path.join(pdir, "Stabilized Images"), exist_ok=True)
    os.makedirs(os.path.join(pdir, "Video"), exist_ok=True)
    return pdir

  @staticmethod
  def touch_last(name):
    ProjectManager.ensure_base()
    with open(os.path.join(ProjectManager.base_dir(), ".last_project"), "w", encoding="utf-8") as f:
      f.write(name.strip())

  @staticmethod
  def read_last():
    try:
      with open(os.path.join(ProjectManager.base_dir(), ".last_project"), "r", encoding="utf-8") as f:
        return f.read().strip()
    except Exception:
      return None


class ProjectPicker(QDialog):
  def __init__(self, parent=None):
    super().__init__(parent)
    self.setWindowTitle("Select Project")
    self.setModal(True)
    lay = QVBoxLayout(self)
    self.listw = QListWidget(self)
    self.name_edit = QLineEdit(self)
    self.btn_row = QHBoxLayout()
    self.new_btn = QPushButton("New")
    self.open_btn = QPushButton("Open")
    self.rename_btn = QPushButton("Rename")
    self.delete_btn = QPushButton("Delete")
    self.cancel_btn = QPushButton("Cancel")

    self.btn_row.addWidget(self.new_btn)
    self.btn_row.addWidget(self.open_btn)
    self.btn_row.addWidget(self.rename_btn)
    self.btn_row.addWidget(self.delete_btn)
    self.btn_row.addStretch(1)
    self.btn_row.addWidget(self.cancel_btn)

    lay.addWidget(QLabel("Projects"))
    lay.addWidget(self.listw)
    lay.addWidget(QLabel("New name"))
    lay.addWidget(self.name_edit)
    lay.addLayout(self.btn_row)

    self.selected = None
    self.populate()

    self.new_btn.clicked.connect(self.create_new)
    self.open_btn.clicked.connect(self.open_selected)
    self.rename_btn.clicked.connect(self.rename_selected)
    self.delete_btn.clicked.connect(self.delete_selected)
    self.cancel_btn.clicked.connect(self.reject)
    self.listw.itemDoubleClicked.connect(lambda _: self.open_selected())

  def populate(self):
    self.listw.clear()
    for p in ProjectManager.list_projects():
      self.listw.addItem(p)
    last = ProjectManager.read_last()
    if last:
      items = self.listw.findItems(last, Qt.MatchExactly)
      if items:
        self.listw.setCurrentItem(items[0])

  def get_current_name(self):
    item = self.listw.currentItem()
    return item.text() if item else None

  def create_new(self):
    name = self.name_edit.text().strip()
    try:
      ProjectManager.create_project(name)
    except Exception as e:
      QMessageBox.warning(self, "Error", str(e))
      return
    self.populate()
    self.name_edit.clear()

  def open_selected(self):
    name = self.get_current_name()
    if not name:
      QMessageBox.information(self, "Select", "Pick a project")
      return
    self.selected = name
    self.accept()

  def rename_selected(self):
    old = self.get_current_name()
    new = self.name_edit.text().strip()
    if not old or not new:
      QMessageBox.information(self, "Rename", "Pick a project and enter a new name")
      return
    old_p = os.path.join(ProjectManager.base_dir(), old)
    new_p = os.path.join(ProjectManager.base_dir(), new)
    if os.path.exists(new_p):
      QMessageBox.warning(self, "Error", "Target name exists")
      return
    try:
      os.rename(old_p, new_p)
    except Exception as e:
      QMessageBox.warning(self, "Error", str(e))
      return
    self.populate()
    self.name_edit.clear()

  def delete_selected(self):
    name = self.get_current_name()
    if not name:
      return
    pdir = os.path.join(ProjectManager.base_dir(), name)
    try:
      shutil.rmtree(pdir)
    except Exception as e:
      QMessageBox.warning(self, "Error", str(e))
      return
    self.populate()

def make_icon_button(icon_path, label, min_width, style_sheet, click_slot, parent=None):
  btn = QPushButton(parent)
  icon = QSvgWidget(resource_path(icon_path), btn)
  icon.setFixedSize(16, 16)
  effect = QGraphicsColorizeEffect(icon)
  effect.setColor(QColor("#ffffff"))
  icon.setGraphicsEffect(effect)
  text_lbl = QLabel(label, btn)
  text_lbl.setStyleSheet("color: white;")
  lay = QHBoxLayout(btn)
  lay.setContentsMargins(12, 12, 12, 12)
  lay.setSpacing(8)
  lay.addWidget(icon)
  lay.addWidget(text_lbl)
  lay.setAlignment(Qt.AlignCenter)
  btn.setLayout(lay)
  btn.setCursor(Qt.PointingHandCursor)
  btn.setMinimumWidth(min_width)
  btn.setSizePolicy(QSizePolicy.Minimum, QSizePolicy.Fixed)
  btn.setStyleSheet(style_sheet)
  btn.clicked.connect(click_slot)
  return btn

def resource_path(relative_path):
  """ Get absolute path to resource, works for dev and for PyInstaller """
  if hasattr(sys, '_MEIPASS'):
    return os.path.join(sys._MEIPASS, relative_path)
  return os.path.join(os.path.abspath("."), relative_path)


class CustomLabelButton(QLabel):
  def __init__(self, text, parent=None):
    super().__init__(text, parent)
    self.setAlignment(Qt.AlignCenter)
    self.setFixedSize(40, 40)
    self.setFont(QFont("Arial", 12))
    self.setStyleSheet(self.get_style_sheet(text))

  def mousePressEvent(self, event: QMouseEvent):
    if event.button() == Qt.LeftButton:
      self.on_click()

  def on_click(self):
    pass

  def get_style_sheet(self, text):
    margin_bottom = "0px"
    font_size = "24px" if text == "⎯" else "28px"
    hover_color = (
      "rgba(255, 0, 0, 0.5)"
      if text == "×"
      else "rgba(255, 255, 255, 0.1)"
    )

    return f"""
          QLabel {{
              color: white;
              background-color: transparent;
              border: none;
              margin-bottom: {margin_bottom};
              font-size: {font_size};
          }}
          QLabel:hover {{
              background-color: {hover_color};
          }}
      """


class CustomTitleBar(QWidget):
  def __init__(self, parent=None):
    super().__init__(parent)
    self.setAutoFillBackground(True)
    self.setFixedHeight(40)
    self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
    self.setAttribute(Qt.WA_StyledBackground, True)
    self.setObjectName("title_bar")

    self.setStyleSheet(f"""
      QWidget#title_bar {{
        background-color: {TITLE_BAR_COLOR};
        border-bottom: 1px solid rgba(51,65,85,0.5);
      }}
    """)
    self.project_label = None
    self.init_ui()

  def set_project_name(self, name: str):
    if self.project_label is not None:
      text = f"Project: {name}"
      self.project_label.setText(text)
      self.project_label.setToolTip(text)

  def init_ui(self):
    if sys.platform == "darwin":
      self.setup_mac_title_bar()
    else:
      self.setup_windows_title_bar()

  def setup_windows_title_bar(self):
    self.logo_label = QLabel(self)
    self.logo_label.setFixedSize(120, 30)
    pixmap = QPixmap(
      resource_path('assets/images/agelapse.png')
    ).scaled(
      self.logo_label.size(),
      Qt.KeepAspectRatio,
      Qt.SmoothTransformation
    )
    self.logo_label.setPixmap(pixmap)

    self.minimize_button = CustomLabelButton("⎯", self)
    self.minimize_button.on_click = self.minimize_window

    self.restore_button = CustomLabelButton("▢", self)
    self.restore_button.on_click = self.restore_window

    self.close_button = CustomLabelButton("×", self)
    self.close_button.on_click = self.close_window

    layout = QHBoxLayout(self)
    layout.setContentsMargins(10, 0, 10, 0)
    layout.setSpacing(5)
    layout.setAlignment(Qt.AlignVCenter)

    self.logo_container = QWidget(self)
    logo_layout = QHBoxLayout(self.logo_container)
    logo_layout.setContentsMargins(0, 0, 0, 0)
    logo_layout.setSpacing(6)

    logo_layout.addWidget(self.logo_label)

    self.version_badge = QLabel(f"Desktop {__version__}", self.logo_container)
    self.version_badge.setStyleSheet("""
        background-color: rgba(249,115,22,0.75);
        color: white;
        font-size: 10px;
        padding: 1px 2px;
        border: 1px solid rgba(234,88,12,0.6);
        margin-left: 7px;
        border-radius: 10px;
    """)
    logo_layout.addWidget(self.version_badge)

    self.project_label = QLabel("", self.logo_container)
    self.project_label.setStyleSheet("color:#cbd5e1; font-size:12px; margin-left:10px;")
    self.project_label.setSizePolicy(QSizePolicy.Maximum, QSizePolicy.Preferred)
    logo_layout.addWidget(self.project_label)

    layout.addWidget(self.logo_container)
    layout.addStretch(1)
    layout.addWidget(self.minimize_button)
    layout.addWidget(self.restore_button)
    layout.addWidget(self.close_button)

    self.setLayout(layout)

  def setup_mac_title_bar(self):
    self.setStyleSheet(f"""
        QWidget#title_bar {{
            background-color: {TITLE_BAR_COLOR};
            border-bottom: 1px solid rgba(51,65,85,0.5);
        }}
    """)

    self.close_button = QPushButton(self)
    self.minimize_button = QPushButton(self)
    self.restore_button = QPushButton(self)

    circular_style = """
      QPushButton {{
          border-radius: 6px;
          background-color: {};
      }}
    """

    self.close_button.setStyleSheet(circular_style.format("#ff5f56"))
    self.minimize_button.setStyleSheet(circular_style.format("#ffbd2e"))
    self.restore_button.setStyleSheet(circular_style.format("#28c940"))

    for btn in (self.close_button, self.minimize_button, self.restore_button):
        btn.setFixedSize(12, 12)

    self.close_button.clicked.connect(self.close_window)
    self.minimize_button.clicked.connect(self.minimize_window)
    self.restore_button.clicked.connect(self.restore_window)

    self.logo_label = QLabel(self)
    self.logo_label.setFixedSize(120, 30)
    pixmap = QPixmap(
        resource_path('assets/images/agelapse.png')
    ).scaled(
        self.logo_label.size(),
        Qt.KeepAspectRatio,
        Qt.SmoothTransformation
    )
    self.logo_label.setPixmap(pixmap)

    main_layout = QHBoxLayout(self)
    main_layout.setContentsMargins(10, 3, 10, 3)
    main_layout.setAlignment(Qt.AlignVCenter)

    main_layout.addWidget(self.close_button)
    main_layout.addWidget(self.minimize_button)
    main_layout.addWidget(self.restore_button)
    main_layout.addStretch(1)

    self.logo_container = QWidget(self)
    logo_layout = QHBoxLayout(self.logo_container)
    logo_layout.setContentsMargins(0, 0, 0, 0)
    logo_layout.setSpacing(4)

    logo_layout.addWidget(self.logo_label)

    self.version_badge = QLabel(f"Desktop {__version__}", self.logo_container)
    self.version_badge.setStyleSheet("""
        background-color: rgba(249,115,22,0.75);
        color: white;
        font-size: 10px;
        padding: 1px 2px;
        border: 1px solid rgba(234,88,12,0.6);
        margin-left: 7px;
        border-radius: 10px;
    """)
    logo_layout.addWidget(self.version_badge)

    main_layout.addWidget(self.logo_container)
    main_layout.addStretch(1)

    self.project_label = QLabel("", self)
    self.project_label.setStyleSheet("color:#cbd5e1; font-size:12px;")
    self.project_label.setSizePolicy(QSizePolicy.Maximum, QSizePolicy.Preferred)
    main_layout.addWidget(self.project_label)

    invisible_button = QWidget(self)
    invisible_button.setFixedSize(66, 12)
    main_layout.addWidget(invisible_button)

    self.setLayout(main_layout)

  def get_button_style(self, close=False):
    hover_color = "#ff3333" if close else "#555"
    return f"""
            QPushButton {{
                border: none;
                padding: 5px 10px;
            }}
            QPushButton:hover {{
                background-color: {hover_color};
                cursor: pointer
            }}
        """

  def get_mac_button_style(self, color):
    return f"""
            QPushButton {{
                background-color: {color};
                border-radius: 25px;
                margin: 5px;
            }}
            QPushButton:hover {{
                background-color: {color};
                cursor: pointer
            }}
        """

  def close_window(self):
    self.window().close()

  def minimize_window(self):
    self.window().showMinimized()

  def restore_window(self):
    if self.window().isMaximized():
      self.window().showNormal()
    else:
      self.window().showMaximized()


class DropArea(QFrame):
    def __init__(self, main_window, parent=None):
        super().__init__(parent)
        self.main_window = main_window
        self.setAcceptDrops(True)
        self.setCursor(QCursor(Qt.PointingHandCursor))

        self.base_style = (
          "QFrame{background: rgba(30,41,59,0.5);"
          "border:2px dashed #475569;"
          "border-radius:16px;"
          "padding:48px;}"
        )
        self.hover_style = (
          "QFrame{background: rgba(30,41,59,0.5);"
          "border:2px dashed #60a5fa;"
          "border-radius:16px;"
          "padding:48px;}"
        )
        self.setStyleSheet(self.base_style)

        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignCenter)
        layout.setSpacing(4)

        self.icon_widget = QSvgWidget(resource_path("assets/icons/import.svg"), self)
        self.icon_widget.setFixedSize(64, 64)
        self.icon_effect = QGraphicsColorizeEffect(self.icon_widget)
        self.icon_effect.setColor(QColor("#ffffff"))
        self.icon_widget.setGraphicsEffect(self.icon_effect)

        self.header_label = QLabel("Drag and drop a directory containing image files", self)
        self.header_label.setStyleSheet("border:none;background:transparent;font-size:18px;color:#cbd5e1")
        self.header_label.setAlignment(Qt.AlignCenter)

        self.sub_label = QLabel("(Click to browse for a directory)", self)
        self.sub_label.setStyleSheet("border:none;background:transparent;font-size:14px;color:#94a3b8")
        self.sub_label.setAlignment(Qt.AlignCenter)

        layout.addWidget(self.icon_widget, 0, Qt.AlignHCenter)
        layout.addWidget(self.header_label, 0, Qt.AlignHCenter)
        layout.addWidget(self.sub_label, 0, Qt.AlignHCenter)

    def setText(self, text):
        self.header_label.setText(text)

    def enterEvent(self, event):
      self.setStyleSheet(self.hover_style)
      self.icon_effect.setColor(QColor("#60A5FA"))
      super().enterEvent(event)

    def leaveEvent(self, event):
      self.setStyleSheet(self.base_style)
      self.icon_effect.setColor(QColor("#ffffff"))
      super().leaveEvent(event)

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.LeftButton:
            self.main_window.browse_directory()

    def dragEnterEvent(self, event: QDragEnterEvent):
      if event.mimeData().hasUrls():
        self.setStyleSheet(self.hover_style)
        self.setText("Drop it...")
        self.icon_effect.setColor(QColor("#60A5FA"))
        event.acceptProposedAction()

    def dragLeaveEvent(self, event: QDragLeaveEvent):
      self.setStyleSheet(self.base_style)
      self.setText("Drag and drop a directory containing image files")
      self.icon_effect.setColor(QColor("#ffffff"))

    def dropEvent(self, event: QDropEvent):
      self.setStyleSheet(self.base_style)
      self.icon_effect.setColor(QColor("#ffffff"))
      urls = event.mimeData().urls()
      if not urls:
        return

      paths = [u.toLocalFile() for u in urls]

      if len(paths) == 1 and os.path.isdir(paths[0]):
        self.setText("processing dir")
        self.main_window.process_directory(paths[0])
        return

      image_files = [
        p for p in paths
        if os.path.isfile(p) and p.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.heic'))
      ]
      if image_files:
        self.setText("processing files")
        self.main_window.process_files(image_files)
      else:
        self.setText("Please drop image files or a directory")


class MainWindow(QMainWindow):
  update_progress_signal = pyqtSignal(int)
  finished_signal = pyqtSignal()
  status_text_signal = pyqtSignal(str)
  video_status_signal = pyqtSignal(str)
  video_finished_signal = pyqtSignal(bool)
  log_signal = pyqtSignal(str)

  def __init__(self):
    super().__init__()

    try:
      icon: QIcon = QtGui.QIcon(resource_path('assets/256x256.ico'))
      self.setWindowIcon(icon)
    except Exception as e:
      print(e)
    else:
      print("Window icon loaded")

    self.setWindowFlags(
      Qt.FramelessWindowHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    )

    self.selected_framerate = 15
    self.selected_resolution = "1080p"
    self.image_paths = []
    self.order_ascending = True
    self.temp_input_dir = None
    self.video_output_file = None
    self.media_player = None
    self.video_widget = None
    self.playlist = None

    #self.setStyleSheet(MAIN_GRADIENT)
    self.title_bar = CustomTitleBar(self)

    self.main_widget = QWidget(self)
    self.main_layout = QVBoxLayout(self.main_widget)
    self.main_layout.setContentsMargins(0, 0, 0, 0)
    self.main_layout.setSpacing(0)
    self.main_layout.addWidget(self.title_bar)

    self.main_widget.setObjectName("main_widget")
    self.main_widget.setStyleSheet("""
        QWidget#main_widget {
            background-color: #0f172a;
            color: white;
        }
    """)

    self.create_settings_section()
    self.stacked_widget = QStackedWidget(self)
    self.gallery_container = self.create_gallery_container()

    self.stacked_widget.addWidget(self.gallery_container)
    self.content_widget = QWidget()
    content_layout = QVBoxLayout(self.content_widget)
    content_layout.setContentsMargins(13, 13, 13, 13)
    content_layout.setSpacing(8)

    content_layout.addWidget(self.stacked_widget)
    self.main_layout.addWidget(self.content_widget)

    self.setCentralWidget(self.main_widget)
    self.build_menus()
    self.stacked_widget.setCurrentWidget(self.gallery_container)

    self.executor = None
    self.update_progress_signal.connect(self.update_progress)
    self.finished_signal.connect(self.on_processing_finished)
    self.status_text_signal.connect(self.status_header.setText)
    self.video_status_signal.connect(self.status_header.setText)
    self.video_finished_signal.connect(self.on_video_finished)
    self.log_signal.connect(self.append_log_line)
    self.state = APP_STATE_IDLE

    self.resize(1200, 800)
    if sys.platform == "darwin":
      self.update_window_mask()

    self.resizing_direction = None
    self.start_pos = None
    self.start_size = None

    self.ensure_project_selected()
    self.output_dir = self.stab_img_dir

    self.log_viewer = QTextEdit(self)
    self.log_viewer.setReadOnly(True)
    self.log_viewer.setVisible(False)

    self.stdout = sys.stdout
    sys.stdout = self

    self.main_layout.addWidget(self.log_viewer)

  def ensure_project_selected(self):
    ProjectManager.ensure_base()
    last = ProjectManager.read_last()
    if last and os.path.isdir(os.path.join(ProjectManager.base_dir(), last)):
      self.set_project(last)
      return
    dlg = ProjectPicker(self)
    if dlg.exec_() == QDialog.Accepted and dlg.selected:
      self.set_project(dlg.selected)
    else:
      name = f"Project {int(time.time())}"
      ProjectManager.create_project(name)
      self.set_project(name)

  def set_project(self, name):
    ProjectManager.touch_last(name)
    self.project_name = name
    self.project_dir = os.path.join(ProjectManager.base_dir(), name)
    self.app_dir = self.project_dir
    self.stab_img_dir = os.path.join(self.project_dir, "Stabilized Images")
    self.output_video_dir = os.path.join(self.project_dir, "Video")
    os.makedirs(self.stab_img_dir, exist_ok=True)
    os.makedirs(self.output_video_dir, exist_ok=True)
    self.output_dir = self.stab_img_dir
    if hasattr(self, "status_header"):
      self.status_header.setText(f"Project: {self.project_name}")
    self.setWindowTitle(f"AgeLapse — {self.project_name}")
    if hasattr(self, "title_bar") and hasattr(self.title_bar, "set_project_name"):
      self.title_bar.set_project_name(self.project_name)

  def switch_project(self):
      dlg = ProjectPicker(self)
      if dlg.exec_() == QDialog.Accepted and dlg.selected:
          if getattr(self, "media_player", None):
              try:
                  self.media_player.stop()
              except Exception:
                  pass
          if getattr(self, "playlist", None):
              try:
                  self.playlist.clear()
              except Exception:
                  pass

          self.set_project(dlg.selected)

          self.image_paths = []
          self.temp_input_dir = None
          self.video_output_file = None

          self.populate_image_table()
          self.drop_area.setVisible(True)
          self.drop_area.setText("Drag and drop a directory containing image files")
          self.intro_label.setVisible(True)
          self.intro_line.setVisible(True)
          self.image_list_widget.setVisible(False)
          self.image_list_header.setVisible(False)
          self.space_between.setVisible(False)

          self.start_button.setEnabled(False)
          self.start_button.setVisible(False)
          self.open_stabilized_folder_button.setVisible(False)
          self.open_video_folder_button.setVisible(False)
          self.settings_section.setVisible(False)
          self.settings_card.setVisible(True)
          self.settings_icon.setVisible(True)
          self.settings_title_lbl.setVisible(True)

          self.status_card.setVisible(False)
          self.progress_bar.setValue(0)
          self.progress_value_label.setText("")
          self.status_header.setText(f"Project: {self.project_name}")

          self.log_viewer.clear()
          self.show_log_label.setText("Show Log")
          self.log_viewer.setVisible(False)

          if hasattr(self, "left_container"):
              self.left_container.setVisible(True)
          if hasattr(self, "tabs_bar"):
              self.tabs_bar.setVisible(False)

  def show_images_tab(self):
    if hasattr(self, "status_card"):
        self.status_card.setVisible(False)
    if hasattr(self, "result_wrapper"):
        self.result_wrapper.setVisible(False)
    if hasattr(self, "left_container"):
        self.left_container.setVisible(True)
    if hasattr(self, "image_list_header"):
        self.image_list_header.setVisible(True)
    if hasattr(self, "image_list_widget"):
        self.image_list_widget.setVisible(True)
    if hasattr(self, "tab_images_btn"):
        self.tab_images_btn.setStyleSheet(
            "background-color:#1e293b;color:white;border:1px solid #475569;border-radius:8px;padding:6px 12px;")
    if hasattr(self, "tab_result_btn"):
        self.tab_result_btn.setStyleSheet(
            "background-color:#334155;color:#cbd5e1;border:1px solid #475569;border-radius:8px;padding:6px 12px;")

  def show_result_tab(self):
    if hasattr(self, "image_list_header"):
        self.image_list_header.setVisible(False)
    if hasattr(self, "image_list_widget"):
        self.image_list_widget.setVisible(False)
    if hasattr(self, "left_container"):
        self.left_container.setVisible(False)
    if hasattr(self, "result_wrapper"):
        self.result_wrapper.setVisible(True)
    if hasattr(self, "status_card"):
        self.status_card.setVisible(True)
    if hasattr(self, "tab_result_btn"):
        self.tab_result_btn.setStyleSheet(
            "background-color:#1e293b;color:white;border:1px solid #475569;border-radius:8px;padding:6px 12px;")
    if hasattr(self, "tab_images_btn"):
        self.tab_images_btn.setStyleSheet(
            "background-color:#334155;color:#cbd5e1;border:1px solid #475569;border-radius:8px;padding:6px 12px;")

  def build_menus(self):
    menubar = self.menuBar()
    try:
      menubar.setNativeMenuBar(True)
    except Exception:
      pass

    project_menu = menubar.addMenu("Project")
    new_or_switch = QAction("Open or Create…", self)
    new_or_switch.triggered.connect(self.switch_project)
    project_menu.addAction(new_or_switch)

    help_menu = menubar.addMenu("Help")
    docs_action = QAction("Documentation", self)
    docs_action.triggered.connect(lambda: webbrowser.open("https://agelapse.com/docs/intro"))
    help_menu.addAction(docs_action)

  def update_resolution(self, index):
    text = self.resolution_dropdown.itemText(index)

    # if the selected text mentions 4K (2160), store "4K", else default to "1080p"
    self.selected_resolution = "4K" if "4K" in text or "2160" in text else "1080p"
    print(f"[LOG] Resolution changed to {self.selected_resolution}")

  def create_settings_section(self):
    self.settings_section = QWidget(self)
    settings_layout = QVBoxLayout(self.settings_section)

    self.framerate_dropdown = styled_combobox(self.settings_section)
    self.framerate_dropdown.addItems([str(i) for i in range(1, 31)])
    self.framerate_dropdown.setCurrentIndex(self.selected_framerate - 1)
    self.framerate_dropdown.currentIndexChanged.connect(self.update_framerate)

    self.image_order_dropdown = styled_combobox(self.settings_section)
    self.image_order_dropdown.addItems(["Filename (Asc)", "Filename (Desc)"])
    self.image_order_dropdown.setCurrentIndex(0)
    self.image_order_dropdown.currentIndexChanged.connect(self.update_image_order)

    self.resolution_dropdown = styled_combobox(self.settings_section)
    self.resolution_dropdown.addItems(["1080p (1920 x 1080)", "4K (3840 x 2160)"])
    self.resolution_dropdown.currentIndexChanged.connect(self.update_resolution)

    settings_layout.addWidget(self.framerate_dropdown)

    self.settings_section.setLayout(settings_layout)
    self.settings_section.setVisible(False)
    self.settings_section.setStyleSheet("color: white;")

    self.main_layout.addWidget(self.settings_section)

  def update_framerate(self, index):
    self.selected_framerate = int(self.framerate_dropdown.itemText(index))
    print(f"[LOG] Framerate changed to {self.selected_framerate}")

  def update_image_order(self, index):
    self.order_ascending = (index == 0)
    self.apply_sort()
    self.populate_image_table()

  def apply_sort(self):
    self.image_paths.sort(reverse=not self.order_ascending)

  def populate_image_table(self):
    self.image_list_widget.setRowCount(0)
    for image_path in self.image_paths:
      row = self.image_list_widget.rowCount()
      self.image_list_widget.insertRow(row)
      self.image_list_widget.setItem(row, 0, QTableWidgetItem(os.path.basename(image_path)))
      date_str = self.get_image_creation_date(image_path) or ""
      self.image_list_widget.setItem(row, 1, QTableWidgetItem(date_str))

  def get_ordered_input_dir(self):
    tmp_dir = tempfile.mkdtemp(prefix="agelapse_ordered_")
    for idx, src in enumerate(self.image_paths, 1):
      dst = os.path.join(tmp_dir, f"{idx:06d}{Path(src).suffix.lower()}")
      shutil.copy2(src, dst)
    self.temp_input_dir = tmp_dir
    return tmp_dir

  def toggle_log(self):
    if self.log_viewer.isVisible():
      self.log_viewer.setVisible(False)
      self.show_log_label.setText("Show Log")
    else:
      self.log_viewer.setVisible(True)
      self.show_log_label.setText("Hide Log")

  def write(self, message):
    self.log_signal.emit(message)

  def append_log_line(self, message):
    cursor = self.log_viewer.textCursor()
    cursor.movePosition(QTextCursor.End)
    self.log_viewer.setTextCursor(cursor)
    self.log_viewer.insertPlainText(message)
    self.log_viewer.ensureCursorVisible()

  def flush(self):
    pass

  def closeEvent(self, event):
    sys.stdout = self.stdout
    event.accept()

  def create_gallery_container(self):
    self.drop_area = DropArea(self)
    self.drop_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

    self.image_list_widget = QTableWidget(self)
    self.image_list_widget.setColumnCount(2)
    self.image_list_widget.setHorizontalHeaderLabels(["File Name", "Date Created"])
    self.image_list_widget.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
    self.image_list_widget.verticalHeader().setVisible(False)
    self.image_list_widget.setAlternatingRowColors(True)
    self.image_list_widget.setEditTriggers(QTableWidget.NoEditTriggers)
    self.image_list_widget.setVisible(False)
    self.image_list_widget.setStyleSheet("""
        QTableWidget {
            background: rgba(30,41,59,0.5);
            border: 1px solid rgba(51,65,85,0.5);
            border-radius: 12px;
            color: white;
            gridline-color: #475569;
            selection-background-color: #334155;
        }
        QHeaderView::section {
            background-color: #1e293b;
            color: #cbd5e1;
            padding: 4px;
            border: 1px solid #475569;
        }
        QTableWidget::item {
            padding: 6px;
        }
    """)

    BUTTON_DEFS = [
      ("assets/icons/play.svg", "Start Stabilization", 177, """
            QPushButton {
                border-radius: 8px;
                height: 50px;
                min-width: 177px;
                background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
                    stop:0 #2563EB, stop:1 #1D4ED8);
            }
            QPushButton:hover {
                background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
                    stop:0 #1D4ED8, stop:1 #1E40AF);
            }
            QPushButton:disabled {
                background: #555;
            }
        """, self.start_stabilization),
      ("assets/icons/folder.svg", "Open Stabilized Folder", 205, """
            QPushButton {
                border-radius: 8px;
                height: 50px;
                min-width: 205px;
                background-color: #00a63e;
            }
            QPushButton:hover {
                background-color: #475569;
            }
            QPushButton:disabled {
                background: #555;
            }
        """, self.open_stabilized_folder),
      ("assets/icons/folder.svg", "Open Video Folder", 185, """
            QPushButton {
                border-radius: 8px;
                height: 50px;
                min-width: 185px;
                background-color: #00a63e;
            }
            QPushButton:hover {
                background-color: #475569;
            }
            QPushButton:disabled {
                background: #555;
            }
        """, self.open_video_folder),
      ("assets/icons/eye.svg", "Show Log", 123, """
            QPushButton {
                border-radius: 8px;
                height: 50px;
                max-width: 123px;
                background-color: #334155;
            }
            QPushButton:hover {
                background-color: #475569;
            }
            QPushButton:disabled {
                background: #555;
            }
        """, self.toggle_log),
      ("assets/icons/book.svg", "Read Documentation", 185, """
            QPushButton {
                border-radius: 8px;
                height: 50px;
                min-width: 185px;
                background-color: #334155;
            }
            QPushButton:hover {
                background-color: #475569;
            }
            QPushButton:disabled {
                background: #555;
            }
        """, lambda: webbrowser.open("https://agelapse.com/docs/intro")),
    ]
    self.buttons = {}
    for icon, text, width, style, slot in BUTTON_DEFS:
      btn = make_icon_button(icon, text, width, style, slot, self)
      if text not in ("Show Log", "Read Documentation"):
        btn.setVisible(False)
      self.buttons[text] = btn

    self.start_button = self.buttons["Start Stabilization"]
    self.start_button.setEnabled(False)
    self.open_stabilized_folder_button = self.buttons["Open Stabilized Folder"]
    self.open_video_folder_button = self.buttons["Open Video Folder"]
    self.show_log_button = self.buttons["Show Log"]
    self.read_docs_button = self.buttons["Read Documentation"]
    self.read_docs_button.setVisible(True)
    self.show_log_label = self.show_log_button.findChild(QLabel)

    self.progress_bar = QProgressBar(self)
    self.progress_bar.setStyleSheet(progress_bar_style)
    self.progress_bar.setTextVisible(False)
    self.progress_bar.setVisible(False)

    self.progress_value_label = QLabel(self)
    self.progress_value_label.setAlignment(Qt.AlignCenter)
    self.progress_value_label.setVisible(False)
    self.progress_value_label.setStyleSheet("color: white;")

    self.log_viewer = QTextEdit(self)
    self.log_viewer.setReadOnly(True)
    self.log_viewer.setStyleSheet(
      "QTextEdit{font-family:monospace;font-size:11px;background:rgba(15,23,42,0.6);border:none}")
    self.log_viewer.setVisible(False)

    grid = QGridLayout()
    grid.setHorizontalSpacing(24)
    grid.setVerticalSpacing(16)
    grid.setContentsMargins(0, 0, 0, 0)
    grid.setColumnStretch(0, 1)
    grid.setColumnStretch(1, 1)
    grid.setColumnStretch(2, 1)
    grid.setRowStretch(0, 0)
    grid.setRowStretch(1, 1)
    grid.setRowStretch(2, 0)
    grid.setRowStretch(3, 0)

    self.left_box = QVBoxLayout()
    self.left_box.setSpacing(16)

    self.intro_label = QLabel("To begin, drag & drop a directory containing image files or click to browse.")
    self.intro_label.setWordWrap(True)
    self.intro_label.setStyleSheet("color:#cbd5e1;font-size:14px")
    self.intro_line = QFrame()
    self.intro_line.setFixedHeight(1)
    self.intro_line.setStyleSheet(
      "background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 transparent, stop:0.5 #475569, stop:1 transparent)")
    self.left_box.addWidget(self.intro_label)
    self.left_box.addWidget(self.intro_line)

    header_hbox = QHBoxLayout()
    header_hbox.setSpacing(8)

    self.settings_icon = QSvgWidget(resource_path("assets/icons/settings.svg"))
    self.settings_icon.setFixedSize(20, 20)
    self.settings_icon.setStyleSheet("background: transparent;")
    icon_effect = QGraphicsColorizeEffect(self.settings_icon)
    icon_effect.setColor(QColor("#60A5FA"))
    self.settings_icon.setGraphicsEffect(icon_effect)

    self.settings_title_lbl = QLabel("Settings")
    self.settings_title_lbl.setStyleSheet("font-size: 18px; font-weight: 600; color: white;")

    header_hbox.addWidget(self.settings_icon)
    header_hbox.addWidget(self.settings_title_lbl)
    header_hbox.addStretch(1)
    self.left_box.addLayout(header_hbox)

    self.settings_card = QFrame(self)
    self.settings_card.setLayout(QVBoxLayout())
    self.settings_card.layout().setContentsMargins(16, 16, 16, 16)
    self.settings_card.setStyleSheet(GLASS_PANEL)

    settings_hbox = QHBoxLayout()
    settings_hbox.setSpacing(24)

    fr_col = QVBoxLayout()
    fr_col.setContentsMargins(0, 0, 0, 0)
    fr_col.setSpacing(6)
    res_col = QVBoxLayout()
    res_col.setContentsMargins(0, 0, 0, 0)
    res_col.setSpacing(6)

    framerate_label = QLabel("Framerate (FPS):", self.settings_card)
    framerate_label.setStyleSheet("border:none;background:transparent;color:white;font-size:14px;")
    fr_col.addWidget(framerate_label)
    self.framerate_dropdown.setParent(self.settings_card)
    self.framerate_dropdown.setStyleSheet(
      "QComboBox{background:#334155;color:white;padding:6px 12px;border:1px solid #475569;border-radius:8px}")
    fr_col.addWidget(self.framerate_dropdown)

    resolution_label = QLabel("Resolution:", self.settings_card)
    resolution_label.setStyleSheet("border:none;background:transparent;color:white;font-size:14px;")
    res_col.addWidget(resolution_label)
    self.resolution_dropdown.setParent(self.settings_card)
    self.resolution_dropdown.setStyleSheet(
      "QComboBox{background:#334155;color:white;padding:6px 12px;border:1px solid #475569;border-radius:8px}")
    res_col.addWidget(self.resolution_dropdown)

    settings_hbox.addLayout(fr_col)
    settings_hbox.addLayout(res_col)
    self.settings_card.layout().addLayout(settings_hbox)

    settings_hbox = QHBoxLayout()
    settings_hbox.setSpacing(24)

    io_col = QVBoxLayout()
    io_col.setContentsMargins(0, 0, 0, 0)
    io_col.setSpacing(6)

    framerate_label = QLabel("Image Order:", self.settings_card)
    framerate_label.setStyleSheet("border:none;background:transparent;color:white;font-size:14px;")
    io_col.addWidget(framerate_label)
    self.image_order_dropdown.setParent(self.settings_card)
    self.image_order_dropdown.setStyleSheet(
      "QComboBox{background:#334155;color:white;padding:6px 12px;border:1px solid #475569;border-radius:8px}")
    io_col.addWidget(self.image_order_dropdown)

    settings_hbox.addLayout(io_col)
    self.settings_card.layout().addLayout(settings_hbox)

    self.left_box.addWidget(self.settings_card)
    self.space_between = QWidget(self)
    self.space_between.setFixedHeight(10)
    self.space_between.setVisible(False)
    self.left_box.addWidget(self.space_between)

    self.image_list_header = QWidget(self)
    header_layout = QHBoxLayout(self.image_list_header)
    header_layout.setContentsMargins(0, 0, 0, 0)
    header_layout.setSpacing(8)

    self.image_list_icon = QSvgWidget(resource_path("assets/icons/image.svg"))
    self.image_list_icon.setFixedSize(20, 20)
    self.image_list_icon.setStyleSheet("background: transparent;")
    icon_effect = QGraphicsColorizeEffect(self.image_list_icon)
    icon_effect.setColor(QColor("#60A5FA"))
    self.image_list_icon.setGraphicsEffect(icon_effect)

    self.image_list_label = QLabel("Image List")
    self.image_list_label.setStyleSheet("font-size:18px; font-weight:600; color:white")

    header_layout.addWidget(self.image_list_icon)
    header_layout.addWidget(self.image_list_label)
    header_layout.addStretch(1)

    self.image_list_header.setVisible(False)

    self.left_box.addWidget(self.image_list_header)
    self.left_box.addWidget(self.image_list_widget)
    self.left_box.addStretch(1)

    self.status_card = QFrame(self)
    self.status_card.setLayout(QVBoxLayout())
    self.status_card.layout().setContentsMargins(16, 16, 16, 16)
    self.status_card.layout().setSpacing(2)
    self.status_card.setObjectName("status_card")
    self.status_card.setStyleSheet("""
        QFrame#status_card {
            background: rgba(30,41,59,0.5);
            border: 1px solid rgba(51,65,85,0.5);
            border-radius: 12px;
        }
    """)
    self.status_card.setVisible(False)
    self.status_card.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
    self.status_header = QLabel("Stabilizing...")
    self.status_header.setAlignment(Qt.AlignCenter)
    self.status_header.setVisible(True)
    self.status_header.setStyleSheet(common_title_style)
    self.status_card.layout().addWidget(self.status_header)

    self.progress_view = QWidget(self.status_card)
    pv_layout = QVBoxLayout(self.progress_view)
    pv_layout.setContentsMargins(0, 0, 0, 0)
    header_layout = QHBoxLayout()
    header_layout.setContentsMargins(0, 0, 0, 0)
    progress_static_label = QLabel("Progress", self.progress_view)
    progress_static_label.setStyleSheet("color: white;")
    header_layout.addWidget(progress_static_label)
    header_layout.addWidget(self.progress_value_label, alignment=Qt.AlignRight)
    pv_layout.addLayout(header_layout)
    pv_layout.addWidget(self.progress_bar)

    self.player_view = QWidget(self.status_card)
    pl_layout = QVBoxLayout(self.player_view)
    pl_layout.setContentsMargins(0, 0, 0, 0)
    self.player_container = QFrame(self.player_view)
    self.player_container.setStyleSheet("QFrame{background: #000; border-radius: 8px;}")
    self.player_container.setLayout(QVBoxLayout())
    self.player_container.layout().setContentsMargins(0, 0, 0, 0)
    self.player_container.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
    self.player_container.setMinimumHeight(0)
    pl_layout.addWidget(self.player_container)

    self.status_stack = QStackedLayout()
    self.status_stack.addWidget(self.progress_view)
    self.status_stack.addWidget(self.player_view)
    self.status_card.layout().addLayout(self.status_stack)

    self.status_card.setMinimumWidth(600)

    self.left_box.addWidget(self.drop_area)

    self.tabs_bar = QWidget(self)
    tabs_layout = QHBoxLayout(self.tabs_bar)
    tabs_layout.setContentsMargins(0, 0, 0, 0)
    tabs_layout.setSpacing(8)
    self.tab_images_btn = QPushButton("Images", self.tabs_bar)
    self.tab_result_btn = QPushButton("Result", self.tabs_bar)
    self.tab_images_btn.setStyleSheet(
      "background-color:#334155;color:#cbd5e1;border:1px solid #475569;border-radius:8px;padding:6px 12px;")
    self.tab_result_btn.setStyleSheet(
      "background-color:#334155;color:#cbd5e1;border:1px solid #475569;border-radius:8px;padding:6px 12px;")
    self.tab_images_btn.clicked.connect(self.show_images_tab)
    self.tab_result_btn.clicked.connect(self.show_result_tab)
    tabs_layout.addWidget(self.tab_images_btn)
    tabs_layout.addWidget(self.tab_result_btn)
    self.tabs_bar.setVisible(False)

    self.left_container = QWidget()
    self.left_container.setLayout(self.left_box)
    self.left_container.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)

    self.bottom_buttons = QWidget(self)
    bottom_layout = QHBoxLayout(self.bottom_buttons)
    bottom_layout.setContentsMargins(0, 0, 0, 0)
    bottom_layout.setSpacing(8)
    bottom_layout.addWidget(self.open_stabilized_folder_button)
    bottom_layout.addWidget(self.open_video_folder_button)
    bottom_layout.addStretch(1)
    bottom_layout.addWidget(self.start_button)
    bottom_layout.addWidget(self.show_log_button)
    bottom_layout.addWidget(self.read_docs_button)

    grid.addWidget(self.tabs_bar, 0, 0, 1, 3)
    grid.addWidget(self.left_container, 1, 0, 1, 3)
    self.result_wrapper = QWidget(self)
    self.result_wrapper.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
    _result_wrap_layout = QVBoxLayout(self.result_wrapper)
    _result_wrap_layout.setContentsMargins(0, 0, 0, 0)
    _result_wrap_layout.setSpacing(0)
    _result_wrap_layout.addStretch(1)
    _result_wrap_layout.addWidget(self.status_card, 0, Qt.AlignHCenter)
    _result_wrap_layout.addStretch(1)
    _result_wrap_layout.setAlignment(self.status_card, Qt.AlignHCenter | Qt.AlignVCenter)
    grid.addWidget(self.result_wrapper, 1, 0, 1, 3)
    self.result_wrapper.setVisible(False)
    grid.addWidget(self.bottom_buttons, 2, 0, 1, 3)
    grid.addWidget(self.log_viewer, 3, 0, 1, 3)

    gallery_container = QWidget()
    gallery_container.setLayout(grid)
    return gallery_container

  def get_image_creation_date(self, image_path):
    try:
      with open(image_path, 'rb') as f:
        tags = exifread.process_file(f, stop_tag="EXIF DateTimeOriginal", details=False)
      date_tag = tags.get('EXIF DateTimeOriginal')
      if date_tag:
        return str(date_tag)
    except Exception:
      pass
    modification_time = os.path.getmtime(image_path)
    return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(modification_time))

  def toggle_image_list_visibility(self):
    if self.image_list_widget.isVisible():
      self.image_list_widget.setVisible(False)
    else:
      self.image_list_widget.setVisible(True)

  def process_files(self, file_paths):
    self.drop_area.setText("Processing files...")
    QApplication.processEvents()
    if self._load_images(file_paths):
        self.input_dir = os.path.dirname(self.image_paths[0])
    else:
        self.drop_area.setText("No valid image files selected.")

  def browse_directory(self):
    files, _ = QFileDialog.getOpenFileNames(
      self,
      "Select images (or cancel to choose a folder)",
      "",
      "Images (*.png *.jpg *.jpeg *.webp *.heic)"
    )
    if files:
      self.process_files(files)
      return

    directory = QFileDialog.getExistingDirectory(self, "Select Directory")
    if directory:
      self.process_directory(directory)

  def process_directory(self, directory):
    print("[LOG] Processing directory...")
    try:
      self.drop_area.setText("Processing directory...")
      QApplication.processEvents()
      self.input_dir = get_path(directory)
      files = [
        os.path.join(self.input_dir, f)
        for f in os.listdir(self.input_dir)
      ]
      if not self._load_images(files):
        self.drop_area.setText("No valid images found in the directory.")
    except FileNotFoundError as e:
      self.drop_area.setText(f"Error: Directory not found: {e}")
    except PermissionError as e:
      self.drop_area.setText(f"Error: Permission denied: {e}")
    except Exception as e:
      self.drop_area.setText(f"An unexpected error occurred: {e}")

  def start_stabilization(self):
    self.state = APP_STATE_STABILIZING
    self.start_button.setEnabled(False)
    self.start_button.setVisible(False)
    self.settings_section.setVisible(False)
    self.settings_card.setVisible(False)
    self.settings_icon.setVisible(False)
    self.settings_title_lbl.setVisible(False)
    self.open_stabilized_folder_button.setVisible(False)
    self.open_video_folder_button.setVisible(False)
    self.status_card.setVisible(True)
    self.progress_bar.setVisible(True)
    self.progress_value_label.setVisible(True)
    if self.media_player:
      self.media_player.stop()
    self.status_card.setMaximumHeight(560)
    self.player_container.setMinimumHeight(0)
    self.player_container.setMaximumHeight(480)
    self.status_card.setMaximumHeight(560)
    self.status_stack.setCurrentIndex(0)
    self.status_header.setVisible(True)
    self.status_header.setText("Stabilizing...")
    if hasattr(self, "tabs_bar"):
      self.tabs_bar.setVisible(True)
      self.show_result_tab()

    ordered_input = self.get_ordered_input_dir()

    if self.executor is None:
      self.executor = ThreadPoolExecutor(max_workers=1)

    self.executor.submit(self.run_stabilization, ordered_input, self.output_dir)

  def run_stabilization(self, input_dir, output_dir):
    print("[LOG] Initializing Tensorflow...")
    # all GUI updates via the queued signal
    self.status_text_signal.emit("Initializing Tensorflow...")

    try:
      from src.face_stabilizer import stabilize_image_directory

      self.status_text_signal.emit("Stabilizing...")
      stabilize_image_directory(
        input_dir,
        output_dir,
        self.update_progress_signal.emit,
        self.selected_resolution
      )
    except Exception as e:
      print(f"Error: {e}")
      self.status_text_signal.emit(f"Error: {e}")
    else:
      self.finished_signal.emit()

  def thumbnails_have_loaded(self, thumbnail_dir_path):
    print(f"Thumbnails have loaded successfully at {thumbnail_dir_path}")
    self.executor.submit(self.thumbnail_loader.load_thumbnails, thumbnail_dir_path)

  def add_thumbnail_to_grid(self, pixmap):
    row, col = divmod(self.grid_layout.count(), 4)
    thumbnail_label = QLabel(self)
    thumbnail_label.setPixmap(pixmap.scaled(100, 100, Qt.KeepAspectRatio))
    self.grid_layout.addWidget(thumbnail_label, row, col)

  def update_progress(self, value):
    if self.state in (APP_STATE_STABILIZING, APP_STATE_COMPILING):
      clamped = min(int(value), 99)
    else:
      clamped = int(value)
    self.progress_bar.setValue(clamped)
    self.progress_value_label.setText(f"{clamped}%")

  def _load_images(self, paths):
    self.image_paths = [
        p for p in paths
        if p.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.heic'))
    ]
    if not self.image_paths:
        return False
    self.apply_sort()
    self.populate_image_table()
    count = len(self.image_paths)
    self.image_list_label.setText(f"Image List ({count})")
    print(f"[LOG] Loaded {count} images.")
    self.start_button.setEnabled(True)
    self.drop_area.setVisible(False)
    self.intro_label.setVisible(False)
    self.intro_line.setVisible(False)
    self.image_list_widget.setVisible(True)
    self.start_button.setVisible(True)
    self.image_list_header.setVisible(True)
    self.space_between.setVisible(True)
    return True

  def on_processing_finished(self):
    self.state = APP_STATE_COMPILING
    self.status_header.setText("Compiling video...")
    self.progress_bar.setValue(99)
    self.progress_value_label.setText("99%")
    self.open_stabilized_folder_button.setVisible(False)
    self.open_video_folder_button.setVisible(False)
    self.status_stack.setCurrentIndex(0)
    QApplication.processEvents()
    if hasattr(self, "tabs_bar"):
      self.tabs_bar.setVisible(True)
      self.show_result_tab()

    if self.executor is None:
      self.executor = ThreadPoolExecutor(max_workers=1)

    self.executor.submit(self.compile_video_worker)

  def compile_video_worker(self):
    try:
      self.output_video_dir = os.path.join(self.project_dir, "Video")
      os.makedirs(self.output_video_dir, exist_ok=True)

      framerate = self.selected_framerate

      self.video_output_file = compile_video(
        self.stab_img_dir,
        os.path.join(self.output_video_dir, "video.mp4"),
        framerate
      )
      self.video_finished_signal.emit(True)
    except Exception as e:
      self.video_status_signal.emit(f"Error during video compilation: {e}")
      self.video_finished_signal.emit(False)

  def on_video_finished(self, success):
    if self.temp_input_dir and os.path.isdir(self.temp_input_dir):
      shutil.rmtree(self.temp_input_dir)
      self.temp_input_dir = None

    if not success:
      self.state = APP_STATE_ERROR
      self.progress_bar.setValue(99)
      self.progress_value_label.setText("99%")
      self.status_header.setText("Compilation failed.")
      self.open_stabilized_folder_button.setVisible(False)
      self.open_video_folder_button.setVisible(False)
      self.status_stack.setCurrentIndex(0)
      if hasattr(self, "tabs_bar"):
        self.tabs_bar.setVisible(True)
        self.show_result_tab()
      return

    self.state = APP_STATE_DONE
    self.progress_bar.setValue(100)
    self.progress_value_label.setText("100%")
    self.open_stabilized_folder_button.setVisible(True)
    self.open_video_folder_button.setVisible(True)

    if not self.media_player:
      self.media_player = QMediaPlayer(self)
      self.video_widget = QVideoWidget(self.player_container)
      self.video_widget.setAspectRatioMode(Qt.KeepAspectRatio)
      self.video_widget.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
      self.player_container.layout().addWidget(self.video_widget)
      self.media_player.setVideoOutput(self.video_widget)
      self.playlist = QMediaPlaylist(self)
      self.media_player.setPlaylist(self.playlist)
      self.media_player.setMuted(True)

    self.playlist.clear()
    if self.video_output_file and os.path.isfile(self.video_output_file):
      self.playlist.addMedia(QMediaContent(QUrl.fromLocalFile(self.video_output_file)))
    else:
      if hasattr(self, "output_video_dir"):
        candidate = os.path.join(self.output_video_dir, "video.mp4")
        if os.path.isfile(candidate):
          self.video_output_file = candidate
          self.playlist.addMedia(QMediaContent(QUrl.fromLocalFile(candidate)))

    self.playlist.setCurrentIndex(0)
    self.playlist.setPlaybackMode(QMediaPlaylist.CurrentItemInLoop)

    self.status_card.setMaximumHeight(16777215)

    self.player_container.setMinimumHeight(360)
    self.player_container.setMaximumHeight(16777215)

    self.status_stack.setCurrentIndex(1)
    self.status_header.setVisible(False)
    if hasattr(self, "tabs_bar"):
      self.tabs_bar.setVisible(True)
      self.show_result_tab()
    if hasattr(self, "result_wrapper"):
      self.result_wrapper.setVisible(True)
    self.video_widget.show()
    self.player_view.show()
    if self.playlist.mediaCount() == 0 and self.video_output_file:
      self.media_player.setMedia(QMediaContent(QUrl.fromLocalFile(self.video_output_file)))
    self.media_player.setPosition(0)
    self.media_player.play()

  def open_stabilized_folder(self):
    if os.path.isdir(self.output_dir):
      if sys.platform == 'darwin':
        subprocess.run(['open', self.output_dir])
      elif sys.platform == 'win32':
        os.startfile(self.output_dir)
      elif sys.platform.startswith('linux'):
        subprocess.run(['xdg-open', self.output_dir])
    else:
      self.drop_area.setText("Invalid folder path.")

  def open_video_folder(self):
    if self.video_output_file and os.path.isfile(self.video_output_file):
      directory = os.path.dirname(self.video_output_file)
      if sys.platform == 'darwin':
        subprocess.run(['open', directory])
      elif sys.platform == 'win32':
        os.startfile(directory)
      elif sys.platform.startswith('linux'):
        subprocess.run(['xdg-open', directory])
    else:
      print("Error opening video folder.")
      self.drop_area.setText("Invalid video file path.")

  def mousePressEvent(self, event: QMouseEvent):
    if event.button() == Qt.LeftButton:
      self.start_pos = event.globalPos()
      self.start_size = self.size()
      self.resizing_direction = self.get_resizing_direction(event.pos())
      if self.resizing_direction is None:
        self.offset = event.pos()

  def mouseMoveEvent(self, event: QMouseEvent):
    direction = self.get_resizing_direction(event.pos())
    self.update_cursor_shape(direction)

    if self.resizing_direction is not None:
      diff = event.globalPos() - self.start_pos
      new_rect = QRect(self.geometry())
      if self.resizing_direction & Qt.LeftEdge:
        new_rect.setLeft(new_rect.left() + diff.x())
      elif self.resizing_direction & Qt.RightEdge:
        new_rect.setRight(new_rect.right() + diff.x())
      if self.resizing_direction & Qt.TopEdge:
        new_rect.setTop(new_rect.top() + diff.y())
      elif self.resizing_direction & Qt.BottomEdge:
        new_rect.setBottom(new_rect.bottom() + diff.y())
      self.setGeometry(new_rect)
      self.start_pos = event.globalPos()
    elif hasattr(self, 'offset') and event.buttons() == Qt.LeftButton:
      x = event.globalX()
      y = event.globalY()
      x_w = self.offset.x()
      y_w = self.offset.y()
      self.move(x - x_w, y - y_w)

  def event(self, event):
    if event.type() == QEvent.MouseMove:
      direction = self.get_resizing_direction(event.pos())
      self.update_cursor_shape(direction)
    return super().event(event)

  def resizeEvent(self, event):
    super().resizeEvent(event)
    if sys.platform == "darwin":
      self.update_window_mask()

  def update_window_mask(self):
    radius = 12.0
    rectf = QRectF(self.rect())
    path = QPainterPath()
    path.addRoundedRect(rectf, radius, radius)
    self.setMask(QRegion(path.toFillPolygon().toPolygon()))

  def update_cursor_shape(self, direction):
    if direction is not None:
      if direction & (Qt.LeftEdge | Qt.RightEdge):
        self.setCursor(QCursor(Qt.SizeHorCursor))
      if direction & (Qt.TopEdge | Qt.BottomEdge):
        self.setCursor(QCursor(Qt.SizeVerCursor))
      if direction == (Qt.TopEdge | Qt.LeftEdge) or direction == (Qt.BottomEdge | Qt.RightEdge):
        self.setCursor(QCursor(Qt.SizeFDiagCursor))
      if direction == (Qt.TopEdge | Qt.RightEdge) or direction == (Qt.BottomEdge | Qt.LeftEdge):
        self.setCursor(QCursor(Qt.SizeBDiagCursor))
    else:
      self.setCursor(QCursor(Qt.ArrowCursor))

  def leaveEvent(self, event):
    self.setCursor(QCursor(Qt.ArrowCursor))
    super().leaveEvent(event)

  def mouseReleaseEvent(self, event: QMouseEvent):
    self.resizing_direction = None

  def get_resizing_direction(self, pos):
    margins = 5
    rect = self.rect()
    direction = 0
    if pos.x() <= margins:
      direction |= Qt.LeftEdge
    elif pos.x() >= rect.width() - margins:
      direction |= Qt.RightEdge
    if pos.y() <= margins:
      direction |= Qt.TopEdge
    elif pos.y() >= rect.height() - margins:
      direction |= Qt.BottomEdge
    return direction if direction != 0 else None
