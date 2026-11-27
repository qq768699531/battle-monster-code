extends "res://tests/unit/gut_case.gd"

const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const NetworkScene = preload("res://game/menu/network/network.tscn")


## NET 页的宿主（`menu_view`）在测试里只留确认时真正用到的接口。
class FakeHost extends Control:
	const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")

	var network_navigation_open := true
	var selected_network_index := 0
	var network_scroll_start := 0
	var notice := ""
	var bought: Array = []
	var renders := 0

	func _render_content() -> void:
		renders += 1

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


## NET 页确认时把光标那一格交给宿主购买（写背包与 `progress_changed` 都在宿主侧）。
func test_screen_confirm_delegates_to_the_host() -> void:
	var host := FakeHost.new()
	add_child_autofree(host)
	var screen: Control = NetworkScene.instantiate()
	host.add_child(screen)
	assert_eq(screen._offers.size(), Menu.native_network_offers().size(),
		"货架来自原生包裹表")
	host.selected_network_index = 2
	screen._confirm()
	assert_eq(host.bought.size(), 1, "确认一次只下一单")
	assert_eq(int(host.bought[0]["id"]), int(screen._offers[2]["id"]), "买的是光标那一格")

## 野外会把菜单提交的快照按 `last_progress_operation` 重放一遍校核（`_menu_progress_changed`），
## 所以 NET 购买必须能被 `replay_operation` 原样重放，否则整单会被拒。
func test_replay_reproduces_the_network_purchase() -> void:
	var live := {"inventory": {}, "parameter": {"moneyBalance": 0}}
	var snapshot: Dictionary = live.duplicate(true)
	var offer := {"id": 7000, "quantity": 6}
	assert_true(bool(Menu.buy_network_offer(snapshot, offer).get("ok", false)), "先按面板那样买一单")
	var replay := Menu.replay_operation(live, null, {"kind": "network-buy", "item_id": 7000,
		"count": 6})
	assert_true(bool(replay.get("ok", false)), "重放认得 network-buy")
	assert_eq(replay["progress"], snapshot, "重放结果与提交快照逐字段相等")