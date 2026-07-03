from collections import deque
import os
import time

import psutil

from imports import REPAINT, QHideEvent, QMouseEvent, QPainterPath, QPen, QPoint, QRect, QShowEvent, QTimer, QWidget, QFont, QFontMetricsF, Qt, QWheelEvent, QPainter, QColor, event_bus
from core.app_context import AppContext
from core.lyric_video_export import lyricVideoExportDebugInfo, lyricVideoExportDebugProcessPids
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
        self.collect_timer = QTimer(self)
        self.collect_timer.timeout.connect(self.updateDatas)
        self.total_mem = psutil.virtual_memory().total
        self.mmax_value: EaseOutTimer = EaseOutTimer(1, 2)

        self.cpu_datas: dict[str, deque[float]] = {}
        self.cpu_smoothed: dict[str, deque[float]] = {}
        self.cpu_cores = os.cpu_count() or 1
        self.last_cpu_time: dict[int, float] = {}
        self.last_wall: dict[int, float] = {}
        self.cmax_value: EaseOutTimer = EaseOutTimer(1, 2)
        self.tracked_pids: dict[str, set[int]] = {}
        
        self.raise_timer = QTimer(self)
        self.raise_timer.timeout.connect(self.tryRaise)

        self.process_cache: dict[int, psutil.Process] = {}

        self.offset_timer = EaseOutTimer(0.3, 2)

        event_bus.subscribe(REPAINT, self.refresh)

    def showEvent(self, event: QShowEvent) -> None:
        self.collect_timer.start(50)
        self.raise_timer.start(1000)
        return super().showEvent(event)

    def hideEvent(self, event: QHideEvent) -> None:
        self.collect_timer.stop()
        self.raise_timer.stop()
        return super().hideEvent(event)

    def tryRaise(self):
        if self.isHidden():
            return
        self.raise_()

    def updateDatas(self) -> None:
        pids = self._activeProcessPids()
        self._clearStaleProcessData(pids)
        self.updateMemories(pids)
        self.updateCpus(pids)

    def _processPids(self) -> dict[str, int]:
        pids = dict(self.ctx.process_pids)
        pids.update(lyricVideoExportDebugProcessPids())
        return pids

    def _activeProcessPids(self) -> dict[str, int]:
        active_pids: dict[str, int] = {}
        for name, pid in self._processPids().items():
            try:
                if not self.process_cache.get(pid):
                    self.process_cache[pid] = psutil.Process(pid)
                if not self.process_cache[pid].is_running():
                    continue
            except psutil.Error:
                continue
            active_pids[name] = pid
        return active_pids

    def _clearStaleProcessData(self, pids: dict[str, int]) -> None:
        stale_names = (
            set(self.mem_datas)
            | set(self.cpu_datas)
            | set(self.cpu_smoothed)
            | set(self.tracked_pids)
        ) - set(pids)
        for name in stale_names:
            self.mem_datas.pop(name, None)
            self.cpu_datas.pop(name, None)
            self.cpu_smoothed.pop(name, None)
            for pid in self.tracked_pids.pop(name, set()):
                self.last_cpu_time.pop(pid, None)
                self.process_cache.pop(pid, None)

        active_parent_pids = set(pids.values())
        for pid in list(self.last_wall):
            if pid not in active_parent_pids:
                self.last_wall.pop(pid, None)

    def _shouldTrackChildren(self, name: str) -> bool:
        return name.startswith('lyric-video-')

    def _trackedProcesses(self, name: str, pid: int) -> list[psutil.Process]:
        if not self.process_cache.get(pid):
            self.process_cache[pid] = psutil.Process(pid)
        process = self.process_cache[pid]
        if not self._shouldTrackChildren(name):
            return [process]
        return [process, *process.children(recursive=True)]

    def _updateTrackedPids(self, name: str, processes: list[psutil.Process]) -> None:
        pids = {process.pid for process in processes}
        for pid in self.tracked_pids.get(name, set()) - pids:
            self.last_cpu_time.pop(pid, None)
            self.process_cache.pop(pid, None)
        self.tracked_pids[name] = pids

    def updateMemories(self, pids: dict[str, int]) -> None:
        if not self.ctx.debugging:
            return
        
        for name, pid in pids.items():
            if not self.mem_datas.get(name):
                self.mem_datas[name] = deque(maxlen=200)
            try:
                processes = self._trackedProcesses(name, pid)
                rss = sum(
                    process.memory_info().rss
                    for process in processes
                )
                self.mem_datas[name].append(rss)
            except psutil.Error:
                continue

        max_v = 0
        for _, lst in self.mem_datas.items():
            for v in lst:
                max_v = max(max_v, v)
        self.mmax_value.target_value = max_v

    def updateCpus(self, pids: dict[str, int]) -> None:
        if not self.ctx.debugging:
            return
        
        for name, pid in pids.items():
            if not self.cpu_datas.get(name):
                self.cpu_datas[name] = deque(maxlen=200)
                self.cpu_smoothed[name] = deque(maxlen=20)
            try:
                processes = self._trackedProcesses(name, pid)
                self._updateTrackedPids(name, processes)
                cpu_delta = 0.0
                for process in processes:
                    times = process.cpu_times()
                    cpu_time = times.user + times.system
                    last_cpu_time = self.last_cpu_time.get(process.pid)
                    if last_cpu_time is not None:
                        cpu_delta += max(0.0, cpu_time - last_cpu_time)
                    self.last_cpu_time[process.pid] = cpu_time
            except psutil.Error:
                continue
            now = time.perf_counter()
            elapsed = max(now - self.last_wall.get(pid, 0.0), 0.001)
            cpu_percent = cpu_delta / elapsed / self.cpu_cores * 100
            self.cpu_smoothed[name].append(cpu_percent)
            self.cpu_datas[name].append(sum(self.cpu_smoothed[name]) / len(self.cpu_smoothed[name]))
            self.last_wall[pid] = now

        max_v = 0
        for _, lst in self.cpu_datas.items():
            for v in lst:
                max_v = max(max_v, v)
        self.cmax_value.target_value = max_v

    def wheelEvent(self, event: QWheelEvent) -> None:
        self.offset_timer.target_value += event.angleDelta().y()
        return super().wheelEvent(event)

    def refresh(self, _multiple_factor: float = 1.0, raise_overlay: bool = False) -> None:
        self.setVisible(self.ctx.debugging)
        if self.ctx.debugging:
            if raise_overlay:
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
        try:
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.translate(0, 50 + self.offset_timer.current_value)

            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(
                QColor(255, 255, 255, 100)
                if theme.isLight()
                else QColor(0, 0, 0, 100)
            )

            y = 0
            mem_rect = QRect(5, y - 215, self.width() - 10, 200)
            cpu_rect = QRect(5, y - 430, self.width() - 10, 200)

            painter.drawRect(
                0,
                -int(self.offset_timer.current_value) - 50,
                self.width(),
                self.height(),
            )
            painter.drawRect(mem_rect) # make the
            painter.drawRect(mem_rect) # color darker
            painter.drawRect(cpu_rect) # make the
            painter.drawRect(cpu_rect) # color darker

            painter.setPen(
                QPen(
                    QColor(255, 255, 255) if theme.isDark() else QColor(0, 0, 0),
                    1,
                )
            )
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.setFont(self.content_ft)

            mem_max = self.mmax_value.current_value * 1.1
            if mem_max > 0:
                painter.save()
                painter.setClipRect(mem_rect)
                for name, values in self.mem_datas.items():
                    path = QPainterPath()
                    if not values:
                        continue
                    path.moveTo(5, values[0] / mem_max * -200 + y - 15)
                    for i, v in enumerate(values):
                        x = 5 + (self.width() - 10) * (i / 200)
                        y_ = v / mem_max * -200 - 15
                        path.lineTo(x, y_)
                    txt = f'{name} - {(values[-1] / 1024/ 1024):.2f} MB'
                    painter.drawText(
                        int(
                            max(
                                0,
                                x - self.content_metri.horizontalAdvance(txt) - 5,
                            )
                        ),
                        int(y_ - 5),
                        txt,
                    )
                    painter.drawPath(path)
                painter.restore()

            cpu_max = self.cmax_value.current_value
            if cpu_max > 0:
                painter.save()
                painter.setClipRect(cpu_rect)
                for name, values in self.cpu_datas.items():
                    path = QPainterPath()
                    if not values:
                        continue
                    path.moveTo(5, values[0] / cpu_max * -200 + y - 230)
                    for i, v in enumerate(values):
                        x = 5 + (self.width() - 10) * (i / 200)
                        y_ = v / cpu_max * -200 - 230
                        path.lineTo(x, y_)
                    txt = f'{name} - {(values[-1]):.2f}%'
                    painter.drawText(
                        int(
                            max(
                                0,
                                x - self.content_metri.horizontalAdvance(txt) - 5,
                            )
                        ),
                        int(y_ - 5),
                        txt,
                    )
                    painter.drawPath(path)
                painter.restore()

            y += 10
            export_info = lyricVideoExportDebugInfo()
            if export_info:
                painter.setFont(self.title_ft)
                painter.drawText(10, y, 'Lyric Video Export')
                y += self.title_height + 10
                painter.setFont(self.content_ft)
                for line in export_info:
                    painter.drawText(20, y, line)
                    y += self.content_height + 1

            for info in self.ctx.debugging_obj.infos:
                name, lines = next(iter(info.items()))
                painter.setFont(self.title_ft)
                painter.drawText(10, y, name)
                y += self.title_height + 10
                painter.setFont(self.content_ft)
                for line in lines:
                    painter.drawText(20, y, line)
                    y += self.content_height + 1
        finally:
            painter.end()
