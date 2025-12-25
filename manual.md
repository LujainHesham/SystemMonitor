# System Monitor Project Manual (Finalized)

This manual provides the complete, finalized instructions for setting up, running, and maintaining the System Monitor project. It consolidates previous versions into a single authoritative guide.

## Table of Contents
1. [Prerequisites & Host Setup](#1-prerequisites--host-setup)
2. [Project installation & Structure](#2-project-installation--structure)
3. [Configuration](#3-configuration)
4. [Running the System](#4-running-the-system)
5. [Using the GUI Dashboard (Zenity/YAD)](#5-using-the-gui-dashboard-zenityyad)
6. [Features (PDF, QR, Web Server)](#6-features-pdf-qr-web-server)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites & Host Setup

### 1.1 Install WSL2
1. Open **Windows PowerShell (Admin)**.
2. Run: `wsl --install`
3. Reboot if prompted.
4. Verify installation: `wsl -l -v` (Ensure Ubuntu is Version 2).

### 1.2 Install Docker Desktop
1. Download and install Docker Desktop.
2. Go to **Settings → General** and check "Use WSL 2 based engine".
3. Go to **Settings → Resources → WSL Integration** and enable it for your Ubuntu distribution.
4. Go to **Settings → Resources → File Sharing** and add the drive where the project lives (e.g., `D:\`).

### 1.3 Enable PowerShell Scripts
Open PowerShell as Admin and run:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 1.4 Install Host Tools
1. **HWiNFO64**: Install and use in "Sensors-only" mode.
2. **Tools**: Ensure you have tools to edit code (VS Code recommended).

---

## 2. Project Installation & Structure

### 2.1 Directory Structure
Ensure your project directory (e.g., `D:\AASTMT\5th Semester\OS_Project\SystemMonitor\`) looks like this:

```text
SystemMonitor/
├── docker/
│   ├── .env (Auto-generated/updated by starter script)
│   ├── Dockerfile
│   └── docker-compose.yml
├── scripts/
│   ├── monitor.sh
│   └── zenity_dashboard.sh
├── reports/ (Auto-generated HTML/PDFs)
├── logs/ (Auto-generated)
├── start_system_monitor.ps1 (The main starter script)
└── install.sh (Optional helper)
```

### 2.2 Host Data Locations
The system relies on files in `D:\My_Documents` (or your chosen location) for host telemetry:
*   **CSV logging**: `D:\My_Documents\hwinfo_temps.csv`
*   **Exporter Script**: `D:\My_Documents\export_host_metrics.ps1`
*   **JSON Output**: `D:\My_Documents\host_metrics.json`

---

## 3. Configuration

### 3.1 Configure HWiNFO64 (CSV Logging)
1. Open HWiNFO64 in **Sensors-only mode**.
2. Click **Settings** (Gear icon) → **Logging** tab.
3. Enable **"Log sensors to CSV"**.
4. Set path to: `D:\My_Documents\hwinfo_temps.csv`.
5. Set Sampling Period to **2–5 seconds**.
6. **Important**: Keep HWiNFO running for data to appear.

### 3.2 Configure Windows Exporter
Save your `export_host_metrics.ps1` to `D:\My_Documents\`. This script extracts Disk/GPU health to JSON.

---

## 4. Running the System

There are two ways to run the system. The **Recommended** way handles IP detection, Firewall rules, and the background exporter automatically.

### Option A: Recommended (PowerShell Starter Script)
This method auto-detects your IP for QR codes and ensures the web server works across Wi-Fi networks.

1. **Connect** your PC and Phone to the same Wi-Fi.
2. **Start HWiNFO** logging (Step 3.1).
3. Open **PowerShell** and navigate to your project folder.
4. Run the starter script:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start_system_monitor.ps1
   ```
   *   *Note: This script will start the background JSON exporter, configure the firewall for port 8088, update the `.env` file with your local IP, and run `docker compose up`.*

5. **Verify**:
   *   PC: Open `http://localhost:8088` or `http://<your-ip>:8088`.
   *   Phone: Scan the QR code in the latest report to open the PDF.

### Option B: Manual Method
1. **Start the Windows Exporter**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "D:\My_Documents\export_host_metrics.ps1" -OutputPath "D:\My_Documents\host_metrics.json" -IntervalSeconds 30
   ```
2. **Run Docker**:
   ```bash
   cd /mnt/d/path/to/project/docker
   docker compose up --build
   ```

---

## 5. Using the GUI Dashboard (Zenity/YAD)

This dashboard runs inside WSL to provide a graphical interface for reports and stats.

### 5.1 Prerequisites (Inside WSL)
```bash
sudo apt update
sudo apt install zenity xdg-utils yad -y
```

### 5.2 Running the Dashboard
1. Open your WSL terminal.
2. Navigate to the project scripts:
   ```bash
   cd /mnt/d/AASTMT/5th Semester/OS_Project/SystemMonitor/scripts
   ```
3. Make executable:
   ```bash
   chmod +x zenity_dashboard.sh
   ```
4. Run:
   ```bash
   ./zenity_dashboard.sh
   ```

### 5.3 Dashboard Features
*   **View Latest Report**: Opens the most recent HTML report.
*   **Report Index**: Opens the full list of reports.
*   **Live Stats**: Displays real-time CPU/Memory/Network stats.
*   **Theme**: Cyberpunk-Neon styled interface.

---

## 6. Features (PDF, QR, Web Server)

### 6.1 PDF Generation
*   **Tool**: `wkhtmltopdf`
*   **Function**: Automatically converts the HTML report to PDF.
*   **Use**: Click the "Download PDF" link in the report.

### 6.2 QR Code Sharing
*   **Tool**: `qrencode`
*   **Function**: Generates a QR code pointing to the PDF URL.
*   **Setup**: The `start_system_monitor.ps1` script automatically sets the `REPORT_BASE_URL` to your local Wi-Fi IP so the QR code works on mobile devices on the same network.

### 6.3 HTTP Server
*   The container invokes Python's `http.server` on port **8088**.
*   Exposes the `reports/` directory.

---

## 7. Troubleshooting & Known Issues

### 7.1 Installation & Build Issues

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **Build hangs at `apt-get install` (tzdata)** | Interactive prompt for timezone selection. | Fixed in Dockerfile using `ENV DEBIAN_FRONTEND=noninteractive`. |
| **Docker pull token timeout / DNS error** | WSL DNS configuration issues. | 1. In WSL: `sudo nano /etc/wsl.conf` set `generateResolvConf=false`.<br>2. `sudo rm /etc/resolv.conf`<br>3. `echo "nameserver 8.8.8.8" \| sudo tee /etc/resolv.conf` |
| **Container restarting (Exit 127)** | `log_message: command not found` in `monitor.sh`. | Fixed by defining utility functions before calling them in the script. |
| **Message: "Script/runtime errors"** | `monitor.sh` has Windows line endings (`\r`). | Run `dos2unix scripts/monitor.sh` in WSL. |
| **Package `xdg-open` or `yad` not found** | Missing dependencies in WSL. | Run `sudo apt update && sudo apt install xdg-utils yad -y`. |
| **Wrong file name in Theme extraction** | Using `tar` on a `.zip` file. | Use `unzip` instead. |

### 7.2 Runtime & Data Issues

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **CSV parsing shows labels (e.g., DTS°C) instead of numbers** | Naive CSV splitting; quoted fields/units. | Set `CSV_DELIM=","` and ensure HWiNFO logs numeric values (Settings → Custom). |
| **"Windows GPU/Disk info unavailable"** | Exporter not running or JSON path wrong. | Ensure `export_host_metrics.ps1` is running and writing to the mounted JSON path. |
| **"No Windows physical disks/GPUs found"** | JSON structure mismatch (Object vs Array). | Fixed in `jq` filters to handle both single objects and arrays. |
| **Thermal zones empty** | Common on modern Windows via WSL. | Rely on HWiNFO CSV temps instead. |
| **Network throughput initially 0 Mb/s** | Sampling during idle period. | Generate traffic (e.g., `curl` download) or wait for longer sampling windows. |
| **Bash array errors (`TX1[eth0]...`)** | Missing `=` or unbound variables. | Fixed in script logic (e.g., `${TX1[$iface]:-0}`). |
| **WSL path error (`-bash: cd: D:\...`)** | Using Windows paths in Linux. | Use WSL paths: `/mnt/d/AASTMT/...`. |
| **Reports saving in wrong location** | Relative path confusion. | Fixed by using absolute paths (`PROJECT_ROOT`) in scripts. |

### 7.3 Network & Feature Issues (QR/PDF)

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **Phone cannot open QR link** | 1. Different Wi-Fi networks.<br>2. Windows Network Profile is Public.<br>3. Firewall blocking port. | 1. Connect to same Wi-Fi.<br>2. Set Network Profile to **Private**.<br>3. Run `start_system_monitor.ps1` (it adds Firewall rule). |
| **PowerShell parser error (`http://$ip:$Port`)** | Variable interpolation syntax. | Use `http://$($ip):$($Port)`. |
| **"Generating..." in index forever** | Index generator looking at wrong path. | Fixed by using absolute paths in the index generation loop. |

### 7.4 Zenity/GUI Dashboard Issues

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **Invisible menu options** | Pango markup in list columns. | Removed markup from data columns (kept it for headers only). |
| **Deprecated Zenity flags warnings** | Old flags like `--window-icon`. | Removed deprecated flags. |
| **Extra header dialogs** | Header logic inside loop. | Moved header display overlap to startup only. |
| **Theme not applying** | GTK settings not reloaded. | Logout/Login or Reboot after setting `gtk-theme-name`. |
| **Tabs not switching in HTML** | JS ID mismatch. | Fixed JavaScript event listeners and IDs. |

### 7.5 Quick Verification Commands
*   **Check JSON**: `Get-Content "D:\My_Documents\host_metrics.json" -TotalCount 20`
*   **Check Exporter**: `Get-Process | Where-Object {$_.ProcessName -eq "powershell"}`
*   **Check Docker**: `docker logs -f system_monitor`
*   **Check Firewall**: `Get-NetFirewallRule -DisplayName "Docker Reports 8088"`

---

## 8. Quick Command Cheatsheet

**1. Start HWiNFO64**
*   **Action**: Open App → "Sensors-only" → Start.
*   **Logging**: Settings (Gear) → Logging → "Log sensors to CSV" → `D:\My_Documents\hwinfo_temps.csv`.

**2. Start System (Recommended)**
```powershell
# In PowerShell (Project Directory)
powershell -ExecutionPolicy Bypass -File .\start_system_monitor.ps1
```

**3. Start System (Manual / No Script)**
```powershell
# 1. Start Exporter (Window 1)
powershell -ExecutionPolicy Bypass -File "D:\My_Documents\export_host_metrics.ps1" -OutputPath "D:\My_Documents\host_metrics.json" -IntervalSeconds 30

# 2. Start Docker (Window 2 - WSL)
cd /mnt/d/AASTMT/5th\ Semester/OS_Project/SystemMonitor/docker
docker compose up --build
```

**4. Generate Network Traffic (For testing)**
```bash
# In a new WSL/Docker terminal
docker exec -it system_monitor bash -lc 'timeout 30s curl -s http://speedtest.tele2.net/100MB.zip >/dev/null'
```

**5. Start Dashboard (WSL)**
```bash
cd /mnt/d/AASTMT/5th\ Semester/OS_Project/SystemMonitor/scripts
./zenity_dashboard.sh
```