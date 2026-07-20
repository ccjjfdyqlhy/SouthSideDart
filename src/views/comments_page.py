import logging
import os
from typing import TYPE_CHECKING

import requests

from core.backend import getBackend
from imports import (
    AvatarWidget,
    CaptionLabel,
    FluentIcon,
    InfoBar,
    Path,
    PrimaryPushButton,
    PrimaryToolButton,
    QHBoxLayout,
    QPixmap,
    QSizePolicy,
    QSpacerItem,
    QVBoxLayout,
    QWidget,
    Qt,
    TextEdit,
    TitleLabel,
    bindText,
)
from views.list_widget import SScrollArea
from views.translation_handler import TranslationHandler
from core.i18n import tr


if TYPE_CHECKING:
    from core.app_context import AppContext


class CommentsPage(SScrollArea):
    def __init__(self, ctx: AppContext):
        super().__init__()
        self._logger = logging.getLogger(__name__)
        self.ctx = ctx

        widget = QWidget()
        layout = QVBoxLayout()
        widget.setLayout(layout)

        title_label = TitleLabel('')
        bindText(title_label, 'comments_page.title')
        layout.addWidget(title_label)

        top_layout = QHBoxLayout()
        self.avatar_widget = AvatarWidget(
            str(Path('./images/def_avatar.png').resolve())
        )
        top_layout.addWidget(self.avatar_widget)
        self.inputer = TextEdit()
        self.inputer.textChanged.connect(self.recalculatePayload)
        topright_layout = QVBoxLayout()
        topright_layout.addWidget(self.inputer)
        self.send_button = PrimaryToolButton(FluentIcon.SEND)
        toprightbottom_layout = QHBoxLayout()
        toprightbottom_layout.addSpacerItem(
            QSpacerItem(0, 0, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Ignored)
        )
        self.remain_label = CaptionLabel('140')
        toprightbottom_layout.addWidget(self.remain_label)
        toprightbottom_layout.addWidget(self.send_button)
        topright_layout.addLayout(toprightbottom_layout)
        self.send_button.clicked.connect(self.send)
        top_layout.addLayout(topright_layout)
        place_handler = TranslationHandler()
        bindText(place_handler, 'comments_page.say_sth')
        place_handler.textChanged.connect(lambda t: self.inputer.setPlaceholderText(t))
        self.inputer.setPlaceholderText(tr('comments_page.say_sth'))
        layout.addLayout(top_layout)

        self.setWidget(widget)
        self.setWidgetResizable(True)

    def _getTextPayload(self, text: str) -> int:
        units = sum(2 if '\u4e00' <= char <= '\u9fff' else 1 for char in text)
        return (units + 1) // 2

    def recalculatePayload(self):
        text = self.inputer.toPlainText()
        payload = self._getTextPayload(text)
        self.remain_label.setText(str(int(140 - payload)))
        self.send_button.setEnabled(payload <= 140)

    def loadComments(self):
        current = self.ctx.playing_manager.current_song
        if current is None:
            return

    def send(self):
        backend = getBackend()
        if not backend.getAccountInfo().logged_in:
            InfoBar.warning('Error', 'You\' not logged in!', duration=3500, parent=self.ctx.main_window)
            return
        
        current = self.ctx.playing_manager.current_song
        if not current:
            return
        backend.addComment(current.id, self.inputer.toPlainText())
        self.inputer.clear()

        InfoBar.success('Success', 'Added a comment successfully', duration=3500, parent=self.ctx.main_window)

    def refreshInformations(self):
        if os.path.exists('images/avatar.png'):
            os.remove('images/avatar.png')

        backend = getBackend()
        account = None

        try:
            account = backend.getAccountInfo()
            if account.avatar_url:
                self._logger.debug(f'{account.avatar_url=}')
                avatar_url = account.avatar_url
                avatar_data = requests.get(avatar_url).content
                with open('images/avatar.png', 'wb') as f:
                    f.write(avatar_data)
        except Exception as e:
            self._logger.warning(f'Failed to fetch user detail or avatar: {e}')

        nickname = 'Anonymous User'
        if account is not None and account.nickname.strip():
            nickname = account.nickname.strip()
        self._nickname = nickname

        if not os.path.exists('images/avatar.png'):
            pixmap = QPixmap('./images/def_avatar.png')
        else:
            pixmap = QPixmap('./images/avatar.png')
        if not pixmap.isNull():
            self.avatar_widget.setPixmap(pixmap)
