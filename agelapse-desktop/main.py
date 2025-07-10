from PyQt5.QtWidgets import QApplication, QSplashScreen
from PyQt5.QtGui import QPixmap, QPainter, QColor, QFont
from PyQt5.QtCore import Qt, QSize, QRect

import sys
from src.ui import MainWindow


def main():
    app = QApplication(sys.argv)


    logo_path = "./assets/images/agelapse.png"
    logo = QPixmap(logo_path).scaled(200, 200, Qt.KeepAspectRatio, Qt.SmoothTransformation)

    splash_size = QSize(600, 400)
    splash_pixmap = QPixmap(splash_size)
    splash_pixmap.fill(QColor("#1e1e1e"))

    painter = QPainter(splash_pixmap)

    x = (splash_size.width() - logo.width()) // 2
    y = (splash_size.height() - logo.height()) // 2 - 20
    painter.drawPixmap(x, y, logo)

    painter.setPen(QColor("#B0B0B0"))
    font = QFont()
    font.setPointSize(12)
    painter.setFont(font)
    text = "Preparing AgeLapse, please wait...\nThis may take a moment."
    text_rect = QRect(0, y + logo.height() + 20, splash_size.width(), 60)
    painter.drawText(text_rect, Qt.AlignHCenter | Qt.AlignTop, text)

    painter.end()

    splash = QSplashScreen(splash_pixmap, Qt.WindowStaysOnTopHint)
    splash.show()
    app.processEvents()

    print("[LOG] Initializing Tensorflow, this may take a moment. Please wait...")
    import tensorflow as tf
    print("[LOG] TensorFlow", tf.__version__)

    window = MainWindow()
    window.show()
    splash.finish(window)

    sys.exit(app.exec_())


if __name__ == '__main__':
    main()