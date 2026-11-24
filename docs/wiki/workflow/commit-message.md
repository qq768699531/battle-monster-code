# 提交信息（强制）

索引：[agents-workflow.md](agents-workflow.md)

- 标题格式：`<beads-id>[<issue_type>]: <中文短句>`，例如 `bm-100[bug]: 结算窗口不出现`；
  `issue_type` 以 `bd show <id>` 为准。
- **一个提交只对应一个条目**；多条目拆开提交；不夹带没有条目归属的改动。
- 正文可选：空一行后按 `- ` 列要点（改了什么、验证命令与结果）。
- **不写署名 trailer**（不加 `Co-authored-by:`／`Signed-off-by:`）。
- **只提交，不推送（强制）**：`git commit` 落到本地即止；`git push`、`bd github push`、`bd github sync`
  都会改远端（或把远端副本导回），一律由用户执行。代理报告里只写提交号，不写「已推送」。
- 无对应条目的提交（仓库约定、工具清理、文档归档）用 `chore: <中文短句>`，正文写一句为什么不建条目。
- 自查：`git log -1 --format=%s` 匹配
  `^[A-Za-z0-9_-]+\[(bug|task|feature|epic|chore|decision)\]: ` 或 `^chore: `，
  且 `%B` 里没有 `Co-authored-by`。
