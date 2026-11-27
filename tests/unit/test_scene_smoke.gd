extends "res://tests/unit/gut_case.gd"

## 冒烟：主场景的脚本在加载期不能有解析错误（GDScript 的类型推断错误只在这一步暴露，
## `--headless` 启动同样会因此失败；单测不会覆盖没被提到的脚本）。
const SCENES := [
	"res://game/field/runtime/field_runtime/field_runtime.tscn",
	"res://game/battle/combat/battle.tscn",
	"res://game/menu/screen/menu/menu.tscn",
	"res://game/prime/title/title_visual/title_visual.tscn",
]


func test_main_scenes_load_without_parse_errors() -> void:
	for path: String in SCENES:
		assert_not_null(load(path), path.get_file())
