from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import logging
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import tempfile
import threading
import time
from typing import Callable
from urllib.request import Request, urlopen

from PySide6.QtCore import QLocale, QTimer, Qt, Signal
from PySide6.QtWidgets import (
    QApplication,
    QLabel,
    QProgressBar,
    QVBoxLayout,
    QWidget,
)

SCRIPT_DIR = Path(__file__).resolve().parent
PYTHON_EXE = SCRIPT_DIR / 'python' / 'python.exe'
FREE_THREADED_PYTHON_EXE = SCRIPT_DIR / 'freethreaded_python' / 'python.exe'
FULL_REQUIREMENTS = SCRIPT_DIR / 'full_requirements.txt'
MAIN_SCRIPT = SCRIPT_DIR / 'src' / 'main.py'
SITE_PACKAGES = PYTHON_EXE.parent / 'Lib' / 'site-packages'
DATA_DIR = SCRIPT_DIR / 'data'
PIP_CACHE_DIR = DATA_DIR / 'pip-cache'
PIP_WHEELHOUSE = DATA_DIR / 'pip-wheels'

PYSIDE_REQUIREMENT_NAMES = {
    'pyside6',
    'pyside6-addons',
    'pyside6-essentials',
    'shiboken6',
}
PYSIDE_REQUIRED_FILES = [
    Path('PySide6') / 'Qt6WebEngineCore.dll',
    Path('PySide6') / 'Qt6WebEngineWidgets.dll',
    Path('PySide6') / 'QtWebEngineCore.pyd',
    Path('PySide6') / 'QtWebEngineWidgets.pyd',
    Path('PySide6') / 'QtWebEngineProcess.exe',
    Path('PySide6') / 'resources' / 'qtwebengine_resources.pak',
]
MAX_WHEEL_DOWNLOAD_WORKERS = 8
PIP_RETRIES = '2'
PIP_TIMEOUT = '20'
MIRROR_LATENCY_TIMEOUT = 3
FREE_THREADED_REQUIREMENT_NAMES = [
    'numpy',
    'scipy',
    'pillow',
    'pydub',
    'audioop-lts',
]
FREE_THREADED_IMPORT_CHECKS = {
    'audioop-lts': 'audioop',
    'numpy': 'numpy',
    'pillow': 'PIL',
    'pydub': 'pydub',
    'scipy': 'scipy',
}
PIP_SIZE_RE = re.compile(r'\((?P<size>\d+(?:\.\d+)?)\s*(?P<unit>bytes?|kB|KB|MB|GB)\)')
PIP_SIZE_UNITS = {
    'byte': 1,
    'bytes': 1,
    'kb': 1000,
    'mb': 1000 * 1000,
    'gb': 1000 * 1000 * 1000,
}

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%H:%M:%S',
    handlers=[logging.StreamHandler()],
)
_logger = logging.getLogger('bootstrap')

MIRRORS: dict[str, str] = {
    'PyPI': 'https://pypi.org/simple/',
    'Tsinghua': 'https://pypi.tuna.tsinghua.edu.cn/simple/',
    'Aliyun': 'https://mirrors.aliyun.com/pypi/simple/',
    'Tencent': 'https://mirrors.cloud.tencent.com/pypi/simple/',
    'USTC': 'https://pypi.mirrors.ustc.edu.cn/simple/',
    'Huawei': 'https://repo.huaweicloud.com/repository/pypi/simple/',
}


def runMain() -> None:
    bwindow.hide()

    _logger.debug('spawning main: %s %s', PYTHON_EXE, MAIN_SCRIPT)
    proc = subprocess.Popen(
        [str(PYTHON_EXE), str(MAIN_SCRIPT)],
        cwd=str(SCRIPT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )
    if not proc.stdout:
        app.quit()
        return
    for line in proc.stdout:
        print(line.strip())
    proc.wait()
    if proc.returncode != 0:
        _logger.error('main.py exited with code %d', proc.returncode)
    app.quit()


class RequirementInfo:
    def __init__(self, name: str, version: str = '') -> None:
        self.name = name
        self.version = version

    name: str
    version: str


def getRequirements() -> list[RequirementInfo]:
    result = []
    for line in FULL_REQUIREMENTS.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if '==' not in line:
            continue
        name, version = line.split('==', 1)
        result.append(RequirementInfo(name=name, version=version))
    return result


def getFreeThreadedRequirements() -> list[RequirementInfo]:
    return [RequirementInfo(name=name) for name in FREE_THREADED_REQUIREMENT_NAMES]


def getTableRequirements() -> list[RequirementInfo]:
    result = getRequirements()
    existing = {normalizePackageName(requirement.name) for requirement in result}
    for requirement in getFreeThreadedRequirements():
        normalized = normalizePackageName(requirement.name)
        if normalized not in existing:
            result.append(requirement)
            existing.add(normalized)
    return result


def normalizePackageName(name: str) -> str:
    return re.sub(r'[-_.]+', '-', name).lower()


def getRequirementSpec(requirement: RequirementInfo) -> str:
    if not requirement.version:
        return requirement.name
    return f'{requirement.name}=={requirement.version}'


def ensurePipCacheDirs() -> None:
    PIP_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    PIP_WHEELHOUSE.mkdir(parents=True, exist_ok=True)


def getRuntimeWheelhouse(python_exe: Path) -> Path:
    return PIP_WHEELHOUSE / normalizePackageName(python_exe.parent.name)


def getPipEnv(env: dict[str, str] | None = None) -> dict[str, str]:
    result = os.environ.copy() if env is None else env.copy()
    result.setdefault('PIP_DISABLE_PIP_VERSION_CHECK', '1')
    result.setdefault('PIP_NO_INPUT', '1')
    result.setdefault('PIP_CACHE_DIR', str(PIP_CACHE_DIR))
    result.setdefault('PIP_DEFAULT_TIMEOUT', PIP_TIMEOUT)
    return result


def findCachedWheel(requirement: RequirementInfo, wheelhouse: Path) -> Path | None:
    normalized_name = normalizePackageName(requirement.name)
    for wheel in wheelhouse.glob('*.whl'):
        parts = wheel.name.split('-')
        if len(parts) < 2:
            continue
        if normalizePackageName(parts[0]) != normalized_name:
            continue
        if requirement.version and parts[1] != requirement.version:
            continue
        return wheel
    return None


def parsePipDownloadSize(line: str) -> int | None:
    match = PIP_SIZE_RE.search(line)
    if match is None:
        return None
    unit = match.group('unit').lower()
    multiplier = PIP_SIZE_UNITS.get(unit)
    if multiplier is None:
        return None
    return int(float(match.group('size')) * multiplier)


def getInstalledPackages(
    python_exe: Path = PYTHON_EXE,
    env: dict[str, str] | None = None,
) -> list[RequirementInfo]:
    result = []
    completed = subprocess.run(
        [str(python_exe), '-m', 'pip', 'list', '--format', 'json'],
        cwd=str(SCRIPT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
        env=getPipEnv(env),
    )
    if completed.returncode != 0:
        _logger.warning(
            'pip list failed for %s: %s',
            python_exe,
            completed.stdout.strip(),
        )
        return result
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        _logger.warning('pip list returned invalid JSON for %s', python_exe)
        return result
    for data in parsed:
        if normalizePackageName(data['name']) == 'pip':
            continue
        result.append(RequirementInfo(name=data['name'], version=data['version']))
    return result


def getUnsatisfiedRequirements(
    installed: list[RequirementInfo], required: list[RequirementInfo]
) -> list[RequirementInfo]:
    installed_versions = {
        normalizePackageName(requirement.name): requirement.version
        for requirement in installed
    }
    return [
        requirement
        for requirement in required
        if (
            installed_versions.get(normalizePackageName(requirement.name))
            != requirement.version
            if requirement.version
            else normalizePackageName(requirement.name) not in installed_versions
        )
    ]


def mergeRequirements(requirements: list[RequirementInfo]) -> list[RequirementInfo]:
    result: list[RequirementInfo] = []
    seen: set[str] = set()
    for requirement in requirements:
        normalized = normalizePackageName(requirement.name)
        if normalized in seen:
            continue
        result.append(requirement)
        seen.add(normalized)
    return result


def getMissingImports(
    python_exe: Path,
    required: list[RequirementInfo],
    import_checks: dict[str, str],
    env: dict[str, str] | None = None,
) -> list[RequirementInfo]:
    missing: list[RequirementInfo] = []
    for requirement in required:
        module_name = import_checks.get(normalizePackageName(requirement.name))
        if module_name is None:
            continue
        completed = subprocess.run(
            [str(python_exe), '-c', f'import {module_name}'],
            cwd=str(SCRIPT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        if completed.returncode != 0:
            _logger.warning(
                '%s import failed in %s: %s',
                module_name,
                python_exe,
                completed.stdout.strip(),
            )
            missing.append(requirement)
    return missing


def getPySideRequirements(required: list[RequirementInfo]) -> list[RequirementInfo]:
    return [
        requirement
        for requirement in required
        if normalizePackageName(requirement.name) in PYSIDE_REQUIREMENT_NAMES
    ]


def isFullPySideInstalled(site_packages: Path = SITE_PACKAGES) -> bool:
    return all((site_packages / path).exists() for path in PYSIDE_REQUIRED_FILES)


def getFreeThreadedEnv() -> dict[str, str]:
    env = os.environ.copy()
    env['PYTHON_GIL'] = '0'
    return env


def isFreeThreadedPython(python_exe: Path) -> bool:
    if not python_exe.is_file():
        return False
    try:
        completed = subprocess.run(
            [
                str(python_exe),
                '-c',
                (
                    'import sys, sysconfig; '
                    'print(int(not getattr(sys, "_is_gil_enabled", lambda: True)())); '
                    'print(sysconfig.get_config_var("Py_GIL_DISABLED"))'
                ),
            ],
            cwd=str(SCRIPT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=5,
            env=getFreeThreadedEnv(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if completed.returncode != 0:
        return False
    values = [line.strip() for line in completed.stdout.splitlines()]
    return values[:2] == ['1', '1']


class BootstrapWindow(QWidget):
    latencyFinished = Signal(str, str, float)
    allDone = Signal()

    task = Signal(object)
    progressChanged = Signal(int, str)

    def __init__(self):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.Dialog | Qt.WindowType.NoTitleBarBackgroundHint
        )
        locale_name = QLocale.system().name().lower()
        self._language = 'zh' if locale_name in {'zh_cn', 'zh_hans_cn'} else 'en'
        self._text_map = {
            'en': {
                'title': 'Setting up Environment',
                'initial_status': 'Preparing dependency environment...',
                'initial_tip': 'Tip: SouthsideMusic will start automatically when setup finishes.',
                'tips': [
                    'Tips: Lyrics, cover art, and playback state are cached for faster startup next time.',
                    "Tips: FFMpeg only needs to be prepared once; it won't be re-downloaded on later launches.",
                    'Tips: Multiple wheels are downloaded in parallel; this part goes by quickly.',
                    'Tips: SouthsideMusic was originally called LyricsStudio.',
                    'Tips: Follow my Bilibili account! @Adreno9135',
                    'Tips: SouthsideMusic is developed by just one person.',
                    'Tips: Loudness normalization helps different songs feel closer in volume.',
                    'Tips: The spectrum view gives the music a little visual shadow.',
                    'Tips: You can edit lyrics, translate them, and export lyric videos.',
                    'Tips: Crossfade tries to make the space between two songs less abrupt.',
                    'Tips: The library remembers your collection, sorting, and play counts.',
                    'Tips: Onerad asks for confirmation before performing actions in the app.',
                    'Tips: Private roaming and similar songs are there for moments when search is empty.',
                    'Tips: Cache cleanup protects core data and prefers removing less-used files first.',
                ],
                'mirror': 'Using {mirror} mirror ({latency} ms). Installing dependencies...',
                'checking': 'Environment check complete. Preparing dependencies from {mirror}...',
                'starting': 'Dependencies installed. Starting SouthsideMusic...',
                'download_stage': 'Downloading wheels ({workers} parallel tasks)...',
                'download': 'Downloading {package} ({percent}%)...',
                'downloaded': 'Downloaded {package} ({current}/{total})',
                'cached': 'Using cached wheel {package} ({current}/{total})',
                'finalizing': 'Downloads complete. Finalizing dependencies; finishing up...',
                'checking_install': 'Installation complete. Running a final check...',
                'installing': 'Installing dependencies; finishing up...',
                'runtime_install': 'Installing {runtime} requirements...',
            },
            'zh': {
                'title': '设置环境',
                'initial_status': '正在准备依赖环境…',
                'initial_tip': 'Tips: SouthsideMusic 准备完成后会自动启动。',
                'tips': [
                    'Tips: 歌词、封面和播放状态会缓存，下次启动会更快。',
                    'Tips: FFMpeg 只需首次准备，之后启动不用重新下载。',
                    'Tips: 多个 wheel 会并行下载，这一段很快就好。',
                    'Tips: SouthsideMusic 最开始的名字叫 LyricsStudio',
                    'Tips: 关注我的 Bilibili 账号！@Adreno9135',
                    'Tips: SouthsideMusic 的开发者只有一个人。',
                    'Tips: 响度均衡可以让不同歌曲听起来更接近同一个音量。',
                    'Tips: 频谱让声音多了一点可以看见的影子。',
                    'Tips: 你可以编辑歌词、翻译歌词，还能导出歌词视频。',
                    'Tips: 交叉淡化会尽量把两首歌之间生硬的缝隙磨平。',
                    'Tips: 库页面会记住你的收藏、排序方式和播放次数。',
                    'Tips: Onerad 在执行应用内操作前，会先停下来等待确认。',
                    'Tips: 不知道听什么时，可以试试私人漫游和相似歌曲。',
                    'Tips: 缓存清理会保护核心数据，并优先回收较少使用的文件。',
                ],
                'mirror': '正在使用 {mirror} 镜像（{latency} 毫秒），开始安装依赖…',
                'checking': '环境检查完成，正在从 {mirror} 准备依赖…',
                'starting': '依赖安装完成，正在启动 SouthsideMusic…',
                'download_stage': '正在并行下载 wheel（{workers} 路）…',
                'download': '正在下载 {package}（{percent}%）…',
                'downloaded': '已下载 {package}（{current}/{total}）',
                'cached': '使用缓存 wheel {package}（{current}/{total}）',
                'finalizing': '下载完成，正在整理依赖；马上就好…',
                'checking_install': '安装完成，正在做最后检查…',
                'installing': '正在安装依赖，最后整理一下…',
                'runtime_install': '正在安装 {runtime} 依赖…',
            },
        }
        self._tips = self._text_map[self._language]['tips']
        self._tip_index = 0
        self._tip_text = self._tips[0]
        self._tip_phase = 'hold'
        self._tip_timer = QTimer(self)
        self._tip_timer.timeout.connect(self._animateTip)

        self.setWindowTitle(self._text('title'))
        self.setFixedWidth(int(app.primaryScreen().size().width() * 0.3))

        self._layout = QVBoxLayout()
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        self.progress_bar.setTextVisible(True)
        self.status_label = QLabel(self._text('initial_status'))
        self.status_label.setWordWrap(True)
        self.tip_label = QLabel(self._text('initial_tip'))
        self.tip_label.setWordWrap(True)
        self.tip_label.setStyleSheet('color: #888888; font-size: 9pt;')
        self._layout.addWidget(self.progress_bar)
        self._layout.addWidget(self.status_label)
        self._layout.addWidget(self.tip_label)
        self.setLayout(self._layout)
        self._scheduleTipHold()

        self._download_total = 0
        self._download_completed = 0
        self._download_progress: dict[str, int] = {}
        self._download_progress_lock = threading.Lock()

        self.latency_test_threads = []
        self.latency_testing = False
        self.latency_lock = threading.Lock()
        self.latencyFinished.connect(self.latencyTestFinished)
        self.progressChanged.connect(self.updateProgressUi)

        self.task.connect(self.doTask)

        self.show()

    def _text(self, key: str, **kwargs: object) -> str:
        return self._text_map[self._language][key].format(**kwargs)  # type: ignore

    def _scheduleTipHold(self) -> None:
        self._tip_phase = 'hold'
        self._tip_timer.setSingleShot(True)
        self._tip_timer.start(random.randint(2000, 2500))

    def _beginTipErase(self) -> None:
        self._tip_phase = 'erase'
        self._tip_timer.setSingleShot(False)
        self._tip_timer.start(25)

    def _animateTip(self) -> None:
        if self._tip_phase == 'hold':
            self._beginTipErase()
            return
        if self._tip_phase == 'erase':
            self._tip_text = self._tip_text[:-1]
            self.tip_label.setText(self._tip_text)
            if not self._tip_text:
                self._tip_index = (self._tip_index + 1) % len(self._tips)
                self._tip_text = ''
                self._tip_phase = 'write'
        else:
            next_tip = self._tips[self._tip_index]
            self._tip_text += next_tip[len(self._tip_text)]
            self.tip_label.setText(self._tip_text)
            if self._tip_text == next_tip:
                self._scheduleTipHold()

    def doTask(self, content: object):
        if isinstance(content, Callable):
            content()

    def latencyTestFinished(self, mirror_name: str, mirror_url: str, latency: float):
        _logger.info(f'latency test finished: {mirror_name} {mirror_url} {latency}s')

        self.progressChanged.emit(
            10,
            self._text('checking', mirror=mirror_name),
        )
        threading.Thread(
            target=self.installRequirements, args=(mirror_name, mirror_url, latency)
        ).start()

    def installRequirements(self, mirror_name: str, mirror_url: str, latency: float):
        self.updateStatusText(
            self._text('mirror', mirror=mirror_name, latency=int(latency * 1000))
        )
        self.installRuntimeRequirements(
            'GIL Python',
            PYTHON_EXE,
            getRequirements(),
            mirror_url,
            site_packages=SITE_PACKAGES,
            reinstall_pyside=True,
        )
        self.installFreeThreadedRequirements(mirror_url)
        self.progressChanged.emit(
            100,
            self._text('starting'),
        )
        self.allDone.emit()

    def installFreeThreadedRequirements(self, mirror_url: str) -> None:
        if not FREE_THREADED_PYTHON_EXE.exists():
            _logger.warning(
                'free-threaded Python not found: %s', FREE_THREADED_PYTHON_EXE
            )
            return
        if not isFreeThreadedPython(FREE_THREADED_PYTHON_EXE):
            _logger.warning(
                'free-threaded Python failed validation: %s',
                FREE_THREADED_PYTHON_EXE,
            )
            return

        self.installRuntimeRequirements(
            'no-GIL Python',
            FREE_THREADED_PYTHON_EXE,
            getFreeThreadedRequirements(),
            mirror_url,
            env=getFreeThreadedEnv(),
            import_checks=FREE_THREADED_IMPORT_CHECKS,
        )

    def installRuntimeRequirements(
        self,
        runtime_name: str,
        python_exe: Path,
        required: list[RequirementInfo],
        mirror_url: str,
        *,
        site_packages: Path | None = None,
        reinstall_pyside: bool = False,
        install_args: list[str] | None = None,
        env: dict[str, str] | None = None,
        import_checks: dict[str, str] | None = None,
    ) -> None:
        self.updateStatusText(self._text('runtime_install', runtime=runtime_name))
        installed = getInstalledPackages(python_exe, env=env)
        unsatisfied = getUnsatisfiedRequirements(installed, required)
        if import_checks is not None:
            unsatisfied = mergeRequirements(
                unsatisfied
                + getMissingImports(python_exe, required, import_checks, env=env)
            )
        pyside_incomplete = (
            reinstall_pyside
            and site_packages is not None
            and not isFullPySideInstalled(site_packages)
        )
        if not unsatisfied and not pyside_incomplete:
            return

        installed_versions = {
            normalizePackageName(requirement.name): requirement.version
            for requirement in installed
        }
        for requirement in required:
            installed_version = installed_versions.get(
                normalizePackageName(requirement.name)
            )
            if (
                installed_version == requirement.version
                if requirement.version
                else installed_version is not None
            ):
                self.updateStatus(requirement.name, 'Installed')
            else:
                self.updateStatus(requirement.name, 'Waiting')

        if unsatisfied:
            returncode = self.runFastPipInstall(
                python_exe,
                mirror_url,
                unsatisfied,
                install_args
                if install_args is not None
                else [getRequirementSpec(requirement) for requirement in unsatisfied],
                env=env,
            )
            if returncode == 0:
                for requirement in required:
                    self.updateStatus(requirement.name, 'Installed')

        if pyside_incomplete:
            pyside_requirements = getPySideRequirements(required)
            for requirement in pyside_requirements:
                self.updateStatus(requirement.name, 'Uninstalling')
            self.runPipUninstall(
                python_exe,
                [requirement.name for requirement in pyside_requirements],
                env=env,
            )
            for requirement in pyside_requirements:
                self.updateStatus(requirement.name, 'Uninstalled')
            returncode = self.runFastPipInstall(
                python_exe,
                mirror_url,
                pyside_requirements,
                [
                    getRequirementSpec(requirement)
                    for requirement in pyside_requirements
                ],
                env=env,
            )
            if returncode == 0:
                for requirement in pyside_requirements:
                    self.updateStatus(requirement.name, 'Installed')

    def runFastPipInstall(
        self,
        python_exe: Path,
        mirror_url: str,
        download_requirements: list[RequirementInfo],
        install_args: list[str],
        env: dict[str, str] | None = None,
    ) -> int:
        ensurePipCacheDirs()
        if not download_requirements:
            return self.runPipInstall(python_exe, mirror_url, install_args, env=env)

        wheelhouse = getRuntimeWheelhouse(python_exe)
        wheelhouse.mkdir(parents=True, exist_ok=True)
        failed = self.downloadRequirementWheels(
            python_exe, mirror_url, download_requirements, wheelhouse, env=env
        )
        has_wheels = any(wheelhouse.glob('*.whl'))
        if failed:
            _logger.warning(
                'wheel predownload failed for: %s',
                ', '.join(getRequirementSpec(requirement) for requirement in failed),
            )
        returncode = self.runPipInstall(
            python_exe,
            mirror_url,
            install_args,
            wheelhouse=wheelhouse if has_wheels else None,
            no_index=has_wheels and not failed,
            env=env,
        )
        if returncode != 0 and has_wheels and not failed:
            _logger.warning('offline wheel install failed, retrying with index')
            return self.runPipInstall(
                python_exe,
                mirror_url,
                install_args,
                wheelhouse=wheelhouse,
                no_index=False,
                env=env,
            )
        return returncode

    def downloadRequirementWheels(
        self,
        python_exe: Path,
        mirror_url: str,
        requirements: list[RequirementInfo],
        wheelhouse: Path,
        env: dict[str, str] | None = None,
    ) -> list[RequirementInfo]:
        workers = min(MAX_WHEEL_DOWNLOAD_WORKERS, len(requirements))
        self.updateStatusText(self._text('download_stage', workers=workers))
        wheelhouse.mkdir(parents=True, exist_ok=True)
        copy_lock = threading.Lock()

        def download(requirement: RequirementInfo) -> bool:
            if findCachedWheel(requirement, wheelhouse) is not None:
                self.updateStatus(requirement.name, 'Cached')
                return True

            self.updateStatus(requirement.name, 'Downloading (0%)')
            spec = getRequirementSpec(requirement)
            with tempfile.TemporaryDirectory(prefix='southside-wheel-') as temp_dir:
                temp_path = Path(temp_dir)
                progress_stop = threading.Event()
                progress_lock = threading.Lock()
                expected_bytes = 0
                last_percent = -1

                def tempDownloadSize() -> int:
                    total = 0
                    for path in temp_path.rglob('*'):
                        try:
                            if path.is_file():
                                total += path.stat().st_size
                        except OSError:
                            continue
                    return total

                def updateProgress(force: bool = False) -> None:
                    nonlocal last_percent
                    with progress_lock:
                        total = expected_bytes
                    if total <= 0:
                        return
                    percent = min(99, max(0, int(tempDownloadSize() * 100 / total)))
                    if force or percent != last_percent:
                        last_percent = percent
                        self.updateDownloadProgress(requirement.name, percent)

                def watchProgress() -> None:
                    while not progress_stop.wait(0.2):
                        updateProgress()

                progress_thread = threading.Thread(
                    target=watchProgress,
                    daemon=True,
                    name=f'southside-wheel-progress-{requirement.name}',
                )
                progress_thread.start()
                popen = subprocess.Popen(
                    [
                        str(python_exe),
                        '-m',
                        'pip',
                        'download',
                        '--disable-pip-version-check',
                        '--no-input',
                        '--only-binary',
                        ':all:',
                        '--no-deps',
                        '--prefer-binary',
                        '--retries',
                        PIP_RETRIES,
                        '--timeout',
                        PIP_TIMEOUT,
                        '--cache-dir',
                        str(PIP_CACHE_DIR),
                        '--index-url',
                        mirror_url,
                        '--dest',
                        str(temp_path),
                        spec,
                    ],
                    cwd=str(SCRIPT_DIR),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True,
                    env=getPipEnv(env),
                )
                if popen.stdout:
                    for line in popen.stdout:
                        line_text = line.strip()
                        _logger.debug('[download %s] %s', spec, line_text)
                        if 'Downloading' in line_text:
                            size = parsePipDownloadSize(line_text)
                            if size is not None:
                                with progress_lock:
                                    expected_bytes += size
                                updateProgress(force=True)
                popen.wait()
                progress_stop.set()
                progress_thread.join(timeout=0.5)
                if popen.returncode != 0:
                    self.updateStatus(requirement.name, 'Download Failed')
                    return False

                copied = 0
                with copy_lock:
                    for wheel in temp_path.glob('*.whl'):
                        target = wheelhouse / wheel.name
                        if not target.exists():
                            shutil.copy2(wheel, target)
                        copied += 1
                self.markDownloadComplete(requirement.name, copied > 0)
                return True

        failed = []
        with ThreadPoolExecutor(max_workers=workers) as executor:
            future_map = {
                executor.submit(download, requirement): requirement
                for requirement in requirements
            }
            for future in as_completed(future_map):
                requirement = future_map[future]
                try:
                    if not future.result():
                        failed.append(requirement)
                except Exception as e:
                    _logger.exception(e)
                    self.updateStatus(requirement.name, 'Download Failed')
                    failed.append(requirement)
        return failed

    def runPipInstall(
        self,
        python_exe: Path,
        mirror_url: str,
        args: list[str],
        wheelhouse: Path | None = None,
        no_index: bool = False,
        env: dict[str, str] | None = None,
    ) -> int:
        ensurePipCacheDirs()
        self.progressChanged.emit(
            90,
            self._text('finalizing'),
        )
        command = [
            str(python_exe),
            '-m',
            'pip',
            'install',
            '--disable-pip-version-check',
            '--no-input',
            '--no-compile',
            '--prefer-binary',
            '--retries',
            PIP_RETRIES,
            '--timeout',
            PIP_TIMEOUT,
            '--cache-dir',
            str(PIP_CACHE_DIR),
        ]
        if no_index:
            command.append('--no-index')
        else:
            command.extend(['--index-url', mirror_url])
        if wheelhouse is not None:
            command.extend(['--find-links', str(wheelhouse)])
        command.extend(args)
        popen = subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=getPipEnv(env),
        )
        if not popen.stdout:
            popen.wait()
            return popen.returncode
        for line in popen.stdout:
            c = line.strip()
            _logger.debug(c)
            if 'Collecting' in c:
                self.updateStatusText(self._text('installing'))
                # Extract package name from "Collecting package_name" or "Collecting package_name (version)"
                match = re.search(r'Collecting\s+([a-zA-Z0-9_\-\.]+)', c)
                if match:
                    package = match.group(1)
                    self.updateStatus(package, 'Collecting')
            elif 'Downloading' in c:
                # Extract package name from "Downloading package_name-version..."
                match = re.search(r'Downloading\s+([a-zA-Z0-9_\-]+)', c)
                if match:
                    package = match.group(1)
                    self.updateStatus(package, 'Downloading')
            elif 'Using cached' in c:
                # Extract package name from "Using cached package_name-version..."
                match = re.search(r'Using cached\s+([a-zA-Z0-9_\-]+)', c)
                if match:
                    package = match.group(1)
                    self.updateStatus(package, 'Cached')
            elif 'Installing collected packages:' in c:
                # Extract all package names after "Installing collected packages:"
                packages_str = c.split('Installing collected packages:')[1]
                packages = [p.strip() for p in packages_str.split(',') if p.strip()]
                for package in packages:
                    self.updateStatus(package, 'Installing')
            elif 'Successfully installed' in c:
                # Extract all package names after "Successfully installed"
                packages_str = c.split('Successfully installed')[1]
                # Parse "package-version package2-version..." format
                matches = re.findall(r'([a-zA-Z0-9_\-]+)-[\d\.]+', packages_str)
                for package in matches:
                    self.updateStatus(package, 'Installed')
        popen.wait()
        if popen.returncode == 0:
            self.progressChanged.emit(
                99,
                self._text('checking_install'),
            )
        return popen.returncode

    def runPipUninstall(
        self,
        python_exe: Path,
        package_names: list[str],
        env: dict[str, str] | None = None,
    ) -> int:
        ensurePipCacheDirs()
        popen = subprocess.Popen(
            [
                str(python_exe),
                '-m',
                'pip',
                'uninstall',
                '--disable-pip-version-check',
                '-y',
                *package_names,
            ],
            cwd=str(SCRIPT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=getPipEnv(env),
        )
        if popen.stdout:
            for line in popen.stdout:
                _logger.debug(line.strip())
        popen.wait()
        return popen.returncode

    def updateStatusText(self, text: str) -> None:
        self.task.emit(lambda: self.status_label.setText(text))

    def updateProgressUi(self, value: int, text: str) -> None:
        self.progress_bar.setValue(max(0, min(100, value)))
        self.status_label.setText(text)

    def updateDownloadProgress(self, package_name: str, package_percent: int) -> None:
        if self._download_total <= 0:
            return
        normalized = normalizePackageName(package_name)
        with self._download_progress_lock:
            self._download_progress[normalized] = package_percent
            total_percent = sum(self._download_progress.values()) / (
                100 * self._download_total
            )
        overall = 11 + int(total_percent * 79)
        self.progressChanged.emit(
            overall,
            self._text('download', package=package_name, percent=package_percent),
        )

    def markDownloadComplete(self, package_name: str, downloaded: bool) -> None:
        normalized = normalizePackageName(package_name)
        with self._download_progress_lock:
            already_complete = self._download_progress.get(normalized, 0) >= 100
            self._download_progress[normalized] = 100
        if already_complete:
            return
        self._download_completed = min(
            self._download_total, self._download_completed + 1
        )
        overall = 11 + int(self._download_completed * 79 / max(1, self._download_total))
        state = 'Downloaded' if downloaded else 'Using cached wheel'
        self.progressChanged.emit(
            overall,
            f'{state} {package_name} ({self._download_completed}/{self._download_total})',
        )

    def updateStatus(self, package_name: str, status: str) -> None:
        self.updateStatusText(f'{package_name}: {status}')

    def testLatency(self, mirror_name: str, mirror_url: str):
        _logger.debug('testing latency of %s: %s', mirror_name, mirror_url)
        request = Request(mirror_url)
        start_time = time.perf_counter()
        try:
            with urlopen(request, timeout=MIRROR_LATENCY_TIMEOUT) as response:
                if response.status != 200:
                    return
                end_time = time.perf_counter()
                latency = end_time - start_time
                with self.latency_lock:
                    if not self.latency_testing:
                        return
                    self.latency_testing = False
                self.latencyFinished.emit(mirror_name, mirror_url, latency)
        except Exception:
            return

    def finishLatencyFallback(self) -> None:
        for thread in self.latency_test_threads:
            thread.join(timeout=MIRROR_LATENCY_TIMEOUT + 1)
        with self.latency_lock:
            if not self.latency_testing:
                return
            self.latency_testing = False
        self.latencyFinished.emit(
            'PyPI', MIRRORS['PyPI'], float(MIRROR_LATENCY_TIMEOUT)
        )

    def startTestLatency(self):
        installed = getInstalledPackages(PYTHON_EXE)
        required = getRequirements()
        unsatisfied = getUnsatisfiedRequirements(installed, required)
        pyside_incomplete = not isFullPySideInstalled()
        ft_unsatisfied: list[RequirementInfo] = []
        if FREE_THREADED_PYTHON_EXE.exists():
            if isFreeThreadedPython(FREE_THREADED_PYTHON_EXE):
                ft_installed = getInstalledPackages(
                    FREE_THREADED_PYTHON_EXE,
                    env=getFreeThreadedEnv(),
                )
                ft_required = getFreeThreadedRequirements()
                ft_unsatisfied = getUnsatisfiedRequirements(ft_installed, ft_required)
                ft_unsatisfied = mergeRequirements(
                    ft_unsatisfied
                    + getMissingImports(
                        FREE_THREADED_PYTHON_EXE,
                        ft_required,
                        FREE_THREADED_IMPORT_CHECKS,
                        env=getFreeThreadedEnv(),
                    )
                )
                _logger.info(
                    '%d no-GIL packages installed, %d required',
                    len(ft_installed),
                    len(ft_required),
                )
            else:
                _logger.warning(
                    'free-threaded Python failed validation: %s',
                    FREE_THREADED_PYTHON_EXE,
                )
        else:
            _logger.warning(
                'free-threaded Python not found: %s', FREE_THREADED_PYTHON_EXE
            )

        _logger.info(f'{len(installed)} installed, {len(required)} required')
        if not unsatisfied and not pyside_incomplete and not ft_unsatisfied:
            _logger.info('all requirements satisfied')
            self.allDone.emit()
            return
        _logger.info(f'{len(unsatisfied)} requirements need install/update')
        if ft_unsatisfied:
            _logger.info(
                '%d no-GIL requirements need install/update', len(ft_unsatisfied)
            )
        if pyside_incomplete:
            _logger.info('PySide6 needs install overwrite to restore full files')

        pyside_download_count = (
            len(getPySideRequirements(required)) if pyside_incomplete else 0
        )
        self._download_total = (
            len(unsatisfied) + len(ft_unsatisfied) + pyside_download_count
        )
        self._download_completed = 0
        self._download_progress.clear()

        for mirror_name, mirror_url in MIRRORS.items():
            thread = threading.Thread(
                target=self.testLatency, args=(mirror_name, mirror_url)
            )
            thread.daemon = True
            self.latency_test_threads.append(thread)

        self.latency_testing = True
        for thread in self.latency_test_threads:
            thread.start()
        threading.Thread(target=self.finishLatencyFallback, daemon=True).start()


if __name__ == '__main__':
    app = QApplication([])
    bwindow = BootstrapWindow()
    bwindow.allDone.connect(runMain)
    bwindow.startTestLatency()
    app.exec()
