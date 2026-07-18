from __future__ import annotations

import math

from typing import override

from imports import (
    QResizeEvent,
    QSizePolicy,
    QTextCursor,
    QTextOption,
    QTimer,
    Qt,
    QVBoxLayout,
    Signal,
    QWidget,
)
from qfluentwidgets import TextBrowser


class ChattingViewer(QWidget):
    finished = Signal()
    charReceived = Signal(int)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._markdown = ''
        self._append_buffer = ''
        self._stream_finished = False

        self._append_timer = QTimer(self)
        self._append_timer.setSingleShot(True)
        self._append_timer.timeout.connect(self._drainAppendBuffer)

        self.browser = TextBrowser(self)
        self.browser.setReadOnly(True)
        self.browser.setOpenExternalLinks(True)
        self.browser.setLineWrapMode(TextBrowser.LineWrapMode.WidgetWidth)
        self.browser.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.browser.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.browser.setSizePolicy(
            QSizePolicy.Policy.Expanding,
            QSizePolicy.Policy.Fixed,
        )
        self.browser.setStyleSheet(
            'background: transparent; border: none; padding: 0px; font-size: 15px;'
        )

        text_option = self.browser.document().defaultTextOption()
        text_option.setWrapMode(QTextOption.WrapMode.WrapAnywhere)
        self.browser.document().setDefaultTextOption(text_option)
        self.browser.document().setDocumentMargin(4)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.browser)

    def reset(self) -> None:
        self._append_timer.stop()
        self._markdown = ''
        self._append_buffer = ''
        self._stream_finished = False
        self.browser.clear()
        self._fitDocument()

    def appendChunk(self, chunk_content: str) -> None:
        if not chunk_content:
            return
        self._stream_finished = False
        self._append_buffer += chunk_content
        if not self._append_timer.isActive():
            self._append_timer.start(0)

    def finishStream(self) -> None:
        self._stream_finished = True
        self._append_timer.stop()
        self._consumeAppendBuffer(len(self._append_buffer))
        self._renderMarkdown()
        self._stream_finished = False
        self.finished.emit()

    def _drainAppendBuffer(self) -> None:
        if self._append_buffer:
            take = max(1, (len(self._append_buffer) + 7) // 8)
            self._consumeAppendBuffer(take)
            self._renderMarkdown()

        if self._append_buffer:
            self._append_timer.start(16)
        elif self._stream_finished:
            self._stream_finished = False
            self.finished.emit()

    def _consumeAppendBuffer(self, length: int) -> None:
        if length <= 0:
            return
        chunk = self._append_buffer[:length]
        self._append_buffer = self._append_buffer[length:]
        self._markdown += chunk
        self.charReceived.emit(len(chunk))

    def _renderMarkdown(self) -> None:
        self.browser.setMarkdown(self._markdown)
        text_option = self.browser.document().defaultTextOption()
        text_option.setWrapMode(QTextOption.WrapMode.WrapAnywhere)
        self.browser.document().setDefaultTextOption(text_option)
        self._enableCodeBlockWrapping()
        self._fitDocument()

    def _enableCodeBlockWrapping(self) -> None:
        block = self.browser.document().begin()
        while block.isValid():
            block_format = block.blockFormat()
            if block_format.nonBreakableLines():
                block_format.setNonBreakableLines(False)
                cursor = QTextCursor(block)
                cursor.setBlockFormat(block_format)
            block = block.next()

    def _fitDocument(self) -> None:
        content_width = max(120, self.width())
        self.browser.setFixedWidth(content_width)
        viewport_width = max(80, self.browser.viewport().width())
        document = self.browser.document()
        document.setTextWidth(viewport_width)
        height = math.ceil(document.size().height())
        height += self.browser.frameWidth() * 2 + 4
        self.browser.setFixedHeight(max(24, height))
        self.updateGeometry()

    @override
    def resizeEvent(self, event: QResizeEvent) -> None:
        super().resizeEvent(event)
        self._fitDocument()
