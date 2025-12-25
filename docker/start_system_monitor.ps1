param(
  [int]$Port = 8088,

  # Windows path to your docker-compose folder
  [string]$ComposeDirWin = "D:\AASTMT\5th Semester\OS_Project\SystemMonitor\docker",

  # WSL path to the same folder
  [string]$ComposeDirWSL = "/mnt/d/AASTMT/5th Semester/OS_Project/SystemMonitor/docker",

  # Host metrics exporter
  [string]$ExporterScript = "D:\My_Documents\export_host_metrics.ps1",
  [string]$ExporterOutput = "D:\My_Documents\host_metrics.json",
  [int]$IntervalSeconds = 30
)

# --- helpers ---
function Get-LanIPv4 {
  $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1
  if (-not $defaultRoute) { throw "No default route found (are you connected to Wi‑Fi/Ethernet?)." }

  $ipConfig = Get-NetIPConfiguration | Where-Object { $_.InterfaceIndex -eq $defaultRoute.InterfaceIndex }
  if (-not $ipConfig -or -not $ipConfig.IPv4Address) { throw "No IPv4 found for interface index $($defaultRoute.InterfaceIndex)." }

  $ipConfig.IPv4Address.IPAddress
}

function Write-EnvReportBaseUrl {
  param([string]$Ip, [int]$Port, [string]$ComposeDirWin)
  $envPathWin = Join-Path $ComposeDirWin ".env"
  $url = "http://$($Ip):$($Port)"

  Write-Host "Detected IPv4: $Ip"
  Write-Host "Writing REPORT_BASE_URL=$url to $envPathWin"

  $lines = @()
  if (Test-Path $envPathWin) {
    $lines = Get-Content $envPathWin
    $lines = $lines | Where-Object { $_ -notmatch '^REPORT_BASE_URL=' }
  }
  $lines += "REPORT_BASE_URL=$url"
  Set-Content -Path $envPathWin -Value $lines -Encoding UTF8
}

function Ensure-FirewallRule {
  param([int]$Port)
  $name = "Docker Reports $Port"
  $rule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
  if (-not $rule) {
    Write-Host "Creating firewall rule for TCP $Port (Private/Public)"
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any | Out-Null
  } else {
    Write-Host "Firewall rule exists: $name"
  }
}

function Ensure-ExporterRunning {
  param([string]$ScriptPath, [string]$OutputPath, [int]$IntervalSeconds)
  if (-not (Test-Path $ScriptPath)) {
    Write-Warning "Exporter script not found: $ScriptPath"
    return
  }
  $existing = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match [Regex]::Escape($ScriptPath)
  }
  if ($existing) {
    Write-Host "Host metrics exporter already running (PID: $($existing.ProcessId))"
    return
  }

  Write-Host "Starting host metrics exporter..."
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"", "-OutputPath", "`"$OutputPath`"", "-IntervalSeconds", "$IntervalSeconds")
  Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null
}

function Compose-Up {
  param([string]$ComposeDirWSL)
  Write-Host "Starting container via docker compose in WSL..."
  # Quote the WSL path to handle spaces
  $cmd = "bash -lc 'cd ""$ComposeDirWSL"" && docker compose up -d --force-recreate'"
  wsl.exe bash -lc "cd '$ComposeDirWSL' && docker compose up -d --force-recreate"
}

# --- main ---
try {
  $ip = Get-LanIPv4
  Ensure-FirewallRule -Port $Port
  Ensure-ExporterRunning -ScriptPath $ExporterScript -OutputPath $ExporterOutput -IntervalSeconds $IntervalSeconds
  Write-EnvReportBaseUrl -Ip $ip -Port $Port -ComposeDirWin $ComposeDirWin
  Compose-Up -ComposeDirWSL $ComposeDirWSL

  Write-Host "`nDone. Test on your PC:"
  Write-Host "  http://$($ip):$($Port)  (should list reports)"
  Write-Host "Open the newest HTML and scan the QR from your phone (same Wi‑Fi)."
}
catch {
  Write-Error $_
  Write-Host "If campus Wi‑Fi blocks LAN access, use a tunnel (ngrok):"
  Write-Host "  ngrok http $Port  -> set REPORT_BASE_URL to the ngrok URL in .env and rerun this script."
}