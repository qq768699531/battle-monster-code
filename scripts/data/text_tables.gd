extends Resource
class_name TextTables

## 文本结构总表：源标识 → payload（与原生一致的结构字典）。
##
## 只存结构（记录号、分组、flags、opcode 序列），正文一律在 `assets/translations/zh_CN.tres`。
## qst 在 `assets/events.tres`，地图信息在地图 Scene，都不在这里。

## 任务正文的源标识：`Qst_stdSET@0x93B34:31-33` 的 `EFC_fsLoadRES("qst/qstlist.fxt")`，
## 任务页与任务详情页共用这一处（`JC_fxtCOPY(RES, quest_id)` 按任务号取正文）。
const QUEST_SOURCE := "qst/qstlist.fxt"

@export var payloads: Dictionary = {}
