from __future__ import annotations
import threading
import time

from PySide6.QtCore import Qt
from PySide6.QtGui import QPalette
from PySide6.QtWidgets import (
    QApplication,
    QLabel,
    QProgressBar,
    QSizePolicy,
    QSpacerItem,
    QVBoxLayout,
    QWidget,
)


class LaunchWindow(QWidget):
    def __init__(self, app: QApplication) -> None:
        super().__init__()
        self._app: QApplication = app
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setFixedSize(app.primaryScreen().size() * 0.25)
        screen_geometry = app.primaryScreen().availableGeometry()
        self.move(screen_geometry.center() - self.rect().center())

        self._stack: list[str] = []

        launchlayout = QVBoxLayout()
        title_label = QLabel('Southside Music')
        title_label.setStyleSheet('font-size: 28px; font-weight: 600;')
        launchlayout.addWidget(
            title_label,
            alignment=Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignBottom,
        )
        self.sublabel = QLabel('Launching...')
        self.sublabel.setStyleSheet('font-size: 16px;')
        launchlayout.addWidget(
            self.sublabel,
            alignment=Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop,
        )
        launchlayout.addSpacerItem(
            QSpacerItem(
                0,
                0,
                QSizePolicy.Policy.Ignored,
                QSizePolicy.Policy.Expanding,
            )
        )
        self.subtitlel = QLabel()
        launchlayout.addWidget(self.subtitlel)
        progress_bar = QProgressBar()
        progress_bar.setRange(0, 0)
        progress_bar.setTextVisible(False)
        progress_bar.setFixedHeight(4)
        launchlayout.addWidget(progress_bar)
        self.setLayout(launchlayout)

        is_light = app.palette().color(QPalette.ColorRole.Window).lightness() > 127
        self.setStyleSheet(
            f'QWidget {{ background-color: {"#dddddd" if is_light else "#111111"}; }} '
            f'QLabel {{ color: {"black" if is_light else "white"}; }}'
        )

        self.show()
        self.raise_()
        self.activateWindow()
        self._app.processEvents()

    def subtitle(self, text: str) -> None:
        self.subtitlel.setText(text)
        self._app.processEvents()

    def clear(self) -> None:
        pass
