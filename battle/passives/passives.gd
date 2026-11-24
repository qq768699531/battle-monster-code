extends Node
## 被动技能：把 0–5 号槽位折算成 66 项效果表（原生 `Param_passiveSet`）。
## 数据在同目录 `passives.tres`，条目类型在 `passive_definition/`。

const PASSIVE_EFFECT_COUNT := 66


static func effect_table(catalog: GameplayData, slots: Array) -> Array[int]:
	var passives: Array[int] = []
	passives.resize(PASSIVE_EFFECT_COUNT)
	passives.fill(0)
	for entry: Array in slots:
		var level := int(entry[1])
		if level <= 0:
			continue
		var found: PassiveDefinition = catalog.passive(int(entry[0]))
		assert(found != null)
		var effect := found.effect
		assert(effect >= 0 and effect < passives.size())
		passives[effect] = (passives[effect] + found.base +
			(level - 1) * found.increment) & 255
	return passives
