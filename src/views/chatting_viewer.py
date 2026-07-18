from __future__ import annotations

import math
import logging
import re
from html import escape

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
from markdown_it import MarkdownIt


_MATH_PATTERN = re.compile(r'(?s)(\$\$.*?\$\$|(?<!\\)\$[^$\n]+(?<!\\)\$)')
_MARKDOWN = MarkdownIt('commonmark', {'html': False, 'breaks': True}).enable(
    ['table', 'strikethrough']
)
logging.getLogger('markdown_it').setLevel(logging.WARNING)


def renderMarkdown(markdown: str) -> str:
    """Render chat Markdown with tables, fenced code, links, and readable math."""
    parts: list[str] = []
    offset = 0
    for match in _MATH_PATTERN.finditer(markdown):
        parts.append(_MARKDOWN.render(markdown[offset : match.start()]))
        formula = match.group(0).strip('$').strip()
        parts.append(
            '<div class="math-block">'
            if match.group(0).startswith('$$')
            else '<span class="math-inline">'
        )
        parts.append(escape(formula))
        parts.append('</div>' if match.group(0).startswith('$$') else '</span>')
        offset = match.end()
    parts.append(_MARKDOWN.render(markdown[offset:]))
    return ''.join(parts)


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
        self.browser.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
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
            self._append_timer.start(80)

    def finishStream(self) -> None:
        self._stream_finished = True
        self._append_timer.stop()
        self._consumeAppendBuffer(len(self._append_buffer))
        self._renderMarkdown()
        self._stream_finished = False
        self.finished.emit()

    def _drainAppendBuffer(self) -> None:
        if self._append_buffer:
            self._consumeAppendBuffer(len(self._append_buffer))
            self._renderMarkdown()

        if self._stream_finished:
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
        self.browser.setHtml(
            '<style>'
            'body{color:inherit;}'
            'pre{white-space:pre-wrap; word-wrap:break-word; background:rgba(128,128,128,.16); padding:8px; border-radius:4px;}'
            'code{font-family:monospace;}'
            'table{border-collapse:collapse;} th,td{border:1px solid #666; padding:4px 8px;}'
            '.math-inline,.math-block{font-family:serif; color:inherit;}'
            '.math-block{margin:8px 0; text-align:center;}'
            '</style>' + renderMarkdown(self._markdown)
        )
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
