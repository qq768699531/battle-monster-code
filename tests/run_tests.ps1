<#
按「本轮改动覆盖的文件」跑指定测试文件，一次 Godot 启动跑完清单。

- **只接受显式文件清单**（不带 `tests/unit/` 前缀、不带 `.gd`，例如 `test_battle,test_world_map`）；
  传目录、通配符、`all`、空清单都会直接报错退出。
- **一轮最多 3 个文件**（默认就是 1 个）：测试范围是本轮改动直接覆盖的用例，不是每轮回归全量。
  超了要拆轮次，或用 `-All` 明确表示这是回归基线。
- **清单合成一次 GUT 调用**（`-gtest=` 逗号分隔）：Godot 冷启动 8–30 秒，逐个起会把同一轮的成本乘以文件数。
  `-gdir=` 留空，**不加 `--headless`**（用例要 `await RenderingServer.frame_post_draw`，headless 下会挂住）。
- 输出走 `Start-Process -RedirectStandardOutput` 落盘再读：Windows 上直接 `2>&1 | Out-String` 可能拿到 0 字节，
  重定向到文件两条路径都稳定。

用法：
    .\tests\run_tests.ps1 -Tests test_battle,test_world_map
    .\tests\run_tests.ps1 -Tests test_battle -Full    # 看完整 banner，只在排查环境问题时用
    .\tests\run_tests.ps1 -List                       # 只列现有用例文件名，不启动 Godot
    .\tests\run_tests.ps1 -All                        # 回归基线，跑整个 tests/unit

默认只回 Run Summary 与失败行。
#>
param(
	[string[]]$Tests,
	[switch]$List,
	## 只跑关键项（默认）：约 5 秒，覆盖战斗结算／战斗核心／存档／事件任务／提示栈／任务数据／数据完整性。
	[switch]$Key,
	## 全量回归基线：57 个脚本、109 项，约 30 秒。只在发布前或大改后跑。
	[switch]$All,
	[switch]$Full,
	[string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$unit = Join-Path $PSScriptRoot "unit"

# 一轮能跑几个用例文件：测试范围 = 本轮改动直接覆盖的用例，不是「跑一遍心里踏实」。
$MaxTests = 3

## 关键项：改动最容易踩到、且跑得快的用例。加项前先量一次总时间，别超过 5 秒。
$KeyTests = @(
	"test_battle_settlement",   # 战斗结算：掉落、金币、经验写回
	"test_battle",              # 战斗核心：行动、伤害、终局
	"test_save_store",          # 存档读写与槽位校验
	"test_story",               # 事件/任务流程与稳定快照
	"test_message_stack",       # 提示栈：绘制、图标、颜色
	"test_quests",              # 任务数据装载
	"test_original_resource_export"  # 资源完整性：数据表条数与启动错误
)

if ($List) {
	Get-ChildItem $unit -Filter "test_*.gd" |
		ForEach-Object { $_.BaseName } |
		Sort-Object
	exit 0
}

if (-not $Godot) {
	foreach ($candidate in @("godot_console", "godot")) {
		if (Get-Command $candidate -ErrorAction SilentlyContinue) {
			$Godot = $candidate
			break
		}
	}
}
if (-not $Godot) {
	throw "找不到 Godot 可执行文件；用 -Godot 指定路径。"
}

$targets = ""
$useKey = $Key -or (-not $All -and (-not $Tests -or $Tests.Count -eq 0))
if ($All) {
	Write-Host "=== 全量回归基线：tests/unit（约 30 秒）==="
} elseif ($useKey) {
	$Tests = $KeyTests
	$targets = ($Tests | ForEach-Object { "res://tests/unit/$_.gd" }) -join ","
	Write-Host "=== 关键项（$($Tests.Count) 个文件，约 5 秒）==="
} else {
	if (-not $Tests -or $Tests.Count -eq 0) {
		throw "必须显式给出测试文件名（或用 -All 跑回归基线；-List 只列清单）。"
	}
	foreach ($test in $Tests) {
		if ($test -notmatch '^test_[a-z0-9_]+$') {
			throw "只接受 test_xxx 形式的文件名（实际收到 '$test'）；不接受目录、通配符或 all。"
		}
	}
	if ($Tests.Count -gt $MaxTests) {
		throw "一次最多 $MaxTests 个用例文件（收到 $($Tests.Count) 个）：只跑本轮改动直接覆盖的用例，不跑回归全量。"
	}
	$repeated = $Tests | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
	if ($repeated) {
		throw "同一个文件本轮只能跑一次：$($repeated -join ', ')。改完再跑，别重复启动 Godot。"
	}
	$targets = ($Tests | ForEach-Object { "res://tests/unit/$_.gd" }) -join ","
	Write-Host "=== $($Tests -join ', ')（一次启动）==="
}

$outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gut-" + [guid]::NewGuid().ToString("N") + ".log")
$errFile = "$outFile.err"
$gutArgs = @("--path", $project, "-s", "addons/gut/gut_cmdln.gd", "-gexit")
if ($All) {
	$gutArgs = @("--path", $project, "-s", "addons/gut/gut_cmdln.gd", "-gdir=res://tests/unit", "-gexit")
} elseif ($targets) {
	$gutArgs = @("--path", $project, "-s", "addons/gut/gut_cmdln.gd", "-gdir=", "-gtest=$targets", "-gexit")
}
try {
	$process = Start-Process -FilePath $Godot -ArgumentList $gutArgs -NoNewWindow -Wait -PassThru `
		-RedirectStandardOutput $outFile -RedirectStandardError $errFile
	$text = Get-Content $outFile -Raw
	if (-not $text) {
		$text = Get-Content $errFile -Raw
	}
} finally {
	Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
}

# 默认摘要：只保留「Run Summary」之后的汇总与失败行，剔掉 Godot／GUT 启动 banner。
function Select-Summary([string]$raw) {
	$lines = @($raw -split "\r?\n")
	if ($lines.Count -eq 0) { return "" }
	$start = 0
	for ($i = 0; $i -lt $lines.Count; $i++) {
		if ($lines[$i] -match 'Run Summary') { $start = [Math]::Max(0, $i - 1); break }
	}
	$failed = @($lines | Where-Object { $_ -match '\[Failed\]' } | Select-Object -First 12)
	$tail = @($lines[$start..($lines.Count - 1)])
	return (@($failed) + $tail | Where-Object { $_ -notmatch '^\s*$' -and $_ -notmatch 'is now available' }) -join "`n"
}

if ($Full) { Write-Host $text } else { Write-Host (Select-Summary $text) }

$passing = [regex]::Match($text, 'Passing Tests\s+(none|\d+)')
$failing = [regex]::Match($text, 'Failing Tests\s+(none|\d+)')
if (-not $passing.Success) {
	# GUT 在脚本解析失败时会打印这些字样但仍以 0 退出；没有汇总行时才靠它们定性。
	if ($text -match 'Failed to load script|Ignoring script|Nothing was run') {
		Write-Host "FAILED: 脚本没有被 GUT 执行（见上方 Failed to load script / Nothing was run）"
	} else {
		Write-Host "FAILED: 没抓到 GUT 汇总行，无法确认用例真的跑过"
	}
	exit 1
}
$passingCount = if ($passing.Groups[1].Value -eq 'none') { 0 } else { [int]$passing.Groups[1].Value }
$failingCount = if ($failing.Success -and $failing.Groups[1].Value -ne 'none') {
	[int]$failing.Groups[1].Value
} else {
	0
}
if ($passingCount -le 0) {
	Write-Host "FAILED: 汇总行里没有通过用例"
	exit 1
}
if ($failingCount -gt 0) {
	Write-Host "FAILED: $failingCount 个用例失败"
	exit 1
}
# Start-Process -PassThru 偶尔拿不到 ExitCode（拿到 $null），这时只信汇总行。
$code = $process.ExitCode
if ($null -ne $code -and $code -ne 0) {
	Write-Host "FAILED: Godot 退出码 $code"
	exit $code
}
Write-Host "OK: $($(if ($All) { 'tests/unit 全量' } else { $Tests -join ', ' }))"
exit 0
