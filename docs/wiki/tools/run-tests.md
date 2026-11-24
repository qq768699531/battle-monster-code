# run_tests.ps1

索引：[`tools.md`](tools.md)

跑 GUT 用例，只跑本轮覆盖的文件。策略、断言写法与自检产物清理见
[`../workflow/testing-guide.md`](../workflow/testing-guide.md)。

| 命令 | 用途 |
| --- | --- |
| `tests\run_tests.ps1 -Tests <用例名>` | 跑单个用例，**默认摘要输出**（约 12 行） |
| `tests\run_tests.ps1 -Tests a,b` | 一轮最多 3 个，一次启动 |
| `tests\run_tests.ps1 -Tests <用例名> -Full` | 看完整 Godot／GUT banner，只在排查环境问题时用 |
| `tests\run_tests.ps1 -List` | 只列现有用例文件名，不启动 Godot |
| `tests\run_tests.ps1 -All` | 回归基线（整个 `tests/unit`），只在用户明确要求时跑 |

约束：`-gdir=` 留空；不加 `--headless`；同一文件每轮只跑一次；110 个用例不是每轮都跑，
跑全量必须用户明确要求。

首次跑之前导一次工程，否则 GUT 的全局类名没进 `.godot/global_script_class_cache.cfg`：

```powershell
godot --headless --path . --import
```
