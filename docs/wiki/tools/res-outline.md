# res_outline.py

索引：[`tools.md`](tools.md)

把 `.tres`／`.tscn` 压成「结构 + 行号」清单，之后用 `code_read` 取窗口。
替代整读：`text-tables.tres` 有 34692 行，`obj_f_99.tscn` 1.4 MB。

| 参数 | 作用 |
| --- | --- |
| `<文件>` | 必填，只接受 `.tres`／`.tscn` |
| `--res` | 另外列出 `ext_resource`／`sub_resource`（默认只报条数） |
| `--grep 正则` | 只保留命中行，用来按资源名筛 |
| `--max N` | 最多输出条数，默认 40 |
| `--full` | 不截断 |

示例：`python tools\res_outline.py assets\text-tables.tres` → 5 行，其中
`payloads = <容器 34685 行>`；`python tools\res_outline.py <场景> --res --grep Texture2D --max 3`。

失败处置：报「找不到文件」先 `glob` 定位；报扩展名不对说明拿错了目标，不要改用 `read` 兜底。
