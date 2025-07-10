print("[LOG] Initializing Tensorflow, this may take a moment. Please wait...")

import tensorflow as tf
print("[LOG] TensorFlow", tf.__version__)

import sys
from PyQt5.QtWidgets import QApplication
from src.ui import MainWindow

def main():
    app = showUI()
    sys.exit(app.exec_())


def showUI():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    return app


if __name__ == '__main__':
    main()
