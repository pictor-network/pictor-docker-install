#requires -RunAsAdministrator
<#
 Pictor Worker Installer (Windows, GPU-enabled)
 - Fixed PowerShell syntax for docker pull
 - Avoids variable parsing errors in "-v" by using argument array
 - Removes non-ASCII emojis to prevent encoding issues
#>

param(
    [string]$DefaultConfigPath = "$env:USERPROFILE\worker-config.json"
)

function Fail($msg) {
    Write-Host "ERROR: $msg"
    exit 1
}

Write-Host "Pictor Worker Installer (GPU-enabled, Windows)"

# Detect GPU
try {
    $gpuNames = (Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty Name) -join ' '
} catch {
    $gpuNames = ""
}
$gpuNamesLower = ($gpuNames | Out-String).ToLower()
$GPU_TYPE = ""
$IMAGE_REPO = ""

if ($gpuNamesLower -match "nvidia") {
    $GPU_TYPE = "nvidia"
    $IMAGE_REPO = "pictornetwork/worker-app"
} elseif ($gpuNamesLower -match "amd|advanced micro devices|radeon") {
    $GPU_TYPE = "amd"
    $IMAGE_REPO = "pictornetwork/worker-app-amd"
} else {
    Fail "No supported GPU detected."
}

# Check Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "Docker not found. Please install Docker Desktop."
}
try { docker info | Out-Null } catch { Fail "Docker not running." }

# Pull image
$LATEST_TAG = "v1.0"
$IMAGE_NAME = "$IMAGE_REPO`:$LATEST_TAG"

docker image inspect "$IMAGE_NAME" *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Pulling image $IMAGE_NAME ..."
    docker pull "$IMAGE_NAME"
    if ($LASTEXITCODE -ne 0) { Fail "Failed to pull image $IMAGE_NAME." }
} else {
    Write-Host "Image already exists locally: $IMAGE_NAME"
}

# Config file
$CONFIG_PATH = Read-Host "Enter path to worker-config.json (Default: $DefaultConfigPath)"
if ([string]::IsNullOrWhiteSpace($CONFIG_PATH)) { $CONFIG_PATH = $DefaultConfigPath }
if (-not (Test-Path $CONFIG_PATH)) { Fail "File not found: $CONFIG_PATH" }

# Remove old container if stopped
$containerName = "pictor-worker"
$status = (docker inspect -f '{{.State.Status}}' $containerName) 2>$null
if ($LASTEXITCODE -eq 0) {
    if ($status -in @("exited","created")) {
        Write-Host "Removing stopped container '$containerName'..."
        docker rm $containerName | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Failed to remove old container $containerName." }
    } elseif ($status -eq "running") {
        Write-Host "Container '$containerName' is already running. Reusing it."
        Write-Host "To stop container: docker stop $containerName"
        exit 0
    } else {
        Fail "Found container '$containerName' in unexpected state: $status"
    }
}

# Run container (use array for arguments to avoid quoting issues)
Write-Host "Starting container '$containerName'..."
$volumeSpec = "{0}:/worker-config.json" -f $CONFIG_PATH
$runArgs = @(
    "-d"
    "--name", $containerName
    "--gpus", "all"
    "-e", "GPU_TYPE=$GPU_TYPE"
    "-v", $volumeSpec
    $IMAGE_NAME
)
docker run @runArgs
if ($LASTEXITCODE -ne 0) { Fail "Failed to start container." }

Write-Host "Worker is running."
Write-Host "Container Name: $containerName"
# Write-Host "Check logs: docker logs -f $containerName"
Write-Host "Stop: docker stop $containerName"
