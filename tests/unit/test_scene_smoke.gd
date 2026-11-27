extends "res://tests/unit/gut_case.gd"

## 冒烟：把工程里每个 .gd 都 load 一遍。GDScript 的解析错误（类型推断失败、语法错）
## 只在加载该脚本时暴露——单测碰不到、但启动时会被预载的脚本最容易漏，所以这里全量过一遍。
## `addons/`（GUT 自带）不在检查范围。
const ROOTS := ["res://engine", "res://game", "res://content"]


func test_every_script_parses() -> void:
	var scripts: Array[String] = []
	for root: String in ROOTS:
		_collect(root, scripts)
	assert_true(scripts.size() > 100, "扫到的脚本数量异常：%d" % scripts.size())
	var broken: Array[String] = []
	for path: String in scripts:
		if load(path) == null:
			broken.append(path)
	assert_eq(broken, [] as Array[String], "这些脚本解析失败")


func _collect(directory: String, out: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for directory_name: String in dir.get_directories():
		_collect(directory.path_join(directory_name), out)
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(directory.path_join(file_name))
