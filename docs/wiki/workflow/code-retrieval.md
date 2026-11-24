# 代码检索与最小改动

适用：读任何 `.gd`／`.py`／`.ts` 等脚本，以及 `.tres`／`.tscn` 资源文件。目标是不把整份脚本塞进上下文；本页是红线 3 的操作细则。

## 顺序（强制）

1. `code_outline(file_path)` 先拿定义表；已知符号用 `code_outline(file_path, symbol)` 只取该定义体。
2. 不知道符号名时 `code_search(pattern, path, include=".gd")` 定位 `file:line`，不要靠猜。
3. 只读命中附近：`code_read(file_path, start_line, end_line)`，单次 ≤120 行；不够再取下一段。
4. 改：对定位到的唯一文本用 `code_patch(file_path, replacements=[...])`；单处等价改动可用 `edit`。
   禁止“先整读一遍再改”。

## 路径（强制）

- 打开任何文件前，路径必须来自 `glob` 命中、`code_search` 命中，或页面／命令输出里原样出现的相对路径；
  禁止按记忆拼目录（`game\scripts\components\monster_animation.gd` 猜成 `game\scripts\monster_animation.gd`）。
- 报「找不到路径」／`ENOENT` 时先 `glob`／`code_search` 定位真实文件，再按区间读；同一路径不许原样重试第二次。
- `res://` 以 `game\` 为根：`res://scripts/x.gd` 就是仓库里的 `game\scripts\x.gd`。

## 资源文件（`.tres`／`.tscn`）

- 一律先 `python tools\res_outline.py <文件>`：输出 `[gd_resource]`／`[node]` 段头、顶层属性与行号，
  多行容器只报行数不展开（`assets\text-tables.tres` 的 `payloads` 有 34685 行）。
- 再 `code_read` 取对应窗口（≤120 行）；要按名字看资源加 `--grep 正则`，要资源清单加 `--res`。
- 禁止 `read` 整读任何 `.tres`／`.tscn`；也不要对它用 `code_outline`（无规则，直接报错）。

## 同一个窗口只读一次（强制）

- 改完不重读：以 `code_patch` 返回的行号为准。
- 需要重新定位时用 `code_search`（只回 `file:line`），不要用 `code_read` 复核上下文。
- `code_patch` 报 `old_string not found` 时**不要重读整段**：本仓工作区是 CRLF，多行 `old_string`
  常因此失配；改用单行锚点，一次到位。
- 同一会话里同一个 `start_line`／`end_line` 读第二次算预算违规；除非第一次的窗口已被改动覆盖。

## 禁令

- **`read` 只接受 ≤8 KB 的文件**（或任意文件的头尾片段，带 `offset`／`limit`）；超过 8 KB 一律局部检索：
  `.tres`／`.tscn` 用 `res_outline.py`，脚本用 `code_read` 窗口，文档与数据用 `read` 的 `offset`／`limit`。
- 禁止用 `read` 整读 `.gd`／`.py` 等脚本；`read` 只用于非代码小文件、配置或文件头尾，且必须带 `offset`／`limit`。
- 禁止以“先了解全貌”为理由通读脚本；先看定义表与搜索命中。
- 需要跨文件追踪时，先 `code_search` 找调用点，再逐个窗口读；不要把相邻几个文件一起整读。

## 回退

- `code_outline` 报无定义规则（`.tres`／`.tscn` 必然如此）→ 先 `python tools\res_outline.py <文件>`，再 `code_read` 取它给出的行号。
- `code_search` 无命中 → 换关键词或加 `literal`，不要退回整读。
- 检索工具不可用（插件未加载）→ 用 `read` 带 `offset`／`limit` 分段读，并在交付说明里注明工具缺失。
