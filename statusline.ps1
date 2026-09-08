# cc-statusbar - Claude Code Status Bar (PowerShell)
# https://github.com/DreamingStrawberry/claude-code-statusline

# Force UTF-8 output for unicode bar characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Claude Code sends UTF-8 JSON on stdin. Read the raw stream and decode it as
# UTF-8 ourselves: the console default is the system code page (CP949 on Korean
# Windows, etc.), which mangles non-ASCII values such as a renamed session title.
# ConvertFrom-Json then fails and the bar silently disappears for that session.
# This path needs -InputFormat None in the launch command, otherwise PowerShell
# consumes stdin into the pipeline before we get here. The two fallbacks keep
# older installs working until their settings.json is upgraded.
$rawInput = ''
try {
    $stdinReader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding $false))
    $rawInput = $stdinReader.ReadToEnd()
    $stdinReader.Dispose()
} catch { }
if (-not $rawInput) { $rawInput = $input | Out-String }
if (-not $rawInput) { $rawInput = [Console]::In.ReadToEnd() }
$input = $rawInput

# ===================================================
# Config
# ===================================================
$SHOW_MODEL=$true; $SHOW_PATH=$true; $SHOW_GIT_BRANCH=$true; $SHOW_CONTEXT=$true
$SHOW_5H_LIMIT=$true; $SHOW_7D_LIMIT=$true; $SHOW_COST=$false; $SHOW_COMMANDS=$true
$SHOW_VERSION=$true; $SHOW_EFFORT=$true; $SHOW_FAST=$true; $LANGUAGE="en"; $BAR_STYLE="blocks"; $BAR_WIDTH=10

$confPath = Join-Path $env:USERPROFILE ".claude\statusline.conf"
if (-not (Test-Path $confPath)) { $confPath = Join-Path $HOME ".claude\statusline.conf" }
if (Test-Path $confPath) {
    foreach ($line in (Get-Content $confPath -Encoding UTF8)) {
        if ($line -match '^(\w+)=(.*)$') {
            $k = $Matches[1]; $v = $Matches[2].Trim('"', "'")
            switch ($k) {
                'SHOW_MODEL'      { $SHOW_MODEL = $v -eq 'true' }
                'SHOW_PATH'       { $SHOW_PATH = $v -eq 'true' }
                'SHOW_GIT_BRANCH' { $SHOW_GIT_BRANCH = $v -eq 'true' }
                'SHOW_CONTEXT'    { $SHOW_CONTEXT = $v -eq 'true' }
                'SHOW_5H_LIMIT'   { $SHOW_5H_LIMIT = $v -eq 'true' }
                'SHOW_7D_LIMIT'   { $SHOW_7D_LIMIT = $v -eq 'true' }
                'SHOW_COST'       { $SHOW_COST = $v -eq 'true' }
                'SHOW_COMMANDS'   { $SHOW_COMMANDS = $v -eq 'true' }
                'SHOW_VERSION'    { $SHOW_VERSION = $v -eq 'true' }
                'SHOW_EFFORT'     { $SHOW_EFFORT = $v -eq 'true' }
                'SHOW_FAST'       { $SHOW_FAST = $v -eq 'true' }
                'LANGUAGE'        { $LANGUAGE = $v }
                'BAR_STYLE'       { $BAR_STYLE = $v }
                'BAR_WIDTH'       { $BAR_WIDTH = [int]$v }
                # BAR_FILL/BAR_EMPTY ignored in PowerShell: encoding-unsafe.
                # Use BAR_STYLE instead (blocks, dots, squares, lines, triangles, ascii)
            }
        }
    }
}

# ===================================================
# Parse JSON
# ===================================================
try { $json = $input | ConvertFrom-Json } catch { $json = $null }
if (-not $json) { exit }

$model = $json.model.display_name
$cwd = $json.workspace.current_dir; if (-not $cwd) { $cwd = $json.cwd }
$exceeds200k = $json.exceeds_200k_tokens
$fastMode = $json.fast_mode
$thinkingEnabled = $json.thinking.enabled
$effortLevel = $json.effort.level
$usedPct = [int]($json.context_window.used_percentage)
$ctxSize = [int]($json.context_window.context_window_size)
$fiveHPct = [int]($json.rate_limits.five_hour.used_percentage)
$fiveHReset = [int]($json.rate_limits.five_hour.resets_at)
$sevenDPct = [int]($json.rate_limits.seven_day.used_percentage)
$sevenDReset = [int]($json.rate_limits.seven_day.resets_at)
$totalCost = $json.cost.total_cost_usd

# ===================================================
# ANSI colors
# ===================================================
$E = [char]27
$R = "$E[0m"; $B = "$E[1m"; $D = "$E[2m"; $BK = "$E[5m"
$CY = "$E[36m"; $GN = "$E[32m"; $YL = "$E[33m"; $RD = "$E[31m"
$GR = "$E[90m"; $MG = "$E[35m"; $BL = "$E[34m"; $OR = "$E[38;5;208m"

function Get-PctColor([int]$p) {
    if ($p -ge 80) { return $RD }
    if ($p -ge 50) { return $YL }
    return $GN
}

# ===================================================
# Bar
# ===================================================
$STYLES = @{
    blocks    = @{ fill = [char]0x2593; empty = [char]0x2591 }
    dots      = @{ fill = [char]0x25CF; empty = [char]0x25CB }
    squares   = @{ fill = [char]0x25A0; empty = [char]0x25A1 }
    lines     = @{ fill = [char]0x2501; empty = [char]0x2500 }
    triangles = @{ fill = [char]0x25B0; empty = [char]0x25B1 }
    ascii     = @{ fill = "#"; empty = "." }
}

function Make-Bar([int]$pct) {
    $s = $STYLES[$BAR_STYLE]; if (-not $s) { $s = $STYLES['blocks'] }
    $n = [Math]::Round($pct * $BAR_WIDTH / 100); if ($n -gt $BAR_WIDTH) { $n = $BAR_WIDTH }
    $m = $BAR_WIDTH - $n
    # Force string conversion - [char] * int doesn't repeat in PS 5.1
    $fs = [string]$s.fill
    $es = [string]$s.empty
    return ($fs * $n) + ($es * $m)
}

# Get-Date -UFormat %s is buggy on PowerShell 5.1: in non-UTC time zones it
# returns local-clock-as-UTC, off by the zone offset (e.g. 9h early in KST).
# DateTimeOffset is timezone-safe.
function Get-UnixTime { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Format-Time([int]$sec, [string]$fmt) {
    if ($sec -le 0) { return "now" }
    if ($fmt -eq "hm") { return "{0}h {1}m" -f [Math]::Floor($sec/3600), [Math]::Floor($sec%3600/60) }
    return "{0}d {1}h {2}m" -f [Math]::Floor($sec/86400), [Math]::Floor($sec%86400/3600), [Math]::Floor($sec%3600/60)
}

# ===================================================
# Language
# ===================================================
switch ($LANGUAGE) {
    'ko' { $L = @{ ctx="$([char]0xCEE8)$([char]0xD14D)$([char]0xC2A4)$([char]0xD2B8)"; h5="5$([char]0xC2DC)$([char]0xAC04)"; d7="7$([char]0xC77C)"; svc="$([char]0xC11C)$([char]0xBE44)$([char]0xC2A4)"; set="$([char]0xC124)$([char]0xC815)" } }
    'ja' { $L = @{ ctx="ctx"; h5="5h"; d7="7d"; svc="svc"; set="$([char]0x8A2D)$([char]0x5B9A)" } }
    'zh' { $L = @{ ctx="$([char]0x4E0A)$([char]0x4E0B)$([char]0x6587)"; h5="5$([char]0x5C0F)$([char]0x65F6)"; d7="7$([char]0x5929)"; svc="$([char]0x670D)$([char]0x52A1)"; set="$([char]0x8BBE)$([char]0x7F6E)" } }
    default { $L = @{ ctx="ctx"; h5="5h"; d7="7d"; svc="svc"; set="settings" } }
}

# ===================================================
# Git branch
# ===================================================
$gitBranch = ""
if ($SHOW_GIT_BRANCH -and $cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $gitBranch = git -C $cwd branch --show-current 2>$null
}
$shortPath = ($cwd -replace '\\','/') -replace '^.*/([^/]+/[^/]+)$','$1'

# ===================================================
# Line 1
# ===================================================
$out = ""
$sep = ""

if ($SHOW_MODEL) {
    $out += "${CY}${B}${model}${R}"
    # Prefer thinking.enabled. Fallback to ctx_size > 200k for older Claude Code.
    if ($thinkingEnabled -eq $true) {
        $out += " ${GN}thinking:on${R}"
    } elseif ($thinkingEnabled -eq $false) {
        $out += " ${GR}thinking:off${R}"
    } elseif ($exceeds200k -or ($ctxSize -gt 200000)) {
        $out += " ${GN}thinking:on${R}"
    } else {
        $out += " ${GR}thinking:off${R}"
    }
    if ($SHOW_EFFORT -and $effortLevel) {
        $ec = switch ($effortLevel) { 'max' { $RD } 'xhigh' { $RD } 'high' { $YL } default { $GN } }
        $out += " ${ec}effort:${effortLevel}${R}"
    }
    if ($SHOW_FAST -and $fastMode -eq $true) {
        $out += " ${YL}fast:on${R}"
    }
    $sep = " ${GR}|${R} "
}
if ($SHOW_PATH) {
    $out += "${sep}${BL}${shortPath}${R}"
    if ($gitBranch) { $out += "${GR}@${R}${MG}${gitBranch}${R}" }
    $sep = " ${GR}|${R} "
}
if ($SHOW_CONTEXT) {
    $cc = Get-PctColor $usedPct
    $ctxUsedN = [Math]::Floor($ctxSize * $usedPct / 100)
    $ctxUsedFmt = if ($ctxUsedN -ge 1000000) { "{0}.{1}M" -f [Math]::Floor($ctxUsedN/1000000), [Math]::Floor($ctxUsedN%1000000/100000) } elseif ($ctxUsedN -ge 1000) { "{0}k" -f [Math]::Floor($ctxUsedN/1000) } else { "$ctxUsedN" }
    $ctxTotalFmt = if ($ctxSize -ge 1000000) { "{0}.{1}M" -f [Math]::Floor($ctxSize/1000000), [Math]::Floor($ctxSize%1000000/100000) } else { "{0}k" -f [Math]::Floor($ctxSize/1000) }
    $out += "${sep}$($L.ctx) ${cc}$(Make-Bar $usedPct)${R} ${cc}${usedPct}%${R} ${GR}${ctxUsedFmt}/${ctxTotalFmt}${R}"
    $sep = " ${GR}|${R} "
}
# Only show rate limits when Claude Code actually sends them (resets_at > 0).
# Fast mode and some session states omit rate_limits entirely.
if ($SHOW_5H_LIMIT -and $fiveHReset -gt 0) {
    $fc = Get-PctColor $fiveHPct
    $out += "${sep}$($L.h5) ${fc}$(Make-Bar $fiveHPct)${R} ${fc}${fiveHPct}%${R}"
    $d5 = $fiveHReset - [int](Get-UnixTime)
    $out += " ${GR}$(Format-Time $d5 'hm')${R}"
    $sep = " ${GR}|${R} "
}
if ($SHOW_7D_LIMIT -and $sevenDReset -gt 0) {
    $sc = Get-PctColor $sevenDPct
    $out += "${sep}$($L.d7) ${sc}$(Make-Bar $sevenDPct)${R} ${sc}${sevenDPct}%${R}"
    $d7 = $sevenDReset - [int](Get-UnixTime)
    $out += " ${GR}$(Format-Time $d7 'dhm')${R}"
    $sep = " ${GR}|${R} "
}
if ($SHOW_COST -and $totalCost -and $totalCost -ne 0) {
    $out += "${sep}${GR}`$${totalCost:F2}${R}"
    $sep = " ${GR}|${R} "
}
if ($SHOW_COMMANDS -or $SHOW_VERSION) {
    $out += "$sep"
    if ($SHOW_VERSION) { $out += "${GR}v1.0.31${R}" }
    if ($SHOW_VERSION -and $SHOW_COMMANDS) { $out += " ${GR}|${R} " }
    if ($SHOW_COMMANDS) { $out += "${D}${GR}$($L.set): npx cc-statusbar${R}" }
}

Write-Host $out

# ===================================================
# Line 2: DevLauncher (native PowerShell, fast)
# ===================================================
$dlPath = Join-Path $env:USERPROFILE "DevLauncher.ps1"
if (-not (Test-Path $dlPath)) { exit }

$cache = Join-Path $env:TEMP ".devlauncher-status-cache"
$now = [int](Get-UnixTime)
$needRefresh = $true

if (Test-Path $cache) {
    $lines = Get-Content $cache
    if ($lines.Count -gt 0) {
        $cachedAt = [int]$lines[0]
        if (($now - $cachedAt) -lt 10) { $needRefresh = $false }
    }
}

if ($needRefresh) {
    # Start-Job dies with the parent powershell.exe (this script exits right after
    # printing), so the cache would never fill. Use a detached process instead.
    $refreshScript = Join-Path $PSScriptRoot "devlauncher-cache-refresh.ps1"
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$refreshScript","$dlPath","$cache" `
        -ErrorAction SilentlyContinue | Out-Null
}

if (Test-Path $cache) {
    $raw = (Get-Content $cache | Select-Object -Skip 1) -join "`n"
    $frames = @([char]0x280B,[char]0x2819,[char]0x2839,[char]0x2838,[char]0x283C,[char]0x2834,[char]0x2826,[char]0x2807)
    $spin = $frames[[int](Get-UnixTime) % 8]
    $parts = ""
    foreach ($line in ($raw -split "`n")) {
        if (-not $line.Trim()) { continue }
        $fields = $line -split '\s+'
        $nm = $fields[1]; $pt = $fields[3]; $st = $fields[4]
        switch ($st) {
            'Running'  { $parts += " ${GN}$([char]0x25CF)${R} ${GN}${B}${nm}${pt}${R}" }
            'Starting' { $parts += " ${YL}${spin}${R} ${YL}${B}${nm}${pt}${R}" }
            'Error'    { $parts += " ${BK}${RD}$([char]0x2716)${R} ${RD}${B}${nm}${pt}${R}" }
            default    { $parts += " ${GR}$([char]0x25CF) ${nm}${pt}${R}" }
        }
    }
    if ($parts) { Write-Host "${GR}$($L.svc)${R}$parts" }
}

# ===================================================
# Auto-update (daily, silent, background)
# ===================================================
$updateFlag = Join-Path $env:USERPROFILE ".claude\.cc-last-check"
$needCheck = $true
if (Test-Path $updateFlag) {
    try {
        $last = [int]((Get-Content $updateFlag -ErrorAction SilentlyContinue) -join '')
        if (($now - $last) -lt 86400) { $needCheck = $false }
    } catch {}
}
if ($needCheck -and (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    try {
        $now | Set-Content $updateFlag -ErrorAction SilentlyContinue
        Start-Process -WindowStyle Hidden -FilePath "cmd.exe" `
            -ArgumentList "/c","npm install -g cc-statusbar@latest >nul 2>&1 && cc-statusbar install >nul 2>&1" `
            -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}
