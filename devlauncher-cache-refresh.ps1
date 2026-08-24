param($dlp, $cp)
# Get-Date -UFormat %s is buggy on PS 5.1 in non-UTC zones (off by the zone offset).
$now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$r = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dlp status 2>$null
@($now) + $r | Set-Content $cp
