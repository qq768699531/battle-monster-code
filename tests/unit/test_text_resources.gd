extends "res://tests/unit/gut_case.gd"

var _assets: Node


func before_all() -> void:
	_assets = get_node("/root/AssetCatalog")


func test_translation_resource_is_registered() -> void:
	assert_eq(_assets.TEXT_TRANSLATION.resource_path,
		"res://engine/ui/message_stack/zh_CN.tres", "唯一可编辑的 Translation 资源")


func test_menu_messages_resolve_through_translation() -> void:
	assert_eq(_assets.text_message(Msg.SOURCE, Msg.Id.LOCKED), "[已上锁]")


## 原生 `#C`／`#P` 换色已落成正文内联的 `[color=#RRGGBB]…[/color]`（`script\export_text_colors.py`
## 从 `JC_fntDrawText:265-274`／`JC_fntSetPALETTE` 的调色板语义展开），正文里不再有控制码。
func test_translation_bodies_use_color_markup() -> void:
	assert_eq([_assets.text_message(Msg.SOURCE, Msg.Id.DAMAGE_ADVANTAGE).begins_with(
			"[color=#FFFF00]"),
		_assets.text_message(Msg.SOURCE, Msg.Id.DAMAGE_DISADVANTAGE).begins_with(
			"[color=#F00000]")], [true, true],
		"407 保留原生黄 0xFFFF00、408 保留原生红 0xF00000")
	var keys: Array = _assets.TEXT_TRANSLATION.get_message_list()
	var coded: Array[String] = []
	for key: String in keys:
		var body := String(_assets.TEXT_TRANSLATION.get_message(key))
		if body.contains("#C") or body.contains("#P"):
			coded.append(key)
	assert_true(not keys.is_empty() and coded.is_empty(),
		"全表正文里残留的原生 #C／#P 控制码为 0 条")


func test_startup_reports_no_errors() -> void:
	assert_eq(_assets.get_startup_errors(), [], "启动期没有资源错误")


## 点阵字库没有「娲」「樨」两字（精灵 20／60 的名字），主题必须挂一个 CJK 回退字体，
## 否则整条名字在 `native_label` 里报缺字并不绘制。
func test_native_label_has_cjk_fallback() -> void:
	var theme: Theme = load("res://engine/ui/native_label/ui_theme.tres")
	var font := theme.default_font as FontVariation
	assert_true(font != null and not font.fallbacks.is_empty(), "原生点阵字挂了回退字体")
	assert_eq(_assets.text_message("common/item_mon.dat", "item_mon.group.59.name"), "木樨兽",
		"No.060 的名字仍有原文，不靠改词规避缺字")
	assert_eq(_assets.text_message("common/item_mon.dat", "item_mon.group.19.name"), "女娲",
		"No.020 的名字仍有原文")
