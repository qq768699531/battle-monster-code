extends RefCounted
class_name BattleSide
## 原生战斗对象的 `direction_code`：`Battle_objNextDirect` 给我方表（+20650）写 1、
## 敌方表（+20654）写 2，`Battle_objGetPosition`／`Battle_objPOS`／`Object_drawSPRITE` 都用它
## 决定坐标增减与镜像方向。地图侧的朝向码不是这一套（见 `FieldAction` 与 `field_actors`）。

enum Code {
	PLAYER = 1,
	ENEMY = 2,
}
