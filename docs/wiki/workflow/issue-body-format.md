# 条目标题、正文与编号（强制）

索引：[agents-workflow.md](agents-workflow.md)

- **标题只写现象／行为**，不写函数名、地址、文件名、字段名或代码标识符；具体代码放描述里
  （`issue-title-no-code` 校验未闭环条目的标题）。
- **条目正文用 UTF-8 + LF**（`issue-body-markdown` 校验）：`--body-file` 落盘时不要 CRLF，
  不要 3 个以上连续换行，**表格行之间不留空行**。`bd github sync`（CLI 兜底）会原样把描述推到 GitHub issue，
  这些都会把表格拆成多段（2026-11-22 实测：306 条描述带 CRLF、63 条表格行间有空行，全量重推两次才修干净）。
- **新增条目**：先取最大号 +1 再 `bd create`（语法见 [`beads-cli.md`](beads-cli.md)）；不给 id
  会生成随机后缀，不符合格式。最大号从 `bd list --limit 0 --json` 的 `id` 数字部分最大值加一，
  显式传 `--id bm-<n>`。必须带上**由用户提供的** `## Acceptance Criteria` 段
  （见 [`issue-acceptance.md`](issue-acceptance.md)）；前置依赖用 `bd dep add`，不要只写在文字里。
- **不要建「原版逻辑管理」这类无功能归属的桶 epic**（已按用户要求删除，不得重建）：
  IDB／工具类条目按它影响的功能归属（例如 `MenuData` 动作表挂「菜单」）。
- 收口跑 `bd lint` 与 `python tools\check_conventions.py`，要求 0 问题。
