param(
	[string[]]$Tests,
	[switch]$List,
	[switch]$Full,
	[string]$Godot = ""
)

# 测试预算：单项 ≤ 100ms。实测见 .tmp/test_times.csv 的测量方式（逐项单跑减去约 430ms 固定开销）。
# 超预算的测试直接删掉，不要改成"只跑一次"或调小并行来掩盖。
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$unit = Join-Path $PSScriptRoot "unit"

if ($List) {
	Get-ChildItem $unit -Filter "test_*.gd" | ForEach-Object { $_.BaseName } | Sort-Object
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

$gutArgs = @("--path", $project, "-s", "addons/gut/gut_cmdln.gd", "-gexit")
if ($Tests -and $Tests.Count -gt 0) {
	foreach ($test in $Tests) {
		if ($test -notmatch '^test_[a-z0-9_]+$') {
			throw "只接受 test_xxx 形式的文件名（实际收到 '$test'）。"
		}
	}
	$targets = ($Tests | ForEach-Object { "res://tests/unit/$_.gd" }) -join ","
	$gutArgs += @("-gdir=", "-gtest=$targets")
	Write-Host "=== $($Tests -join ', ')（一次启动）==="
} else {
	$gutArgs += @("-gdir=res://tests/unit")
	Write-Host "=== 全部用例（单项 ≤ 100ms）==="
}

$outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gut-" + [guid]::NewGuid().ToString("N") + ".log")
$errFile = "$outFile.err"
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
	exit 1
}
Write-Host "OK: $($(if ($Tests -and $Tests.Count -gt 0) { $Tests -join ', ' } else { 'tests/unit 全部' }))"
