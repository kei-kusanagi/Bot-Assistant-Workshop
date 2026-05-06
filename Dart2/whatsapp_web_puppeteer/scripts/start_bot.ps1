param(
  [switch]$SkipChromeCleanup,
  [switch]$SkipPubGet,
  [switch]$SkipOllamaCheck
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EnvFile = Join-Path $ProjectRoot ".env"
$EnvExampleFile = Join-Path $ProjectRoot ".env.example"
$SessionPath = Join-Path $ProjectRoot "data\whatsapp-session"
$ChromiumPath = Join-Path $ProjectRoot ".local-chromium"

function Write-Step($Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-DotEnvValue($Name, $DefaultValue) {
  $environmentValue = [Environment]::GetEnvironmentVariable($Name, "Process")
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue
  }

  if (-not (Test-Path $EnvFile)) {
    return $DefaultValue
  }

  foreach ($line in Get-Content $EnvFile) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
      continue
    }

    $parts = $trimmed -split "=", 2
    if ($parts.Count -ne 2) {
      continue
    }

    if ($parts[0].Trim() -eq $Name) {
      return $parts[1].Trim().Trim('"').Trim("'")
    }
  }

  return $DefaultValue
}

function Stop-BotChromeProcesses {
  $projectRootText = $ProjectRoot.Path
  $sessionText = $SessionPath
  $chromiumText = $ChromiumPath

  $processes = Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" |
    Where-Object {
      ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($projectRootText)) -or
      ($_.CommandLine -and (
        $_.CommandLine.Contains($projectRootText) -or
        $_.CommandLine.Contains($sessionText) -or
        $_.CommandLine.Contains($chromiumText)
      ))
    }

  if (-not $processes) {
    Write-Host "No residual bot Chrome processes found."
    return
  }

  foreach ($process in $processes) {
    Write-Host "Stopping bot Chrome process $($process.ProcessId)..."
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  }
}

Set-Location $ProjectRoot

Write-Step "Preparing WhatsApp bot local startup"
Write-Host "Project: $($ProjectRoot.Path)"

if (-not (Test-Path $EnvFile)) {
  if (-not (Test-Path $EnvExampleFile)) {
    throw "Missing .env and .env.example. Cannot create local configuration."
  }

  Write-Step "Creating .env from .env.example"
  Copy-Item $EnvExampleFile $EnvFile
  Write-Host "Created $EnvFile. Review it if you need custom values."
}

if (-not $SkipChromeCleanup) {
  Write-Step "Cleaning residual bot Chrome processes"
  Stop-BotChromeProcesses
} else {
  Write-Step "Skipping Chrome cleanup"
}

Write-Step "Checking Dart"
$dartCommand = Get-Command dart -ErrorAction Stop
Write-Host "Dart: $($dartCommand.Source)"

if (-not $SkipOllamaCheck) {
  Write-Step "Checking Ollama"
  $ollamaBaseUrl = Get-DotEnvValue "OLLAMA_BASE_URL" "http://localhost:11434"
  try {
    Invoke-WebRequest -Uri "$ollamaBaseUrl/api/tags" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "Ollama reachable at $ollamaBaseUrl"
  } catch {
    Write-Warning "Ollama did not respond at $ollamaBaseUrl. The bot can start, but AI replies may fall back until Ollama is running."
  }
} else {
  Write-Step "Skipping Ollama check"
}

if (-not $SkipPubGet) {
  Write-Step "Running dart pub get"
  & dart pub get
  if ($LASTEXITCODE -ne 0) {
    throw "dart pub get failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Step "Skipping dart pub get"
}

Write-Step "Starting WhatsApp bot"
& dart run
exit $LASTEXITCODE
