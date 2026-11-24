extends Resource
class_name SpriteOrigins

## 精灵原点表（原 sprite manifest 的 `xOffset`／`yOffset`）。
##
## 键是精灵标识（`assets/sprite` 下的相对路径去掉 `.webp`），值是相对图片左上角的像素原点。
## 未登记的精灵按 (0, 0) 处理。

@export var origins: Dictionary = {}
