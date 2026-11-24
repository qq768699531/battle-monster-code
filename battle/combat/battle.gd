extends RefCounted
class_name BattleModel
## Battle60 战斗模型（纯逻辑）：出战队伍、行动、伤害与胜负判定。
## 不持有任何视图；界面由 battle_view 消费这里的结果。

const Passives = preload("res://battle/passives/passives.gd")

## 战斗里真正会被读到的被动效果编号。原生把效果号当 `extended_state + 468 + 编号` 的字节下标
## （`Param_passiveSet` 一次写 66 字节），读取点：
##   `Param_atk1PASSIVE`（普攻加成）：0／1 = 目标属性 0／1、2 = 自身 HP < 30%、
##   3 = 连击（`passives[3] + extended_state[537] − 1`，门见下，537 无写点恒不生效）；
##   `Param_atk2PASSIVE`（技能加成）：4／5 = 目标属性 0／1、6 = 自身 HP < 30%、
##   7 = 连击（同 3，门是 537）；
##   `Param_def1PASSIVE`（普攻防守）：12／13 = 攻击方属性 0／1、14 = 我方属性被克、
##   15 = 自身 HP < 30%；
##   `Param_def2PASSIVE`（技能防守）：16／17／18／19 同上；
##   `Param_dmg1PASSIVE`（命中附状态与抗性）：25–29 依次附状态 27／38／9／7／8，
##   48／49／50／53／54 是这五个状态的抗性（抵抗时把状态反弹回攻击者）；
##   暴击 8／9／10／11、暴击倍率 60、封印抗性 53、经验 23、金钱 61、逃跑 63、HP 上限 20、
##   逃跑 63、HP 上限 20、SP 上限 22 由本模型直接读（明细见各函数）。
## `Param_dmg1PASSIVE` 的 25–29（附状态）与 48／49／50／53／54（这五个状态的抗性／反弹）
## 也已经在 `_passive_status` 里读；该函数顺带把「哪几只的被动这次发动了」带进命中结果
## （`activated_passives`，原生 `Param_dmg1PASSIVE` 的两组 `Param_atkPASSIVE` 调用），
## 提示栈的 556「发动」由界面按这份名单推。
## 曾按未接通用 `support_error()` 挡住、挂在 `bm-P0-9`（已闭环）上的 9 个残留编号
## 已逐个处置：3／7 按该条的判定**不建模**（门 `extended_state[537] != 0` 恒不成立，537 全库无写入点，
## 见 `wiki\battle\passive-residue.md` §2.1／§2.2）；21 是 `ItemEffect` 的 `FEEL_PASSIVE`、57 是
## `POISON_HEAL_PASSIVE`、59 是 `PRIORITY_PASSIVE`、64 是 `SKILL_BACKOFF_PASSIVE`，46／51／52 是
## `_skill_status_hit` 的 `SKILL_REFLECT_PASSIVES`。因此 `SUPPORTED_PASSIVE_EFFECTS` 现覆盖 0–65
## 全表，`support_error()` 的被动闸不再挡住任何编号。
## 普攻侧的 30（吸血）／31／32／33（无效化）／35／36（被打后立即反击）／37／38／39（必杀）／
## 47（必杀反噬）／55（反吸血）由 `_physical_passives` 读，技能侧的 34（相性不利闪避）与 40–45
## （按攻击方属性的六档免疫）由 `_skill_passives` 读；46／51／52 是技能附状态时「受方掷中就把这条
## 状态改附给施术者」的反弹，在 `_skill_status_hit` 里读（`Param_dmg2SKILL`）；
## 56／62 是战後结算（回 HP／回满 SP）、
## 65 是行动后不减速、59 是开场抢在所有人之前行动（`Battle_Ready_Set`，见 `PRIORITY_PASSIVE`）。
## 64 是 `Battle_Delay_init` 的 `0x34dfe`：技能这一手把 `ext[536]` 写成目标组
## （见 `AiTargetGroup`），被动掷中就把刚写的清回 0，对应球的 `ai_target_group`。
## 3／7 是**已确证的空操作**：门是 `extended_state[537] != 0`（`Param_atk1PASSIVE` 的
## `0x79654`、`Param_atk2PASSIVE` 的 `0x78e08`），而 `537`（`=0x219`）全库只有这两条读，
## 没有任何写点；对象创建 `Object_sttCreate` 对 544 字节的 `extended_state` 池块按 `0x220`
## `memset` 清零。出货二进制里这两支永远进不去，所以按「不支持＝空操作」放行，不实现
## `passives[3] + ext[537] − 1` 那条公式（本工程也没有连击段这个状态）。21 与 57 见各自的常量。
const SUPPORTED_PASSIVE_EFFECTS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
	17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
	40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
	63, 64, 65]
## 原生 `Param_dmg1PASSIVE`（由 `Param_dmgBASIC1` 在满命中时调用）：
## 按 25 → 26 → 27 → 28 → 29 依次掷攻击方被动，第一个命中的给目标附上对应状态——
## 25 → 中毒 27、26 → 减速 38、27 → 状态 9、28 → 封印 7、29 → 状态 8；目标的被动
## 48／49／50／53／54 掷中时把状态**反弹回攻击者**。入口条件里还有一条
## `PINFO[目标][1] >= 目标 HP` 就直接返回——`PINFO[1]` 就是 `Param_dmg1BASIC` 刚算出的
## 本次伤害，所以「一击必杀时不附状态」。
const INFLICT_PASSIVES := [[25, 27, 48], [26, 38, 49], [27, 9, 50], [28, 7, 53], [29, 8, 54]]
## 命中带状态、而且本工程已经建模的状态码：其余状态码的生效方式属于主动效果槽
## （`Param_activeSet`），现在按普通伤害结算；槽规则与写入点见已闭环的 `bm-P1-8`。
## 原生 `Param_dmg2SKILL` 的 `switch` 里，1、6、7、9–32 与 38–40 这几支**不兑现伤害**，
## 所以它们走「只施加状态」的分支：1（槽 1）、6（槽 6）、7、攻／防／受伤／中毒加成的 9–32、
## 减速度 38–40。35（全清）、36／37（`LABEL_21` 会打伤害并反伤自己）等分支
## 本工程未建模，仍按普通伤害结算（建模范围与「不建模」理由见已闭环的 `bm-P1-8`）。
## 注 1／6 确实一点伤害都不打——伤害在这条链上是「先预算、后按命中帧兑现」两段：
##   `Battle_Skill_init`（`0x349BC` 的同型循环）只调 `Param_dmg2BASIC`，
##   而它只写 `PINFO[1..4]`（`0x78ffc`／`0x78ffe`／`0x79000`／`0x79010`–`0x79034`），
##   从不调 `Param_dmgBASIC`／`Param_dmgNUMBER`，所以那时只是「算出池子」；
##   真正扣血只有 `Param_dmgBASIC` 的 `Param_dmgNUMBER`（`0x79f88`），调用点只有三处：
##   `0x7a04a`（`Param_dmgBASIC2`）、`0x7a5f0`（`LABEL_76`，`n100` 恒 0）、
##   `0x7a93c`（普攻的 `Param_dmgBASIC1`）；而 `Param_dmgBASIC2` 只被 `0x7a1a4`／`0x7a1ba`
##   （`LABEL_20`／`LABEL_21`）调用。`case 1`（`0x7a228`–`0x7a25e`／`0x7a6ac`）与
##   `case 6`（`0x7a348`–`0x7a380`／`0x7a6c6`）附完状态就 `break`，两头都不到，
##   所以它们的前置门 `if (v8[2] <= 0)` 读的是「预算出的池子」——池子为 0（被闪避／无效化）
##   才连状态一起跳过，池子 > 0 也只附状态、不扣血。
##   两支的其余副作用只有 `Param_atkPASSIVE(受方, 0, 46／52)` 的「被动发动」提示（纯显示）。
const MODELED_STATUS := [1, 6, StatusEffect.Code.SEAL, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
	19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 35, 38, 39, 40]
## 技能码 1 的受方反弹被动：`Param_dmg2SKILL` 的 `case 1` 掷受方 `ext[514]`（`0x7a23e`）。
const REFLECT_SKILL_1_PASSIVE := 46
## 技能码 6 的受方反弹被动：同函数的 `case 6` 掷受方 `ext[520]`（`0x7a360`）。
const REFLECT_SKILL_6_PASSIVE := 52
## 技能码 24／25／26 的受方反弹被动：同函数的 `case 0x18／0x19／0x1A` 掷受方 `ext[519]`
## （`0x7a436`）。
const REFLECT_SKILL_18_PASSIVE := 51
## 原生 `Param_dmg2SKILL` 的「受方掷中就把这条状态改附给施术者」三支，键是技能码：
##   1 → `case 1`（附 active 12）；6 → `case 6`（附封印 7）；24／25／26 → `case 0x18／0x19／0x1A`
##   （附 active 34）。没有被动的受方，或者掷不中，照常附给受方。
const SKILL_REFLECT_PASSIVES := {1: REFLECT_SKILL_1_PASSIVE, 6: REFLECT_SKILL_6_PASSIVE,
	24: REFLECT_SKILL_18_PASSIVE, 25: REFLECT_SKILL_18_PASSIVE, 26: REFLECT_SKILL_18_PASSIVE}
## 状态码 38／39／40（原生 `Param_dmg2SKILL` 的 `case 0x26…0x28`）：不打伤害，按 30／50／70
## 减一次速度（`Ball_stdSPEED(ball, 0, -v)`）。48–54 这一族的抗性／反弹分在
## `_passive_status` 的 `INFLICT_PASSIVES`（48／49／50／53／54，普攻侧的 26 → 减速 38 就是其中一支）
## 与 `_skill_status_hit` 的 `SKILL_REFLECT_PASSIVES`（46／51／52），这里只管减速本身。
const SLOW_CODES := [38, 39, 40]
const SLOW_VALUES := [30, 50, 70]
## 状态码 35（原生 `case 0x23`）：不打伤害，把**目标**的这 17 个槽清空（毒 27–29、6、8、1、
## 护盾 9–11、回复 2–5、封印 7、减伤 24–26），随后给槽 0 写一条「持续 29」的计数。
## 槽 0 的消费者没定位到（它紧挨着 `cooldown`），所以这里只做清槽。
const CLEAR_STATUS := 35
const CLEAR_CODES := [27, 28, 29, 6, 8, 1, 9, 10, 11, 2, 3, 4, 5, 7, 24, 25, 26]
## 状态码 36／37／49（原生 `case 0x24／0x25／0x31`）：`Param_dmgBASIC2(目标, |percent|, n20)`，
## 伤害是**目标当前 HP 的百分比**；只要攻击方 HP 非 0 就按同一数值再打自己一次（`LABEL_21` 第二支）。
## 49 会先把目标的 `direction_code` 翻转。判定用的暴击倍率同 `Param_atk2CRITICAL`，本模型不叠暴击。
const PERCENT_HP_CODES := [36, 37, 49]
const FLIP_DIRECTION := 49
## `Param_dmgPOISON` 的等级 → 百分比表（行 = 三段槽 27／28／29，列 = |槽 id| 1／2／3）：
## 第一段 10／30／50、第二段 20／40／60、第三段 20／40／70。
const POISON_PERCENT := [[10, 30, 50], [20, 40, 60], [20, 40, 70]]
## `Param_def1ACTIVE`／`Param_def2ACTIVE` 里「按 |槽 id| 查表」的两张 rodata：
## 槽 18／19／20 是**加受伤**（`0x643F4C00` → 0／76／63／100%），槽 24／25／26 是**减受伤**
## （`0x1E140100`／`0x28210200`／`0x322A0400` → 0／1／20／30、0／2／33／40、0／4／42／50%）。
const TAKEN_UP_TABLE := [0, 76, 63, 100]
const TAKEN_DOWN_TABLE := [[0, 1, 20, 30], [0, 2, 33, 40], [0, 4, 42, 50]]
## `Param_dmgFREEZE`：挨打时一次性清掉的槽——回复 2–5、护盾 9／10／11、减伤 24／25／26、
## 防御 33。回复槽 2–5 在清掉之前还会按下面的百分比把 HP 抬高（`50／100／150／200 × 层数`）。
const FROZEN_SLOTS := [2, 3, 4, 5, 9, 10, 11, 24, 25, 26, StatusEffect.Code.DEFENCE]
const REGEN_PERCENT := {2: 50, 3: 100, 4: 150, 5: 200}
## 复活道具：`Battle_Die_init` 用 `Item_fndCount(ITEM_KIND_UNKNOWN_7, 23)` 判有没有
## （第 7 组第 23 号，`item_basic.group.7.entry.23.name`＝妖姬之眼）。
const REVIVE_ITEM_GROUP := ItemKind.Kind.GROUP_7
const REVIVE_ITEM_INDEX := 23

## 觉醒后的物种号偏移：`Ball_stdFeel` 的 `definition_id = definition_id % 1000 + 1000`，
## 结算经验翻倍、捕获率 ÷8、菜单名字描黄都按「物种号 > 999」判觉醒。
## 道具效果本身（含觉醒）的分派在 `ItemEffect`（`Ball_stdUse`），两处共用一份规则。
const AWAKENED_SPECIES_OFFSET := 1000
## 被动 57（`extended_state + 525`）：`Battle_Poison_init` 的 `0x385d6` 读 `ext[525]`，
## `v3 > 0` 时先 `Ball_stdHP(球, 0, v3)`（`Ball_stdHP`：`hp += 0 + 上限 × v3 / 100`，夹到 `[0, 上限]`），
## 之后才 `Param_dmgPOISON(球)` 结算毒伤——所以是毒回合先回血再掉血。
const POISON_HEAL_PASSIVE := 57
## 被动 59（`extended_state + 527`）：`Battle_Ready_Set` 开场逐只掷
## `rand()%100 < passives[59]`（`0x33126`／`0x33178`），命中就把自己的 `ext[539]` 写成 100
## （`0x331ac`／`0x331dc`）并把 `obj+264` 写成对方阵营的随机序号（`0x331c4`／`0x331f2`）。
## 两条阵营链共用一个「上一只命中者」寄存器，后命中的会把它清 0（`0x331d2`／`0x33200`），
## 所以整场只有最后一只保留先手。
const PRIORITY_PASSIVE := 59
## `ext[539]` 的「抢在所有人之前行动」标志值（`Battle_Ready_Set` 写的 100）。
const PRIORITY_BOOST := 100
## `Battle_Character_init` 的行动值 `100000 × ext[539] + speed(u16@+24)`
## （`0x353ee`／`0x353f4`／`0x3557c`），所以 539 非 0 的球一定排在所有人前面。
const PRIORITY_WEIGHT := 100000
## 被动 36 叠加进 `ext[539]` 时的上限（`Param_dmg1BASIC` 的 `0x79ab0`：相加超过 255 写 −1）。
const PRIORITY_LIMIT := 255
## 被动 35（`extended_state + 503` = `ext + 468 + 35`）／36（`+504`）：受方被普攻打中后把**自己**的
## `ext[539]` 置成 35 的值、`obj+264` 指向攻击方（`0x79938`）；相性不利时再把 36 加上去（`0x79ab0`）。
## 于是下一回合它抢先行动、这一击锁定那个攻击方，伤害按 `539%` 结算——是「立即反击」，
## 不是「蓄力缩放自己下一次出手」。
const COUNTER_PRIORITY_PASSIVE := 35
const COUNTER_DISADVANTAGE_PASSIVE := 36
## `Param_attrStrength` 的三档返回值（1 有利、−1 不利、0 无关）在 `CSWTCH.95_0` 里各占一列，
## 表项是 0／1：普攻 `Param_dmg1BASIC:68-69` 取到的两列**只当闸门**（有利才掷攻击方被动 39、
## 不利才掷受方被动 33／36），不参与伤害算术；技能的 `Param_dmg2BASIC:98-105` 才按同一张表
## 缩放伤害——有利用 `+40%`、不利用 `−60%`。逐行取证见 `wiki\battle\battle-field.md`「普攻的相性倍率」。
const SKILL_ADVANTAGE_DAMAGE_PERCENT := 40
const SKILL_DISADVANTAGE_DAMAGE_PERCENT := 60
## 相性有利时暴击率多加的百分点（`Param_atk1CRITICAL:31`／`Param_atk2CRITICAL:27`：
## `n5 = 10 × 该列 + 20／30`，该列就是 `CSWTCH.95_0` 的有利标志）。
const ADVANTAGE_CRITICAL_PERCENT := 10
## 出战槽位布局：0–2 敌方、3–5 我方（原生 `Battle_objFIND` 的 0–5 槽；敌方链在 `+20654`、
## 我方链在 `+20650`，所以两边的指定目标基址正好相反）。
const ENEMY_SLOTS := 3
## 「没有指定目标」，对应原生 `obj+264` 只在 `ext[539] != 0` 时才被读取的空位。
const NO_TARGET := -1
## 原生 `extended_state[536]`：AI 这一手技能用掉的目标组，非 0 时 `Battle_Menu_Auto`
## 不再选技能（`0x30eaa` 与函数末尾同型的那处判断）、只打普攻。写入点在
## `Battle_Delay_init`：本回合是技能（`+20668 == 2`）时取
## `Battle_Monster_procTarget(obj, 2) & 0x60`，`0x20` 写 1（`0x34e16`）、`0x40` 写 2（`0x34de8`）；
## `Battle_Delay_Proc` 每次出手自减（`0x34b22`），`Battle_Die_Revival` 复活时清 0
## （`0x31bfe`）。两档对应的就是 `Battle_Skill_init` 里那两支：`& 0x60 == 0x20` 只对
## `BattleData + 20676` 那只结算一次，`== 0x40` 按 `+20706` 的个数逐个 `Param_dmg2BASIC`——
## 即单体技能之后补 1 手普攻、全体技能之后补 2 手。
enum AiTargetGroup {
	NONE = 0,
	SINGLE = 1,
	ALL = 2,
}
## 被动 64（`extended_state + 532`）：`Battle_Delay_init` 的技能那一支里掷
## `rand()%100 < passives[64]`（`0x34dfe`），命中就把同一支刚写的 `ext[536]` 清回 0
## （`0x34e20`）——「这一手技能不用补普攻」，AI 因此可以连着放技能。
const SKILL_BACKOFF_PASSIVE := 64
## 原生 `Ball_stdSet` 建记录时把 `brain_limit`（+0x2C）写死 99，`brain_current`（+0x2B）
## 由调用方给：事件 `Evt_stdPROC` 的 0x1F 传 0，驯化 `Game_Monster_Enchant_Proc`
## 成功时 +1、失败时把上限压到当前值（`Ball_stdBrain`）。`Ball_stdBasic` 的
## 六项数值里每一处 `level + brain_current` 都含它。
const BRAIN_LIMIT := 99
const BRAIN_CURRENT_INITIAL := 0

## 性格（原生 `nickname_code` 0..6）对六项能力的 ±1 偏置表，逐字节等于
## `Ball_stdNickAbils` 的 42 字节表（行＝性格、列＝atk1／def1／atk2／def2／HP／速度）。
## 基础值在 `make_ball` 里进 `Ball_stdBasic`（`2 × (… ± 1 + 觉醒)`），伤害那一侧
## 由 `effective_stat` 按 `Param_atk1DAMAGE` 一族补 `偏置 × 值 / 20`。
const NICKNAMES := [
	[0, 0, 0, 0, 0, 0], [1, -1, 0, 0, 0, 0], [-1, 1, 0, 0, 0, 0],
	[0, 0, 1, -1, 0, 0], [0, 0, -1, 1, 0, 0], [0, 0, 0, 0, -1, 1],
	[0, 0, 0, 0, 1, -1],
]
## 「性格未指定」：`Ball_stdSet` 建记录时对最后一个实参 `nickname_code` 只有两种处理
## ——`nickname_code >= 0` 就照抄写进记录，否则写 `EFC_mainGetRAND() % 7`。所以原生记录里
## **永远不会留负数**，-1 只表示「让 Ball_stdSet 自己掷」。事件建怪 `Evt_stdPROC`
## 的 0x1F 就是传 -1（调用点 `0x7ED80`）。
## 越界正数（7..127）原生不夹取、照原样存进记录，由消费者各自回落：`Ball_stdNickAbils` 行 18
## 按 `n6 <= 6 ? n6 : 0` 取**第 0 行**（六项全 0，不是夹到 6），`Ball_stdNickText` 行 17-21
## 按 `n6 > 6` 返回空串（不显示性格名）。取值统一走 `nickname_bias_row`，越界值不在 `make_ball` 里被修正。
const NICKNAME_UNSPECIFIED := -1


## 原生 `EFC_mainGetRAND() % 7`：缺记录时掷一个合法性格号（行数就是 `NICKNAMES` 的 7 行）。
static func roll_nickname(roll: Callable) -> int:
	return int(roll.call(NICKNAMES.size()))


## `native_arguments` 就是 `Ball_stdSet` 的十项构造实参（`make_ball` 的 `args` 逐项拆开）：
## `+6` 是标准被动号（被动槽 0 的 `definition_id`）、`+7` 是它的等级。
## 原生 `Param_atkPASSIVE` 的「被动发动」提示要用这个号查被动记录名（`Item_datBasic` 类型 31
## 的 `name_text`，正文在 `common/item_skill.dat` 的 `item_skill.group.<号>.name`）。
const ARGUMENT_PASSIVE_ID := 6
const ARGUMENT_PASSIVE_LEVEL := 7


## 这只球的被动记录号（`Param_passiveSet` 写 66 字节效果表时读的就是它）。
## 被动等级为 0（没有被动）时仍是记录号，调用方自己按需要判空。
static func passive_id_of(ball: Dictionary) -> int:
	return int(ball.native_arguments[ARGUMENT_PASSIVE_ID])


## `Ball_stdSet` 的缺省规则（行 36-39：`nickname_code >= 0` 照抄、否则写 `EFC_mainGetRAND() % 7`）：
## 负值由建记录的人自己掷，落到球上的值因此恒 >= 0。构造方（野外降级球、事件建怪、脚本战斗、
## 公会战）都从这里取，不要直接写 -1 穿过 `make_ball`。
static func nickname_or_roll(nickname: int, roll: Callable) -> int:
	return nickname if nickname >= 0 else roll_nickname(roll)


## 性格偏置的取值（原生 `Ball_stdNickAbils` 行 18）：`*((char *)v3 + 6 * (n6 <= 6 ? n6 : 0) + n5)`。
## `n6` 在原生是无符号，越界正数（7..127）与负数都落到**第 0 行**（六项全 0），不是夹到末行。
## 负数本不该出现在已建好的球上（`Ball_stdSet` 只写 0..6），构造方用 `nickname_or_roll` 先掷。
static func nickname_bias_row(nickname: int) -> Array:
	return NICKNAMES[nickname if nickname >= 0 and nickname < NICKNAMES.size() else 0]


## 每个物种的动作分段（`animation_id` 序列、命中帧、分身）来自
## `game\assets\battle-species.tres`，由 `script\export_battle_species.py` 从
## `Battle_Monster_00NN_procCurr`／`_procNext`／`_procSkill` 导出；模型这边不再按物种写死。

var balls: Array[Dictionary] = []
var actor := -1
var result: Variant = null
var turns := 0
var log: Array[String] = []
var _random: Callable
var unavailable := ""
var allow_flee := false
var hero_level := 0
## 捕获需要的主角参数（原生 `ParamData.ability_values[2]`、`preferred_mastery_index`）与
## `standard_progress` 换算出的等级（`Param_stdSET`）。`standard_level < 0` 表示未记录。
var hero_ability := 0
var preferred_mastery := -1
var standard_level := 0
## 觉醒（`Ball_stdFeel`）要用 `Ball_stdBasic` 按新物种重算六项数值与上限，
## 模型自己不带物种表：由构造方注入（`wild_encounters.battle_entry`／脚本战斗／公会战）。
var catalog: GameplayData = null


## `Ball_stdPassive` 的槽表：0–5 号槽各一对「被动号、等级」，等级 0 是空槽。
## 记录里没有存过槽（旧存档）时，按构造参数的 `passive_id`／`passive_level` 落到 0 号槽。
static func passive_slot_table(args: Array, slots: Array) -> Array:
	var complete := slots.size() == ItemEffect.PASSIVE_SLOT_COUNT
	for entry: Variant in slots if complete else []:
		if not entry is Array or entry.size() != 2 or not entry.all(
				func(value: Variant) -> bool: return value is int):
			complete = false
			break
	if complete:
		var stored: Array = []
		for entry: Array in slots:
			stored.append([int(entry[0]), int(entry[1])])
		return stored
	var table: Array = [[int(args[ARGUMENT_PASSIVE_ID]), int(args[ARGUMENT_PASSIVE_LEVEL])]]
	for _slot: int in range(1, ItemEffect.PASSIVE_SLOT_COUNT):
		table.append([0, 0])
	return table


## `Param_passiveSet`：把 0–5 槽重算成 66 项效果表，只算等级 > 0 的槽，同效果累加。
static func make_ball(catalog: GameplayData, args: Array, nickname: int,
		passive_slots: Array = []) -> Dictionary:
	assert(args.size() == 10 and args.all(func(value: Variant) -> bool: return value is int))
	assert(passive_slots.is_empty() or passive_slots.size() == ItemEffect.PASSIVE_SLOT_COUNT)
	# 原生对 `nickname_code` 是「照存 + 消费方回落」（`Ball_stdNickAbils` 越界取第 0 行、
	# `Ball_stdNickText` 越界返回空串），所以越界正数照存不报错。负值本该由 `Ball_stdSet`
	# 换成掷出的 0..6（`nickname_or_roll`），走到这里说明构造方漏了那一步：回落第 0 行并报一次错。
	if nickname < 0:
		push_error("个体性格 %d 非法：Ball_stdSet 只写 0..%d，缺省 %d 应先经 Battle.nickname_or_roll 掷；按 Ball_stdNickAbils 回落第 0 行" %
			[nickname, NICKNAMES.size() - 1, NICKNAME_UNSPECIFIED])
	var species_id: int = args[0]
	var level: int = args[1]
	var growth: int = args[2]
	# 原生 `Ball_stdBasic` 的 `brain_current`（+0x2B）：六项数值里都按 `level + brain_current`。
	var brain_current: int = args[3]
	var awakening_value: int = args[4]
	var awakened: int = args[5]
	var equipment: int = args[8]
	var species: MonsterDefinition = catalog.monster(species_id)
	assert(species != null)

	var ability: Array = species.ability_inputs
	var attributes: Array = species.attribute_inputs
	var nickname_values: Array = nickname_bias_row(nickname)
	var slot_table := passive_slot_table(args, passive_slots)
	var passives := Passives.effect_table(catalog, slot_table)

	var awakening := 3 * awakened
	var extra := int(awakening_value / 100) if awakening == 3 else 0
	var growth_level := 1 if growth < 0 else growth
	var stats: Array[int] = [
		2 * (int(int(ability[0]) / 2) +
			2 * (extra + growth_level + int(attributes[0]) +
			2 * (int(nickname_values[0]) + awakening) + level + brain_current)),
		2 * (extra + int(attributes[1]) + int(int(ability[1]) / 4) + level + brain_current +
			2 * (int(nickname_values[1]) + awakening)),
		2 * (int(int(ability[2]) / 2) +
			2 * (extra + growth_level + int(attributes[2]) +
			2 * (int(nickname_values[2]) + awakening) + level + brain_current)),
		2 * (int(int(ability[3]) / 4) + extra + int(attributes[3]) + level + brain_current +
			2 * (int(nickname_values[3]) + awakening)),
		int(3 * (4 * (int(nickname_values[4]) + extra + growth_level + awakening +
			5 * int(attributes[4]) + level + brain_current) + int(int(ability[4]) / 2)) / 2),
		0,
	]
	var speed_base := int((int(ability[5]) + int(attributes[5])) / 2) + extra + level + \
		brain_current + int(nickname_values[5]) + 2 * awakening
	stats[5] = 10 * speed_base + int(nickname_values[5]) * int(speed_base / 2)

	var hp_percent := passives[20]
	var percentages: Array[int] = [0, 0, 0, 0]
	if equipment >= 0:
		var item: ItemDefinition = null
		for entry: ItemDefinition in catalog.items:
			if entry.type == ItemKind.Kind.EQUIPMENT and entry.index == equipment:
				item = entry
				break
		assert(item != null)
		var equipment_values: Array = item.detail_slots
		for index in range(4):
			percentages[index] = int(equipment_values[10 + index])
		stats[5] += int((int(equipment_values[5]) * stats[5] + 99) / 100)
		hp_percent += int(equipment_values[8])

	var hp_base := stats[4] + 30 + int(nickname_values[4]) * int(stats[4] / 20)
	var max_hp := hp_base + int((hp_base * hp_percent + 99) / 100)
	var max_sp := passives[22] + 5 + (10 if awakening == 3 else 0)
	return {
		"species": species_id + (AWAKENED_SPECIES_OFFSET if awakened == 1 else 0),
		"level": level,
		"nickname": nickname,
		"attribute": int(species["attribute_group"]) - 1,
		"kind": int(species["kind"]),
		# 原生 `MonsterState` 的 byte 0x84（`kind_specific_84_bits`），捕获率按它分档。
		"grade": int(species["attribute_entry"]),
		"stats": stats,
		"percentages": percentages,
		"passives": passives,
		"passive_slots": slot_table,
		"hp": max_hp,
		"max_hp": max_hp,
		"sp": max_sp,
		"max_sp": max_sp,
		"speed": stats[5],
		"cooldown": 0,
		"direction": 0,
		"statuses": {},
		# 原生 `Ball_stdSet...` 把 `feel_value` 取记录值、`food_value` 写死 100；
		# 战斗内食物道具改这两个字段，结算页（`Battle_Win_SetResult`）的战後变化也写它们。
		"feel": 0,
		"food": ItemEffect.FOOD_MAX,
		# `Ball_stdSet` 的 `feel_state_code = 3 × a7`：觉醒档直接决定状态码。
		"feel_state": ItemEffect.FeelState.AWAKENED if awakened == 1 else \
			ItemEffect.FeelState.NORMAL,
		# `Ball_stdSet` 之后的记录同样带着 `brain_current` 与固定的 `brain_limit` 99，
		# 捕获时整份记录 memcpy 入包（`Ball_stdAddEx`），所以这两项跟着球走。
		"brain_current": brain_current,
		"brain_limit": BRAIN_LIMIT,
		# 原生 `PINFO[3]`（吸血池，被动 30 写入、受伤时按池回血）。
		"drain": 0,
		# 原生 `extended_state[539]`（抢先行动权重：59 开场写 100、35／36 被打时写值，
		# 行动后由 `Battle_Delay_Proc` 消费清零）与 `obj+264`（这一击的指定目标序号）。
		"priority": 0,
		"designated_target": NO_TARGET,
		# 原生 `extended_state[536]`（见 `AiTargetGroup`）：上一手技能留给 AI 的「补普攻」计数。
		"ai_target_group": AiTargetGroup.NONE,
		"pending": 0,

		"native_arguments": args.duplicate(),
	}

static func combat_species(species: int) -> int:
	return species if species == 1099 else species % 1000


## 复活道具的原生道具号（`type * 1000 + index`，见 `ItemKind`）。
static func revive_item_id() -> int:
	return ItemKind.id_of(REVIVE_ITEM_GROUP, REVIVE_ITEM_INDEX)


## 原生 `Battle_Die_Revival` 的 0 档（有复活道具那一支）：`Ball_stdInit(state, -1,
## 100, 100, 100, 100)` 把流派按 -1 保留、速度／HP／SP 都按 100% 回满，再 `Object_objANI(obj, 0)`
## 回待机；`Battle_Die_mRun` 的 4／8 段随后 `BattleCanvas_SetNext(BATTLE_STATE_POSITION)`，
## 也就是「复活后这场战斗继续」，而不是回标题。`Ball_stdInit` 不碰 `Param` 效果槽，所以这里
## 也不清 `guard`／`cooldown`。
func revive() -> bool:
	if result != "lost":
		return false
	for index in range(3, balls.size()):
		var ball: Dictionary = balls[index]
		if ball.is_empty():
			continue
		ball.hp = int(ball.max_hp)
		ball.sp = int(ball.max_sp)
		ball.speed = int(ball.stats[5])
		# `Battle_Die_Revival` 的 `0x31bfe` 在按模式重置之前先清 `ext[536]`。
		ball["ai_target_group"] = AiTargetGroup.NONE
	result = null
	select_actor()
	return true


func support_error() -> String:
	for ball: Dictionary in balls:
		if ball.is_empty():
			continue
		if ball.hp == null or not ball.has("stats"):
			return "旧阵容没有记录完整的原生数值；请返回地图重新遭遇。"
		if not BattleSpeciesTable.has(combat_species(int(ball.species))):
			return "怪物%d的动作分段尚未导出。" % int(ball.species)
		for effect in ball.passives.size():
			if int(ball.passives[effect]) != 0 and not SUPPORTED_PASSIVE_EFFECTS.has(effect):
				return "被动效果%d尚未还原；没有忽略该效果继续战斗。" % effect
	return ""


## 战斗内用道具：原生 `Battle_Target_mKeyPressed` 确认目标后调 `Ball_stdUseEx`，
## 效果与扣道具都在 `Ball_stdUse` 里——分派只有 `ItemEffect.apply` 一份，菜单侧
## （`MenuModel.use_item`）走同一个入口，这里只绑目标校验与觉醒 callback。
## 返回的 `code` 是原生返回码，视图据此选 `msg.fxt` 480–508 与 `b_effect` 的动作号。
func use_item(item: Dictionary, target: int) -> Dictionary:
	if target < 3 or target >= balls.size() or balls[target].is_empty():
		return {"ok": false, "error": "道具目标不是场上的我方对象"}
	return ItemEffect.apply(balls[target], item, _awaken)


## `ItemEffect.apply` 的觉醒 callback：多一行战报（原生 `Game_Evolve_Set` 的可见提示不在本模型）。
func _awaken(ball: Dictionary) -> String:
	var failure := awaken_ball(ball, catalog)
	if failure.is_empty():
		log.append("%d 觉醒为 %d" % [int(ball["native_arguments"][0]), int(ball["species"])])
	return failure


## 原生 `Ball_stdFeel` 的 LABEL_5：`feel_state_code = 3`、`feel_value` 退回旧状态码
## （必为 0，所以觉醒后心情从 0 重新累计）、`definition_id % 1000 + 1000`、清标准被动槽 2–5、
## `Game_Evolve_Set`（进进化队列 ＋ EFC 特效 119）、`Ball_stdBasic` 按新物种重算、
## `Ball_stdHP(ball, 0, 100)`／`Ball_stdSP(ball, 0, 100)` 把 HP／SP 按 100% 回满。
## 返回空串表示成功。`Game_Evolve_mPaint` 的整屏进化演出（200×200 窗口、标题 msg.fxt 132、
## 帧 0–19 基础形 / 20–50 觉醒形）尚未还原，本轮只落状态与数值。
## 战斗（`_awaken`）与菜单（`MenuModel.use_item`）都调这一处，避免两份觉醒规则。
static func awaken_ball(ball: Dictionary, catalog: GameplayData) -> String:
	if catalog == null:
		return "缺少物种数据，无法按 Ball_stdBasic 重算觉醒后的数值"
	var args: Array = ball.get("native_arguments", []).duplicate()
	if args.size() < 10:
		return "这只球没有原始参数，无法按新物种重算觉醒后的数值"
	args[4] = 0
	args[5] = 1
	if args[6] in ItemEffect.AWAKENING_CLEARED_PASSIVES:
		args[6] = 0
		args[7] = 0
	var evolved := make_ball(catalog, args, int(ball["nickname"]))
	for field: String in ["species", "attribute", "kind", "grade", "stats", "percentages",
			"passives", "max_hp", "max_sp", "speed"]:
		ball[field] = evolved[field]
	ball["native_arguments"] = args
	ball["feel"] = 0
	ball["feel_state"] = ItemEffect.FeelState.AWAKENED
	ball["hp"] = int(ball["max_hp"])
	ball["sp"] = int(ball["max_sp"])
	return ""


static func effective_stat(ball: Dictionary, index: int) -> int:
	var value := int(ball["stats"][index])
	return value + int((value * int(ball["percentages"][index]) + 99) / 100) + \
		int(value * int(nickname_bias_row(int(ball["nickname"]))[index]) / 20)


func _init(enemies: Array, party: Array, random: Callable = Callable()) -> void:
	_random = random if random.is_valid() else Callable(self, "_default_random")
	assert(enemies.size() == 3 and party.size() == 3)
	balls.assign(enemies + party)
	for ball: Dictionary in balls:
		if ball.is_empty():
			continue
		if not ball.has("statuses"):
			ball.statuses = {}
		# `ext[539]` 与 `obj+264` 是后补的运行时字段，旧存档的球没有它们。
		if not ball.has("priority"):
			ball["priority"] = 0
		if not ball.has("designated_target"):
			ball["designated_target"] = NO_TARGET
		# 同上：`ext[536]` 的目标组计数也是后补字段。
		if not ball.has("ai_target_group"):
			ball["ai_target_group"] = AiTargetGroup.NONE
		# `feel_state_code`（`Ball_stdSet` 的 `3 × 觉醒档`）同样是后补字段。
		if not ball.has("feel_state"):
			ball["feel_state"] = ItemEffect.FeelState.NORMAL
	unavailable = support_error()
	if not unavailable.is_empty():
		return
	_roll_opening_priority()
	select_actor()


func _default_random(limit: int) -> int:
	assert(limit > 0)
	return randi_range(0, limit - 1)


func _roll(limit: int) -> int:
	var value := int(_random.call(limit))
	assert(value >= 0 and value < limit)
	return value


## 原生 `Battle_Ready_Set`：开场先扫敌方链（`+20654`／`+20657`）、再扫我方链
## （`+20650`／`+20653`），逐只掷 `rand()%100 < passives[59]`；命中就写 `ext[539] = 100` 并把
## `obj+264` 指成对方阵营的随机序号（敌方链 `rand()%我方数 + 3`、我方链 `rand()%敌方数`）。
## 两条链共用同一个「上一只命中者」寄存器，所以只有最后一只保留 539。
func _roll_opening_priority() -> void:
	var previous := NO_TARGET
	for index in range(balls.size()):
		var ball: Dictionary = balls[index]
		if ball.is_empty():
			continue
		if _roll(100) >= int(ball.passives[PRIORITY_PASSIVE]):
			continue
		# 敌方（槽 0–2）锁我方、我方锁敌方，序号基址与本方阵营相反。
		var hostile_base := ENEMY_SLOTS if index < ENEMY_SLOTS else 0
		ball["priority"] = PRIORITY_BOOST
		ball["designated_target"] = hostile_base + _roll(ENEMY_SLOTS)
		if previous != NO_TARGET:
			balls[previous]["priority"] = 0
		previous = index


## 原生 `Battle_Character_init` 读 `obj+264` 前先用 `Battle_objFIND` 取对象，要求它存在、
## 有 `PINFO`（`obj+124`）且 `PINFO` 的 HP（word@+26）非 0，否则把 `ext[539]` 清 0（`0x35522`）。
func _designated_alive(ball: Dictionary) -> bool:
	var index := int(ball["designated_target"])
	return index >= 0 and index < balls.size() and not balls[index].is_empty() and \
		int(balls[index]["hp"]) > 0


## 原生 `Param_dmg1BASIC` 的 `0x79938` 用 `Battle_objINDEX(攻击方)` 写 `obj+264`。
## Godot 的字典 `==` 是按值比较，同种同级的球会互相认错，所以这里按引用（`is_same`）找槽位。
func _ball_index(ball: Dictionary) -> int:
	for index in range(balls.size()):
		if is_same(balls[index], ball):
			return index
	return NO_TARGET


func get_manual() -> bool:
	return actor >= 3 and result == null


func targets() -> Array[int]:
	var output: Array[int] = []
	for index in range(balls.size()):
		if not balls[index].is_empty() and int(balls[index]["hp"]) > 0 and (index < 3) != (actor < 3):
			output.append(index)
	return output


func select_actor() -> void:
	if balls.slice(3).all(func(ball: Dictionary) -> bool: return ball.is_empty() or int(ball["hp"]) == 0):
		result = "lost"
		return
	if balls.slice(0, 3).all(func(ball: Dictionary) -> bool: return ball.is_empty() or int(ball["hp"]) == 0):
		result = "won"
		return
	var choose := func() -> int:
		var best_value := 0
		var selected := -1
		for index in range(balls.size()):
			var ball: Dictionary = balls[index]
			if ball.is_empty():
				continue
			var value := int(ball["speed"])
			if int(ball["hp"]) > 0:
				# 原生 `Battle_Character_init`：行动值 = `100000 × ext[539] + speed`，
				# 539 非 0 时先校验 `obj+264` 指向的对象还活着（`0x353f4`／`0x35522`），死了就清 0。
				if int(ball["priority"]) > 0 and not _designated_alive(ball):
					ball["priority"] = 0
				value += PRIORITY_WEIGHT * int(ball["priority"])
				if value > best_value:
					selected = index
					best_value = value
		return selected
	actor = choose.call()
	if actor < 0:
		for ball: Dictionary in balls:
			if not ball.is_empty() and int(ball["hp"]) > 0:
				ball["speed"] = int(ball["stats"][5])
		actor = choose.call()
	assert(actor >= 0)


func auto_action() -> Dictionary:
	assert(result == null)
	var ball: Dictionary = balls[actor]
	var candidates := targets()
	# 原生 `Battle_Menu_Auto` 的技能那一支还要求 `ext[536] == 0`（`0x30eaa`），
	# 所以上一手技能留下的「补普攻」计数用光之前不会再选技能。
	var may_cast := skill_available(ball) and \
		int(ball["ai_target_group"]) == AiTargetGroup.NONE
	return {
		"action": "skill" if may_cast and _roll(2) != 0 else "attack",
		"target": candidates[_roll(candidates.size())],
	}


func _strength(attacker: Dictionary, defender: Dictionary) -> int:
	var difference := (int(attacker["attribute"]) + 1) % 6
	if difference == int(defender["attribute"]):
		return 1
	if (int(attacker["attribute"]) + 5) % 6 == int(defender["attribute"]):
		return -1
	return 0


## 主动效果槽的读法：层数 = `+2`、id = `+0`（`6 × 相性档 − 3`，公式里只用到绝对值）。
## 原生按 `|id|` 直接索引 rodata 表，这里夹到 `0..3`（表长 4），避免异常 id 越界。
static func _slot_count(ball: Dictionary, code: int) -> int:
	var statuses: Dictionary = ball.get("statuses", {})
	return int(statuses[code].stacks) if statuses.has(code) else 0


static func _slot_tier(ball: Dictionary, code: int) -> int:
	return mini(absi(int(ball.statuses[code].remaining)), 3)


## `Param_atk1ACTIVE`（普攻）／`Param_atk2ACTIVE`（技能）：攻击力百分比。
## 普攻读槽 12／13（每层 `× (rand%2 + 2)`／`× (rand%3 + 2)`），技能读槽 14（`100 × 层数 + 100`）／
## 15（`+150`）／16（`+200`）／17（`+250`）；两组都读弱点 21（`20 × (1 − |id|) − 10` 每层）、
## 22（`−20 × |id|` 每层）、23（`20 × (1 − |id|) − 40` 每层）与 30／31／32（各 +30 每层）。
func _active_attack(ball: Dictionary, skill: bool) -> int:
	var percent := 100
	if skill:
		percent = 100 * _slot_count(ball, 14) + 100
		percent += 150 * _slot_count(ball, 15)
		percent += 200 * _slot_count(ball, 16)
		percent += 250 * _slot_count(ball, 17)
	else:
		for stack in _slot_count(ball, 12):
			percent *= _roll(2) + 2
		for stack in _slot_count(ball, 13):
			percent *= _roll(3) + 2
	var weak := _slot_count(ball, StatusEffect.Code.WEAKNESS)
	if weak > 0:
		percent += weak * (20 * (1 - _slot_tier(ball, StatusEffect.Code.WEAKNESS)) - 10)
	var down := _slot_count(ball, 22)
	if down > 0:
		percent -= 20 * down * _slot_tier(ball, 22)
	var heavy := _slot_count(ball, 23)
	if heavy > 0:
		percent += heavy * (20 * (1 - _slot_tier(ball, 23)) - 40)
	for code: int in [30, 31, 32]:
		percent += 30 * _slot_count(ball, code)
	return maxi(0, percent)


## `Param_def1ACTIVE`／`Param_def2ACTIVE`：防御力百分比（普攻与技能读同一批槽）。
## 槽 9／10／11 每层 `−50／−60／−70`，18／19／20 按 `|id|` 查 `TAKEN_UP_TABLE` 加受伤，
## 24／25／26 按 `|id|` 查 `TAKEN_DOWN_TABLE` 减受伤，30／31／32 每层 `−50／−60／−70`，
## 槽 33（防御）每层 `+100`。
func _active_defense(ball: Dictionary) -> int:
	var percent := 100 - 50 * _slot_count(ball, 9) - 60 * _slot_count(ball, 10) - \
		70 * _slot_count(ball, 11)
	for code: int in [18, 19, 20]:
		var count := _slot_count(ball, code)
		if count > 0:
			percent += count * int(TAKEN_UP_TABLE[_slot_tier(ball, code)])
	for slot in TAKEN_DOWN_TABLE.size():
		var code: int = 24 + slot
		var count := _slot_count(ball, code)
		if count > 0:
			percent -= count * int(TAKEN_DOWN_TABLE[slot][_slot_tier(ball, code)])
	percent -= 50 * _slot_count(ball, 30) + 60 * _slot_count(ball, 31) + \
		70 * _slot_count(ball, 32)
	percent += 100 * _slot_count(ball, StatusEffect.Code.DEFENCE)
	return maxi(0, percent)


func _base_damage(attacker: Dictionary, defender: Dictionary, skill: bool) -> int:
	var level_difference := int(attacker["level"]) - int(defender["level"])
	var threshold := 1000 if level_difference > 10 else 950 if level_difference >= -9 else \
		900 if level_difference >= -19 else 850
	var hit := _roll(1000) < threshold
	if not hit and not skill:
		return 0
	var offset := 2 if skill else 0
	var attacker_stats: Array = attacker["stats"]
	var attacker_value := effective_stat(attacker, offset) + \
		int(int(attacker_stats[offset]) * _roll(3) / 100)
	var attack_passives: Array = attacker.passives
	var attack_percent := _active_attack(attacker, skill)
	if int(defender.kind) in [0, 1]:
		attack_percent += int(attack_passives[(4 if skill else 0) + int(defender.kind)])
	if int(attacker.hp) < int(30 * int(attacker.max_hp) / 100):
		attack_percent += int(attack_passives[6 if skill else 2])
	# 原生 `Param_dmg1BASIC`／`Param_dmg2BASIC`：攻击方饱食度 0 时把
	# `atk1／atk2` 的「`active + passive` 之和」减半，防御方饱食度 0 时把 `def1／def2` 减半。
	if int(attacker.get("food", ItemEffect.FOOD_MAX)) == 0:
		attack_percent /= 2
	attacker_value = int(attacker_value * maxi(0, attack_percent) / 100)
	var defense_index := offset + 1
	var defense := effective_stat(defender, defense_index)
	var passive_values: Array = defender["passives"]
	var passive_defense := int(passive_values[(16 if skill else 12) + int(attacker["kind"])]) \
		if int(attacker.kind) in [0, 1] else 0
	if _strength(attacker, defender) == -1:
		passive_defense += int(passive_values[18 if skill else 14])
	if int(defender.hp) < int(30 * int(defender.max_hp) / 100):
		passive_defense += int(passive_values[19 if skill else 15])
	var defense_percent := _active_defense(defender) + passive_defense
	if int(defender.get("food", ItemEffect.FOOD_MAX)) == 0:
		defense_percent /= 2
	var damage := maxi(0, attacker_value - maxi(0, int(defense * defense_percent / 100)))
	# 相性倍率只落在技能这一支（`Param_dmg2BASIC:98-105`）；普攻取到的同一张表只当闸门、
	# 不缩放伤害，见 `_physical_passives` 与 `wiki\battle\battle-field.md`「普攻的相性倍率」。
	if skill:
		var relation := _strength(attacker, defender)
		if relation == 1:
			damage += int(SKILL_ADVANTAGE_DAMAGE_PERCENT * damage / 100)
		elif relation == -1:
			damage += int(SKILL_DISADVANTAGE_DAMAGE_PERCENT * damage / -100)
		damage = _skill_passives(attacker, defender, damage)
	else:
		damage = _physical_passives(attacker, defender, damage)
	# 原生 `Param_dmg1BASIC` 的 `v6[1] = max(伤害, PINFO[1])`：`PINFO[1]` 是被 47／55 反噬时
	# 写进攻击方的残值，攻击方自己挨打时至少吃这么多伤害；`Param_dmgBASIC` 按 `n100%` 消费后扣减，
	# 所以这里用一次就清掉。
	var pending := int(defender.get("pending", 0))
	if pending > damage:
		damage = pending
	# 原生 `Param_dmg1BASIC` 在算完伤害之后读攻击方的 `extended_state[539]`（59 抢到的 100
	# 或 35／36 写进去的值），把这**一击**的伤害按 `539%` 缩放（`0x7972a`／`0x79794`）。
	if int(attacker["priority"]) > 0:
		damage = damage * int(attacker["priority"]) / 100
	return damage if hit else 0


## 原生 `Param_dmg1BASIC` 里的被动分支（普攻命中时，按代码顺序）：
##   37／38 = 对「kind 0／1」目标的一击必杀率、39 = 相性有利时的必杀率（三者都把伤害
##   直接设成目标最大 HP，图标 7）；
##   31／32 = 受方对「攻击方 kind 0／1」的无效化、33 = 相性不利时的无效化（伤害归零，图标 18）；
##   30 = 吸血（伤害记进**攻击方**的吸血池 `PINFO[3]`，该对象受伤时按池回血）；
##   35／36 = 受方被打后立刻锁住攻击方抢先反击一次（见函数体开头）。
## 相性用 `Param_attrStrength`（本工程 `_strength`）：1 有利、−1 不利、0 无关；
## `CSWTCH.95_0` 里 `+72` 那列只在「有利」为 1、`+76` 那列只在「不利」为 1，两列在这条链上
## **只当闸门**（不缩放伤害，倍率只出现在 `Param_dmg2BASIC` 的技能支）。
## 目标被动 47（必杀反噬）与 55（反吸血）也在这里读，一起落地：47 在必杀那一支把攻击方的
## `pending` 残值写成它的最大 HP（必杀被反噬成 0 伤害），55 在吸血那一支把这一击的伤害改写成
## 攻击方的 `pending`（反噬攻击者，吸血池不增）。
func _physical_passives(attacker: Dictionary, defender: Dictionary, damage: int) -> int:
	# 原生 `Param_dmg1BASIC` 的 `0x79938`：受方被打后把**自己**的 `ext[539]` 置成被动 35、
	# `obj+264` 指成攻击方；相性不利时再把被动 36 加上去（`0x79ab0`，上限 255）。下一回合它抢先
	# 行动、锁定这个攻击方，这一击的伤害按 `539%` 结算。原生把它写在 37–33／30 那几支之后，但那几支
	# 都不读 539，所以放在最前面等价。
	var attacker_index := _ball_index(attacker)
	var counter := int(defender.passives[COUNTER_PRIORITY_PASSIVE])
	if counter > 0:
		defender["priority"] = counter
		defender["designated_target"] = attacker_index
	if _strength(attacker, defender) == -1:
		var disadvantage := int(defender.passives[COUNTER_DISADVANTAGE_PASSIVE])
		if disadvantage > 0:
			defender["priority"] = mini(PRIORITY_LIMIT,
				disadvantage + int(defender["priority"]))
			defender["designated_target"] = attacker_index
	var kind := int(defender.kind)
	var lethal := false
	if kind in [0, 1] and _roll(100) < int(attacker.passives[37 if kind == 0 else 38]):
		lethal = true
	if not lethal and _strength(attacker, defender) == 1 and \
			_roll(100) < int(attacker.passives[39]):
		lethal = true
	if lethal:
		# 目标被动 47：必杀被反噬——原生把**攻击方**的 `PINFO[1]` 写成它的最大 HP，
		# 那个残值要等攻击方自己挨打时才被消费（见 `_base_damage` 末尾的 `pending`）。
		if _roll(100) < int(defender.passives[47]):
			attacker["pending"] = maxi(int(attacker.get("pending", 0)), int(attacker.max_hp))
			return 0
		return int(defender.max_hp)
	var attacker_kind := int(attacker.kind)
	if attacker_kind in [0, 1] and \
			_roll(100) < int(defender.passives[31 if attacker_kind == 0 else 32]):
		return 0
	if _strength(attacker, defender) == -1 and _roll(100) < int(defender.passives[33]):
		return 0
	if _roll(100) < int(attacker.passives[30]):
		# 目标被动 55：反吸血——这次伤害改成反噬攻击者（写进它的 `pending`）。
		if _roll(100) < int(defender.passives[55]):
			attacker["pending"] = maxi(int(attacker.get("pending", 0)), damage)
			return 0
		attacker["drain"] = maxi(int(attacker.get("drain", 0)), damage)
	return damage


## 原生 `Param_dmg2BASIC` 的两支：
##   34 = 相性不利时受方闪避（`v44 == 1` 即不利，`rand()%100 < 受方被动值` → 伤害归零）；
##   40–45 = `case 0`（普通技能伤害）里按**攻击方属性**取的六档免疫
##   （`*(&n40 + 攻击方属性)`，`rand()%100 < 受方被动值` → 伤害归零）。
func _skill_passives(attacker: Dictionary, defender: Dictionary, damage: int) -> int:
	if _strength(attacker, defender) == -1 and _roll(100) < int(defender.passives[34]):
		return 0
	var attribute := int(attacker.get("attribute", -1))
	if attribute >= 0 and attribute < 6 and \
			_roll(100) < int(defender.passives[40 + attribute]):
		return 0
	return damage


## 原生 `Param_dmgBASIC`：受伤时先按自己的吸血池回血（`n100 × 池 / 100`）再把池扣掉。
static func _absorb_drain(ball: Dictionary) -> void:
	var pool := int(ball.get("drain", 0))
	if pool <= 0:
		return
	ball["drain"] = 0
	ball.hp = mini(int(ball.max_hp), int(ball.hp) + pool)


func _hit(attacker_index: int, target_index: int, skill: bool, percent: int,
		pool: Dictionary, reverse: bool) -> Dictionary:
	var attacker: Dictionary = balls[attacker_index]
	var defender: Dictionary = balls[target_index]
	var remaining := int(pool[target_index])
	var level_difference := int(attacker["level"]) - int(defender["level"])
	var strength := _strength(attacker, defender)
	var advantage := 1 if strength == 1 else 0
	var bonus := ADVANTAGE_CRITICAL_PERCENT * advantage
	var chance := 30 + bonus if level_difference > 5 else \
		20 + bonus if level_difference >= -2 else 5 if level_difference >= -8 else 1
	var attacker_passives: Array = attacker["passives"]
	if int(defender.kind) in [0, 1]:
		chance += int(attacker_passives[8 + int(defender.kind)])
	if advantage == 1:
		chance += int(attacker_passives[10])
	if int(attacker.hp) < int(30 * int(attacker.max_hp) / 100):
		chance += int(attacker_passives[11])
	var critical := _roll(100) < chance
	if reverse:
		defender["direction"] = 1 if int(defender["direction"]) == 0 else 0
	_freeze(defender)
	var portion := int(remaining * percent / 100)
	pool[target_index] = remaining - portion
	# 原生 `Param_dmgBASIC1` 只在满命中（`n100 == 100`）且本次伤害 > 0 时抽查被动附状态；
	# 技能的附加状态来自物种的 `_procSkill`（`battle-species.tres`），不走这一条。
	var activated: Array[int] = []
	if not skill and percent == 100:
		activated = _passive_status(attacker_index, target_index, portion)
	var damage := portion + (int(portion * ((20 if skill else 50) +
		int(attacker_passives[60])) / 100) if critical else 0)
	var previous := int(defender["hp"])
	defender["hp"] = maxi(0, previous - damage)
	_feel_on_death(defender, previous)
	_absorb_drain(defender)
	defender["pending"] = 0
	# `skill` 随命中带出去：相克提示只有技能那一支会推（原生 `Param_dmg2BASIC`
	# 的 `0x79056`，而它只被 `Battle_Skill_init` 调用；普攻走 `Param_dmg1BASIC`）。
	var hit := {"target": target_index, "damage": damage, "critical": critical, "speed_loss": 0,
		"strength": strength, "skill": skill}
	# `activated_passives`：这一击里发动了被动的对象序号（原生 `Param_atkPASSIVE` 在掷中时就推 556）。
	if not activated.is_empty():
		hit["activated_passives"] = activated
	return hit


## 原生 `Param_dmg1PASSIVE`：见 `INFLICT_PASSIVES` 的说明。返回本次「被动发动」要提示的对象序号
## （原生在这一支里调两处 `Param_atkPASSIVE`：掷中就先报攻击方的 25–29，受方抵抗成立时再报它的
## 48／49／50／53／54）；空数组表示没掷中（或这一击会打死目标，原生那条 `PINFO[1] >= 目标 HP` 的门）。
## 状态施加本身由 `_status_hit` 完成，返回值只给界面推 556 用。
func _passive_status(attacker_index: int, target_index: int, damage: int) -> Array[int]:
	var attacker: Dictionary = balls[attacker_index]
	var defender: Dictionary = balls[target_index]
	if damage <= 0 or damage >= int(defender.hp):
		return []
	for entry: Array in INFLICT_PASSIVES:
		if _roll(100) >= int(attacker.passives[entry[0]]):
			continue
		var code: int = entry[1]
		if _roll(100) < int(defender.passives[entry[2]]):
			# 抵抗成立：`Param_dmg2SKILL(目标, 攻击方, code, 100)` 把状态反弹回攻击者，
			# 随后为受方的抗性被动再推一条「被动发动」。
			_status_hit(target_index, attacker_index, code)
			return [attacker_index, target_index]
		_status_hit(attacker_index, target_index, code)
		return [attacker_index]
	return []


## 原生 `Param_dmgNUMBER`：扣血后 HP 归零、且原来非 0 时 `Ball_stdFeel(ball, -20)`。
## 同一函数还带一个「对战类型 − 4 > 5」的闸（联网／公会战不扣心情），本工程没有那些类型。
static func _feel_on_death(ball: Dictionary, previous_hp: int) -> void:
	if previous_hp > 0 and int(ball.hp) == 0:
		ball["feel"] = maxi(0, int(ball.get("feel", 0)) - 20)


static func skill_available(ball: Dictionary) -> bool:
	return int(ball.cooldown) == 0 and int(ball.sp) > 0 and \
		not ball.get("statuses", {}).has(StatusEffect.Code.SEAL)


## 原生 `Param_activeSet`：`id = 槽 +0`、层数 `+1`、强度 = `max(旧值, 本次)`。
static func _apply_slot(ball: Dictionary, code: int, id: int, value := 0) -> void:
	var statuses: Dictionary = ball.statuses
	var status: Dictionary = statuses.get(code, {"stacks": 0})
	status.stacks += 1
	status.remaining = id
	status["value"] = maxi(int(status.get("value", 0)), value)
	statuses[code] = status


func _status_hit(attacker_index: int, target_index: int, code: int) -> Dictionary:
	if SLOW_CODES.has(code):
		var slow: int = SLOW_VALUES[SLOW_CODES.find(code)]
		balls[target_index].speed = maxi(0, int(balls[target_index].speed) - slow)
		return {"target": target_index, "damage": 0, "critical": false, "speed_loss": slow,
			"status": code, "statuses": balls[target_index].statuses.duplicate(true)}
	if code == CLEAR_STATUS:
		for slot_code: int in CLEAR_CODES:
			balls[target_index].statuses.erase(slot_code)
		return {"target": target_index, "damage": 0, "critical": false, "speed_loss": 0,
			"status": code, "statuses": balls[target_index].statuses.duplicate(true)}
	var receiver := target_index
	if code == StatusEffect.Code.SEAL and _roll(100) < int(balls[target_index].passives[53]):
		receiver = attacker_index
	var ball: Dictionary = balls[receiver]
	# `Param_dmg2SKILL` 的 `switch`：`id = 6 × 相性档 − 3`；中毒槽的强度取施加瞬间的 HP 且只涨不落。
	_apply_slot(ball, code, 3 if _strength(balls[attacker_index], balls[receiver]) == 1 else -3,
		int(ball.hp) if StatusEffect.POISON_CODES.has(code) else 0)
	var tick := 0
	if StatusEffect.POISON_CODES.has(code):
		# 施加中毒的同一帧原生就调一次 `Param_dmgPOISON(obj)`（`Param_dmg2SKILL` 的毒分支直接调用，
		# 不经过状态 12），所以会立刻掉一次血、但不触发被动 57 的回血。
		tick = int(settle_poison(receiver, false).get("damage", 0))
	return {"target": receiver, "damage": tick, "critical": false, "speed_loss": 0,
		"status": code, "statuses": ball.statuses.duplicate(true), "poison": tick > 0}


## 原生 `Param_dmg2SKILL` 的技能附状态：受方被动掷中时把这条状态改附给施术者
## （见 `SKILL_REFLECT_PASSIVES`），掷不中或没有这条被动就照常附给受方。两支都由 `_status_hit`
## 结算、只是角色对调——它按 `6 × 相性档 − 3` 取强度档，对调后算出的正好是原生的 `v33`
## （攻击方相性不利才 +3），照常附给受方时是 `v14`（攻击方相性有利才 +3）。
## 技能码没有记录（老数据）时不做反弹判定。
func _skill_status_hit(attacker_index: int, target_index: int, code: int, skill_code: int) -> Dictionary:
	var reflect := int(SKILL_REFLECT_PASSIVES.get(skill_code, 0))
	if reflect > 0 and _roll(100) < int(balls[target_index].passives[reflect]):
		return _status_hit(target_index, attacker_index, code)
	return _status_hit(attacker_index, target_index, code)


## 状态 12 只在中毒时被选中（`Battle_Poison_init` 的入口是毒回合），所以被动 57 的回血也只随
## 毒槽发生：没有任何毒槽时不回血。
static func _has_poison(statuses: Dictionary) -> bool:
	for code: int in StatusEffect.POISON_CODES:
		if statuses.has(code):
			return true
	return false


## 原生状态 12 POISON 的结算：`Battle_Poison_init` → `Param_dmgPOISON`。
## 三段毒槽（27／28／29）各按「强度 × 等级百分比 × 层数 / 100」求和，三段的和一次
## `Param_dmgNUMBER(obj, -和, 0)` 出红字并扣 HP；槽的 id 每回合递减（3 → 2 → 1 → 清槽，
## 负数 −3 → −2 → 清），所以中毒伤害逐回合减弱。
## 被动 57 只在中毒回合（状态 12 的 init）生效：先按上限的 `值%` 回血再结算；施毒当帧
## （`Param_dmg2SKILL` 的毒分支直接调 `Param_dmgPOISON`）不经过状态 12，`poison_state_init`
## 那时传 `false`。
## 返回 `{"damage": 总和, "died": 是否被打到 0}`。
func settle_poison(index: int, poison_state_init := true) -> Dictionary:
	var ball: Dictionary = balls[index]
	if ball.is_empty():
		return {"damage": 0}
	var statuses: Dictionary = ball.statuses
	var previous := int(ball.hp)
	if poison_state_init and _has_poison(statuses):
		ball.hp = ItemEffect.restored(int(ball.max_hp), previous, 0,
			int(ball.passives[POISON_HEAL_PASSIVE]))
		previous = int(ball.hp)
	var total := 0
	for slot in StatusEffect.POISON_CODES.size():
		var code: int = StatusEffect.POISON_CODES[slot]
		if not statuses.has(code):
			continue
		var status: Dictionary = statuses[code]
		var tier := clampi(absi(int(status.remaining)), 0, POISON_PERCENT[slot].size())
		if tier > 0:
			total += int(status.get("value", 0)) * int(POISON_PERCENT[slot][tier - 1]) * \
				int(status.stacks) / 100
		if int(status.remaining) == -3:
			status.remaining = -2
		elif int(status.remaining) in [3, 2]:
			status.remaining -= 1
		else:
			statuses.erase(code)
	if total <= 0:
		return {"damage": 0}
	ball.hp = maxi(0, previous - total)
	_feel_on_death(ball, previous)
	return {"damage": total, "died": int(ball.hp) == 0}


## 行动后的速度／冷却结算。原生没有「状态按回合递减」这一环：槽的 `+4` 持续值只被写、没有任何
## 递减点（`Param_activeIsNext/IsContinue/IsEffAni` 只服务绘制），槽只会被治疗道具（`Ball_stdUse`
## 的 `Param_activeInit`）、`0x23` 全清、阵亡清理（`Battle_objNextPosition`）与 `Param_dmgFREEZE`
## 清掉；中毒档位由 `Param_dmgPOISON` 自己递减。所以这里不再逐回合动 `ball.statuses`。
## 状态码 36／37／49 的命中：`Param_dmgBASIC2(目标, |percent|, n20)` = 「先 `Param_dmgFREEZE`
## 再 `Param_dmgBASIC`」，而 `Param_dmgBASIC` 的伤害是 `percent × 目标当前 HP / 100`；`LABEL_21`
## 的第二支在攻击方 HP 非 0 时对**攻击方自己**再算一次同样的伤害。49 先把目标的朝向翻转。
func _percent_hp_hit(attacker_index: int, target_index: int, code: int, percent: int) -> Array:
	var defender: Dictionary = balls[target_index]
	if code == FLIP_DIRECTION:
		defender["direction"] = 1 if int(defender["direction"]) == 0 else 0
	_freeze(defender)
	var output: Array = []
	for index: int in [target_index, attacker_index]:
		# 第二支的条件是「攻击方 HP 或吸血池非 0」；本工程没有吸血池，按 HP 判。
		if index == attacker_index and int(balls[index].hp) == 0:
			continue
		var ball: Dictionary = balls[index]
		if int(ball.hp) == 0:
			continue
		var damage := int(ball.hp) * absi(percent) / 100
		var previous := int(ball.hp)
		ball.hp = previous - damage
		_feel_on_death(ball, previous)
		output.append({"target": index, "damage": damage, "critical": false, "speed_loss": 0})
	return output


## 原生 `Param_dmgFREEZE`（`Param_dmgBASIC1`／`Param_dmgBASIC2` 在结算伤害前
## 都会先调）：槽 2–5 各按 `50／100／150／200 × 层数` 求和，把 **HP** 抬高该百分比；随后清掉这四个
## 槽与护盾 9／10／11、减伤 24／25／26、防御 33。护盾与防御对**这一击**仍然有效，因为伤害是先算好的。
## 原生同时把 `PINFO[2]` 写成与 HP 相同的值，那个字段本工程没有（按 HP 镜像处理）。
func _freeze(defender: Dictionary) -> void:
	var regen := 0
	for code: int in REGEN_PERCENT:
		regen += int(REGEN_PERCENT[code]) * _slot_count(defender, code)
	if regen > 0:
		defender.hp = mini(int(defender.max_hp),
			int(defender.hp) + int(defender.hp) * regen / 100)
	for code: int in FROZEN_SLOTS:
		defender.statuses.erase(code)


## 原生 `Battle_Delay_Proc`：行动后 `Ball_stdSPEED(ball, -200, 0)`，被动 65 掷中时不减速
## （`Param_atkPASSIVE(…, 65)`）。开头先消费 `ext[539]`：非 0 就清 0 并**直接返回**（`0x34ade`／
## `0x34ae2`），连 `ext[536]` 自减与 34 个主动状态槽的 tick（`0x34b16` 起）都跳过——本模型的
## `cooldown` 与 `ai_target_group` 自减写在同一段里，所以抢先行动这一手也不扣冷却、不减目标组计数。
func _delay(ball: Dictionary) -> void:
	if int(ball["priority"]) > 0:
		ball["priority"] = 0
		return
	if _roll(100) >= int(ball.passives[65]):
		ball.speed = maxi(0, int(ball.speed) - 200)
	ball.cooldown = maxi(0, int(ball.cooldown) - 1)
	if int(ball["ai_target_group"]) > 0:
		ball["ai_target_group"] = int(ball["ai_target_group"]) - 1


## 原生 `Battle_Position_mRun` 里的被动 58 分支：扫一遍我方，发现 HP 0、且这一支还没用过的
## 队员就 `Battle_Die_Revival(obj, 2, 值)`（`Ball_stdInit(ball, -1, 0, 0, 值, 100)`，即
## HP = 上限 × 值 / 100、SP 回满、速度与饱食度不变），用过的记在 `revived_by_passive` 上。
## 返回被复活的槽位（没有则 −1）。
func revive_by_passive() -> int:
	var revived := -1
	for index in range(3, balls.size()):
		var ball: Dictionary = balls[index]
		if ball.is_empty() or int(ball.hp) > 0 or bool(ball.get("revived_by_passive", false)):
			continue
		ball["revived_by_passive"] = true
		var percent := int(ball.passives[58])
		if percent <= 0:
			continue
		# 58 走的也是 `Battle_Die_Revival` 这个入口，同一个 `0x31bfe` 会清 `ext[536]`。
		ball["ai_target_group"] = AiTargetGroup.NONE
		ball.hp = maxi(1, int(int(ball.max_hp) * percent / 100))
		ball.sp = int(ball.max_sp)
		if revived < 0:
			revived = index
	return revived


func flee() -> Dictionary:
	if not allow_flee or not get_manual() or not unavailable.is_empty():
		return {"ok": false, "error": "本战不能逃跑；没有改变行动。"}
	var maximum_level := 1
	for ball: Dictionary in balls.slice(0, 3):
		if not ball.is_empty():
			maximum_level = maxi(maximum_level, int(ball.level))
	var difference := hero_level - maximum_level
	var chance := 70 if difference > 3 else 50 if difference >= -3 else 30 if difference >= -7 else 10
	for ball: Dictionary in balls.slice(3):
		if not ball.is_empty() and int(ball.hp) > 0:
			chance += int(ball.passives[63])
	var escaped := _roll(100) < chance
	if escaped:
		result = "escaped"
	else:
		_delay(balls[actor])
		select_actor()
	turns += 1
	return {"ok": true, "escaped": escaped}


## 原生 `Battle_Capture_Action_IsCapture` 的 `v26` 表：品级 0–5 的基础值，
## `v4 = v26[品级] - 30`。
const CAPTURE_BASE := [90, 80, 50, 30, 7, 5]
## 同一函数里 `v16` 那 48 字节栈表的 8 行（`6 * v13 + 品级 - 6`，`v13 = (能力 - 1) / 30 + 1`）。
const CAPTURE_BONUS := [[5, 4, 3, 2, 1, 1], [6, 5, 4, 3, 1, 1], [7, 6, 5, 4, 2, 2],
	[8, 7, 6, 5, 2, 2], [9, 8, 7, 6, 3, 3], [10, 9, 8, 7, 3, 3],
	[11, 10, 9, 8, 4, 4], [12, 11, 10, 9, 4, 4]]
## 捕获演出：`Battle_Capture_Action_mRun` 的子状态 0 在 `run_counter > 5` 时切走，
## 结果子状态 2（失败）／3（成功）在 `run_counter == 28` 收尾，全程 34 个 0.05 秒帧。
const CAPTURE_THROW_FRAMES := 6
const CAPTURE_RESULT_FRAMES := 28
## 结果演出里的 `Param_atkEFFECT` 动作号（`Battle_Capture_Action_mRun` 子状态 2／3 第 0 帧）：
## 成功 37、失败 38，都是 `obj/b_effect` 的动作。
const CAPTURE_EFFECT := 37
const CAPTURE_EFFECT_FAIL := 38
## 剩余 HP 每低一档（从 90% 起每 10%）各 +3；`v4 -= 30` 是同函数里的固定起点减值。
const CAPTURE_HP_START_PERCENT := 90
const CAPTURE_HP_STEP_PERCENT := 10
const CAPTURE_HP_STEP_BONUS := 3
const CAPTURE_BASE_OFFSET := 30
## 球对属性的加成：属性球与目标同属性 ×1.5，第 7 组 6／7 号球 ×2.2／×2.8。
const CAPTURE_ATTRIBUTE_BALL_PERCENT := 150
const CAPTURE_BALL_PERCENT := 220
const CAPTURE_STRONG_BALL_PERCENT := 280
## 目标属性与玩家流派相同（`ParamData.preferred_mastery_index`）时
## `Battle_Capture_Action_IsCapture` 的 `v6 += 2`。
const CAPTURE_PREFERRED_MASTERY_BONUS := 2


## 原生 `Battle_Capture_Action_IsCapture` 的 `v6`：最终判定是
## `EFC_mainGetRAND() % 1000 < 10 * v6`，即「百分之 v6」的成功率。
## - `bonus_roll` 是那支 `rand() % 100 < n10`（`n10 = 10 * v13`）：命中时按
##   `CAPTURE_BONUS[v13 - 1]` 再加值。
## - `standard_level / 40` 是 `v16.level / 0x28`（`standard_progress` 换算出的等级）。
## - 与主角擅长流派同属性再 +2；剩余 HP 每低 10%（含 90% 本身）再 +3。
## - 球：type 5 与目标同属性 ×1.5（`index - 1` 就是属性，见 `msg.fxt:428–433` 的属性球名），
##   type 7 的 6／7 号无视属性 ×2.2／×2.8（`msg.fxt:445`「可无视属性使抓捕成功率+%d%%」）。
## 原生还会在 `MonsterState.feel_state_code == 3`（觉醒，本工程用物种号 +1000 表示）时把结果
## **最后**除以 8（`if (*(_BYTE *)(ball + 42) == 3) v6 /= 8;` 在所有倍率之后）。
static func capture_rating(target: Dictionary, item: Dictionary, bonus_roll: int,
		ability: int, preferred_mastery: int, standard_level: int) -> int:
	var grade := clampi(int(target.get("grade", 0)), 0, CAPTURE_BASE.size() - 1)
	var rating := int(CAPTURE_BASE[grade]) - CAPTURE_BASE_OFFSET
	var step := mini((ability - 1) / 30 + 1 if ability > 0 else 1, CAPTURE_BONUS.size())
	if bonus_roll < 10 * step:
		rating += int(CAPTURE_BONUS[step - 1][grade])
	rating += int(standard_level / 40)
	if preferred_mastery == int(target.get("attribute", -1)):
		rating += CAPTURE_PREFERRED_MASTERY_BONUS
	var maximum := int(target.get("max_hp", 0))
	var hp_percent := int(int(target.get("hp", 0)) * 100 / maximum) if maximum > 0 else 100
	var threshold := CAPTURE_HP_START_PERCENT
	while hp_percent <= threshold and threshold > 0:
		threshold -= CAPTURE_HP_STEP_PERCENT
		rating += CAPTURE_HP_STEP_BONUS
	var type := int(item.get("type", -1))
	var index := int(item.get("index", -1))
	if type == ItemKind.Kind.ATTRIBUTE_BALL and index >= 1 and index <= 6 and \
			index - 1 == int(target.get("attribute", -1)):
		rating = CAPTURE_ATTRIBUTE_BALL_PERCENT * rating / 100
	elif type == ItemKind.Kind.GROUP_7 and index == ItemKind.CAPTURE_BALL_INDEX:
		rating = CAPTURE_BALL_PERCENT * rating / 100
	elif type == ItemKind.Kind.GROUP_7 and index == ItemKind.CAPTURE_BALL_STRONG_INDEX:
		rating = CAPTURE_STRONG_BALL_PERCENT * rating / 100
	if int(target.get("species", 0)) > 999:
		rating /= 8
	return rating


## 捕获成功的个体：原生 `Battle_Capture_Action_mRun` 把战斗里的 `MonsterState` 整份
## `Ball_stdInit(…, -1, 100, 100, 100, 100)` 后 `Ball_stdAddEx` 进背包——血量／SP／速度按 100、
## 成长（`mastery_value`）归 `-1` 即沿用主角流派。本工程的存档记录只保存
## `[species, level, awakened, equipment, …]`（见 `menu_model.native_member_details`），
## 所以这里同样只带这四项，其余留空。
static func capture_record(ball: Dictionary) -> Dictionary:
	var args: Array = ball.get("native_arguments", [])
	# 入包后的记录按 `Ball_stdSet` 的初值走：`food_value` 100、`feel_value` 0（捕获不改这两项）。
	return {"species": int(args[0]), "level": int(args[1]),
		"nativeArguments": [int(args[0]), int(args[1]), int(args[5]), -1, 0],
		"nickname": int(ball.get("nickname", 0)), "experience": 0,
		"feel": int(ball.get("feel", 0)), "food": int(ball.get("food", ItemEffect.FOOD_MAX)),
		# 捕获沿用战斗里那只球的 `brain_current`（原生 `Ball_stdAddEx` 整份记录入包），
		# `brain_limit` 仍是 `Ball_stdSet` 的 99。
		"brainCurrent": int(ball.get("brain_current", BRAIN_CURRENT_INITIAL)),
		"brainLimit": int(ball.get("brain_limit", BRAIN_LIMIT))}


## 记录里的觉醒档：`native_arguments[2]` 就是 `Ball_stdSet` 的 `a7`，
## 1 表示 `definition_id` 已加过 1000（记录里的物种号仍存基础号）。
static func record_awakened(member: Dictionary) -> bool:
	var args: Variant = member.get("nativeArguments")
	return args is Array and args.size() > 2 and int(args[2]) == 1


## 存档记录侧的觉醒（结算 `Battle_Win_SetResult` 的 `Ball_stdFeel` 与菜单侧
## `Ball_stdUse` 改的都是记录本身）：心情归 0（`Ball_stdFeel` 把旧状态码 0 写回 `feel_value`）、
## 觉醒档置 1。HP／SP 由调用方按 `Ball_stdBasic` 重算后的上限回满；记录不带被动表，
## 标准被动槽 2–5 的清理只落在战斗内那只球的 `passives` 上（见 `_awaken`）。
static func awaken_record(member: Dictionary) -> void:
	member["feel"] = 0
	member["nativeArguments"][2] = 1


## 原生 `Battle_Capture_Item_init`：捕获道具只列 `Battle_Item_Capture_Get` 的 bag 4，
## 选中后 `Battle_Capture_Hide_*` → `Battle_Capture_Action_*`（投球 ANI 18 播完才算
## `IsCapture`）。这里没有战斗里的主角立绘对象，投球用固定 6 帧代替，结果帧播 `b_effect`
## 的 37（成功）／38（失败），`mPaint` 的 msg.fxt:12／11 由视图显示在说明行。
## 与原生一致：**球先扣**（`Item_stdDel(item, 1, 1)` 在 `IsCapture` 里）、判定失败也照样消耗；
## 捕获成功的对象随即移出战斗（原生 `Object_objRemove`），留下 `record` 给调用方入包。
func capture(item: Dictionary, target_index: int) -> Dictionary:
	if result != null:
		return {"ok": false, "error": "战斗已结束"}
	if not unavailable.is_empty():
		return {"ok": false, "error": unavailable}
	if not allow_flee:
		return {"ok": false, "error": "这场战斗不能捕获"}
	if standard_level < 0:
		return {"ok": false, "error": "标准进度未记录，无法确认捕获率"}
	if not targets().has(target_index):
		return {"ok": false, "error": "目标不在原有效敌方候选中"}
	if not item.get("type") is int or not item.get("index") is int:
		return {"ok": false, "error": "捕获道具记录不可用"}
	var target: Dictionary = balls[target_index]
	var arguments: Variant = target.get("native_arguments")
	if not arguments is Array or arguments.size() < 6:
		return {"ok": false, "error": "对手没有记录原始参数；未执行捕获"}
	var rating := capture_rating(target, item, _roll(100),
		hero_ability, preferred_mastery, standard_level)
	var caught := _roll(1000) < 10 * rating
	var record := capture_record(target) if caught else {}
	var steps: Array[Dictionary] = []
	for frame in CAPTURE_THROW_FRAMES + CAPTURE_RESULT_FRAMES:
		var step := {"actor": actor, "action": AniAction.Clip.IDLE, "frame": 0, "hits": []}
		if frame == CAPTURE_THROW_FRAMES:
			step["capture"] = {"target": target_index, "caught": caught,
				"effect": CAPTURE_EFFECT if caught else CAPTURE_EFFECT_FAIL}
		steps.append(step)
	if caught:
		balls[target_index] = {}
	log.append("%d 捕获%s" % [int(balls[actor]["species"]), "成功" if caught else "失败"])
	turns += 1
	select_actor()
	return {"ok": true, "caught": caught, "steps": steps,
		"record": record, "rating": rating}


func _frame_count(frame_counts: Dictionary, species: int, action_index: int) -> int:
	var species_counts: Dictionary = frame_counts.get(species, {})
	var count := int(species_counts.get(action_index, 0))
	if count <= 0:
		return -1
	return count


func _frame_count_error(species: int, action_index: int) -> String:
	return "缺少有效动画帧数：species=%d action=%d" % [species, action_index]


## 原生冲刺（`Battle_Monster_00NN_procCurr` 的 `case 20／21`）：每帧 `x += dash * (n + k)`——
## `(n + 1)`／`~n` 是 k = +1（首帧就冲出去）、`x -= dash * n` 是 k = 0（首帧位移为 0）、
## `(n - 1)`／`(1 - n)` 是 k = −1、`(n + 2)` 是 k = +2（`Battle_Monster_0114_procCurr` 的 `case 21`）；
## `dash` 与 k 都是 `battle-species.tres` 的段字段（`dash`／`dash_addend`，由
## `script\export_battle_species.py` 的 `dash_term()` 从立即数导出）。位移是累加的，所以第 `step`
## 帧（0 起）画出来的偏移是 `dash * Σ_{i=0..step} (i + k) = dash * (step + 1) * (step + 2k) / 2`
## （k = +1、dash = 32 时 32、96、192…）。`dash` 来自该物种这一段分支里的立即数
## （物种 0 是 16，其余多是 32）。我方（`direction == 1`）朝敌方是 −x，敌方朝我方是 +x。
static func dash_offset(direction: int, step: int, dash: int, addend: int) -> float:
	if dash <= 0:
		return 0.0
	var sign := -1 if direction == BattleSide.Code.PLAYER else 1
	return float(sign * dash * (step + 1) * (step + 2 * addend)) / 2.0


## 该动作是否有「对所有敌方对象逐个结算」的命中（原生 `BattleData + 20676` 的循环）。
static func _hits_all(segments: Array) -> bool:
	for segment: Dictionary in segments:
		for hit: Dictionary in segment["hits"]:
			if bool(hit["all"]):
				return true
	return false


## 分身的播放计划：全局帧号 = 前面各段帧数之和 + `Object_objCreate` 那一帧。
## 返回 `String` 表示缺少该分身动作的帧数。
func _clone_plan(segments: Array, frame_counts: Dictionary, animation_species: int) -> Variant:
	var plan: Array = []
	var offset := 0
	for segment: Dictionary in segments:
		var clip := AniAction.action_of(int(segment["animation"]))
		var count := _frame_count(frame_counts, animation_species, clip)
		if count <= 0:
			return _frame_count_error(animation_species, clip)
		for clone: Dictionary in segment["clones"]:
			var clone_clip := AniAction.action_of(int(clone["animation"]))
			var frames := _frame_count(frame_counts, animation_species, clone_clip)
			if frames <= 0:
				# 原生 ANI 里没有该分身动作（物种 106 播 22／23，而导出只有 0–7），
				# 分身无法绘制；它的命中已经落在本体那一段里，不重复结算。
				continue
			plan.append({"start": offset + int(clone["frame"]), "action": clone_clip,
				"frames": frames, "dash": int(clone["dash"]),
				"dash_addend": int(clone["dash_addend"]), "all": bool(clone["all"])})
		offset += count
	return plan


## 第 `index` 帧要画的分身（原生生成时 `Object_objPOS(分身, 本体 x, 本体 y + 1, 0, -1)`：分身盖在
## 本体上，之后每帧由 `Battle_Monster_procPosition` 按该分身动作的 form／code 摆到「**自己的**目标
## 那一槽 ± a4」（`battle-poses.tres`，与本体同一张表），再按 `case 20／21` 逐帧
## `x += dash * (n + k)` 冲出去）。
## `all` 的分身是原生对**每个**敌人各建一具（`Battle_Monster_0062_procCurr` 按 `BattleData + 20706`
## 的循环 `Object_objCreate`），每个都挂在自己那个敌人序号上，所以这里按 `clone_targets` 逐个展开。
func _clone_steps(plan: Array, index: int, direction: int, actor_index: int,
		action_target: int, clone_targets: Array) -> Array:
	var output: Array = []
	for clone: Dictionary in plan:
		var start := int(clone["start"])
		if index < start:
			continue
		var step := index - start
		if step >= int(clone["frames"]):
			continue
		var dash := dash_offset(direction, step, int(clone["dash"]), int(clone["dash_addend"]))
		var clone_targets_for_clone: Array = clone_targets if bool(clone["all"]) else [action_target]
		for clone_target: int in clone_targets_for_clone:
			output.append({"origin": actor_index, "target": clone_target,
				"action": int(clone["action"]), "frame": step,
				"offset": Vector2(dash, 1)})
	return output


func act(action: String, target: int, frame_counts: Dictionary = {}) -> Dictionary:
	if result != null:
		return {"ok": false, "error": "战斗已结束"}
	if not unavailable.is_empty():
		return {"ok": false, "error": unavailable}
	if not ["attack", "skill", "guard"].has(action):
		return {"ok": false, "error": "无效行动"}
	var actor_index := actor
	var ball: Dictionary = balls[actor_index]
	var skill := action == "skill"
	if skill and not skill_available(ball):
		return {"ok": false, "error": "原技能冷却中或SP不足" if not ball.statuses.has(StatusEffect.Code.SEAL) else "技能被封印"}
	# 原生 `Battle_Attack_init`／`Battle_Attack_mRun`：`ext[539]` 非 0 时目标与镜头
	# 都取 `obj+264`，玩家在目标面板选的都不算。
	if action != "guard" and int(ball["priority"]) > 0:
		target = int(ball["designated_target"])
	if action != "guard" and not targets().has(target):
		return {"ok": false, "error": "目标不在原有效敌方候选中"}

	var species := combat_species(int(ball["species"]))
	var animation_species := int(ball.species)
	var segments: Array = BattleSpeciesTable.segments(species, skill)
	if segments.is_empty():
		return {"ok": false, "error": "怪物%d没有记录攻击／技能分段" % species}
	# 本体按原生顺序播的段：每段的 ANI 动作与帧数。`Battle_Monster_procNext` 正常的
	# 物种在攻击／技能播完就回待机，只有少数物种会被 `procNext` 接着播 20／21 段。
	var timeline: Array[Dictionary] = []
	var clones: Array = []
	if action != "guard":
		for segment: Dictionary in segments:
			var clip := AniAction.action_of(int(segment["animation"]))
			var count := _frame_count(frame_counts, animation_species, clip)
			if count <= 0:
				return {"ok": false, "error": _frame_count_error(species, clip)}
			var needed := count
			for hit: Dictionary in segment["hits"]:
				# 命中帧可以超过单趟帧数：原生 `same_animation_request_count * frame_count + frame_index`
				# 是跨循环累计的（物种 106 的分身动作只有 7 帧，命中在第 8／11 帧，即第二趟）。
				needed = maxi(needed, int(hit["frame"]) + 1)
			for frame in range(needed):
				timeline.append({"action": clip, "frame": frame % count, "counter": frame,
					"hits": segment["hits"]})
		var plan: Variant = _clone_plan(segments, frame_counts, animation_species)
		if plan is String:
			return {"ok": false, "error": plan}
		clones = plan
	# 分身的敌人名单在**行动开始时**就固定（原生 `BattleData + 20676` 那张目标表由
	# `Battle_Attack_init`／`Battle_Skill_init` 建档，中途死人也不会缩短循环次数），
	# 所以要在结算任何命中之前取，不能边走时间轴边问 `targets()`。
	var clone_targets: Array = targets() if action != "guard" else []

	var hits_all := _hits_all(segments)
	var attack_targets: Array = targets() if hits_all else [target]
	# 物种的技能码（原生 `Battle_Monster_procSkill` 的返回值 = `Param_dmg2SKILL` 的 `n0x31`）：
	# 它既是 `Param_dmg2SKILL` 的 `switch` 键，也是这条状态占的主动效果槽号。
	var status_code := BattleSpeciesTable.status(species) if skill else 0
	var status_only := MODELED_STATUS.has(status_code)
	var percent_hp := PERCENT_HP_CODES.has(status_code)
	var pool: Dictionary = {}
	if action != "guard" and not status_only and not percent_hp:
		for index in attack_targets:
			pool[index] = _base_damage(ball, balls[index], skill)
	_delay(ball)
	if skill:
		ball["cooldown"] = 2 if species == 62 else 1
		ball["sp"] = int(ball["sp"]) - 1
		# 原生 `Battle_Delay_init`：`Battle_Delay_Proc` 之后、本回合是技能时把 `ext[536]`
		# 写成这一手的目标组（`0x34e16` 单体 1／`0x34de8` 全体 2），随后被动 64 掷中就把刚写的
		# 清回 0（`0x34dfe` → `0x34e20`）。
		ball["ai_target_group"] = AiTargetGroup.ALL if hits_all else AiTargetGroup.SINGLE
		if _roll(100) < int(ball.passives[SKILL_BACKOFF_PASSIVE]):
			ball["ai_target_group"] = AiTargetGroup.NONE

	var steps: Array[Dictionary] = []
	if action == "guard":
		# `Battle_Defence_init` → `Param_dmg2SKILL(自身, 自身, 0x21, 100)`：写槽 33
		# （`id 1`、持续 17、层数 +1），`Param_def1ACTIVE` 每层 +100% 防御，挨打时被清掉。
		_apply_slot(ball, StatusEffect.Code.DEFENCE, 1)
		steps.append({"actor": actor_index, "action": AniAction.Clip.IDLE, "frame": 0, "hits": []})
	else:
		for index in range(timeline.size()):
			var hits: Array[Dictionary] = []
			for hit: Dictionary in timeline[index]["hits"]:
				if int(hit["frame"]) != int(timeline[index]["counter"]):
					continue
				var hit_targets: Array = targets() if bool(hit["all"]) else [target]
				for hit_target: int in hit_targets:
					if status_only:
						hits.append(_skill_status_hit(actor_index, hit_target, status_code,
							BattleSpeciesTable.skill_code(hit)))
					elif percent_hp:
						hits.append_array(_percent_hp_hit(actor_index, hit_target, status_code,
							int(hit["percent"])))
					else:
						hits.append(_hit(actor_index, hit_target, skill, int(hit["percent"]),
							pool, bool(hit["behind"])))
			var step := {"actor": actor_index, "action": int(timeline[index]["action"]),
				"frame": int(timeline[index]["frame"]), "hits": hits}
			var auxiliary := _clone_steps(clones, index, int(ball.direction), actor_index,
				target, clone_targets)
			if not auxiliary.is_empty():
				step["auxiliary"] = auxiliary
			steps.append(step)

	log.append("%d %s" % [int(ball["species"]),
		"攻击" if action == "attack" else "技能" if action == "skill" else "防御"])
	turns += 1
	select_actor()
	return {"ok": true, "steps": steps}
