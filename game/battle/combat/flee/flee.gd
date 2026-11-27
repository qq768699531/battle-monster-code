extends "res://engine/ui/confirm_box/confirm_box.gd"
## 战斗逃跑窗（原生状态 18 `RUN`，`Battle_Run_*`）。同一个 Box2 160×57 窗有两页：
## - 子状态 0 `Menu_win_Box2_DrawSelect`：`msg.fxt` 7「要逃跑吗?」+ 是／否，
##   `Battle_Run_init` 把光标初值置 1（默认「否」）；
## - 子状态 1／2 `Menu_win_Box2_DrawOk`：`msg.fxt` 8「逃跑成功」／9「逃跑失败」+ 确定键。
## 原生落键后先把窗关上（相位 −1），`Battle_Run_mRun` 收到 −4 才重开窗显示结果，
## 所以调用方按「关 → 换文 → 开」两段驱动；第一页按 CLR 等价于「否」。
##
## 窗框、正文折行、点线与按键摆位、光标与落键都在 `engine/ui/confirm_box`，本页只保留原生出处。
