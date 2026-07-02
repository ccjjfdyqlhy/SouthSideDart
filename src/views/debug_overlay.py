from collections import deque
from dataclasses import dataclass
import os

import psutil

from imports import QMouseEvent, QPainterPath, QPen, QPoint, QRect, QTimer, QWidget, QFont, QFontMetricsF, Qt, QWheelEvent, QPainter, QColor
from core.app_context import AppContext
from core.smooth import EaseOutTimer
from core import theme

class DebugOverlay(QWidget):
    def __init__(self, ctx: AppContext, parent: QWidget) -> None:
        super().__init__(parent)
        self.ctx = ctx
        self.title_ft = QFont(ctx.harmony_font_family, 15, QFont.Weight.Bold)
        self.content_ft = QFont(ctx.harmony_font_family, 10, QFont.Weight.Normal)
        self.title_height = int(QFontMetricsF(self.title_ft).height())
        self.content_height = int(QFontMetricsF(self.content_ft).height())
        self.content_metri = QFontMetricsF(self.content_ft)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.hide()

        self.dragging = False
        self.drag_pos: QPoint = QPoint(0, 0)

        self.mem_datas: dict[str, deque[int]] = {}

        self.mem_timer = QTimer(self)
        self.mem_timer.timeout.connect(self.updateMemories)
        self.mem_timer.start(20)
        self.total_mem = psutil.virtual_memory().total
        self.max_value: EaseOutTimer = EaseOutTimer(0.3, 2)

        self.offset_timer = EaseOutTimer(0.2, 2)

    def updateMemories(self):
        if not self.ctx.debugging:
            return
        
        for name, pid in self.ctx.process_pids.items():
            if not self.mem_datas.get(name):
                self.mem_datas[name] = deque(maxlen=200)
            self.mem_datas[name].append(psutil.Process(pid).memory_info().rss)

        max_v = 0
        for _, lst in self.mem_datas.items():
            for v in lst:
                max_v = max(max_v, v)
        self.max_value.target_value = max_v

    def wheelEvent(self, event: QWheelEvent) -> None:
        self.offset_timer.target_value += event.angleDelta().y()
        return super().wheelEvent(event)

    def refresh(self) -> None:
        self.setVisible(self.ctx.debugging)
        if self.ctx.debugging:
            self.raise_()
            self.update()

    def mousePressEvent(self, event: QMouseEvent) -> None:
        event.accept()
        self.dragging = True
        self.drag_pos = QPoint(event.x(), event.y())

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if not self.dragging:
            return super().mouseMoveEvent(event)
        event.accept()
        self.move(self.pos() + event.pos() - self.drag_pos)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        event.accept()
        self.dragging = False

    def paintEvent(self, _) -> None:
        if not self.ctx.debugging:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(
            QColor(255, 255, 255, 100) if theme.isLight() else QColor(0, 0, 0, 100)
        )

        y = 50 + int(self.offset_timer.current_value)
        chart_rect = QRect(5, y - 215, self.width() - 10, 200)

        painter.drawRect(self.rect())
        painter.drawRect(chart_rect) # make the
        painter.drawRect(chart_rect) # color darker

        painter.setPen(QPen(QColor(255, 255, 255) if theme.isDark() else QColor(0, 0, 0), 2))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.setFont(self.content_ft)

        for name, values in self.mem_datas.items():
            path = QPainterPath()
            if not values:
                continue
            path.moveTo(5, values[0] / self.max_value.current_value * -200 + y)
            for i, v in enumerate(values):
                x = 5 + (self.width() - 10) * (i / 200)
                y_ = v / self.max_value.current_value * -200 + y
                path.lineTo(x, y_)
            txt = f'{name} - {(values[-1] / 1024/ 1024):.2f} MB'
            painter.drawText(int(max(0, x - self.content_metri.horizontalAdvance(txt) - 5)), int(y_ - 5), txt)
            painter.drawPath(path)

        painter.setFont(self.content_ft)
        painter.drawText(5, y - 215 - self.title_height, 'Memory')
        y += 100
        for info in self.ctx.debugging_obj.infos:
            name, lines = next(iter(info.items()))
            painter.setFont(self.title_ft)
            painter.drawText(10, y, name)
            y += self.title_height + 10
            painter.setFont(self.content_ft)
            for line in lines:
                painter.drawText(20, y, line)
                y += self.content_height + 1

        painter.end()
