# 资源目录约定

仓库只提交**自产数据层**（`.tres`）。原版游戏的二进制资源（贴图、音频、字体）属于原开发方版权，
不入库，由本地补齐。

## 提交范围

| 路径 | 入库 | 说明 |
| --- | --- | --- |
| `assets/*.tres` | 是 | 由反汇编重建的数据表：图鉴、战斗、事件、任务、文本、商店 |
| `assets/tilesets/*.tres` | 是 | 地图图块的切分、碰撞与动画定义 |
| `assets/ui/*.tres` | 是 | 九宫格与格子样式 |
| `assets/translations/*.tres` | 是 | 文案表 |
| `assets/fonts/ui_theme.tres` | 是 | 主题字号与字体槽位 |
| `assets/audio/default_bus_layout.tres` | 是 | 音频总线布局 |
| `assets/sprite/**` | 否 | 原版贴图 |
| `assets/audio/*.ogg` | 否 | 原版音频 |
| `assets/fonts/*.ttf` | 否 | 原版字体 |
| `assets/**/*.import` | 否 | 导入缓存，由 Godot 生成 |

## 本地补齐二进制资源

克隆后 `assets/` 只有数据层，运行前把原版资源放回下列位置（`res://` 内的相对路径保持不变）：

```text
assets/sprite/     <- 贴图（按现有 scenes/ 引用的 sprite/... 层级放置）
assets/audio/*.ogg
assets/fonts/*.ttf
```

资源来自原版安装包的解包结果，只在本地使用。放好后执行一次导入：

```powershell
godot --headless --path . --import
```

## 缺资源时的表现

缺贴图或字体时启动会打印 `Failed loading resource: res://assets/...`，场景仍可加载，
但对应视觉元素为空；`tests/` 中依赖贴图的用例会报同样的错误。这不是代码缺陷。
