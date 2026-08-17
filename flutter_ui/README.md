# Southside Music UI

Southside Music 下一代界面的 Flutter 桌面原型（Linux 目标）。

> 项目主文档见 [`docs/README.md`](../docs/README.md) 与
> [`docs/README_zh.md`](../docs/README_zh.md)。本目录目前使用 mock 数据，
> 尚未接通真实后端。

## 目录结构

```text
lib/
  main.dart              应用入口与主框架（标题栏 + 侧边栏 + 内容区 + 底部播放栏）
  pages/                 首页 / 搜索 / 歌单 / 收藏 / 播放 / 设置页面
  widgets/               侧边栏、播放栏、歌曲卡片、文件夹卡片、标题栏等组件
  state/player_state.dart  共享播放状态
  theme/app_theme.dart   多主题注册表（明暗模式）
  models/models.dart     数据模型
  data/mock_data.dart    mock 数据
linux/                   Linux 桌面构建配置
```

## 运行

```bash
cd flutter_ui
flutter pub get
flutter run -d linux
```

## 路线

- 当前：mock 数据驱动的 UI 原型
- 计划：通过 [`src/backend/`](../src/backend/) 的无头 JSON 协议（stdin/stdout）
  连接真实核心后端，逐步取代 PySide6 界面
