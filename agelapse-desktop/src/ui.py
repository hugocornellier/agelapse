import concurrent.futures
import os
import platform
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import pillow_heif
import qtawesome as qta
from PyQt5.QtCore import Qt, pyqtSignal, QObject, QTimer, QRect, QEvent
from PyQt5.QtGui import QPixmap, QFont, QDragEnterEvent, QDropEvent, QMouseEvent, QCursor, QTextCursor
from PyQt5.QtWidgets import (
  QMainWindow, QLabel, QVBoxLayout, QWidget, QProgressBar, QPushButton, QSizePolicy,
  QGridLayout, QStackedWidget, QListWidget, QListWidgetItem, QHBoxLayout, QApplication, QFileDialog, QTextEdit
)

from src.video_compile import compile_video
from pathlib import Path


def get_path(filename):
  # Split the filename into the base name and extension
  name = os.path.splitext(filename)[0]
  ext = os.path.splitext(filename)[1]

  if platform.system() == "Darwin":
    from AppKit import NSBundle
    # Attempt to find the file in the macOS app bundle
    file = NSBundle.mainBundle().pathForResource_ofType_(name, ext)
    # Return the found file path or fallback to os.path.realpath
    return file or os.path.realpath(filename)
  else:
    # Use os.path.realpath for non-macOS platforms
    return os.path.realpath(filename)


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
        self.setFont(QFont('Arial', 12))
        self.setStyleSheet(self.get_style_sheet(text))

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.LeftButton:
            self.on_click()

    def on_click(self):
        pass  # Override this method in the subclass or instance

    def get_style_sheet(self, text):
      # Add margin-bottom and adjust font size when the text is a hyphen
      margin_bottom = "5px" if text == "⎯" else "0px"
      font_size = "24px" if text == "⎯" else "28px"

      # Determine the hover color based on the text
      hover_color = "rgba(255, 0, 0, 0.5)" if text == "×" else "rgba(255, 255, 255, 0.1)"

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
      self.init_ui()

  def init_ui(self):
      if sys.platform == "darwin":
          self.setup_mac_ui()
      else:
          self.setup_default_ui()

  def setup_default_ui(self):
      # Logo
      self.logo_label = QLabel(self)
      self.logo_label.setFixedSize(120, 30)
      pixmap = QPixmap(resource_path('assets/images/agelapse.png')).scaled(
          self.logo_label.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
      self.logo_label.setPixmap(pixmap)

      # Buttons
      self.minimize_button = CustomLabelButton("⎯", self)
      self.minimize_button.on_click = self.minimize_window

      self.restore_button = CustomLabelButton("▢", self)
      self.restore_button.on_click = self.restore_window

      self.close_button = CustomLabelButton("×", self)
      self.close_button.on_click = self.close_window

      # Layout
      layout = QHBoxLayout(self)
      layout.setContentsMargins(10, 0, 0, 0)  # Adjust margins as needed
      layout.setSpacing(5)  # Space between buttons
      layout.addWidget(self.logo_label)
      layout.addStretch(1)
      layout.addWidget(self.minimize_button)
      layout.addWidget(self.restore_button)
      layout.addWidget(self.close_button)

      # Set the layout to the main widget (or parent widget)
      self.setLayout(layout)

  def setup_mac_ui(self):
    # macOS standard title bar buttons on the left
    self.setStyleSheet("background-color: transparent;")

    # Button setup
    self.close_button = QPushButton(self)
    self.minimize_button = QPushButton(self)
    self.restore_button = QPushButton(self)

    # Make buttons circular
    circular_style = """
            QPushButton {{
                border-radius: 6px;  /* Half of the button's width and height */
                background-color: {};
            }}
        """

    self.close_button.setStyleSheet(circular_style.format("#ff5f56"))
    self.minimize_button.setStyleSheet(circular_style.format("#ffbd2e"))
    self.restore_button.setStyleSheet(circular_style.format("#28c940"))

    self.close_button.setFixedSize(12, 12)
    self.minimize_button.setFixedSize(12, 12)
    self.restore_button.setFixedSize(12, 12)

    self.close_button.clicked.connect(self.close_window)
    self.minimize_button.clicked.connect(self.minimize_window)
    self.restore_button.clicked.connect(self.restore_window)

    # Logo centered and ensure it does not get cut off
    self.logo_label = QLabel(self)
    self.logo_label.setFixedSize(120, 30)
    pixmap = QPixmap(resource_path('assets/images/agelapse.png')).scaled(self.logo_label.size(), Qt.KeepAspectRatio,
                                                                         Qt.SmoothTransformation)
    self.logo_label.setPixmap(pixmap)

    # Main layout for entire window
    main_layout = QHBoxLayout(self)
    main_layout.setContentsMargins(10, 5, 10, 5)  # Adjusted margins for overall layout

    # Add buttons to the layout
    main_layout.addWidget(self.close_button)
    main_layout.addWidget(self.minimize_button)
    main_layout.addWidget(self.restore_button)
    main_layout.addStretch(1)  # This adds a stretchable space that pushes the logo to center

    # Add the logo
    main_layout.addWidget(self.logo_label)

    # Spacer or invisible widgets to mirror the left side
    main_layout.addStretch(1)  # Ensures the logo is centered

    # Invisible widgets to match the width of the buttons
    invisible_button = QWidget(self)  # Create an invisible widget
    invisible_button.setFixedSize(66, 12)  # Match the total width of the buttons
    main_layout.addWidget(invisible_button)

    self.setLayout(main_layout)  # Set the layout on the main window/widget



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
                border-radius: 15px;
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


class ThumbnailLoader(QObject):
  thumbnail_loaded = pyqtSignal(str, QPixmap)

  def load_thumbnails(self, thumbnail_dir_path):
    pillow_heif.register_heif_opener()
    for filename in os.listdir(thumbnail_dir_path):
      if filename.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.heic')):
        file_path = os.path.join(thumbnail_dir_path, filename)
        pixmap = QPixmap(file_path)
        self.thumbnail_loaded.emit(file_path, pixmap)


class DropArea(QLabel):
  def __init__(self, main_window, parent=None):
    super().__init__(parent)
    self.main_window = main_window
    self.setText("Drag and drop a directory containing image files\n\n(Click to browse for a directory)")
    self.setAlignment(Qt.AlignCenter)
    self.setStyleSheet("""
            border: 2px dashed #aaa; 
            padding: 20px; 
            margin: 10px;
            background-color: #333;  /* Dark background */
            color: white;  /* White text */
        """)
    self.setAcceptDrops(True)

    # Initialize the timer if needed for future use
    self.timer = QTimer(self)

  def mousePressEvent(self, event: QMouseEvent):
    if event.button() == Qt.LeftButton:
      self.main_window.browse_directory()

  def dragEnterEvent(self, event: QDragEnterEvent):
    self.setText("Drop it...")
    if event.mimeData().hasUrls():
      event.acceptProposedAction()

  def dropEvent(self, event: QDropEvent):
    urls = event.mimeData().urls()
    if urls:
      directory = urls[0].toLocalFile()
      if os.path.isdir(directory):
        self.setText("processing dir")
        self.main_window.process_directory(directory)
      else:
        self.setText("Please drop a valid directory")




class MainWindow(QMainWindow):
    update_progress_signal = pyqtSignal(int)
    finished_signal = pyqtSignal()

    def __init__(self):
        super().__init__()

        # Set window flags to remove default title bar but keep resizing capabilities
        self.setWindowFlags(
            Qt.FramelessWindowHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
        )

        # Set the window style
        self.setStyleSheet("background-color: #222; color: white;")  # Dark background and white text

        # Create and add the custom title bar
        self.title_bar = CustomTitleBar(self)

        # Create stacked widget and gallery container
        self.stacked_widget = QStackedWidget(self)
        self.gallery_container = self.create_gallery_container()

        # Add widgets to the stacked layout
        self.stacked_widget.addWidget(self.gallery_container)

        # Main widget and layout setup
        self.main_widget = QWidget(self)
        self.main_layout = QVBoxLayout(self.main_widget)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        self.main_layout.addWidget(self.title_bar)
        self.main_layout.addWidget(self.stacked_widget)

        self.setCentralWidget(self.main_widget)
        self.stacked_widget.setCurrentWidget(self.gallery_container)

        # Initialize executor for background tasks
        self.executor = None
        self.update_progress_signal.connect(self.update_progress)
        self.finished_signal.connect(self.on_processing_finished)

        # Set an initial size
        self.resize(800, 600)

        # Track resizing state
        self.resizing_direction = None
        self.start_pos = None
        self.start_size = None

        # Define home path & output dirs
        home_dir = Path.home()
        self.app_dir = os.path.join(home_dir, "AgeLapse")
        os.makedirs(self.app_dir, exist_ok=True)

        self.stab_img_dir = os.path.join(self.app_dir, "Stabilized Images")
        os.makedirs(self.stab_img_dir, exist_ok=True)

        self.output_dir = self.stab_img_dir

        # Log viewer
        self.log_viewer = QTextEdit(self)
        self.log_viewer.setReadOnly(True)
        self.log_viewer.setVisible(False)  # Initially hidden

        # Redirect stdout to capture print statements
        self.stdout = sys.stdout
        sys.stdout = self

        self.main_layout.addWidget(self.log_viewer)

    def toggle_log(self):
      if self.log_viewer.isVisible():
        self.log_viewer.setVisible(False)
        self.show_log_button.setText("Show Log")  # Change toggle_log_button to show_log_button
      else:
        self.log_viewer.setVisible(True)
        self.show_log_button.setText("Hide Log")  # Change toggle_log_button to show_log_button

    def write(self, message):
      # Move cursor to the end of the text edit to append the new message
      cursor = self.log_viewer.textCursor()
      cursor.movePosition(QTextCursor.End)
      self.log_viewer.setTextCursor(cursor)

      # Insert message without adding a newline
      self.log_viewer.insertPlainText(message)

      # Ensure the log view auto-scrolls to the bottom
      self.log_viewer.ensureCursorVisible()

    def flush(self):
        pass  # Required for the write method to work correctly

    def closeEvent(self, event):
        # Restore stdout when closing the application
        sys.stdout = self.stdout
        event.accept()

    def create_gallery_container(self):
        self.drop_area = DropArea(self)
        self.progress_bar = QProgressBar(self)  # Initialize progress_bar as an attribute of self
        self.progress_bar.setStyleSheet(
            "QProgressBar {background-color: #555; border: 1px solid #444; text-align: center; color: white;} QProgressBar::chunk {background-color: #0066cc;}")
        self.progress_bar.setVisible(False)  # Hide the progress bar initially

        self.image_list_widget = QListWidget(self)  # List widget to show images
        self.image_list_widget.setVisible(False)  # Initially hidden
        self.image_list_widget.setStyleSheet("background-color: #333; color: white;")  # Dark background for list
        self.start_button = QPushButton("Start Stabilization", self)
        self.start_button.setEnabled(False)  # Initially disabled
        self.start_button.clicked.connect(self.start_stabilization)
        self.start_button.setStyleSheet("""
                QPushButton {
                    background-color: #004080;  /* Dark blue background */
                    color: white;  /* White text */
                    border-radius: 5px;  /* Slightly rounded corners */
                    padding: 10px;
                }
                QPushButton:disabled {
                    background-color: #555;  /* Darker gray when disabled */
                    color: #888;  /* Lighter gray text when disabled */
                }
            """)

        self.image_count_label = QLabel(self)  # Label to show the count of images loaded
        self.image_count_label.setAlignment(Qt.AlignCenter)
        self.image_count_label.setVisible(False)  # Initially hidden
        self.image_count_label.setStyleSheet("color: white;")  # White text

        self.progress_value_label = QLabel(self)  # Label to show progress value
        self.progress_value_label.setAlignment(Qt.AlignCenter)
        self.progress_value_label.setVisible(False)  # Initially hidden
        self.progress_value_label.setStyleSheet("color: white;")  # White text

        # Add a button to open the stabilized image folder
        self.open_stabilized_folder_button = QPushButton("Open Stabilized Image Folder", self)
        self.open_stabilized_folder_button.setVisible(False)  # Initially hidden
        self.open_stabilized_folder_button.clicked.connect(self.open_stabilized_folder)
        self.open_stabilized_folder_button.setStyleSheet("""
                QPushButton {
                    background-color: #008000;  /* Dark green background */
                    color: white;  /* White text */
                    border-radius: 5px;  /* Slightly rounded corners */
                    padding: 10px;
                }
                QPushButton:hover {
                    background-color: #006400;  /* Slightly darker green when hovered */
                }
            """)

        # Button to open the video folder
        self.open_video_folder_button = QPushButton("Open Video Folder", self)
        self.open_video_folder_button.setVisible(False)  # Initially hidden
        self.open_video_folder_button.clicked.connect(self.open_video_folder)
        self.open_video_folder_button.setStyleSheet("""
                QPushButton {
                    background-color: #008000;  /* Dark green background */
                    color: white;  /* White text */
                    border-radius: 5px;  /* Slightly rounded corners */
                    padding: 10px;
                }
                QPushButton:hover {
                    background-color: #006400;  /* Slightly darker green when hovered */
                }
            """)

        # Button to show log
        self.show_log_button = QPushButton("Show Log", self)
        self.show_log_button.setVisible(True)
        self.show_log_button.clicked.connect(self.toggle_log)  # Connect to toggle_log
        self.show_log_button.setStyleSheet("""
                QPushButton {
                    background-color: #333333;  /* Dark grey background */
                    color: white;  /* White text */
                    border-radius: 5px;  /* Slightly rounded corners */
                    padding: 10px;
                }
                QPushButton:hover {
                    background-color: #262626;  /* Slightly darker green when hovered */
                }
            """)

        grid_widget = QWidget()
        self.grid_layout = QGridLayout()  # It's also good to initialize this here if needed elsewhere
        grid_widget.setLayout(self.grid_layout)

        # Create the main layout for the gallery container
        layout = QVBoxLayout()
        layout.addWidget(self.drop_area)
        layout.addWidget(self.image_count_label)  # Add image count label to the layout above the list
        layout.addWidget(self.image_list_widget)
        layout.addWidget(self.open_stabilized_folder_button)
        layout.addWidget(self.open_video_folder_button)
        layout.addWidget(self.show_log_button)
        layout.addWidget(self.start_button)
        layout.addWidget(self.progress_bar)
        layout.setSpacing(10)  # Adjust or remove spacing if needed
        layout.setContentsMargins(20, 20, 20, 20)  # Add margins around the entire layout

        gallery_container = QWidget()
        gallery_container.setLayout(layout)

        return gallery_container

    def browse_directory(self):
        # Open a dialog to select a directory
        directory = QFileDialog.getExistingDirectory(self, "Select Directory")
        if directory:
            self.process_directory(directory)  # Process the selected directory

    def process_directory(self, directory):
        print("[LOG] Processing directory...")
        try:
            self.drop_area.setText("I'm in the processing dir call...")
            QApplication.processEvents()  # Force the GUI to update

            # Resolve the directory path
            self.input_dir = get_path(directory)

            # Collect image paths and display them in the list widget
            self.image_list_widget.clear()

            # Use the resolved path to list valid images
            valid_images = [f for f in os.listdir(self.input_dir) if
                            f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.heic'))]

            # Sort the list of valid images alphabetically
            valid_images.sort()

            if valid_images:
                self.image_list_widget.setVisible(True)  # Show the image list widget
                for image in valid_images:
                    item = QListWidgetItem(image)
                    self.image_list_widget.addItem(item)

                self.image_count_label.setVisible(True)  # Show image count label

                valid_image_len = len(valid_images)
                self.image_count_label.setText(f"Images loaded: ({valid_image_len})")  # Update text with image count
                print(f"[LOG] Loaded {valid_image_len} images.")

                self.start_button.setEnabled(True)  # Enable start button when images are loaded
                self.drop_area.setVisible(False)  # Hide the drop area
            else:
                self.drop_area.setText("No valid images found in the directory.")
        except FileNotFoundError as e:
            self.drop_area.setText(f"Error: Directory not found: {e}")
        except PermissionError as e:
            self.drop_area.setText(f"Error: Permission denied: {e}")
        except Exception as e:
            self.drop_area.setText(f"An unexpected error occurred: {e}")

    def start_stabilization(self):
        self.start_button.setEnabled(False)  # Disable start button during processing
        self.start_button.setVisible(False)  # Hide the start button during processing

        # Hide the image list and show the "Stabilizing... please wait" message
        self.image_list_widget.setVisible(False)
        self.image_count_label.setText("Initializing TensorFlow...\nThis will take a moment.")
        self.image_count_label.setVisible(True)
        self.image_count_label.setStyleSheet("font-size: 24px; font-weight: bold; text-align: center; color: white;")

        self.progress_value_label.setText("Progress: 0%")  # Initialize progress text
        self.progress_value_label.setVisible(True)  # Show progress value label
        self.progress_bar.setVisible(True)  # Show progress bar when stabilization starts

        if self.executor is None:
            self.executor = ThreadPoolExecutor(max_workers=1)

        self.executor.submit(self.run_stabilization, self.input_dir, self.output_dir)

    def run_stabilization(self, input_dir, output_dir):
        print("[LOG] Preparing Tensorflow... This may take a moment.")

        def stabilize_in_background(input_dir, output_dir):
            try:
                from src.face_stabilizer import stabilize_image_directory

                self.image_count_label.setText("Stabilizing... please wait")
                self.image_count_label.setVisible(True)
                self.image_count_label.setStyleSheet("font-size: 24px; font-weight: bold; text-align: center; color: white;")

                stabilize_image_directory(input_dir, output_dir, self.update_progress_signal.emit)
            except Exception as e:
                print(f"Error: {e}")
                self.drop_area.setText(f"Error during stabilization: {e}")
            else:
                self.finished_signal.emit()

        # Run stabilization in a separate thread to avoid blocking the UI
        with concurrent.futures.ThreadPoolExecutor() as executor:
            executor.submit(stabilize_in_background, input_dir, output_dir)

    def thumbnails_have_loaded(self, thumbnail_dir_path):
        print(f"Thumbnails have loaded successfully at {thumbnail_dir_path}")
        self.executor.submit(self.thumbnail_loader.load_thumbnails, thumbnail_dir_path)

    def add_thumbnail_to_grid(self, pixmap):
        row, col = divmod(self.grid_layout.count(), 4)
        thumbnail_label = QLabel(self)
        thumbnail_label.setPixmap(pixmap.scaled(100, 100, Qt.KeepAspectRatio))
        self.grid_layout.addWidget(thumbnail_label, row, col)

    def update_progress(self, value):
        self.progress_bar.setValue(value)
        self.progress_value_label.setText(f"Progress: {value}%")  # Update progress value label

    def on_processing_finished(self):
        print("On processing finished call")

        self.image_count_label.setText("Compiling video...")
        self.image_count_label.setStyleSheet("font-size: 24px; font-weight: normal; text-align: center; color: white;")
        self.progress_value_label.setVisible(False)  # Hide progress value label after finishing

        # Show the button to open the stabilized image folder
        self.open_stabilized_folder_button.setVisible(True)
        # Force the GUI to update
        QApplication.processEvents()

        import time
        time.sleep(1)  # Wait for 1 second

        try:
            self.output_video_dir = os.path.join(self.app_dir, "Video")
            os.makedirs(self.output_video_dir, exist_ok=True)

            self.video_output_file = compile_video(
                self.stab_img_dir,
                os.path.join(self.output_video_dir, "video.mp4")
            )

            self.drop_area.setText(f"Processing complete! Your video is at {self.video_output_file}")
            self.image_count_label.setText("Video compiled successfully!")
            self.image_count_label.setStyleSheet("font-size: 24px; font-weight: bold; text-align: center; color: white;")

            # Show the button to open the video folder after compilation
            self.open_video_folder_button.setVisible(True)

        except Exception as e:
            self.drop_area.setText(f"Error during video compilation: {e}")

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
            self.drop_area.setText("Invalid video file path.")

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.LeftButton:
            self.start_pos = event.globalPos()
            self.start_size = self.size()
            self.resizing_direction = self.get_resizing_direction(event.pos())
            if self.resizing_direction is None:
                self.offset = event.pos()

    def mouseMoveEvent(self, event: QMouseEvent):
      # Determine the resizing direction on mouse hover
      direction = self.get_resizing_direction(event.pos())
      self.update_cursor_shape(direction)

      if self.resizing_direction is not None:
        # Perform resizing
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
        # Handle window dragging
        x = event.globalX()
        y = event.globalY()
        x_w = self.offset.x()
        y_w = self.offset.y()
        self.move(x - x_w, y - y_w)

    def event(self, event):
      if event.type() == QEvent.MouseMove:
        # Update cursor on hover
        direction = self.get_resizing_direction(event.pos())
        self.update_cursor_shape(direction)
      return super().event(event)

    def update_cursor_shape(self, direction):
      # Update the cursor shape based on the direction
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
      # Reset cursor when leaving the window
      self.setCursor(QCursor(Qt.ArrowCursor))
      super().leaveEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent):
        self.resizing_direction = None

    def get_resizing_direction(self, pos):
        margins = 5  # Margin in pixels to detect resizing edges
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