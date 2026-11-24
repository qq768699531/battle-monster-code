# Battle Monster

Battle Monster 的公开代码仓库，用于管理源码、测试与文档。

## 原版游戏

《Battle Monster》是一款 Android 平台的怪物养成游戏，由 ensony 开发。本项目是对原版游戏的独立实现。

本项目为非官方项目，与原版游戏开发方无隶属关系，亦未获得其授权。游戏名称、商标及原版资源归各自权利人所有。

## 仓库内容

- 本项目自行实现的游戏代码与开发工具
- 测试、文档和开发约定
- 构建与发布配置

原版游戏资源、APK 及其解包产物，以及本地缓存、个人配置、密钥与凭据不进入本仓库。

## 参与

提交前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

本项目以 [GNU General Public License v3.0](LICENSE) 发布。

## 本地资源

仓库不包含原版游戏的贴图、音频与字体：`assets/` 只提交自产的数据表（`.tres`）。
首次运行前按 [docs/assets.md](docs/assets.md) 补齐二进制资源，否则贴图与字体加载会失败。
