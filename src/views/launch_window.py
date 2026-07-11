from __future__ import annotations

from imports import (
    QApplication,
    IndeterminateProgressBar,
    QLabel,
    QSizePolicy,
    QSpacerItem,
    QVBoxLayout,
    QWidget,
    Qt,
    SubtitleLabel,
    tr,
)
from qfluentwidgets import TitleLabel
import hPyT

from core import theme


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
        hPyT.window_frame.center(self)

        self._stack: list[str] = []

        launchlayout = QVBoxLayout()
        launchlayout.addWidget(
            TitleLabel('Southside Music'),
            alignment=Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignBottom,
        )
        self.sublabel = SubtitleLabel(tr('launch_window.launching'))
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
        launchlayout.addWidget(IndeterminateProgressBar())
        self.setLayout(launchlayout)

        self.setStyleSheet(
            f'QWidget {{ background-color: {"#DDDDDD" if theme.isLight() else "#111111"} }} QLabel {{ color: {"white" if theme.isDark() else "black"}; }}'
        )

        self.show()

    def subtitle(self, text: str) -> None:
        self.subtitlel.setText(text)

    def clear(self) -> None:
        pass
