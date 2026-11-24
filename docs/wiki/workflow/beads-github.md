# GitHub 集成与附件

索引：[agents-workflow.md](agents-workflow.md)

- **GitHub 集成（2026-11-22 接入，`bd github status/sync/push/pull`）**：owner/repo 用
  `bd config set github.owner`／`github.repo` 写进本地库；token 用 `bd config set github.token`
  写进 `.beads/config.yaml`（该文件 2026-11-22 起已取消跟踪并进 `.gitignore`，机密只留在本机），
  也可用用户级环境变量 `GITHUB_TOKEN` 覆盖。**不要手改 config.yaml 里的 `github:` 段**——手写的
  owner/repo 不被 `bd github` 读取（只有 `bd config show` 会显示成 config.yaml 来源），表现为
  「配了却不生效」。fine-grained PAT 必须显式勾选本私有库并给 `Issues: Read and write`（漏勾时
  `/repos/…` 一律 404），classic PAT 勾 `repo` 可一步覆盖。每条条目的 `external_ref` 就是它的 issue
  URL，随 `.beads/issues.jsonl` 提交。
- **首次全量推送会把「本地已关闭」的条目在 GitHub 建成 open**（create 不接受 state，且推送哈希已记录，
  后续 sync 不会补关），同步后必须核对 GitHub 的 open/closed 数量与
  `list(status="open")`／`list(status="closed")` 的条数一致，不一致的用 REST `PATCH /issues/<n>`
  `{"state":"closed"}` 补齐。
- 首次推送后的第一次 `bd github sync` 会报成百条 `Conflict on …: external is newer, importing`——
  那是推送时 GitHub 侧 `updated_at` 必然比本地新的时间戳判据，不是内容差异；`--prefer-local` 会让这些
  冲突两侧都不写（本地改动也不会被推），`--prefer-newer`（默认）会把 GitHub 副本导回本地。
  按需选，不要以为同步坏了。
- **图像不进仓库，也不代用户上传**：GitHub issue 的附件图像由**用户自己**上传，代理不通过 API 传图、
  不在 issue 正文或评论里放 markdown 图片；指图只写文字描述（如「第 2 张附件」），不写仓库路径。
  自检截图一律放系统临时目录，不 `git add`、不提交（`assets` 里的既有美术资源不在此列）。
  **不要在仓库里建截图目录或参考图目录**。
- **只提交，不推送**：`git push`、`bd github push`、`bd github sync` 都由用户执行（见
  [`commit-message.md`](commit-message.md)）。
