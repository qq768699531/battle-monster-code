extends Control
## 战斗边界提示面板：只在 `battle_view` 的边界态（`phase == "boundary"`）显示。
##
## 原生没有这块浮层——它是本工程「这一战不受支持、返回地图／标题」这条出口的唯一文本
## （`battle_view._boundary()`）。普通战斗反馈不画在这里：原生由 `Game_infoInit` 推进全局提示栈，
## `Game_infoDraw` 给每条消息先铺半透明黑底再画字，所以那些文本走 `message_stack`。


func present(text: String) -> void:
	$BoundaryNote.text = text
	$Boundary.visible = true
