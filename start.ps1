param(
    [int] $Port = 0,
    [int] $Ctx = 0,
    [int] $NMax = 0,
    [string] $HostAddr = '',
    [string] $Cors = '',
    [switch] $NoMtp,
    [switch] $WebUi,
    [switch] $ListenLan,
    [switch] $NoAuth
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $Root 'bin'
$LogDir = Join-Path $Root 'logs'
$KeyFile = Join-Path $Root 'api-key.txt'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Read-DotEnv {
    $envFile = Join-Path $Root '.env'
    if (-not (Test-Path $envFile)) { return }
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
        $k, $v = $_ -split '=', 2
        $k = $k.Trim(); $v = $v.Trim().Trim('"').Trim("'")
        if ($k -and -not [Environment]::GetEnvironmentVariable($k)) {
            [Environment]::SetEnvironmentVariable($k, $v, 'Process')
        }
    }
}
Read-DotEnv

if (-not $Port) { $Port = if ($env:FLASH_NEXT_PORT) { [int]$env:FLASH_NEXT_PORT } else { 8097 } }
if (-not $Ctx) { $Ctx = if ($env:FLASH_NEXT_CTX) { [int]$env:FLASH_NEXT_CTX } else { 32768 } }
if (-not $NMax) { $NMax = if ($env:FLASH_NEXT_NMAX) { [int]$env:FLASH_NEXT_NMAX } else { 3 } }
if (-not $HostAddr) {
    $HostAddr = if ($env:FLASH_NEXT_HOST) { $env:FLASH_NEXT_HOST } else { '127.0.0.1' }
}
if ($ListenLan) { $HostAddr = '0.0.0.0' }
if (-not $Cors) { $Cors = if ($env:FLASH_NEXT_CORS) { $env:FLASH_NEXT_CORS } else { 'localhost' } }

$Server = Get-ChildItem $BinDir -Recurse -Filter 'llama-server.exe' | Select-Object -First 1
if (-not $Server) { throw "Engine missing. Run .\setup.ps1 first." }

$Target = $env:FLASH_NEXT_MODEL
if (-not $Target) {
    $Target = 'C:\Users\Y\.lmstudio\models\mradermacher\Qwen3.8-Flash-Next-Uncensored-i1-GGUF\Qwen3.8-Flash-Next-Uncensored.i1-Q3_K_S.gguf'
}
if (-not (Test-Path $Target)) { throw "Missing target GGUF: $Target" }

$MtpDir = Join-Path $Root 'mtp'
$Mtp = $null
if ($env:FLASH_NEXT_MTP -and (Test-Path $env:FLASH_NEXT_MTP)) {
    $Mtp = Get-Item $env:FLASH_NEXT_MTP
} else {
    $Mtp = Get-ChildItem $MtpDir -Recurse -Filter 'mtp-Qwen3.8-Flash-Next-Q8_0.gguf' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*shared*' } |
        Select-Object -First 1
    if (-not $Mtp) {
        $Mtp = Get-ChildItem $MtpDir -Recurse -Filter 'mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
}
if (-not $NoMtp -and -not $Mtp) { throw "MTP sidecar missing. Run .\setup.ps1 first." }

$ApiKey = $env:FLASH_NEXT_API_KEY
if (-not $ApiKey -and (Test-Path $KeyFile)) { $ApiKey = (Get-Content $KeyFile -Raw).Trim() }
if (-not $ApiKey) {
    $ApiKey = [guid]::NewGuid().ToString('N')
    Set-Content -Path $KeyFile -Value $ApiKey -NoNewline
    Write-Host "wrote new API key to api-key.txt (gitignored)"
}

$LogFile = Join-Path $LogDir ("server-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

# Do not name this $args; that is a PowerShell automatic variable.
$serverArgs = @(
    '-m', $Target,
    '--host', $HostAddr,
    '--port', "$Port",
    '--cors-origins', $Cors,
    '--no-cors-credentials',
    '-ngl', '99',
    '-fa', 'on',
    '--jinja',
    '--fit', 'off',
    '-c', "$Ctx",
    '-np', '1',
    '-b', '2048',
    '-ub', '512',
    '--temp', '1.0',
    '--top-p', '0.95',
    '--top-k', '20',
    '--min-p', '0.0',
    '--alias', 'qwen38-flash-next-uncensored',
    '--override-tensor', 'per_layer_token_embd.weight=CPU',
    '--metrics',
    '--slots',
    '--log-file', $LogFile,
    '--log-timestamps',
    '--verbosity', '3'
)

if ($NoAuth) {
    Write-Host "auth    OFF (localhost only). Pass -NoAuth to skip the key."
} else {
    $serverArgs += @('--api-key', $ApiKey)
}

if ($WebUi) { $serverArgs += '--webui' } else { $serverArgs += '--no-webui' }

if (-not $NoMtp) {
    $serverArgs += @(
        '-md', $Mtp.FullName,
        '-ngld', '99',
        '--spec-type', 'draft-mtp,ngram-mod',
        '--spec-draft-n-max', "$NMax",
        '--spec-draft-p-min', '0.75',
        '--spec-ngram-mod-n-max', '64',
        '--spec-ngram-mod-n-match', '24'
    )
}

Write-Host "target  $Target"
if (-not $NoMtp) { Write-Host "draft   $($Mtp.FullName)  n-max=$NMax" }
Write-Host "bind    ${HostAddr}:${Port}  cors=$Cors  webui=$WebUi"
Write-Host "api     http://127.0.0.1:$Port/v1"
if (-not $NoAuth) {
    Write-Host "auth    Authorization: Bearer $ApiKey"
    Write-Host "        (also in $KeyFile -- LM Studio/ST will 401 without this)"
}
Write-Host "stats   flash-next-stats   or  .\stats.ps1"
Write-Host "log     $LogFile"
Write-Host "health  http://127.0.0.1:$Port/health"
Write-Host "Draft acceptance prints at the END of each completion (not during stream)."
Write-Host "Loading ~83 GB. First listen can take a minute. Leave this window open."
Write-Host ""

if ($HostAddr -eq '0.0.0.0') {
    Write-Host "WARNING: listening on all interfaces. Keep the API key private." -ForegroundColor Yellow
}

Set-Location $BinDir
& $Server.FullName @serverArgs
