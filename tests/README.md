# 测试

GUT 9.6.1（`addons/gut`，MIT）＋ `tests/unit/` 下的用例，从旧仓库 `BattleMonster/game/tests` 迁回。

## 跑法

```powershell
.\tests\run_tests.ps1                                    # 全部用例（约 3.6 秒，其中 GUT 0.75 秒）
.\tests\run_tests.ps1 -Tests test_story,test_battle      # 只跑指定文件
.\tests\run_tests.ps1 -List                              # 只列用例文件名
.\tests\run_tests.ps1 -Full                              # 打印 GUT 全量输出
```

- 一次 Godot 启动跑完（`-gdir=res://tests/unit`），冷启动约 1.8 秒，其余是 GUT 实测测试时间。
- **不加 `--headless`**：部分用例仍读帧缓冲，headless 下会挂住。
- 第一次跑之前要导一次工程：`godot --headless --path . --import`。
- GUT 在脚本解析失败时仍会以 0 退出，`run_tests.ps1` 会拦「没跑到」并返回非 0。

## 预算：单项 ≤ 100ms

**任何单项测试超过 100ms 直接删掉**，不靠并行、缓存或"只跑一次"掩盖。这条规则是为了让测试始终能在
一次呼吸内跑完，改一点就能全量验证。

当前基线：**20 个脚本、54 项断言集、GUT 实测 0.75 秒**（2026-11-24）。

保留的都是纯逻辑／数据用例：战斗结算、战斗核心、存档、事件（23 项）、任务数据、怪物合成表、
提示/文本资源、触控映射、窗口过渡等。多数单项真实耗时在 1–60ms。

## 测量方法

GUT 不报单项耗时，用「逐项单跑」的方式测：每次只跑一个 `test_*` 方法，读 GUT 的 `Time`，
再减去约 430ms 的固定开销（脚本加载＋首帧），就是该项的真实耗时。
测量脚本做法见 git 历史里的 `.tmp/measure_cases.ps1`（临时件，不入库）。

老用例删除时的依据（真实耗时 >100ms）：

| 用例 | 单项耗时 | 类型 |
| --- | --- | --- |
| `test_ui_scene_ownership` | 9.7s | 逐个 load 全部场景 |
| `test_monster_mix` | 3.5s | 等 1.4s 计时器 ×2 |
| `test_book` | 2.2s | 长流程 |
| `test_field_runtime`（12 项） | 均 0.4–1.9s | 走位等待 |
| 各 `*_view` 渲染用例 | 0.6–3.7s | UI 截图/布局断言 |
| `test_local_service_*` | 0.6–1.1s | 起服务、等端口 |
| `test_message_stack` | 0.15s/项 | 像素断言 |
| `test_original_resource_export` | 0.19s | 加载 1300+ 资源 |

需要恢复某项时 `git log -- tests/unit/<文件名>` 找回旧版本即可，但**不要直接加回来**：先按 100ms 预算
瘦身（去掉等待、去掉 UI 像素断言）再入库。

## 失败分类

每个失败先判定是**代码错**还是**用例过期**，再动手。历史分类与已修项见
[`../docs/port-audit.md`](../docs/port-audit.md) 与 git log；当前基线全绿。
