# 测试细则

本页是 `AGENTS.md`「测试策略」的完整细则（GUT 命令、runner 禁令、自检产物、夹具与现状基线）。

## 测试策略

**禁止扩张测试规模：只测本轮改动的关键内容，一个功能最多写 2–3 条关键断言。** 除用户明确要求外：
不新增测试文件（新模块才有资格配一个 `test_*.gd`）、不为「顺手看到」的未覆盖行为补用例、不把现有
`test_legacy_suite()` 拆成细粒度用例、不加参数化／边界值矩阵、不为了「更完整」而扩大断言范围。
只守住主路径和最容易被改坏的那条失败分支；想不出本轮真正会回归的点，就不写测试。
测试的价值是防回归，不是数量。

**跑测试的范围 = 本轮改动的直接覆盖用例，只允许跑这个范围内的文件。范围外一律不跑，也不是「跑不跑都行」：
不许习惯性跑、不许为了「确认没回归」而跑、不许跑整套、不许写跑全量的脚本或遍历目录的循环。**
先列出本轮真正动到的模块（哪个脚本／Scene、哪个数据字段、哪个公共组件），再决定跑哪一个 `test_*.gd`。
**一轮最多 3 个文件（默认 1 个）**：110 个用例是回归基线，不是每轮动作；脚本按 `$MaxTests = 3` 硬拦，
跑全量必须先由用户明确要求、再改脚本里的这个数——不是「顺手多列几个」。

现状基线：`tests\unit` 60 个 `test_*.gd`、110 个用例。保持这个量级：新改动用替换或
收缩既有断言来表达，不要把它重新堆回去。

**用 GUT（`addons\gut`，v9.7.1），不要再写自定义的 `extends SceneTree` 测试。** 新增测试放 `tests\unit\test_*.gd`，`extends GutTest`，用 `assert_eq`／`assert_true`／`assert_gt` 等标准断言。

**只允许手动跑本轮指定的测试文件（一条命令一个），没有「跑全部」的入口，也不要再写跑全量的脚本**：

```powershell
# 一次只跑你本轮动到的那一个文件；要核两个就分两条命令
& $godot --path . -s addons/gut/gut_cmdln.gd -gdir= -gtest=res://tests/unit/test_battle_view.gd -gexit
```

- **`-gdir=` 必须给空**：GUT 的 `-gtest` 是「追加」到 `-gdir` 扫描结果之后，漏了就变成跑全目录。
- **一轮的测试文件合并成一条命令（上限 3 个）**：`tests\run_tests.ps1 -Tests test_a,test_b` 把它们塞进
  **同一次 Godot 启动**（`-gtest=` 逗号分隔）。它只接受显式 `test_xxx` 清单：目录／通配符／`all`／空清单
  **以及超过 3 个**都直接报错，同一文件重复传入也报错（没有跑全量的入口）；`-gdir=` 空、不加 `--headless`。
  不知道文件名就先 `run_tests.ps1 -List`（只列清单、不启动 Godot），别为找名字去 glob 或整读目录。
- **同一个文件每轮最多跑一次**：Godot 冷启动 8-30 秒是固定成本，改一处跑一次会把同一轮的成本乘以改动次数。
  把该文件要改的地方一次改完，再跑那一次。实测一轮 9 次启动累计 104 秒，合并后约 3-10 秒。
- **所有用例一律带窗口（有 UI）跑，不要加 `--headless`**。用例会 `await RenderingServer.frame_post_draw` 取真实帧缓冲，headless 下这个信号永不前进，用例直接挂住不退出——那才是「进程堆积／看起来卡死」的根因。项目也不提供 headless 开关，避免再走回头路。
- **子代理的一次性自检同样受这条约束**：临时 GUT 文件或临时 `.gd` 脚本一律带窗口跑、不加 `--headless`；
  一次运行超过 60 秒没有输出就先 Kill 掉再查原因，不许「放着等它自己退出」（`await RenderingServer.frame_post_draw`
  与 `create_timer` 看门狗在无窗口时会永远等下去，表现为进程一直不退）。自检文件跑完必须删掉，
  报告里要写「自检文件已删除、`git status` 只剩白名单文件」。2026-11-21 就出现过子代理的初始精灵选择自检卡住不退。
- **自检产物只许放临时目录或 `tests\unit\`**：中途截图、日志、探针场景一律写到系统临时目录，
  **不许在 `game\` 根或 `tools\` 下自建 `_probe_*` 脚本／场景／png**。2026-11-22 一个飞艇代理在
  `game\` 根留了 20 多个 `_probe_warp*` 与十几张 png，收口时全要人工清。
- 跑测试期间不要同时用编辑器导入或跑 `--import`：两边会抢 `.godot/` 导入缓存。
- 结构固定：`tests\` 根下只留 `unit\`，共用夹具是 `tests\unit\gameplay_fixtures.gd`
  （`Fixtures.data()` 等构造 typed 记录）。不要再往 `tests\` 根加测试或夹具。
- 不要恢复旧自研 runner 管道：`extends SceneTree` + 结尾 `quit()`、`_noop()`、
  `before_all` 里的 `create_timer(...).timeout.connect(...)` 看门狗、`before_all(): pass`、
  headless 备选分支，以及 `before_all` 里 `call_deferred("_run")`（会让套件跑两遍、访问已释放的
  `main`）。用例只保留一条真路径；超时由命令行外部兜底。
- 「一个被测模块 → 一个 `test_*.gd`」，不改被测行为。文件名只加 `test_` 前缀，不要再叠加 `_test`
  后缀（`test_menu_view.gd`）。当前每个文件只有一个 `test_*` 用例
  （多数叫 `test_legacy_suite()`），内部仍按旧 `_run()` 的顺序断言，尚未拆成细粒度用例。
- 用例基类 `tests\unit\gut_case.gd`：`before_each` 隐藏 `GutRunner/GutLayer`（否则像素断言全部失败），`after_each` 释放遗留在 root 的节点并复位 `Engine.time_scale`、`paused` 与窗口尺寸。单进程连跑靠它隔离，不需要逐文件重启。
- 场景里不要留 `before_all` 里 `call_deferred("_run")` 的旧写法：那会让套件跑两遍，第二遍访问已释放的 `main`（表现为 `previously freed`、`get_tree()` 为 null、成堆孤儿节点）。
- **被测代码里故意触发的 `push_error` 要用 `assert_push_error("片段")` 声明**，否则 GUT 把它记成用例的意外错误（`test_island_view` 的非法岛资料分支、`test_prime_startup` 的存储检查失败分支都是这么修的）。
- **需要真实回环服务的用例自己拉起服务**：`LocalServiceProcess` + 探到的临时空闲端口（`_available_port()`）与独立数据目录（`user://local-service-test`），跑完 `stop()` 并删目录；不要依赖开发者先在 8765 上跑 `local_server.py`，也不要复用它的数据（`test_local_service_client`，另见 `test_local_service_autostart` 的同一套做法）。
- **只允许跑本轮测试范围内的用例；跑范围外或整套是禁止的，不是「不要求」**：改动的代码被哪个用例直接
  覆盖就只跑哪一个文件（命令见上），通过即停。范围判定按「本轮真正动到的脚本／Scene／数据字段／公共组件」
  算；无关模块（标题、市场、邮箱、本地服务等）即使没跑过也不许顺手跑，它们的通过也不作为本轮验收依据。
  改到跨模块契约时，覆盖到几个模块就跑那几个文件，一条命令一个，**任何时候都不跑全目录**。
  清理过期测试：被测行为已删、断言作废、被别的用例完全覆盖的，直接删或收缩到最小断言。GPU 期望值必须能由
  当前 shader／Scene 或原生证据推导，不能按实测值回填。

**约定兜底**：可机械判定的部分曾用 `python script\check_conventions.py` 校验（本节的不加 `--headless`／只留 `unit\`／旧 runner 已删／文件不叠 `_test`／不 preload 主场景，加上 Box4 单一实现、资源目录不放 CSV、待办单一来源）。**该脚本已随原版取证工具移到 decompile 仓库**：它的规则表引用旧 AGENTS.md 与 `script/ani_actions.py`，跟本仓库结构还没对齐，重新启用前要按本页逐条重写规则表。
细则以本页与 [CONTRIBUTING.md](../../../CONTRIBUTING.md) 为准。
