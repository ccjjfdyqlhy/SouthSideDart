[English Version](README.md)

# Southside Music

> 能用是及格，值得用才是作品。真正的功夫，都在看不见的时间里。

## 友情链接

- [LINUX DO](https://linux.do) - 新的理想型社区

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Adreno5/SouthsideMusic)

Southside Music 是一款 Windows 专用的网易云音乐第三方桌面客户端。它把专注的音乐管理、自研音频引擎、逐字歌词、桌面歌词、本地收藏、歌曲与歌词动画导出、Onerad 助手和 SouthsideClient 联动放在了同一个桌面应用里。

> 想了解项目一路走来的过程，可以阅读 [SouthsideMusic Story](SouthsideMusic_Story.md)。

---

## 目录

- [项目简介](#项目简介)
- [功能亮点](#功能亮点)
- [安装](#安装)
- [快速开始](#快速开始)
- [功能指南](#功能指南)
- [快捷键与使用技巧](#快捷键与使用技巧)
- [开发](#开发)
- [许可](#许可)

---

## 项目简介

Southside Music 面向希望在桌面上使用网易云音乐、同时保留播放控制权的用户。登录后可以搜索曲库、浏览云端歌单、收听每日推荐，也可以用本地收藏夹重新组织自己的音乐。

播放器使用独立音频管线，而不是把听歌体验交给网页容器。响度、速度、音调、立体声宽度、混响、歌曲衔接、静音检测、预加载、歌词和可视化都由应用直接处理。

Southside Music 是独立、非商业项目，并非网易云音乐官方客户端。

---

## 功能亮点

### 音频

- 可调整目标 LUFS 的响度均衡
- `0.1x` 到 `3.0x` 变速播放，并通过时间伸缩保持音调
- `-12` 到 `+12` 半音的独立变调
- 可选立体声 Haas 加宽和混响
- 智能交叉淡化，支持自适应时长、过渡曲线、节拍与调性匹配、自动增益控制
- 结尾静音检测，可调整阈值和检测时间窗口
- 预加载当前歌曲和下一首，改善拖动进度与切歌体验
- 自由选择音频输出设备

### 歌词与视觉

- 支持 LRC 行级时间和 YRC 逐字时间
- 有 YRC 数据时自动逐字高亮
- 有翻译数据时可即时开关翻译歌词
- 桌面歌词置顶悬浮窗，支持保存位置和顶部吸附
- 实时 FFT 频谱可视化
- 使用当前封面参与主题背景色混合
- 导出歌词动画，可设置格式、码率、对齐、行数、背景、动画、翻译和音频
- 支持明暗主题、英文和简体中文界面

### 曲库与导出

- 网易云歌曲和歌单搜索，滚动增量加载
- 每日推荐歌曲和推荐歌单
- 在同一个侧边栏管理本地收藏夹和网易云云端歌单
- 批量选择、替换播放列表、追加队列、移除和本地排序
- “库”页面汇总全部本地收藏歌曲
- 导出歌曲时写入封面、歌词、专辑、歌手和曲目元数据
- 在首页、搜索、库和收藏页面把歌曲插入当前播放之后

### 助手与联动

- Onerad 助手侧栏，支持流式输出和明确的工具调用确认
- 支持 OpenAI 兼容 Chat Completions、OpenAI Responses 和 Anthropic 服务
- API Key 使用 Windows 数据保护 API 加密
- SouthsideClient WebSocket 桥接端口为 `15489`
- 向 SouthsideClient 发送歌词、封面、歌曲信息、播放进度、状态和 FFT
- 接收 SouthsideClient 的暂停/继续、跳转、下一首和上一首控制

### 可靠性

- 在应用内检查 GitHub Releases 并处理更新
- 启动时检查 FFmpeg、Python 运行时、音频输出、网络和 OpenGL
- 缺少 FFmpeg 时提供引导下载
- 自动清理过旧或超过空间上限的可重新下载缓存
- 未捕获异常通过弹窗显示 traceback 详情
- 按 `F3` 打开运行时调试覆盖层

---

## 安装

1. 打开 [Releases 页面](https://github.com/Adreno5/SouthsideMusic/releases)。
2. 下载最新的 `SouthsideMusic_<版本号>_win64_setup.exe`。
3. 运行安装程序，然后启动 Southside Music。

首次启动时会执行依赖检查。如果缺少 FFmpeg，依赖窗口可以自动下载并安装。

> Southside Music 目前仅支持 Windows。

---

## 快速开始

### 1. 登录

在首页或侧边栏的账号区域选择登录方式：

- **Cell Phone / 手机号** - 输入手机号和验证码。
- **QR Code / 二维码** - 使用网易云音乐 App 扫码并确认登录。
- **Cookie** - 从浏览器 DevTools 复制 `MUSIC_U` Cookie 值并粘贴（F12 → Application → Cookies → music.163.com）。

匿名会话可以启动应用，但每日推荐、云端歌单和大多数账号功能需要登录网易云音乐。

### 2. 查找音乐

点击标题栏搜索框，输入关键词并按回车。在搜索页面切换 **Songs / 歌曲** 和 **Playlists / 歌单**，向下滚动会继续加载结果。

### 3. 组织播放队列

点击歌曲会立即播放。在支持的歌曲卡片上点击封面，可以把歌曲插入当前播放之后。打开文件夹或歌单后，可以替换当前队列，也可以追加到队列末尾。

### 4. 管理收藏

在 Local / 本地区域使用 **Add folder / 添加文件夹** 创建应用管理的收藏夹。歌曲操作支持添加、移除、导出和排序；云端歌单则独立显示在 Cloud / 云端区域。

---

## 功能指南

### 播放区

点击底部播放栏可以打开完整播放页面，其中包含封面、歌曲信息、同步歌词、翻译控制和歌词动画导出。紧凑控制栏始终保留播放进度、当前歌词、FFT、上一首/播放/下一首和队列入口。

歌曲准备好后可拖动进度线跳转。打开队列面板后，可以播放、排序、导出、单曲循环、移除或清空队列中的歌曲。

### 智能交叉淡化

交叉淡化会分析相邻歌曲，并在当前歌曲接近结尾时准备过渡。高级设置提供过渡强度、曲线、最大时长、BPM 窗口、节拍匹配、调性匹配和自动增益控制。如果需要保留精确的曲目边界，可以关闭交叉淡化。

### 歌词与歌词动画

YRC 歌词使用逐字高亮；没有 YRC 时间数据时自动回退到 LRC 行级显示。网易云提供翻译数据时，可以同时显示翻译歌词。

播放页面的导出按钮可以把同步歌词渲染为 `.mp4`、`.av1`、`.mkv` 或 `.webm`。导出选项包括码率、显示行数、逐字时间、翻译、对齐方式、纯色背景、滚动动画，以及是否包含原始音频。

### 桌面歌词

在设置中启用桌面歌词后，会打开置顶悬浮歌词窗口。窗口位置会跨启动保存；拖到屏幕顶部可以吸附，也可以在设置中使用 **Reset Position / 重置位置**。

### 收藏与歌曲导出

收藏页面既可以显示本地文件夹，也可以显示网易云云端歌单。本地文件夹支持排序和移除；两个视图都可以替换队列、追加队列，并在可用时执行批量操作。

歌曲导出支持 `.mp3`、`.m4a`、`.flac`、`.wav`、`.ogg` 和 `.opus`。Southside Music 会把可用的封面、歌词、专辑、歌手和曲目信息写入导出文件。

### Onerad

先在设置中配置模型服务，然后点击标题栏聊天按钮。Onerad 支持流式回答，也可以请求执行搜索、打开文件夹、控制播放或修改设置等应用操作。会影响应用的工具调用需要用户确认。

### SouthsideClient

Southside Music 会在本机 `15489` 端口启动 WebSocket 服务。连接会向 SouthsideClient 发送播放状态、歌曲数据、歌词、封面、进度和 FFT 数据，并接收基础播放控制。设置页面会显示连接状态、流量、延迟以及连接/断开按钮。

### 设置

设置页面默认保持精简。启用 **Advanced Settings / 高级设置** 后，会显示完整的音频、FFT、LLM、存储和歌曲衔接参数。

| 分组 | 主要选项 |
| --- | --- |
| 应用 | 语言和下载并发数 |
| 缓存存储 | 自动清理、缓存时限和空间上限 |
| 播放 | 播放顺序、智能跳过、立体声、混响、输出设备 |
| 交叉淡化 | 强度、曲线、时长、BPM、节拍、调性和增益匹配 |
| 播放效果 | 速度、音调、静音阈值和检测窗口 |
| LLM | 提供商、API 格式、密钥、Base URL 和模型 |
| 窗口 | 封面颜色背景混合 |
| 歌词 | 动画平滑参数 |
| 桌面歌词 | 显示开关和位置重置 |
| FFT | 频谱、平滑、缓冲、大小和客户端缩放 |
| 响度 | 目标 LUFS |
| 连接 | SouthsideClient 状态、流量、延迟和控制 |

---

## 快捷键与使用技巧

- 按 **空格键** 暂停或继续播放。
- 按 **F3** 切换调试覆盖层。
- 点击底部播放栏中进度线下方的区域，展开或收起播放页面。
- 歌曲加载完成后，拖动进度线可以跳转播放位置。
- 在支持的列表中点击歌曲封面，把歌曲插入当前播放之后。
- 打开 **Library / 库**，集中查看所有本地收藏夹中的歌曲。
- 在设置中修改 **Language**，立即切换英文和简体中文。
- 如果不同歌曲的感知音量不一致，可以调整 **Target LUFS**。

---

## 开发

### 环境要求

- Windows
- Python `>=3.13`
- [`uv`](https://docs.astral.sh/uv/)
- 初次搭建环境和下载依赖时需要网络连接

### 准备工作区

```bash
git clone https://github.com/Adreno5/SouthsideMusic.git
cd SouthsideMusic
python setup_workspace.py
```

搭建脚本会同步 `uv` 环境，准备 Python 3.14.2 嵌入式运行时和 free-threaded `3.14t` worker 环境，创建独立的 Nuitka 构建环境，验证运行时，并按需安装 Inno Setup。

### 从源码运行

```bash
uv run src/main.py
```

如果已经激活项目环境，也可以运行：

```bash
python src/main.py
```

### 验证

```bash
python -m py_compile src/main.py
uv run ruff check .
uv run ruff format --check .
uv run mypy src/
python scripts/check_backend_no_qt.py   # 验证核心后端在无 PySide6 环境下可正常导入
```

项目目前没有正式的自动化测试套件。`src/test.py` 是手动 API 探索脚本，不是 pytest 测试。

### 构建

```bat
build.bat
```

构建脚本会使用 Nuitka 编译 `launcher.py`，组装嵌入式运行时和应用资源，并在存在 `ISCC.exe` 时调用 Inno Setup。

```text
build.result\
├── raw\          可直接运行的便携目录
└── installer\    已安装 Inno Setup 时生成带版本号的安装器
```

如果没有 Inno Setup，便携构建仍会保留在 `build.result\raw\`。

### 无界面核心后端（Headless Backend）

最近的几次重构把核心逻辑抽到了 `src/backend/` 下 UI 无关的独立包中。`CoreBackendService` 在不创建任何 Qt 控件的前提下完成配置、网易云 API、收藏、音频播放器、歌词解析、播放管理器、LLM 客户端和 WebSocket 桥接的初始化。`backend/shim.py` 和 `backend/signals.py` 提供了极小的 Qt-free 垫片，使 `src/core/` 下所有模块都能在没有 PySide6 的环境里导入；桌面 UI 在可用时仍使用原生 PySide6 行为。

`standalone.py` 是完全不依赖 PySide6 的无头入口，通过 stdin/stdout 提供换行分隔的 JSON 协议：

```bash
python scripts/check_backend_no_qt.py        # 验证无 Qt 导入链路

printf '{"id":1,"method":"ping"}\n{"id":2,"method":"shutdown"}\n' | \
  python src/backend/standalone.py
```

每个请求为 `{"id": ..., "method": ..., "params": {...}}`，响应为 `{"id": ..., "result": ...}` 或 `{"id": ..., "error": {"code": ..., "message": ...}}`。

`standalone.py` 也在 TCP RPC 服务（端口 `15490`，可用 `--port` 修改）上暴露同一协议，
前端既可以作为子进程启动内核，也可以连接手动启动的内核。

支持的全部 RPC 方法（都在 `standalone.py` 中）：

| 分组 | 方法 |
| --- | --- |
| 生命周期 | `ping`、`shutdown`、`get_status`、`get_config`、`set_config` |
| 搜索 / 发现 | `search`、`daily_recommend` |
| 歌单 | `user_playlists`、`get_playlist`、`folder_songs`、`list_favorites`、`clear_playlist`、`create_playlist`、`remove_playlist`、`remove_playlist_song` |
| 播放 | `play_songs`、`play_playlist`、`play_storable`、`queue_song`、`play_control`、`play_mode`、`get_playback`、`get_lyrics` |

`play_mode` 除用于常规播放模式外，也支持智能推荐模式：`heart`（心动模式）、
`fm`（私人漫游）、`radar`（私人雷达）、`similar`（相似歌曲），分别对应内核的
`startHeartMode` / `startPersonalFM` / `startPrivateRadar` / `startSimilarSongs`。
| 收藏 | `get_liked_songs`、`like_song`、`unlike_song` |
| 账号 / 登录 | `get_account_info`、`logout`、`login_cellphone_send`、`login_cellphone_verify`、`login_qr_create`、`login_qr_check`、`login_cookie` |
| 详情 | `get_album_tracks`、`get_artist`、`get_user`、`get_comments`、`add_comment` |
| 下载 | `download_song` |

播放/队列变更还会向已连接客户端推送 `SONG_CHANGED`、`PLAY_STATE_CHANGED`、
`PLAYLIST_CHANGED`、`PLAYBACK_LYRICS_UPDATED`、`LYRIC_LINE_CHANGED` 事件
（Flutter 的 `PlayerState` 会消费这些事件）。

### Flutter UI 重写

`flutter_ui/` 是下一代界面的 Flutter 桌面原型，通过 `lib/services/backend_client.dart`
使用与上述一致、换行分隔的 JSON 协议驱动无头后端 `src/backend/standalone.py`，
支持两种传输：

- **TCP RPC**（`connectTcp`，默认 `127.0.0.1:15490`）：手动启动内核后连接；
- **进程模式**（`connectProcess`）：由前端启动内核子进程，经 stdin/stdout 直连
  （生命周期随前端、无需手动启动、无端口依赖）。

已实现的页面：首页（每日推荐、模式卡、云端歌单）、搜索（歌曲/歌单）、收藏
（本地收藏夹 + 云端歌单）、歌单详情、播放页（经典/单行布局、翻译开关、播放
模式、播放列表抽屉、红心、下载、分享）、评论、歌手、专辑、用户主页、登录
（二维码/手机/cookie）、设置。共享的 `PlayerState` 通过轮询 + 事件订阅与后端
保持播放同步。

PySide6 桌面界面仍是当前正式交付的界面；Flutter UI 正在向其功能对齐，之后才
取代 PySide6 界面。

### 项目结构

```text
src/
  main.py          应用入口和启动生命周期
  imports.py       共享 Qt、类型和事件导入
  backend/         UI 无关的核心后端服务（不依赖 Qt）
  core/            音频、配置、模型、歌词、主题和后端
  services/        事件总线、更新和应用服务
  views/           PySide6 页面、卡片、面板、窗口和控件
  pyncm/           内置网易云音乐 API 客户端
flutter_ui/        Flutter 桌面 UI 原型（UI 重写进行中）
scripts/           构建与健康检查脚本
docs/              中英文项目文档
data/              运行时缓存和本地收藏数据
fonts/             内置 HarmonyOS Sans SC 字体
icons/, images/    应用界面资源
config.json        持久化用户配置
```

### 技术栈

| 层级 | 技术 |
| --- | --- |
| 界面（当前） | PySide6 + PySide6-Fluent-Widgets |
| 界面（原型） | Flutter（`flutter_ui/`） |
| 核心后端 | 无 Qt 依赖的 `src/backend/` 服务，提供无头 JSON 协议 |
| 窗口 | qframelesswindow + hPyT |
| 音频与 DSP | sounddevice + pydub + NumPy + SciPy |
| 元数据 | mutagen |
| 网易云 API | 内置 `pyncm` 客户端 |
| 网络 | requests + Tornado WebSocket server |
| 助手 | OpenAI SDK + Anthropic SDK |
| 打包 | Nuitka + Inno Setup |

### 配置与数据

- 持久化设置保存在 `config.json`。
- 本地收藏和运行时缓存保存在 `data/` 下。
- 旧版 `config.pkl` 数据会迁移并删除。
- LLM API Key 使用 `CryptProtectData` 为当前 Windows 用户加密。
- 可重新下载的缓存可以按文件年龄和总占用空间自动清理。

---

## 许可

Southside Music 使用 [PolyForm Noncommercial License 1.0.0](../LICENSE)。

本软件仅供个人学习、研究和私人娱乐使用，禁止商业用途。通过应用导出的音乐由用户自行负责，不得传播或倒卖导出的音频文件。
