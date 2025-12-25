# PC Health System Monitoring Tool — Stage 1

A Bash-based system monitoring tool that runs in Docker on WSL2 and generates HTML reports. It collects CPU, memory, disk, network, alerts, and integrates Windows host telemetry via:
- CSV temperatures from HWiNFO64
- A PowerShell exporter that writes Windows GPU/Disk health JSON the container can read

This README merges your existing Stage 1 documentation with a complete setup guide tailored to your environment.

## Features

- CPU usage sampling (model, cores, load averages)
- Memory and filesystem stats (WSL mounts included)
- Windows Disk Health (Get-PhysicalDisk via PowerShell exporter JSON)
- Temperatures via CSV (HWiNFO/HWMonitor)
- Network interfaces and default gateway
- Windows GPU adapters, utilization, memory (via JSON exporter)
- System Alerts (Memory, Root FS, Load)
- HTML report with dark mode and collapsible sections
- Auto-generated `reports/index.html` listing all reports

## Requirements

- Windows 11 with WSL2
  - Install/confirm: `wsl --install`
  - Verify: `wsl -l -v` (Ubuntu should be Version 2)
- Docker Desktop
  - Settings → General: “Use WSL 2 based engine”
  - Settings → Resources → WSL Integration: Enable for Ubuntu
- HWiNFO64 (Sensors-only mode) or HWMonitor for CSV temperatures
- PowerShell script execution enabled on Windows:
  - `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- Bash and core tools inside the container (installed by Dockerfile):
  - bash, coreutils, sed, awk, jq, lm-sensors, smartmontools, iproute2, bc, dos2unix
- Project layout (example paths):
  ```
  D:\AASTMT\5th Semester\OS_Project\SystemMonitor\
    docker\Dockerfile
    docker\docker-compose.yml
    scripts\monitor.sh
    reports\ (auto-generated)
    logs\    (auto-generated)
  ```
- Host telemetry files:
  - CSV temps: `D:\My_Documents\hwinfo_temps.csv`
  - PowerShell exporter script: `D:\My_Documents\export_host_metrics.ps1`
  - JSON output: `D:\My_Documents\host_metrics.json`

## Setting up HWiNFO64 CSV Logging (Windows)

1. Install HWiNFO64.
2. Run in Sensors-only mode.
3. Start logging:
   - Click “Logging start”, choose CSV format.
   - Save to `D:\My_Documents\hwinfo_temps.csv`.
4. Ensure columns include:
   - CPU Package [°C]
   - Core #n [°C] (optional, recommended)
   - GPU Temperature [°C] (if available)
5. Keep HWiNFO running so it keeps appending rows.

Tip on delimiter:
- If your Windows locale uses comma decimal separators, HWiNFO may use `;` as the CSV delimiter. The script auto-detects, but you can force `CSV_DELIM=";"` in docker-compose if needed.

## Windows Host Metrics Exporter (PowerShell JSON)

This exporter writes Windows GPU adapter info and counters, and Windows disk health to JSON the container can read.

- Save script at `D:\My_Documents\export_host_metrics.ps1` (you already have this).
- Start the exporter and keep it running:
  ```
  powershell -ExecutionPolicy Bypass -File "D:\My_Documents\export_host_metrics.ps1" -OutputPath "D:\My_Documents\host_metrics.json" -IntervalSeconds 30
  ```
- Verify output:
  ```
  Get-Content "D:\My_Documents\host_metrics.json" -TotalCount 40
  ```
Note: Your monitor.sh JSON readers are robust and handle `.disks`/`.gpus` being either arrays or single objects.

## Docker Setup

Dockerfile:
```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    bash curl jq lm-sensors smartmontools iproute2 bc dos2unix \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY scripts /app/scripts
RUN dos2unix /app/scripts/monitor.sh && chmod +x /app/scripts/monitor.sh
CMD ["bash", "/app/scripts/monitor.sh"]
```

docker-compose.yml:
```yaml
services:
  system_monitor:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: system_monitor
    environment:
      GENERATE_HTML: "true"
      BRIEF_MODE: "false"
      RUN_INTERVAL_SECONDS: "60"     # set "0" for single run
      CPU_SAMPLE_SECONDS: "1"
      VERBOSE: "false"
      USE_WINDOWS_INTEGRATION: "true"
      WINDOWS_TEMPS_CSV: "/data/hwinfo_temps.csv"
      HOST_METRICS_JSON: "/data/host_metrics.json"
      CSV_MAX_CORES: "6"
      CSV_DELIM: ""                  # set ";" if needed
    volumes:
      - ../reports:/app/reports
      - ../logs:/app/logs
      - /mnt/d/My_Documents/hwinfo_temps.csv:/data/hwinfo_temps.csv:ro
      - /mnt/d/My_Documents/host_metrics.json:/data/host_metrics.json:ro
    restart: unless-stopped
```

## Running Stage 1

From WSL Ubuntu:
```bash
cd /mnt/d/AASTMT/5th Semester/OS_Project/SystemMonitor/docker
docker compose up --build
```

Single run (not loop):
- In `docker-compose.yml`, set:
```
RUN_INTERVAL_SECONDS: "0"
```
Then:
```bash
docker compose up --build
docker compose down
```

Brief mode:
```bash
BRIEF_MODE=true ./scripts/monitor.sh   # WSL direct run
# In Docker, set BRIEF_MODE: "true" in compose env
```

WSL direct run (no Docker) to use PowerShell directly:
```bash
cd /mnt/d/AASTMT/5th Semester/OS_Project/SystemMonitor
WINDOWS_TEMPS_CSV="/mnt/d/My_Documents/hwinfo_temps.csv" USE_WINDOWS_INTEGRATION=true ./scripts/monitor.sh
```

## How to Open Reports

- On Windows:
  ```
  D:\AASTMT\5th Semester\OS_Project\SystemMonitor\reports\index.html
  ```
- Click the latest `system_report_YYYYMMDD_HHMMSS.html`.
- Assets:
  - `reports/assets/style.css` and `reports/assets/report.js` (auto-created if missing).

## What You Should See

- CPU/Memory/Disk/Network/Alerts: Linux container stats.
- Temperatures (CSV):
  - `CPU Package Temp (CSV): 48–62°C` (example values).
  - Core temps and GPU temp if present in the CSV.
- Windows Host Disk Health (JSON):
  - FriendlyName, HealthStatus, OperationalStatus, SizeGB.
- Windows Host GPU (JSON):
  - Adapter name, driver, processor.
  - GPU Engine Utilization (many entries, often 0% when idle).
  - GPU Memory dedicated usage (often 0 MB when idle).

## Useful Environment Variables

- `GENERATE_HTML=true|false` — enable HTML (default: true)
- `BRIEF_MODE=true|false` — shorter output (default: false)
- `RUN_INTERVAL_SECONDS=N` — loop mode seconds; `0` runs once
- `CSV_MAX_CORES=6` — how many core temps to print from CSV
- `CSV_DELIM=","` or `";"` — override delimiter (auto-detect if unset)
- `WINDOWS_TEMPS_CSV="D:\path\file.csv"` — CSV path (Windows or WSL-style)
- `USE_WINDOWS_INTEGRATION=true|false` — enables Windows helpers (JSON in Docker; PowerShell in WSL)

## Troubleshooting

CSV not found or no temperatures:
- Ensure HWiNFO logging is running and CSV has rows.
- Confirm mount and env:
  - `WINDOWS_TEMPS_CSV=/data/hwinfo_temps.csv`
  - `/mnt/d/My_Documents/hwinfo_temps.csv:/data/hwinfo_temps.csv:ro`
- Check delimiter:
  ```
  head -n 1 "/mnt/d/My_Documents/hwinfo_temps.csv"
  ```
  - If semicolons, set `CSV_DELIM=";"` in compose env.

Windows sections “unavailable” in Docker:
- A Linux container cannot run `powershell.exe`. Use the PowerShell exporter that writes JSON and ensure:
  - `HOST_METRICS_JSON=/data/host_metrics.json`
  - `/mnt/d/My_Documents/host_metrics.json:/data/host_metrics.json:ro`

Exporter script not found:
- Error: `.\export_host_metrics.ps1 is not recognized`
- Fix: Run with full path or change directory:
  ```
  cd D:\My_Documents
  .\export_host_metrics.ps1 -OutputPath "D:\My_Documents\host_metrics.json" -IntervalSeconds 30
  # or
  powershell -ExecutionPolicy Bypass -File "D:\My_Documents\export_host_metrics.ps1" -OutputPath "D:\My_Documents\host_metrics.json" -IntervalSeconds 30
  ```

Docker pull failures (auth.docker.io timeout) in WSL:
- Error: `failed to fetch oauth token ... i/o timeout`
- Fix A: Pull in Windows PowerShell:
  ```
  docker pull ubuntu:22.04
  ```
- Fix B: Set static DNS in WSL:
  ```
  # In Ubuntu (WSL)
  sudo nano /etc/wsl.conf
  [network]
  generateResolvConf = false

  sudo rm /etc/resolv.conf
  echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | sudo tee /etc/resolv.conf
  sudo chmod 644 /etc/resolv.conf

  # In Windows PowerShell
  wsl --shutdown
  # Relaunch Ubuntu, then:
  cd /mnt/d/AASTMT/5th Semester/OS_Project/SystemMonitor/docker
  docker compose up --build
  ```

jq errors reading JSON:
- Error: `Cannot index string with string "FriendlyName"` or `"VideoProcessor"`
- Cause: `.disks`/`.gpus` are single objects (not arrays) or mixed types.
- Fix: monitor.sh uses jq filters that normalize object-or-array and select only objects.

Windows thermal zones unavailable:
- Message: `No Windows thermal zones available or access denied.`
- Normal on many systems; rely on HWiNFO CSV temps.

HTML not generated:
- Ensure `GENERATE_HTML="true"`; output to `reports/system_report_...html`.

Syntax/line-ending issues:
- Use Unix line endings for scripts:
  ```
  sudo apt install -y dos2unix
  dos2unix scripts/monitor.sh
  bash -n scripts/monitor.sh   # quick syntax check
  ```

## Optional: Serve Reports via Nginx

Add a web service:
```yaml
reports-web:
  image: nginx:alpine
  container_name: system_monitor_reports_web
  ports:
    - "8080:80"
  volumes:
    - ../reports:/usr/share/nginx/html:ro
  restart: unless-stopped
```
Open `http://localhost:8080/index.html`.

## What’s Included in Reports

- `reports/system_report_YYYYMMDD_HHMMSS.txt` — raw text report
- `reports/system_report_YYYYMMDD_HHMMSS.html` — enhanced HTML report
- `reports/index.html` — auto-generated index of all reports

## Next Steps (Optional)

- Add a small GUI using dialog/whiptail or Zenity (to match course spec)
- Export JSON summaries for charts or dashboards
- Add log/report rotation (keep last N reports)
- Integrate InfluxDB/Grafana if historical charts are desired

---

AASTMT Project — Stage 1 • Owner: LujainHesham ,Nour Mohamed, Hala Mohamed(GitHub)
