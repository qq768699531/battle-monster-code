extends "res://tests/unit/gut_case.gd"

const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const NetworkScene = preload("res://game/menu/network/network.tscn")
const Box = preload("res://engine/ui/confirm_box/confirm_box.gd")


## NET 页的宿主（`menu_view`）在测试里只留确认时真正用到的接口。
class FakeHost extends Control:
	const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")

	var network_navigation_open := true
	var selected_network_index := 0
	var network_scroll_start := 0
	var notice := ""
	var story_progress: Dictionary = {"inventory": {}, "parameter": {"moneyBalance": 0}}
	var bought: Array = []
	var renders := 0

	func _render_content() -> void:
		renders += 1

	func _menu_text(id: int) -> String:
		return "文本%d" % id

	func buy_network_offer(offer: Dictionary) -> bool:
		bought.append(offer)
		return true


## 付款阶段尚未接通：整包数量一次入包，金币不动。
func test_model_adds_the_whole_package_without_payment() -> void:
	var progress := {"inventory": {}, "parameter": {"moneyBalance": 0}}
	var result := Menu.buy_network_offer(progress, {"id": 7000, "quantity": 6})
	assert_true(bool(result.get("ok", false)), "没接通付款也照常入包")
	assert_eq(int(progress["inventory"]["7000"]), 6, "整包数量一次写入背包")
	assert_eq(int(progress["parameter"]["moneyBalance"]), 0, "跳过付款：不扣金币")


## 背包放不下就整单拒绝，不留半包道具。
func test_model_rejects_a_full_bag() -> void:
	var progress := {"inventory": {}, "itemCapacity": [0, 0, 0, 0, 0, 0]}
	var result := Menu.buy_network_offer(progress, {"id": 7000, "quantity": 1})
	assert_true(not bool(result.get("ok", true)), "背包满了拒绝购买")
	assert_true(not progress["inventory"].has("7000"), "拒绝时不入包")


## 野外会把菜单提交的快照按 `last_progress_operation` 重放一遍校核（`_menu_progress_changed`），
## NET 购买走 Story 的入手入口，快照级重放仍要能对得上。
func test_replay_reproduces_the_network_purchase() -> void:
	var live := {"inventory": {}, "parameter": {"moneyBalance": 0}}
	var snapshot: Dictionary = live.duplicate(true)
	var offer := {"id": 7000, "quantity": 6}
	assert_true(bool(Menu.buy_network_offer(snapshot, offer).get("ok", false)), "先按面板那样买一单")
	var replay := Menu.replay_operation(live, null, {"kind": "network-buy", "item_id": 7000,
		"count": 6})
	assert_true(bool(replay.get("ok", false)), "重放认得 network-buy")
	assert_eq(replay["progress"], snapshot, "重放结果与提交快照逐字段相等")


## 原生 `Menu_Network_mKeyPressed` 组 1 的 −5：先开付款确认窗（光标停在「否」），
## 选「是」才交给宿主入包，随后换「购买完毕」的确定页。
func test_screen_confirm_opens_payment_then_buys() -> void:
	var host := FakeHost.new()
	add_child_autofree(host)
	var screen: Control = NetworkScene.instantiate()
	host.add_child(screen)
	host.selected_network_index = 2
	screen._confirm()
	var confirm: Control = screen.get_node("Confirm")
	assert_true(confirm.visible and confirm.selection() == 1,
		"先开付款确认窗，光标默认落在「否」")
	confirm.set_selection(0)
	confirm.get_node("AnimationPlayer").advance(1.0)
	confirm.accept()
	assert_eq(host.bought.size(), 1, "选「是」才下这一单")
	assert_eq(int(host.bought[0]["id"]), int(screen._offers[2]["id"]), "买的是光标那一格")
	assert_eq(confirm.form(), Box.Form.OK, "付款后换「购买完毕」的确定页")
