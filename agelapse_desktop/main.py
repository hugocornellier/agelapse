import sys
from PyQt5.QtWidgets import QApplication
from src.ui import MainWindow  # Import the MainWindow from the ui module

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
