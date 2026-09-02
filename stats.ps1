# Print speculative-decoding counters from a running server.
param([int] $Port = 8097)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeyFile = Join-Path $Root 'api-key.txt'
$ApiKey = $env:FLASH_NEXT_API_KEY
if (-not $ApiKey -and (Test-Path $KeyFile)) { $ApiKey = (Get-Content $KeyFile -Raw).Trim() }
if (-not $ApiKey) { throw "No API key. Start the server once so api-key.txt is created." }

$headers = @{ Authorization = "Bearer $ApiKey" }
$base = "http://127.0.0.1:$Port"

Write-Host "=== /metrics (spec + throughput) ==="
try {
    $metrics = Invoke-RestMethod -Headers $headers -Uri "$base/metrics"
    $metrics -split "`n" | Where-Object {
        $_ -match 'draft|spec|predicted|prompt_tokens|n_decode|tokens_predicted|llamacpp:'
    }
} catch {
    Write-Host "metrics failed: $_"
}

Write-Host ""
Write-Host "=== /slots (per-request draft stats) ==="
try {
    Invoke-RestMethod -Headers $headers -Uri "$base/slots" | ConvertTo-Json -Depth 8
} catch {
    Write-Host "slots failed: $_"
}

Write-Host ""
Write-Host "Also grep the latest log for 'draft acceptance':"
Get-ChildItem (Join-Path $Root 'logs') -Filter 'server-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object {
        Write-Host $_.FullName
        Select-String -Path $_.FullName -Pattern 'draft acceptance|speculative|n_draft|accepted' |
            Select-Object -Last 20
    }
