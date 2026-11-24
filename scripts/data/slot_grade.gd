extends RefCounted
## 品级描边色表。原生一张一档的 `CSWTCH.125`：
## * `Item_stdGradeRGB`：`#FFFFFF`／`#C676FB`／`#FCCF45`／`#FF2020`（4 档，道具）；取色 `Menu_Item_GetRGB`。
## * `Ball_stdGradeRGB`：`#20C0B2`／`#226BFF`／`#FD7139`／`#B85EF3`／`#60A22A`／`#FCCF45`（6 档，球／怪物）；
##   取色 `Menu_Party_GetRGB`。越界档位退化成 `#FFFFFF`。
## 描边画法见 `wiki\ui\slot-frame.md` 第 1 节：1 px、圆角 1、叠在 `Menu_winDrawIcon16` 的格底上。
const ITEM_GRADE_RGB := [
	Color("#ffffff"), Color("#c676fb"), Color("#fccf45"), Color("#ff2020"),
]
const BALL_GRADE_RGB := [
	Color("#20c0b2"), Color("#226bff"), Color("#fd7139"),
	Color("#b85ef3"), Color("#60a22a"), Color("#fccf45"),
]


## `Menu_Item_GetRGB`／`Menu_Party_GetRGB` 的取色结果：负数表示没有品级（不画描边），
## 超出表长的档位退化成白（原生 `CSWTCH.125` 之外的默认值）。
static func of(grade_index: int, party_member: bool) -> Variant:
	var palette: Array = BALL_GRADE_RGB if party_member else ITEM_GRADE_RGB
	if grade_index < 0:
		return null
	return palette[grade_index] if grade_index < palette.size() else Color.WHITE
