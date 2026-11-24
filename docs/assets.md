# 资源目录约定

仓库按**用途**分目录，不按文件类型分层：一个对象的场景、脚本、数据与贴图放在同一个目录里。

```text
monsters/mon1/m_f_000/
  m_f_000.tscn      场景
  m_f_000.webp      该对象的整张精灵图（无损 WebP）
maps/m0/
  m0.tscn           地图场景
  t0_0.tscn         地形层
  m0_0.tres         TileSet
  m0_0.webp         地图图层
```

## 入库范围

| 路径 | 入库 | 说明 |
| --- | --- | --- |
| `**/*.tscn` `**/*.gd` `**/*.tres` `**/*.gdshader` | 是 | 场景、脚本、数据表、着色器 |
| `**/*.webp`（`.tscn` 引用的图集） | 否 | 原版美术资源，版权归原开发方，本地补齐 |
| `assets/audio/**` | 否 | 原版音频 |
| `assets/fonts/*.ttf` | 否 | 原版字体 |
| `**/*.import` | 否 | Godot 导入缓存 |

## 精灵图约定

- 一个对象一张图集：该对象的所有动画帧合并成 `<对象名>.webp`，网格排布、无损编码。
- 场景用 `AtlasTexture` 引用图集中的帧：`atlas` 指向图集，`region` 是该帧在原图中的矩形。
  这样每帧的尺寸与原点都不变，动画轨道的 `values` 也从 `ExtResource` 换成 `SubResource`。
- 地图图层例外：每个图层本来就是单帧整图，直接是 `<对象名>.webp`，TileSet 用普通
  `Texture2D` 引用——`AtlasTexture` 会让 Godot 拒绝创建任何 tile。
- 多个场景共用的贴图簇（`ui/window/`、`ui/number/`、`battle/hud/`、`ui/touch_button/`）
  后续由各自的通用场景持有，不再让每个场景重复引用。

## 本地补齐二进制资源

克隆后只有场景/脚本/数据，运行前把原版资源按下列位置放回（`res://` 相对路径保持不变）：

```text
assets/sprite/<对象>/<对象>.webp     # 各功能目录下的图集
assets/audio/**/*.ogg
assets/fonts/*.ttf
```

放好后执行一次导入：

```powershell
godot --headless --path . --import
```

## 缺资源时的表现

缺图集或字体时启动会打印 `Failed loading resource: res://...`，场景仍可加载，但对应视觉元素为空。
这不是代码缺陷。
