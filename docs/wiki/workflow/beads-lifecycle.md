# 条目状态、落盘与清理

索引：[agents-workflow.md](agents-workflow.md)

命令写法只在 [`beads-cli.md`](beads-cli.md) 一页；本页只说「什么时候用哪条」，不复述语法。

- **状态与证据都改 beads**：领条目用 claim，记阻塞用 `--status=blocked --notes`，收工用 `close --reason`；
  原生依据／代码现状／做法写进 `--description`（多行走 stdin），每轮增量与更正用 `bd comment`（只追加、
  自带时间戳）。前置依赖只用 `bd dep add`，不在文字里再描述一遍依赖。
- **`.beads/issues.jsonl` 只写不读（强制）**：唯一写入口是 `bd export -o .beads/issues.jsonl`（以及 `bd`
  自身的写操作）；**不许**用 `view`／`git diff`／任何方式读取、diff、grep 或检查它的内容。
  条目状态与正文一律用 `bd show`／`bd list`／`bd comments` 的收窄形态确认（见 [`beads-cli.md`](beads-cli.md)）；导出落盘后**直接提交**，
  不再做二次 diff 核对。
- **代码与状态同一轮收口**：动手前 claim；做完 close 并用 `bd export -o .beads/issues.jsonl` 落盘，
  两处进同一个提交。本轮做的事对不上任何条目，就要么 `bd create` 补条目，要么说明为何不属于待办。
- **环境与 bootstrap**：`bd` 直接读仓库根的 `.beads\`，不需要额外服务或认位。新克隆先
  `bd init -p bm --skip-agents --non-interactive --init-if-missing`，再 `bd import .beads/issues.jsonl`。
  `.beads/embeddeddolt` 是本地库、不入库，`.beads/issues.jsonl` 才是随仓库走的那份状态，
  条目改动后用 `bd export -o .beads/issues.jsonl` 落盘。安装：`winget install GasTownHall.Beads`。
- **清理只用 `bd gc --skip-decay`**：不要跑裸 `bd gc`——它默认删掉 90 天前 closed 的 issue
  （连同证据一起消失）。压缩与自动 compaction 默认关闭，不要打开。
- **没有汇总表要手改**；发现条目本身写错，用 `bd note` 留痕。
- 状态表（附录 A）是缺页判据，不是完成度；不要在别处再抄一份页面清单。
