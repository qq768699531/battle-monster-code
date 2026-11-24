extends Node2D
## 网络页的详情面板。

const UI = preload("res://prime/layout/layout.gd")


func present(paint: Dictionary) -> void:
	var result: Dictionary = paint.get("network_result", {})
	$Heading.text = str(result.get("operation", "")) + "  [%d]" % int(result.get("status", 0))
	$Body.present(UI.wrap_text(JSON.stringify(result.get("payload", {})), $Body.size.x, UI.UI_FONT).slice(0, 8))
	var detail_action: Dictionary = paint.get("network_detail_action", {})
	var action_label := ""
	if not detail_action.is_empty():
		match str(detail_action.get("kind", "")):
			"claim-mail":
				action_label = "确认：标记首封邮件已领取（附件不写入存档）"
			"buy-market":
				action_label = ("再次确认购买首个挂单：%s Cash" if paint.get("network_action_confirming", false) else
					"确认购买首个挂单：%s Cash") % str(detail_action.get("price", 0))
			"visit-island":
				action_label = "确认：访问首个本地岛屿"
			"like-island":
				action_label = "确认：为此岛点赞（每个账号限一次）"
	elif paint.get("network_request_pending", false):
		action_label = "正在处理本地请求…"
	$Actions.present(UI.wrap_text(action_label, $Actions.size.x, UI.UI_FONT).slice(0, 2), [], Color("#FFB655"))
