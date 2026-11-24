# 项目 wiki

从旧仓库 `BattleMonster/wiki` 迁回，只保留**仓库流程与自有工具**相关的页。

## 索引

| 页 | 内容 |
| --- | --- |
| [`workflow/workflow.md`](workflow/workflow.md) | 工作流程总览 |
| [`workflow/commit-message.md`](workflow/commit-message.md) | 提交信息格式 |
| [`workflow/code-retrieval.md`](workflow/code-retrieval.md) | 按区间读代码，不整读 |
| [`workflow/testing-guide.md`](workflow/testing-guide.md) | 测试策略与自检产物清理 |
| [`workflow/pitfalls.md`](workflow/pitfalls.md) | 踩过的坑 |
| [`workflow/issue-*.md`](workflow/issue-body-format.md) | 条目类型、正文格式、验收标准 |
| [`workflow/beads-*.md`](workflow/beads-cli.md) | 待办库（`bd` CLI）用法 |
| [`tools/tools.md`](tools/tools.md) | 工具手册索引 |
| [`tools/res-outline.md`](tools/res-outline.md) | `.tres`／`.tscn` 结构清单 |
| [`tools/run-tests.md`](tools/run-tests.md) | 跑指定的 GUT 用例 |

## 不在本仓库的页

原版游戏的取证结论、数据格式规格、各模块的原生行为说明（约 109 页），以及 `probe-ida`／`export-*`／
`convert-ani`／`parse-qstlist` 几本手册，都放在**独立的 decompile 仓库**：

- 它们的内容来源是原版 APK／IDA 快照，按本仓库的入库范围（见 README「仓库内容」）不进来。
- 代码注释里仍会引用这些页（例如 `wiki/ui/startup-preload.md`），要查原文去 decompile 仓库。

取舍与对账明细见 [`../port-audit.md`](../port-audit.md)。
