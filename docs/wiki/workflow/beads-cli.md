# `bd` 命令面（唯一口径）

索引：[agents-workflow.md](agents-workflow.md)

**硬约束：待办只在 beads，别处不得另立清单；beads 的操作面是 `bd` CLI。**（规则在 `AGENTS.md`、
取证在 `wiki`、状态与证据在 beads。）`bd` 在仓库根直接读 `.beads\`，不需要先认位。

## 会话纪律（强制）

- **本页是 `bd` 用法的唯一来源**：需要哪条命令就照本页抄，会话里不重新推导、不在回复／条目正文／
  评论／其它 `wiki` 页里复述命令写法或参数表。
- **不探 `--help`**：本页已覆盖的用法不许跑 `bd --help`／`bd <子命令> --help`；只有本页没覆盖的组合
  才允许跑一次，并用**一行**把结论补进下面的表（只加表行，不附解释段）。
- **只贴结论**：`bd` 输出只留条目 id、状态、数量、报错末行，不整段回贴 `bd list`／`bd show`。

## 查询收窄（强制，本机实测）

上下文最贵的来源就是 `bd` 的全量输出：裸 `bd ready --json` 一次 143,593 字符（≈3.6 万 token），
裸 `bd list` 7,400 字符，`bd show` 文本模式 3.8–5.3K 字符且**必带全部评论历史**。
默认一律用下面的收窄形态，**单次 `bd` 输出上限 1,200 字符 / 25 行**，超了换形态重跑，不整段回贴。

| 要做的事 | 收窄形态（照抄） | 实测字符 |
| --- | --- | --- |
| 看该干哪条 | `bd ready -n 10` | 710 |
| 按状态扫一批 | `bd list --status=open --brief -n 15` | 749 |
| 认一条是什么 | `bd show <id> --short` | 34–54 |
| 取正文（描述／验收／备注，无评论、无依赖正文） | `bd show <id> --json --brief-deps` | 1.5–2.7K |
| 只取一个字段 | `(bd show <id> --json \| ConvertFrom-Json)[0].description` | ≈1K |
| 最近一条评论 | `(bd comments <id> --json \| ConvertFrom-Json)[-1].text` | ≈0.8K |
| 规模熔断 | 加 `--max-rows 20`，超限直接报错退出 | — |

**禁**：裸 `bd ready`（4,458）、裸 `bd list`（7,400）、`bd ready --json`（143,593）、
`bd list --json` 不带 `-n`、把 `bd show` 文本输出当正文读（评论历史一并灌入）。
评论只在需要「上一轮做了什么」时读最后一条，不翻全量；依赖关系用 `--short` 逐条看，不用 `--include-dependents`。

## 命令表

| 要做的事 | `bd` 命令 |
| --- | --- |
| 看该干哪条 | `bd ready -n 10`（见上节收窄表） |
| 看被什么卡住 | `bd blocked` |
| 认一条／取正文 | `bd show <id> --short`／`bd show <id> --json --brief-deps`；评论用 `bd comments <id> --json` 取最后一条 |
| 按条件列 | `bd list --status=… --priority=… --type=… --label=… --brief -n 15` |
| 统计 | `bd stats` |
| 领条目（原子：assignee + in_progress） | `bd update <id> --claim` |
| 改状态／优先级／负责人／标题 | `bd update <id> --status=… --priority=… --assignee=… --title=…` |
| 改正文／设计／验收／外部链接 | `bd update <id> --description=… --acceptance=… --design=… --external-ref=…`（多行正文用 `--body-file -`） |
| 追加备注（不覆盖） | `bd note <id> "…"` |
| 追加时间戳评论（每轮增量首选） | `bd comment <id> "…"`；读回用 `bd comments <id>` |
| 收工 | `bd close <id> --reason "…"` |
| 重开 | `bd reopen <id> --reason "…"` |
| 建条目 | `bd create "<标题>" --id bm-<数字> --type <类型> --priority <p> --description … --acceptance … --deps …`（写法见 [`issue-body-format.md`](issue-body-format.md)） |
| 前置依赖 | `bd dep add <子> <父>`（等价 `bd dep <父> --blocks <子>`）；其它关系用 `--deps parent-child:<id>`／`related:<id>` |
| 子条目枚举 | `bd children <epic>` |
| 章节与正文校验 | `bd lint` |
| 状态落盘（随仓库走的那份） | `bd export -o .beads/issues.jsonl`（`.beads/embeddeddolt` 不入库） |
| 新克隆 bootstrap | `bd init -p bm --skip-agents --non-interactive --init-if-missing` + `bd import .beads/issues.jsonl` |
| 清理 | `bd gc --skip-decay`；**不许跑裸 `bd gc`** |
| GitHub 集成 | `bd github status/sync/push/pull`、`bd config set github.*`（推送由用户执行，见 [`beads-github.md`](beads-github.md)） |

`.beads\hooks\*` 与 `.beads\README.md` 由 bd 自己生成与维护，不按本页改写。

**长文本多行走 stdin**：`bd update <id> --body-file -`／`bd create … --body-file -` 从标准输入读正文，
多行正文、引号、全角括号照原样传，不需要转义；`--description`／`--notes`／`--reason`／`--acceptance`
也能直接带多行字符串，但内联时用单引号包住，避免 `--reason` 里嵌引号让整条命令失败。
