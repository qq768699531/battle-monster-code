extends "res://engine/ui/confirm_box/confirm_box.gd"
## 战斗全灭（原生状态 28 DIE，`Battle_Die_*`）的 Box2 窗口。
##
## 原生三个绘制入口共用同一个窗口，只换正文与按键：
## - `Menu_win_Box2_DrawSelect`：子状态 3「使用%s[%s]复活吗?」（`msg.fxt` 23）与
##   子状态 2／6「返回主菜单吗?」（36），正文下点线 + 是／否两颗 44×16；
## - `Menu_win_Box2_DrawOk`：子状态 4／8「全部复活了」（24）与子状态 5
##   「使用100元的情报使用费可以复活」（25），正文下点线 + 一颗 44×16 确定键。
## 子状态 1 的正文取 `Item_datBasic` 的道具说明（本工程的文本表没有该说明，故不单独出页）。
##
## `Battle_Die_init` 先 `Battle_info_Capture()` 把当前画面拍成模糊 + 半透明底，所以本窗用
## `screen_shade = true` 在开窗时挂那一层；窗高与正文摆位和其余 Box2 页共用 `ConfirmLayout`，
## 与逃跑窗是同一个 `engine/ui/confirm_box`，只是多挂一层压暗。
