param($dlp, $cp)
# Get-Date -UFormat %s is buggy on PS 5.1 in non-UTC zones (off by the zone offset).
$now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
# DevLauncher status gets 30 s. A status call that never returned used to keep this process alive forever.
# statusline.ps1 stamps "$cp.lock" before starting this helper. The lock is removed once the cache is written;
# after a timeout it is left to expire (60 s), so a slow machine gets at most one attempt per minute.
$out = [System.IO.Path]::GetTempFileName()
$done = $false
try {
    $p = Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -PassThru `
        -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$dlp`"","status" `
        -RedirectStandardOutput $out -ErrorAction Stop
    if ($p.WaitForExit(30000)) {
        $r = Get-Content $out
        @($now) + $r | Set-Content $cp
        $done = $true
    } else {
        try { $p.Kill() } catch {}
    }
} catch {
} finally {
    Remove-Item $out -ErrorAction SilentlyContinue
    if ($done) { Remove-Item "$cp.lock" -ErrorAction SilentlyContinue }
}
