extends Control
## 技能横幅：原生 `Battle_Skill_mPaint` 的移植。
##
## 技能态（`Battle_Skill_*`）期间，原生先 `Battle_mapDraw(0)` 画底图与战斗对象，再叠一条
## 半透明黑带（`JC_grpSetRESERVE` 存剪裁 → `JC_grpSetMODE(GRP_MODE_ALPHA, 128)` →
## `JC_grpSetRGB(0)` → `JC_grpFillRECT`），在黑带上写技能名（白字，左右各一个 8×8 装饰），
## 最后把施术者的精灵 `Object_drawBASIC` 画在黑带右侧（敌方镜像到左侧）。普攻
## （`Battle_Attack_mPaint`）没有这一段，所以横幅只在技能行动里出现。
##
## 三张按帧取值的表都在 `Battle_Skill_mPaint` 里按 `phase` 索引（`phase` 由
## `run_counter - 2` 折算，见 `phase_for_step()`）。表本身是 .so 里 `0x97C8C + 0x5c` 起的
## 32 字节常量区：前 8 字节与后 8 字节是按帧的**有符号字节**数组（反编译成
## `v20[0]=640167938`／`v20[1]=36057126`、`v19[0]=84095333`／`v19[1]=-1661923572` 这种
## 立即数），中间 16 字节是 int16[8] 的文字横向偏移（`v16` 由四句 `ldm`/`ldr` 从该区拷出）。

const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const UI_THEME = preload("res://engine/ui/native_label/ui_theme.tres")

## `JC_grpSetMODE(GRP_MODE_ALPHA, 128)`：`JC_grpSetMODE` 的 alpha 分量是按 256 计的
## （`PixelData.mode_*_component_256`），128 ⇒ 50% 黑。
const ALPHA_VALUE := 128
const ALPHA_SCALE := 256.0

## `JC_grpSetRESERVE(0, 63 - 高度 / 2, 视口宽, 高度)`：横带的竖直中心行。
const BAND_CENTER_Y := 63

## 横带高度（`v20` 的 8 个有符号字节，解包算式：四字节小端 = 低地址那帧，
## `640167938 = 0x26283002` → `[2, 48, 40, 38]`，`36057126 = 0x02263026` → `[38, 48, 38, 2]`）。
const BAND_HEIGHTS: Array[int] = [2, 48, 40, 38, 38, 48, 38, 2]

## 施术者精灵的横向偏移（`v19` 的 8 个有符号字节）；使用时再加 `PORTRAIT_OFFSET_BASE`。
const PORTRAIT_OFFSETS: Array[int] = [101, 49, 3, 5, 12, 15, -15, -100]
const PORTRAIT_OFFSET_BASE := 48

## 技能名中心的横向偏移（`v16`，`0x97C8C + 0x64` 的 int16[8]）。
const TEXT_OFFSETS: Array[int] = [-200, -130, -50, -47, -47, -47, -47, -200]

## 两侧 8×8 装饰到技能名边缘的距离（`x ∓ (文字宽 / 2 + 10)`）。
const DECORATION_GAP := 10

## 横幅立绘的原生 `animation_id`：`Object_drawBASIC(x, y, 朝向, 对象类型, 资源 id, 107, 0, 0)`。
## 战斗怪物（对象类型 12）的动作号由 `Battle_Monster_procAction` 折算，`107` 走它的 default
## 分支 ⇒ `Object_procACTION` 返回 `animation_id % 100` = **7**，即该单位自己那份 ANI 的
## 动作 7、第 0 帧。`Object_procFRONT` 只在「动作数 <= 7」时才放弃取帧，所以 107 不是无效值。
const PORTRAIT_ANIMATION_ID := 107

## `phase` 从 `step - 2` 折算：`step - 2 > 2` 时先夹到 `HOLD_PHASE`（`run_counter - 2` 落在
## 3..9 的那一段），超过 `HOLD_END` 才按 `step - CLOSE_PHASE_OFFSET` 逐帧收带。
const PHASE_OFFSET := 2
const HOLD_THRESHOLD := 2
const HOLD_END := 9
const HOLD_PHASE := 3
const CLOSE_PHASE_OFFSET := 8
const LAST_PHASE := 7

var _portrait_key := ""


func _ready() -> void:
	clear()


## 原生那条 `Battle_objFIND(...) == 0` 与「`phase > 7` 直接 return」两种情况下都不画横幅。
func clear() -> void:
	visible = false


## 按时间轴步号折算原生 `phase`；返回 -1 表示原生这一帧不画横幅（`run_counter >= 16`）。
static func phase_for_step(step: int) -> int:
	var phase: int
	if step - PHASE_OFFSET > HOLD_THRESHOLD:
		phase = HOLD_PHASE if step - PHASE_OFFSET <= HOLD_END else step - CLOSE_PHASE_OFFSET
	elif step - PHASE_OFFSET < 0:
		phase = 0
	else:
		phase = step - PHASE_OFFSET
	return phase if phase <= LAST_PHASE else -1


## 技能步上显示横幅：`ball` 是施术者，`step` 是本次行动的时间轴步号（一步 = 原生一帧），
## `skill_name` 是该物种当前技能的第一行文本（`Ball_datBasic` 的 `detail_text`，
## 原生用 `JC_fntCHANGE(47 -> 10)` 把 `/` 换成换行后用 `JC_fntGetPage(…, 0, 1, 1)` 只取第一行）。
func show_skill(ball: Dictionary, step: int, skill_name: String) -> bool:
	var phase := phase_for_step(step)
	if phase < 0:
		clear()
		return false
	visible = true
	_apply(phase, ball, skill_name)
	return true


func _apply(phase: int, ball: Dictionary, skill_name: String) -> void:
	var band: ColorRect = $Band
	var height := BAND_HEIGHTS[phase]
	band.position = Vector2(0, BAND_CENTER_Y - height / 2)
	band.size = Vector2(size.x, height)
	band.modulate.a = float(ALPHA_VALUE) / ALPHA_SCALE
	# 原生 `v13 = *(obj + 52) == 2 ? -1 : 1` 与 `x = (立绘偏移 + 48) * v13 + 视口宽 / 2`：
	# 我方画在右半边、敌方镜像到左半边。本工程的 `ball.direction` 是 1（我方）/ 0（敌方）
	# （`battle_view._next()`），所以「非我方 ⇒ -1」与原生「`== 2` ⇒ -1」等价；文字与装饰
	# 用同一个系数，所以两半边的整条横幅是镜像的。
	var mirror := -1 if int(ball.get("direction", BattleSide.Code.ENEMY)) != BattleSide.Code.PLAYER else 1
	var center_x := int(size.x / 2.0)
	var text_center := Vector2(center_x + mirror * TEXT_OFFSETS[phase], BAND_CENTER_Y)
	var width := _name_width(skill_name)
	var label: Control = $Name
	label.text = skill_name
	label.size = Vector2(width, label.size.y)
	label.position = Vector2(text_center.x - width / 2.0, text_center.y - label.size.y / 2.0)
	var gap := width / 2.0 + DECORATION_GAP
	_place_decoration($DecoLeft, Vector2(text_center.x - gap, text_center.y))
	_place_decoration($DecoRight, Vector2(text_center.x + gap, text_center.y))
	var clip: Control = $Clip
	clip.position = band.position
	clip.size = band.size
	_present_portrait(ball, Vector2(center_x + mirror * (PORTRAIT_OFFSETS[phase] + PORTRAIT_OFFSET_BASE),
		BAND_CENTER_Y))


## 8×8 装饰按 `GRP_IMAGE_ANCHOR_MIDDLE_CENTER` 摆：`JC_grpGetANCHOR(…, 8, 8, MIDDLE_CENTER)` 把
## 矩形左上角放在中心减半个 8×8。
func _place_decoration(node: TextureRect, center: Vector2) -> void:
	node.position = center - node.size / 2.0


## 原生的立绘是 `Object_drawBASIC(x, y, 朝向, 对象类型, 资源 id, 107, 0, 0)`：`107` 是
## `Object_objANI` 的 animation_id，经 `Battle_Monster_procAction` 的 default 分支
## （`107 % 100`）落到该 ANI 的**动作 7、第 0 帧**——动作 7 没有语义证据，保持纯数字；
## 该 ANI 若只有 7 个动作（`Object_procFRONT` 的 `动作数 <= 动作号` 那支），原生画空，
## 这里回退到技能动作，保证横幅里始终有一张立绘。
func _present_portrait(ball: Dictionary, at: Vector2) -> void:
	var portrait: Node2D = $Clip/Portrait
	var identity := MonsterAnimation.battle_identity(int(ball.get("species", 0)))
	var direction := int(ball.get("direction", BattleSide.Code.ENEMY))
	var action := AniAction.action_of(PORTRAIT_ANIMATION_ID)
	var key := "%s/%d/%d" % [identity, action, direction]
	if key != _portrait_key:
		_portrait_key = key
		if not portrait.present(identity, action, direction, false, false, AniAction.Clip.SKILL):
			portrait.visible = false
			return
		portrait.visible = true
		portrait.set_running(false)
		portrait.seek_frame(0)
	# 原生把这帧画进黑带的剪裁区（只露脸的一条）；Node2D 立绘在 Field 的兄弟节点里
	# 无法可靠被 Control 的 clip_contents 剪掉（会整只盖到战场上），所以改成按当前
	# 带高整体缩放并居中——带展开／收拢时立绘跟着长大／缩小，不再溢出横带。
	var art: Rect2 = portrait.bounds()
	var available := maxf($Band.size.y - 2.0, 1.0)
	var factor := minf(1.0, available / maxf(art.size.y, 1.0))
	portrait.scale = Vector2.ONE * factor
	var target: Vector2 = at - $Clip.position
	portrait.position = target - (art.position + art.size / 2.0) * factor


## 原生 `JC_fntGetWIDTH(&text_slot_)`：`JC_fntGetSPACE` 遇到第一个换行就把宽度截住，
## 而技能文本在 `JC_fntCHANGE` 之后第一行就是技能名，所以这里只量第一行。
func _name_width(text: String) -> float:
	var layout := TextLayout.layout(text, UI_THEME.default_font, UI_THEME.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return 0.0
	return float(layout.lines[0].width)
