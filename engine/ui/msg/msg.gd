extends RefCounted
class_name Msg
## `common/msg.fxt` 的记录号（原生 `JC_fxt2Return(index)`）：界面文案的唯一入口。
##
## 记录号是原生数据里的裸数字，进逻辑前必须在这里起名——`python script\check_conventions.py`
## 的 `no-magic-message-id` 会拦住 `text_message("common/msg.fxt", <数字>)` 这种写法。
## 正文本身在 `assets\translations\zh_CN.tres`（键 `common/msg.fxt:<记录号>`）。

## 文本源标识：`assets\text-tables.tres` 里的源键，即 `text_message()`／`text_messages()` 的
## 第一个参数。表由原生 `EFC_fsLoadRES("common/msg.fxt")` 载入（`JC_fxt2Return` 的取值来源），
## 全工程只此一处——别在页面里另写字符串字面量或自带 `*_SOURCE` 常量。
const SOURCE := "common/msg.fxt"

enum Id {
	## 自动战斗开启（`BattleCanvas_mKeyPressed:28-36`：`BattleData+24` 从 0 置 1 后，
	## `+25` 的「本场已提示」闸未置位时 `Game_infoInit(-1, JC_fxt2Return(0))`，随后置位）。
	AUTO_BATTLE = 0,          ## 自动战斗时,获得60%的经验
	FLEE_PROMPT = 7,          ## 要逃跑吗?
	FLEE_SUCCEEDED = 8,       ## 逃跑成功
	FLEE_FAILED = 9,          ## 逃跑失败
	CAPTURE_FAILED = 11,      ## 抓捕失败
	CAPTURE_SUCCEEDED = 12,   ## 抓捕成功
	## 相性伤害增减（`Param_dmg2BASIC` 的 `0x79056`：本次伤害 `v25 > 0`、
	## 相性有利 `v45 == 1` 推 407、不利 `v44 == 1` 推 408）。
	DAMAGE_ADVANTAGE = 407,    ## 属性相克导致技能伤害上升
	DAMAGE_DISADVANTAGE = 408, ## 属性相克导致技能伤害下降
	REVIVE_PROMPT = 23,       ## 使用%s[%s]复活吗?
	REVIVE_DONE = 24,         ## 全部复活了
	REVIVE_INFO_FEE = 25,     ## 使用100元的情报使用费可以复活（`Game_Cash_*`，P3-4）
	## 战斗内系统菜单（原生状态 30 CLEAR 的标题与四行；`Battle_Clear_mPaint` 逐条
	## `JC_fxt2Return(31..35)`，顺序＝列表行序＝返回码 0–3，见 `battle_ui/sys_menu.gd`）。
	BATTLE_CLEAR_TITLE = 31,       ## 设定
	BATTLE_CLEAR_CONTINUE = 32,    ## 继续
	BATTLE_CLEAR_SETTINGS = 33,    ## 环境设定
	BATTLE_CLEAR_HELP = 34,        ## 帮助
	BATTLE_CLEAR_MAIN_MENU = 35,   ## 主菜单
	RETURN_TO_MENU = 36,      ## 返回主菜单吗?
	WARP_UNAVAILABLE = 37,    ## 暂时不可传送（`Field_Basic_mKeyPressed` 的 key 48 分支：
	                          ## `map_file_number` ∈ {2, 4} 时只 `Game_infoInit` 这一条，不开 WARP1）
	WARP_BOARD_CONFIRM = 42,  ## 前往飞艇吗?（`Field_Warp1_mPaint` 的 `Menu_win_Box2_DrawSelect` 正文）
	WARP_CANNOT_MOVE = 43,    ## 不能移动（`Field_Warp2_mKeyPressed` 校验失败）
	WARP_CONFIRM_MOVE = 44,   ## 要移动吗?（`Field_Warp2_mPaint` 的 Box2 正文）
	GUILD_LIST_TITLE = 50,    ## 公会事务所（状态 6 列表页标题）
	GUILD_CHALLENGE = 51,     ## 公会排名挑战
	GUILD_QUEST = 52,         ## 公会任务
	GUILD_INFO = 53,          ## 会长的建议
	GUILD_CHALLENGE_TITLE = 54,      ## 公会事务所（状态 7 挑战页标题）
	GUILD_CHALLENGE_SUBTITLE = 55,   ## [公会排名挑战]
	GUILD_CHALLENGE_RANK = 56,       ## 现在的排名:%d（`ParamData.guild_code_bits`）
	GUILD_CHALLENGE_OPPONENT_RANK = 57, ## 对手的排名:%d（`guild_code_bits − 1`）
	GUILD_CHALLENGE_UP = 58,         ## 胜利后排名上升一位
	GUILD_CHALLENGE_PROMPT = 59,     ## 要挑战吗?
	GUILD_INFO_TITLE = 60,    ## 公会事务所（状态 9 资料页标题）
	GUILD_INFO_SUBTITLE = 61, ## [会长的建议]
	GUILD_QUEST_RANK = 47,    ## 可接受公会排名%d以上（任务页：待接任务的档位要求）
	GUILD_QUEST_NONE = 48,    ## 没有任务了
	GUILD_QUEST_TOP = 49,     ## 最高公会排名
	GUILD_TITLE_FIRST = 459,  ## 公会档位名第 0 档「试练生」（`Ball_guildTitle`：459 + 档位，
	                          ## 末档 469「驯兽圣帝」；档位见 `MenuModel.guild_grade`）
	ITEM_WINDOW_TITLE = 75,   ## 道具（战斗道具窗口标题）
	CAPTURE_WINDOW_TITLE = 77, ## 道具（捕获球窗口标题，正文与 75 相同）
	ANSWER_YES = 85,          ## 是
	ANSWER_NO = 86,           ## 否
	BOX_EMPTY = 94,           ## 什么都没有
	BOOK_TITLE = 97,          ## 图鉴
	BOOK_MONSTER_PAGE = 98,   ## 精灵
	BOOK_SKILL_PAGE = 99,     ## 技能书
	BOOK_SKILL_SUBTITLE = 166, ## [技能书]
	## 初始精灵选择（一级 `Game_Character_Select_mPaint` → `Menu_CharacterSelect_Draw`、
	## 二级 `Game_Book_Monster_mPaint`），见 wiki\growth\starter-select.md。
	MASTERY_TITLE = 96,            ## 属性决定（`:7` 的 `JC_fxt2Return(96)` 交给 `Menu_win_Box4_DrawTitle`）
	BOOK_LOADING = 100,            ## 读取中.（`Game_Book_Monster_mPaint:19-22` 的 `Menu_win_Box2_DrawMessage`）
	STARTER_CONFIRM = 101,         ## [%s]确定吗?（`:33`，%s 是 `Item_datBasic` 读出的物种名）
	MASTERY_NAME_WATER = 154,      ## [水（`Menu_CharacterSelect_Draw:56-61` 的 v44 六个流派名）
	MASTERY_NAME_FIRE = 155,       ## [火
	MASTERY_NAME_WOOD = 156,       ## [木
	MASTERY_NAME_WIND = 157,       ## [风
	MASTERY_NAME_LIGHT = 158,      ## [光
	MASTERY_NAME_DARK = 159,       ## [暗
	MASTERY_HEADLINE = 160,        ## 主角的 （`:93`，子相位 ≥ 0 才拼；与 161 连成头部那一行）
	MASTERY_HEADLINE_SUFFIX = 161, ## 请确认属性（`:97`）
	MASTERY_FOOTER = 162,          ## %s属性]精灵（`:105`，%s 是 154–159 之一）
	MASTERY_FOOTER_SUFFIX = 163,   ## 正确使用（`:116`）
	MASTERY_CONFIRM = 164,         ## 决定吗?（`:177-178` 的 `Menu_win_Box2_DrawSelect` 正文）
	## 选项页「存档」的两段 Box2 弹窗（`Menu_Option_mPaint:32-52`）：
	## 层 1／2 是 `Menu_win_Box2_DrawMessage` 的 199，层 3 是 `Menu_win_Box2_DrawOk` 的 200。
	SAVE_IN_PROGRESS = 199,   ## 存档中...
	SAVE_DONE = 200,          ## 存档完毕
	## 选项页「存档」在剧情门槛下的拒绝（`Menu_Option_mKeyPressed:37-40`：`transition_parameter_bits == 0`
	## 且 `ParamData.current_event_resource_id <= 2` 时只 `Game_infoInit(-1, JC_fxt2Return(198))`，
	## 层号不置 1、弹窗根本不开）。与野外存档页的 38 同文、不同记录。
	OPTION_SAVE_UNAVAILABLE = 198,  ## 现在无法存档
	## 野外存档页（`FieldCanvas` 状态 2）的三条：`Field_Save_mPaint:13-25` 的画法依次是
	## 纯消息 39（「数据存档ing...」）→ 写盘 → `Menu_win_Box2_DrawOk` 的 41（「已存档」）；
	## 30 秒未完成 / 不可存档时用 38（「现在无法存档」，`Field_Basic_mKeyPressed` 的失败分支）。
	FIELD_SAVE_UNAVAILABLE = 38,   ## 现在无法存档
	FIELD_SAVE_IN_PROGRESS = 39,   ## 数据存档ing...
	FIELD_SAVE_DONE = 41,          ## 已存档
	LOCKED = 150,             ## [已上锁]（道具/装备栏的空位提示）
	MAP_BLOCKED = 404,        ## 暂时不能通国.
	## 精灵管理所（`GAME_STATE_MONSTER_LIST` = 21）：`Game_Monster_List_mPaint` 传给
	## `Game_Menu_List_Draw` 的三处 `JC_fxt2Return` 实参——标题 102、两个条目 103／104。
	MONSTER_OFFICE = 102,     ## 精灵管理所
	MONSTER_MIX = 103,        ## 精灵合成
	MONSTER_ENCHANT = 104,    ## 精灵强化
	## 强化页（`GAME_STATE_MONSTER_ENCHANT` = 23，`Game_Monster_Enchant_Draw`）：
	## 副标题 124、两个按钮 122（选强化剂）／123（强化）、成功率 125、费用 126，
	## 拒绝分支 127（已满）／128（强化剂不足）／79（金币不足），
	## 执行中／失败／成功 106／108／110（`Game_Monster_DrawInfo2`），
	## 掷骰加成 558（`Game_Monster_Enchant_Proc`）。
	MONSTER_ENCHANT_TITLE = 121,      ## 精灵管理所（强化页标题；与列表页的 102 同文不同记录）
	MONSTER_ENCHANT_SUBTITLE = 124,   ## [精灵强化]
	MONSTER_ENCHANT_ITEM = 122,       ## 强化剂选择
	MONSTER_ENCHANT_RUN = 123,        ## 强化
	MONSTER_ENCHANT_PERCENT = 125,    ## 强化概率
	MONSTER_ENCHANT_FEE = 126,        ## 强化费用
	MONSTER_ENCHANT_FULL = 127,       ## 已经不能强化了
	MONSTER_ENCHANT_SHORTAGE = 128,   ## 强化剂不足
	MONSTER_ENCHANT_RUNNING = 106,    ## 精灵强化中.
	MONSTER_ENCHANT_FAILED = 108,     ## 精灵强化失败
	MONSTER_ENCHANT_SUCCEEDED = 110,  ## 精灵强化成功
	MONSTER_ENCHANT_BONUS = 558,      ## 强化成功率%d%% 增加
	## 合成页（`GAME_STATE_MONSTER_MIX` = 22，`Game_Monster_Mix_Draw`）。
	## 标题 111（与列表页的 102 同文不同记录）、副标题 114、两个按钮 112（选合成石）／113（合成）、
	## 成功率 115、费用 116，拒绝分支 117（品级 5）／118（带装备）／79（金币不足），
	## 执行中／失败／成功 105／107／109（`Game_Monster_DrawInfo2` 的 22 号分支），
	## 掷骰加成 557（`Game_Monster_Mix_Proc`）。
	MONSTER_MIX_TITLE = 111,          ## 精灵管理所（合成页标题）
	MONSTER_MIX_SUBTITLE = 114,       ## [精灵合成]
	MONSTER_MIX_ITEM = 112,           ## 选择合成石
	MONSTER_MIX_RUN = 113,            ## 合成
	MONSTER_MIX_PERCENT = 115,        ## 成功率
	MONSTER_MIX_FEE = 116,            ## 合成费用
	MONSTER_MIX_REFUSED = 117,        ## 不能合成
	MONSTER_MIX_EQUIPMENT = 118,      ## 合成后,身上的装备将会消失
	MONSTER_MIX_LEVEL = 119,          ## 只可同等级合成
	MONSTER_MIX_RUNNING = 105,        ## 精灵合成中.
	MONSTER_MIX_LOW_RESULT = 107,     ## 低等级 精灵合成完毕（`Game_Monster_Mix_Proc` 返回 0）
	MONSTER_MIX_HIGH_RESULT = 109,    ## 高级 精灵合成完毕（同一函数返回 1：品级提升了）
	MONSTER_MIX_BONUS = 557,          ## 合成成功率%d%% 增加
	## 昵称前缀：`471 + 昵称码`，昵称 1–6 → 472–477（有力的／可靠的／华丽的／智慧的／敏捷的／顽强的）。
	## 基址记录 471 本身的正文是「组队点数不足.」（见 `PARTY_POINTS_SHORT`）。
	NICKNAME_PREFIX = 471,
	PARTY_FULL = 470,         ## 组队上限是3.（`Ball_stdIsPartyOn` 第 3 格已占 → −2）
	PARTY_POINTS_SHORT = 471, ## 组队点数不足.（同一函数 PARTY 点超 `Ball_guildPartys` 上限 → −3）
	PARTY_LEVEL_GAP = 559,    ## 不可与比主人公高5级以上的组队（同一函数等级差 → −4）
	ITEM_RECOVER = 480,       ## 恢复
	ITEM_RECOVER_HP_SP = 481, ## 恢复HP和SP %d%%
	ITEM_HP_FULL = 482,       ## 不能再恢复HP了.
	ITEM_SP_FULL = 483,       ## 不能再恢复SP了.
	ITEM_BOTH_FULL = 484,     ## 不能再恢复HP和SP了.
	ITEM_STATUS_CURED = 485,  ## 异常状态已恢复.
	ITEM_NO_STATUS = 486,     ## 没有可治疗的异常状态.
	ITEM_REVIVED = 487,       ## 死去的精灵复活了.
	ITEM_ONLY_DOWN = 488,     ## 只可以复活死去的精灵.
	## 第 1 组 19–24 属性技能上升卡（返回码 11–14 → 489–492，`Ball_stdUseEx:116-131`）。
	ITEM_PASSIVE_UPGRADE_WRONG_KIND = 489, ## 属性（卡属性与怪物 kind 不符）
	ITEM_PASSIVE_UPGRADE_MAX = 490, ## 已经不能升级了.
	ITEM_PASSIVE_UPGRADE_NONE = 491, ## 没有被动技能.
	ITEM_PASSIVE_UPGRADE_DONE = 492, ## 被动技能的等级增加了.
	ITEM_FEEL_FOOD = 493,     ## 增加亲密度以及满足饥饿度.（食物返回码 15／16）
	ITEM_FOOD_RESTORED = 494, ## 满足饥饿度.（返回码 17）
	ITEM_FOOD_STUFFED = 495,  ## 饥饿度已达上限.（返回码 18）
	ITEM_BRAIN_UP = 496,      ## 才能上升了.（第 7 组 3，返回码 19）
	ITEM_BRAIN_MAX = 497,     ## 才能已达上限.（第 7 组 3，返回码 20）
	ITEM_ABILITY_RECOVERED = 500, ## 能力点已退回.（第 7 组 15，返回码 25）
	ITEM_ABILITY_NONE = 501,  ## 没有可退回的能力点.（第 7 组 15，返回码 26）
	ITEM_PASSIVES_CLEARED = 502, ## 已去除被动技能.（第 7 组 21，返回码 29）
	ITEM_PASSIVES_NONE = 503,    ## 没有要去除的被动技能.（第 7 组 21，返回码 30）
	## 道具使用／合成的二级选择窗标题：`Menu_Item_mPaint` 在 quest_layer 9／10 走
	## `Menu_Monster_DrawList(JC_fxt2Return(184), ...)`，即 228×214 Box4 窗的标题。
	ITEM_TARGET_TITLE = 184,  ## 精灵球
	ITEM_TARGET_DOWN = 508,   ## 无法对死去的精灵使用.
	## `Ball_stdUseEx:205-208` 的 `case 36`：经验加成窗口已经在生效时只提示这一条（不扣道具）。
	ITEM_BONUS_ACTIVE = 509,  ## 已在使用中.
	## `Ball_stdUseEx` 的 default：返回码 0 与未登记分支一律取这一条（不扣道具）。
	ITEM_UNUSABLE = 510,      ## 现在无法使用.
	ITEM_MIX_DONE = 504,       ## 合成成功.（第 4 组返回码 31，`Ball_stdUse:169-185`）
	ITEM_MIX_DUPLICATE = 505,  ## 已经学会这个被动了.（返回码 32，`LABEL_96`）
	ITEM_MIX_NO_MATERIAL = 506, ## 材料不足.（`Ball_stdUseEx` 返回码 33，技能书合成用）
	ITEM_MIX_NO_SLOT = 507,    ## 被动槽已满.（返回码 34，`Ball_stdUse:210`）
	## 道具说明记录号（`Item_stdExplain@0x82F70`）：材料（类型 3）在 `:116-118` 只写
	## `n220 = 220; goto LABEL_17`，记录号由 `:136-138` 的 `JC_fxt2Return(2 * n220)` 算出
	## 2×220 = 440（正文「材料道具」）；`ITEM_EXPLANATION_MATERIAL_BASE`（220）本身是「送礼物」，
	## 不是材料说明。同一 `2 * n220` 形态的旁证：类型 5 的 219 → 438。
	ITEM_EXPLANATION_MATERIAL = 440,
	ITEM_EXPLANATION_MATERIAL_BASE = 220,
	## 「发动」：`Param_atkPASSIVE` 的 `0x789C2` 取这条正文，前面按 `"[%s] %s"` 拼被动记录名
	## （`Item_datBasic` 类型 31 的 `name_text`，即 `common/item_skill.dat` 的
	## `item_skill.group.<被动号>.name`），行首再带一档 `#P` 调色板码（我方／敌方）。
	PASSIVE_ACTIVATED = 556,
	## 野外商店（`wiki\field\npc-service-menu.md` §5.8／§5.9，`shop_mode_code` 0 道具／1 装备）。
	SHOP_ITEMS_TITLE = 62,        ## 道具商店（`Field_Item_List_mPaint` 标题）
	SHOP_EQUIPMENT_TITLE = 63,    ## 装备商店
	SHOP_BUY_ITEM = 64,           ## 购买道具
	SHOP_SELL_ITEM = 65,          ## 出售道具
	SHOP_BUY_EQUIPMENT = 66,      ## 购买装备
	SHOP_SELL_EQUIPMENT = 67,     ## 出售装备
	SHOP_FOOD = 70,               ## 食物制作（地图 148 的道具商店第三行）
	SHOP_ITEM_BUY_PAGE = 71,      ## 道具商店-购买（`Field_Item_DrawList` 标题）
	SHOP_EQUIPMENT_BUY_PAGE = 72, ## 装备商店-购买
	SHOP_ITEM_SELL_PAGE = 73,     ## 道具商店-出售
	SHOP_EQUIPMENT_SELL_PAGE = 74, ## 装备商店-出售
	SHOP_NOT_ENOUGH_MONEY = 79,   ## 金币不足
	SHOP_CANNOT_BUY = 80,         ## 不能购买的道具
	SHOP_BAG_FULL = 81,           ## 空间不足
	SHOP_BUY_PROMPT = 83,         ## 要购买吗?
	SHOP_SELL_PROMPT = 84,        ## 要出售吗?
	SHOP_CANNOT_SELL = 87,        ## 不能出售的道具
	## 食物制作（`Field_Item_Food_*`，状态 15）：标题 fxt 78，材料不足 fxt 88；钱不够复用 fxt 79。
	FOOD_CRAFT_TITLE = 78,        ## 食物制作（`Field_Item_DrawList` 的 n6 = 5 分支）
	FOOD_CRAFT_NO_MATERIAL = 88,  ## 材料不足（`Field_Item_Food_Proc` 的 LABEL_7）
	## 旅店（`Field_Inn_mPaint` 的 fxt 90 提示；`Field_Inn_mKeyPressed`
	## 成功后的 fxt 89；失败文案就是商店那条 fxt 79）。
	INN_PROMPT = 90,              ## 要花50金币让队伍里的精灵HP和SP全部恢复吗?
	INN_RESTORED = 89,            ## 全部恢复了
	CONFIRM_OK = 138,             ## 确定
	## 启动页（`Prime_NotMem_mPaint`／`Prime_NotSpace_mPaint`）：欢迎页与存档空间不足页各一组标题+正文。
	STARTUP_NOTICE_TITLE = 562,   ## 启动欢迎页标题（`Prime_NotMem_mPaint` 的 `JC_fxt2Return(562)`）
	STARTUP_NOTICE_BODY = 563,    ## 启动欢迎页正文（同上 `(563)`）
	STARTUP_STORAGE_TITLE = 361,  ## 存档空间不足页标题（`Prime_NotSpace_mPaint` 的 `(361)`）
	STARTUP_STORAGE_BODY = 362,   ## 存档空间不足页正文（同上 `(362)`）
	## 菜单任务页（`MENU_STATE_QUEST` = 3）：列表行的标记与详情页的正文／页脚，实参都在
	## `Menu_Quest_DrawItem` 与 `Menu_Quest_DrawDetail` 里直接写死。
	QUEST_ROW_DONE = 186,         ## [结束]（`Menu_Quest_DrawItem`，达标行右端）
	QUEST_ROW_EMPTY = 187,        ## 无任务（同上，空槽行）
	QUEST_REGION_LABEL = 188,     ## [关联地域]（`Menu_Quest_DrawDetail` 在 `JC_fxt2Return(188)` 前画地域串）
	QUEST_END_NPC_LABEL = 189,    ## [结束NPC]（同上，`QstData + 4` 的 NPC 字段非空时的标签）
	QUEST_ITEM_LABEL = 190,       ## [道具]（同上，目标／道具行的标签）
	QUEST_WORLD_MAP = 191,        ## 世界地图（同上，页脚左按钮正文 + `EFC_mainTouchSET(-3)` 的 49×22 触控区）
	QUEST_ACCEPT = 192,           ## 接受（同上，`Qst_stdFind` 为 null 时的页脚右按钮）
	QUEST_ABANDON = 193,          ## 放弃（同上，任务在册时的页脚右按钮）
	QUEST_ABANDON_PROMPT = 194,   ## 要放弃吗?（`Menu_Quest_Draw` 的 LABEL_13 → `Menu_win_Box2_DrawSelect` 正文）
	QUEST_NO_REGION_INFO = 195,   ## 没有相关情报（`Menu_Quest_DrawDetail` 的 msg 195 分支：详情 OK 但槽里没有地图号）
	## 野外任务详情页（`Qst_chtINIT`／`Qst_chtDRAW`／`Qst_chtKeyPress`）与
	## 菜单侧同一套 `Menu_Quest_DrawDetail`，但提示用自己的一批 `JC_fxt2Return`。
	QUEST_NO_INFO = 511,          ## 没有相关信息（同上，页脚 OK 但任务的 page 3 没有关联地域）
	QUEST_SLOTS_FULL = 512,       ## 不可以再接受更多的任务了.（同上，`Qst_stdEmpty` 抢槽失败）
	QUEST_GUILD_DETAIL_TITLE = 513, ## 公会任务（`Qst_chtDRAW` 按上下文码 2 取标题）
	QUEST_SIDE_DETAIL_TITLE = 514,  ## 支线任务（同上，上下文码 3）
	QUEST_FIELD_ACCEPT_PROMPT = 515, ## 要接受吗?（同上，层 2 的 `Menu_win_Box2_DrawSelect` 正文）
	QUEST_DONE = 410,            ## 「(完成)」（任务完成时的 Game_infoInit）
	QUEST_ACCEPT_SUFFIX = 409,   ## 「(接受)」（`Evt_msgSET`／`Qst_stdSET` 的任务接取提示后缀）
	ITEM_OBTAINED = 416,         ## 「获得%s%s X %d」（`Item_stdAddEx` 的入手提示）
	EXPERIENCE_LABEL = 413,      ## 「经验值」（`Item_datBasic:54-58` 组 23／25 的 detail_text）
	MONEY_LABEL = 414,           ## 「金币」（同上 `:59-64` 组 24／26 的 detail_text）
	PSEUDO_ITEM_OBTAINED = 415,  ## 「获得%s %d」（`Item_stdAddEx:56-58` 组 23–26 的无图标入手提示）
	MONSTER_OBTAINED = 478,      ## 「%s获得」（捕获／获得精灵）
	## 第 7 组 9–14 的入包失败提示（`Ball_stdUseEx` 的 case 22／24 → `msg.fxt:498／499`）。
	ITEM_MONSTER_STORAGE_FULL = 498, ## 「精灵储存空间不足.」：随机球的 `Ball_stdAddEx` 返回空
	ITEM_SKILL_BOOK_STORAGE_FULL = 499, ## 「技能书储存空间不足.」：随机技能书的 `Item_stdAddEx` 返回 0
	## 队伍页：队伍不能为空。`Menu_Party_mKeyPressed@0x4D37C:41-42` 的 −16 分支在
	## `Ball_stdPartys() <= 0` 时 `Game_warnSet(2)`（fxt 133「请组建队伍」）直接返回，不离开页面。
	PARTY_REQUIRED = 133,     ## 请组建队伍
	## NET 商店（`Menu_Network_mKeyPressed` 组 1 的 −5 → `Game_Cash_*` 付款窗）：
	NET_PURCHASED = 95,          ## 「购买完毕」（`Game_Cash_mPaint` 状态 6 的 `Menu_win_Box2_DrawOk` 正文）
	NET_CANNOT_BUY = 196,        ## 「现在无法购买」（同上组 1 的 −5 在 `current_event_resource_id <= 2` 时只推这条）
	NET_CONFIRM_TITLE = 567,     ## 「确认支付」（`Menu_win_Box2_DrawSelectCash` 的标题）
	NET_CONFIRM_BUY = 568,       ## 「要买这个道具吗?」（付款窗正文，现金档 ≤ 3）
	NET_CONFIRM_PAY_AGAIN = 570, ## 「再次确认支付.」（付款窗正文，其余档位）
}
