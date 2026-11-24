extends Node2D
## 存档槽卡片：原生面板、选中框、三只队伍精灵与文字。

const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const MONSTER_SCENE = preload("res://engine/anim/monster_animation/monster_animation.tscn")
const PORTRAIT_COUNT := 3
const SELECTED_BORDER := Color("#7AD0FA")
const IDLE_BORDER := Color("#196485")
const SELECTED_BACKGROUND := Color("#0E1B2F")

var _portrait_positions: Dictionary = {}
var _portraits: Array[Node2D] = []
@onready var _backings: Array[Control] = [$Backing0, $Backing1, $Backing2]
@onready var _clips: Array[Control] = [$Clip0, $Clip1, $Clip2]


func _ready() -> void:
	for clip in _clips:
		var portrait := MONSTER_SCENE.instantiate() as Node2D
		portrait.name = "Monster"
		clip.get_node("PortraitAnchor").add_child(portrait)
		_portraits.append(portrait)


func configure(catalog: Object) -> bool:
	$Empty.texture.atlas = catalog.load_sprite("common/ui_name/frame-003")
	var icons: Texture2D = catalog.load_window_frame(7)
	for icon in [$Occupied/LevelCaption, $Occupied/TimeCaption, $Occupied/TimeUnit]:
		icon.texture.atlas = icons
	$Occupied/Trait.texture.atlas = catalog.load_sprite("common/ui_battle/frame-000")
	var success: bool = $Empty.texture.atlas != null and icons != null and $Occupied/Trait.texture.atlas != null
	for number in [$Occupied/Level, $Occupied/Party0, $Occupied/Party1, $Occupied/Party2, $Occupied/Time]:
		if not number.configure(catalog):
			success = false
	var gameplay: GameplayData = catalog.load_gameplay_catalog()
	if gameplay == null:
		push_error("Prime slot portraits need the gameplay catalog.")
		return false
	for monster: MonsterDefinition in gameplay.monsters:
		_portrait_positions[monster.id] = monster.prime_portrait_position
	return success


func present(occupied: bool, active: bool, card: Dictionary, progress: Dictionary) -> void:
	$Panel.border_color = SELECTED_BORDER if active else IDLE_BORDER
	$Panel.border_width = 2 if active else 1
	$Panel.background_color = SELECTED_BACKGROUND if active else Color.BLACK
	material.set_shader_parameter("grayscale", not active)
	$Selection.visible = true
	_present_selection(0 if active else 1)
	$Empty.visible = not occupied
	$Occupied.visible = occupied and not card.is_empty()
	for index in range(PORTRAIT_COUNT):
		_backings[index].visible = occupied
		_clips[index].visible = false
	if not $Occupied.visible:
		return
	$Occupied/Heading.text = card.heading
	$Occupied/Heading.color = Color.WHITE if active else Color("#B3B3B3")
	$Occupied/Trait.texture.region.position.x = $Occupied/Trait.texture.region.size.x * card.trait
	$Occupied/Level.present("%02d" % card.level, 0 if active else 1)
	var members := MenuModel.native_party_order(progress)
	for member in range(PORTRAIT_COUNT):
		var level := 0
		if member < members.size() and int(members[member]) >= 0:
			var monster: Dictionary = progress.monsters[int(members[member])]
			level = int(monster.level)
			_present_portrait(member, monster, active)
		get_node("Occupied/Party%d" % member).present("%02d" % level, 0 if active else 1)
	$Occupied/Time.visible = progress.has("playedTimeMs")
	if $Occupied/Time.visible:
		var seconds := int(progress.playedTimeMs / 1000)
		$Occupied/Time.present("%02d.%02d.%02d" % [int(seconds / 3600), int(seconds / 60) % 60, seconds % 60],
			0 if active else 1)


func release_portraits() -> void:
	for portrait in _portraits:
		portrait.clear()
	for clip in _clips:
		clip.visible = false


func _present_selection(action: int) -> void:
	var player: AnimationPlayer = $Selection.get_node("AnimationPlayer")
	var name := AniAction.clip_name(player, action)
	if player.current_animation != name:
		player.play(name)


func _present_portrait(member: int, monster: Dictionary, active: bool) -> void:
	var species := int(monster.species)
	var basic_species := species % 1000
	var path := "mon2/m_b_%03d_%d" % [basic_species, 2 if species > 999 else 1]
	var portrait: Node2D = _portraits[member]
	if not _portrait_positions.has(basic_species):
		push_error("Prime slot portrait has no native origin: %d" % basic_species)
		return
	if not portrait.present(path, 0, 1):
		push_error("Prime slot portrait is unavailable: %s" % path)
		return
	var position: int = _portrait_positions[basic_species]
	portrait.position = Vector2(-int(position / 100), absi(position) % 100)
	portrait.set_running(active, not active)
	portrait.set_grayscale(not active)
	_clips[member].visible = true
