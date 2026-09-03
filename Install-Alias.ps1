# Adds `flash-next` and `flash-next-stats` to the current user's PowerShell profile.
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
$marker = '# flash-next-mtp alias'
$block = @"
$marker
function flash-next { & '$Root\start.ps1' @args }
function flash-next-stats { & '$Root\stats.ps1' @args }
function flash-next-status {
    try {
        `$h = Invoke-RestMethod -Uri 'http://127.0.0.1:8097/health' -TimeoutSec 2
        Write-Host ("flash-next health: " + `$h.status)
    } catch { Write-Host 'flash-next not reachable on :8097' }
}
"@
# @args in the functions must survive expansion of this here-string.
$block = $block.Replace('@args', '@' + 'args')

$profiles = @(
    $PROFILE.CurrentUserCurrentHost
    $PROFILE.CurrentUserAllHosts
) | Where-Object { $_ } | Select-Object -Unique

foreach ($p in $profiles) {
    $dir = Split-Path $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path $p) {
        $cur = Get-Content $p -Raw
        if ($cur -match [regex]::Escape($marker)) {
            $cur = [regex]::Replace($cur, "(?s)$([regex]::Escape($marker)).*?(?=# flash-next-mtp alias|\z)", "")
            Set-Content -Path $p -Value ($cur.TrimEnd() + "`r`n`r`n" + $block + "`r`n")
            Write-Host "updated $p"
            continue
        }
        Add-Content -Path $p -Value "`r`n$block`r`n"
        Write-Host "appended $p"
    } else {
        Set-Content -Path $p -Value $block
        Write-Host "created $p"
    }
}

# Also drop a cmd shim on PATH via the user folder.
$shim = Join-Path $env:USERPROFILE 'flash-next.cmd'
Copy-Item (Join-Path $Root 'flash-next.cmd') $shim -Force
Write-Host "shim $shim  (run flash-next from Explorer / Win+R if the folder is on PATH)"
Write-Host "Open a new PowerShell window, then:  flash-next"
Write-Host "  flash-next -WebUi     chat page at http://127.0.0.1:8097"
Write-Host "  flash-next -NoAuth    no API key (127.0.0.1 only, easier for LM Studio)"
Write-Host "  flash-next-status"
Write-Host "  flash-next-stats"
