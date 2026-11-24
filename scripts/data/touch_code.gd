extends RefCounted
class_name TouchCode
## 原生 `EFC_mainTouch` 的固定触控键码：所有页面通用，负数。
##
## 面板上的正数按钮（35／42／48）在不同页面含义不同——42 在地图是图鉴、在战斗是 MON INFO、
## 在存档页是「删除」，战斗页的 AUTO 是 48——所以那些枚举写在各自的页面脚本里（`FieldKey`、
## `battle_view.TouchKey`、`prime/layout.gd` 的 `PanelKey` 等），这里只收全页面一致的固定键。

## 确认／返回／说明三个固定键（`touch_controls.tscn` 的 Confirm／Clear／Help）。
enum Key {
	OK = -5,      ## 确认／交互／翻页
	BACK = -16,   ## 返回／清除／提交并关闭
	HELP = -10,   ## 说明；地图页上它是原生 `Field_Save`
}

## 方向盘四向（地图、菜单、存档页共用同一盘面）。
enum Pad {
	UP = -1,
	DOWN = -2,
	LEFT = -3,
	RIGHT = -4,
}
