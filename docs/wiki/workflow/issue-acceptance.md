# 验收标准（强制）

索引：[agents-workflow.md](agents-workflow.md)

1. **新建条目必须带 `## Acceptance Criteria` 段**（`task`／`bug`／`feature`／`epic` 一律适用），
   标题必须是这个英文名——`bd lint` 与 `tools\check_conventions.py` 的 `issue-acceptance-criteria` 都只认它，
   写成「## 验收」等于没写。
2. **验收标准由用户提供，代理不得代拟**：需要新建条目时先向用户索取；用户尚未给出时，条目建为
   `blocked`，段内写「待用户提供验收标准」，**不许进 ready 池**，等用户提供后才放开。
   代理可以先给**草案**，但必须经用户确认后才写进条目，并在描述里注明「草案经用户确认（日期）」。
3. 标准写成三列表格，一行一项：`项 | 期望（含依据：函数名／raw\ 页） | 命令或观察点`。
   不可执行、不可判伪的写法（「与原生一致」「基本可用」）不算验收标准。
4. **只为即将开工的条目补写验收**，不给存量 backlog 批量回填——批量写必然漂（写作时点离事实最远，
   而且人工批量写没有可重新生成的路径）。存量条目在 `claim(issue_id)` 前补。
5. 收口跑 `bd lint` 与 `python tools\check_conventions.py`，要求 0 问题；后者的
   `issue-acceptance-criteria` 与 `issue-bug-repro-steps` 校验**生效日（2026-11-22）之后新建且未闭环**
   的条目都有对应段落。段落语法与类型要求见 [`issue-types.md`](issue-types.md)。
