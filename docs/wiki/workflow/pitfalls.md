# 已知陷阱与调试

本页是 `AGENTS.md`「已知陷阱」「调试」的全量条目。`AGENTS.md` 只留最常踩的几条并指回本页。

## 调试

- **没有监听器，也没有调试快照**：不要引入「起进程 → 改源码 → 自动重启恢复现场」的一环，
  直接用 `godot --path .\game` 或编辑器跑。
- 手工复现某一次战斗／某个界面时，靠 `wiki` 与 beads 条目里记录的入口与存档操作走到那一步，不靠读档重放。
- 池化的一次性表现（`Field/Hits`、`Field/Effects`，`field.gd` 的 `TRANSIENT_POOL`）只在 `present()` 里建，
  不是持久状态，调试时按需触发。
- 显示 800×480（2 倍），逻辑 400×240。


## 已知陷阱

- **编辑器的内存副本会盖掉磁盘上的 `.tscn`**：Godot 编辑器会把打开着的场景整份从内存重存（顺带写入
  `uid`／`unique_id` 序列化差异），磁盘上的改动会被这份旧副本覆盖——表现为「改了没生效」「刚提交的内容
  其实是旧的」。实测 2026-11-22 `item_cell.tscn` 被覆盖两次，第一次甚至把错误内容提交进了 git。
  处置见「改动与热重载（强制）」：以磁盘为准并请用户重载该场景，**不要**反复重写同一份文件。
- **野外服务页的守卫链会越加越长**：每个页面各引入一个 `*_open` 布尔并并进所有同级守卫链（现在有
  `guild_open`／`shop_open`／`quest_open`／`inn_open`，每加一页要改二十来行）。接线能通、`test_field_runtime`
  也逐页覆盖「开页 → 释放 → `story.paused` 复位」，但**再加页之前应先把它们合并成 `service_open()`
  一处判定 + 单一 key 路由**（该技术债见 beads `bm-82`）。
- **盖住窗口的往往不是 `z_index`**：`menu.tscn` 的 `world_map` 在 `quest_detail` 之后，看起来该在最上层，实际被菜单自身的
  chrome（`Frame` 顶白条 + `Tab0..5`，`get_index()` 更大）压住；原生是靠 `Menu_Quest_mPaint` 在 overlay 2
  **跳过** `Menu_win_DrawBasic` 解决的。判层次先量 `get_index()` 与全局矩形，别先加 `z_index`。
- **`ext[539]` 不是「蓄力百分比」**：它是「本回合抢在所有人之前行动 + 指定目标」（`Battle_Ready_Set` 写、
  `Battle_Character_init` 当行动值权重、`Battle_Delay_Proc` 消费清零）。35／36 是「被打后立即反击」，
  不是缩放自己下一次攻击。
- **`Battle_Monster_procSkill()` 的返回值就是技能码**（`Param_dmg2SKILL` 的 `n0x31`），`battle-species.tres` 老的
  `status` 字段一直存的就是它；不要把它当成「缺失的数据」。
- 批量改写 CSV/大资源要写临时文件再原子替换。曾因「先截断再写」让并发的 Godot 进程读到半张表直接启动报错。
- **容器重排是延后的**：`GridContainer` 这类容器在隐藏状态下加入场景时排序请求会被丢掉，`show()` 的同一帧里所有格子还叠在容器原点，一帧之后才散开。所以「打开窗口 → 立刻点某格」必须在取矩形前 `await get_tree().process_frame`（`test_battle_view` 道具网格 8 条失败就是点在叠起来的最上面那格 `Cell17` 上）；产品侧靠开窗动画掩盖这一帧，不需要额外补排序。
- Godot 4 默认把 `.csv` 当翻译源（`csv_translation`，首列当 msgid、列头当语言）。若将来再引入数据 CSV，必须显式 `importer="keep"`，否则 `--import` 会生成一堆 `.translation` 副产物。
- typed `Array[int]` 会把 `0.5` 静默截断成 `0`，会悄悄废掉「拒绝非整数」的用例。
- `TextureRect` 的 `STRETCH_KEEP_CENTERED` 把偏移算成浮点：奇数尺寸会落在半像素上，最近邻采样会重复或丢掉一列像素。需要「原生整数原点」的图标（如 `item_icon.tscn`）要自己用 `draw_texture_rect` 画，`item_cell.tscn` 的 Icon 因此是实例化的子 Scene，不是带脚本的裸子节点。
- 实例全矩形 anchors 不会清除继承的 offsets，需要清零的要显式清零。
- 节点加入树后再 configure，保证 `@onready` 可用。
- 用例不要在顶层 preload `MainScene`，放到 deferred 的 `_run()` 里动态 load：顶层 preload 会让整个主场景在脚本编译期就进来，加载失败会连累同一文件的其它断言。
- `.tres` 的 payload 里可能有真实控制字符，不要假设是严格 JSON。
- **别在动画回调栈里拆树**：`AnimationPlayer.animation_finished` 触发后宿主立刻 `remove_child` +
  `queue_free` 会让引擎直接崩（2026-11-22 实测飞艇点确认 → signal 11）；同一帧里两个
  `AnimationPlayer` 各播一条收窗动画、再在 `closed` 里拆树也会崩。做法：先收的那层直接 `hide()`
  只留一条收窗动画，宿主的收尾信号用 `closed.emit.call_deferred()` 推到空闲队列再拆。
- **首次开战卡顿不是「加载慢」**：导出的 ANI 场景给每个 `Animation` 标了 `resource_local_to_scene`，
  清标志前的首次 `instantiate()` 会深拷贝整份动画库（单只 128 ms 量级），在 `start()` 里批量实例化
  就是那 900 ms。要摊平只能用 `MonsterAnimation.warm()`（只读入 + `_normalize_scene` 清标志、不实例化）
  ＋ `field_runtime` 的预读队列，别在同步路径里 `instantiate()`。见 `../battle/battle-performance.md`。
- **别用 `Start-Process` + `Stop-Process $p.Id` 管进程**：工具守卫会直接拒绝这类调用。长驻服务用
  async／detach 起，要停就 `Stop-Process -Id <PID>` 显式给 ID；子代理自检挂住也用这条收尾。
