# Download Unsloth Vulkan llama.cpp (qwen4exp MTP) + shared Q8 MTP sidecar.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $Root 'bin'
$MtpDir = Join-Path $Root 'mtp'
New-Item -ItemType Directory -Force -Path $BinDir, $MtpDir | Out-Null

$Tag = 'b10715-mix-86bd2d3'
$ZipName = "app-$Tag-windows-x64-vulkan.zip"
$ZipUrl = "https://github.com/unslothai/llama.cpp/releases/download/$Tag/$ZipName"
$ZipPath = Join-Path $BinDir $ZipName
$Server = Join-Path $BinDir 'llama-server.exe'

if (-not (Test-Path $Server)) {
    Write-Host "Downloading $ZipName ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
    Write-Host "Extracting engine..."
    Expand-Archive -Path $ZipPath -DestinationPath $BinDir -Force
    # Unsloth zips sometimes nest one folder.
    $nested = Get-ChildItem $BinDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'llama-server.exe') }
    if ($nested) {
        Get-ChildItem $nested.FullName | Move-Item -Destination $BinDir -Force
    }
    if (-not (Test-Path $Server)) {
        $found = Get-ChildItem $BinDir -Recurse -Filter 'llama-server.exe' | Select-Object -First 1
        if ($found) { $Server = $found.FullName }
    }
    if (-not (Test-Path $Server)) { throw "llama-server.exe not found after extract" }
    Write-Host "Engine ready: $Server"
} else {
    Write-Host "Engine already present: $Server"
}

function Get-Mtp([string]$Name, [string]$Remote) {
    $dest = Join-Path $MtpDir $Name
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -ge 1GB)) {
        Write-Host ("MTP already present: {0} ({1:N2} GB)" -f $Name, ((Get-Item $dest).Length / 1GB))
        return
    }
    Write-Host "Downloading MTP sidecar $Name ..."
    python -c @"
from huggingface_hub import hf_hub_download
p = hf_hub_download(
    repo_id='unsloth/Qwen3.8-Flash-Next-GGUF',
    filename='$Remote',
    local_dir=r'$MtpDir',
)
print(p)
"@
    $found = Get-ChildItem $MtpDir -Recurse -Filter $Name | Select-Object -First 1
    if ($found -and $found.FullName -ne $dest) {
        Move-Item $found.FullName $dest -Force
    }
    if (-not (Test-Path $dest)) { throw "MTP sidecar did not land at $dest" }
    Write-Host ("MTP ready: {0:N2} GB" -f ((Get-Item $dest).Length / 1GB))
}

# Self-contained (has token_embd.weight) — required so --fit can measure the draft.
Get-Mtp 'mtp-Qwen3.8-Flash-Next-Q8_0.gguf' 'MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf'
Get-Mtp 'mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf' 'MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf'

$Target = 'C:\Users\Y\.lmstudio\models\mradermacher\Qwen3.8-Flash-Next-Uncensored-i1-GGUF\Qwen3.8-Flash-Next-Uncensored.i1-Q3_K_S.gguf'
if (-not (Test-Path $Target)) { throw "Missing target GGUF: $Target" }
Write-Host ("Target: {0:N2} GB" -f ((Get-Item $Target).Length / 1GB))
Write-Host "Done. Run .\start.ps1"
