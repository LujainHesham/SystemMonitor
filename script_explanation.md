# System Monitor Script: Deep Dive & Explanation

This document provides a comprehensive breakdown of the `monitor.sh` script, designed to prepare you for presenting the project. It covers the script's architecture, key functions, command explanations, unit testing strategies, and troubleshooting concepts.

## 1. Script Architecture & Flow

The `monitor.sh` script is a **Bash shell script** that orchestrates system monitoring. Its primary flow is:

1.  **Configuration**: Sets up paths, variables, and environment defaults.
2.  **Environment Detection**: Checks if running in Docker or WSL (Windows Subsystem for Linux).
3.  **Utilities**: Defines helper functions for logging, error handling, and text processing.
4.  **Data Collection**: Gathers metrics (CPU, Memory, Disk, Temp, Network, GPU) using Linux commands or Windows integration.
5.  **Report Generation**:
    *   **Text Report**: Saves raw data to a `.txt` file.
    *   **HTML Report**: Generates a cyberpunk-themed HTML dashboard.
    *   **PDF/QR**: Converts HTML to PDF and generates a QR code for mobile access.
6.  **Loop/Once Mode**: Runs once or enters a loop based on the `--interval` argument.

---

## 2. Detailed Function Breakdown

### 2.1 Configuration & Setup
*   **Shebang (`#!/usr/bin/env bash`)**: Tells the system to execute the file using Bash.
*   **`set -euo pipefail`**: A "safety mode" for scripts:
    *   `-e`: Exit immediately if any command fails.
    *   `-u`: Exit if using an undefined variable.
    *   `-o pipefail`: Exit if any part of a pipeline (e.g., `cmd1 | cmd2`) fails.
*   **Path Resolution**:
    ```bash
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ```
    Calculates the absolute path of the script directory, ensuring logs/reports are saved correctly regardless of where you run the command from.

### 2.2 Core Utilities
*   **`log_message`**: Prints timestamps and messages to both the console and a log file (`tee -a`).
*   **`command_exists`**: Checks if a tool (like `jq` or `bc`) is installed using `command -v`.
*   **`is_wsl`**: Detects WSL by looking for "microsoft" in `/proc/version`.
*   **`powershell` function**: unique to WSL. It calls `powershell.exe` on the Windows host to run commands and strips Windows carriage returns (`tr -d '\r'`).

### 2.3 Data Collection Functions & Command Breakdown

This section details exactly *how* we extract data using Linux commands.

#### A. `get_cpu_info`
*   **Goal**: Get CPU Model Name and Cores.
*   **Command**: `grep -m1 "model name" /proc/cpuinfo | cut -d: -f2`
    *   `grep -m1`: Search for "model name" but stop after the **first match** (m1).
    *   `cut -d: -f2`: Split the line by colon (`:`) and take the **second field** (the actual name).
    *   `sed 's/^ \+//'`: Removes leading spaces for a clean string.

#### B. `cpu_usage_percent` (The Math)
*   **Goal**: Calculate realtime CPU usage % over a 1-second window.
*   **Data Source**: `/proc/stat` (Kernel statistics).
*   **Logic**:
    1.  Read line starting with `cpu`: `cpu  2255 34 2290 22625563 ...`
        *   Columns: `user`, `nice`, `system`, `idle`, `iowait`, `irq`, `softirq`.
    2.  **Snapshot 1**: Read values.
    3.  `sleep 1`: Wait.
    4.  **Snapshot 2**: Read values again.
    5.  **Calculate Delta**: difference between Snap2 and Snap1.
    6.  **Formula**: `(Total_Delta - Idle_Delta) / Total_Delta * 100`.
    *   *Note*: This manual calculation is more portable than installing `top` or `mpstat` inside a container.

#### C. `get_disk_info`
*   **Goal**: Show disk usage for key filesystems.
*   **Command**: `df -h --output=source,pcent,target`
    *   `df`: "Disk Free" command.
    *   `-h`: Human-readable sizes (G for Gigabytes, M for Megabytes).
    *   `--output=...`: Customizes columns to show only what we need (Clean output!).
    *   `grep -vE ...`: Excludes "virtual" filesystems like `tmpfs` or `overlay` to reduce noise.

#### D. `get_network_info` & `print_net_throughput`
*   **Goal**: Calculate upload/download speed (Mb/s).
*   **Data Source**: `/sys/class/net/<iface>/statistics/rx_bytes` (Raw byte counters).
*   **Logic**:
    *   `RX1` = Read Received Bytes.
    *   `sleep 1`
    *   `RX2` = Read Received Bytes again.
    *   **Speed**: `(RX2 - RX1) / 1 second`.
    *   **Math**: We use `bc` (Basic Calculator) for floating point math (`scale=2` for 2 decimal places).

#### E. `check_alerts`
*   **Goal**: Warn if values exceed safety thresholds.
*   **Commands**: Simple Bash `if` statements.
    *   `if [[ $mem_percent -gt 90 ]]; then ...`
    *   **Integer Comparison**: Bash handles integers natively (`-gt` means Greater Than).
    *   **Floating Point**: For load averages (e.g., 1.5), we pipe to `bc` because Bash cannot natively compare floats.


### 2.4 HWiNFO & Temperature Strategy (The "Bridge")
Since WSL cannot directly access motherboard sensors, we rely on **HWiNFO64** running on Windows to write to a CSV file (`hwinfo_temps.csv`).
*   **`print_csv_temps`**: This bash function reads that CSV file.
*   **Logic**: It grabs the last line of the CSV (most recent data), parses the columns to find headers like "CPU Package", and extracts the corresponding value.
*   **Workaround**: If HWiNFO is not installed, the script falls back to:
    1.  **Windows WMI Thermal Zones**: Basic sensors exposed by Windows itself (often less accurate).
    2.  **`sensors` command**: Only works on native Linux (not WSL).
    3.  **Manual Check**: Advises the user to verify manually via Task Manager.

### 2.5 Report Generation (`generate_html_report`)
*   **Heredocs (`cat << 'EOF'`)**: Used to embed the HTML, CSS, and JavaScript directly inside the bash script. This makes the script portable (single file).
*   **Variable Injection**: Bash variables (like `${cpu_output}`) are injected into the HTML template.
*   **Cyberpunk Theme**: We injected custom CSS/JS to provide the neon aesthetic and tab functionality.

---

## 3. Unit Testing & Verification Concepts

To test this script professionally (Unit Testing), you would isolate individual functions. Since Bash doesn't have a built-in framework like JUnit, we use techniques:

### 3.1 Mocking Commands
How do you test `get_disk_info` without a real disk? You **mock** the `df` command.
*   **Concept**: Create a fake `df` function during testing that returns predictable text.
    ```bash
    # Test Setup
    df() { echo "Filesystem Size Used Avail Use% Mounted on"; echo "/dev/sda1 100G 50G 50G 50% /"; }
    # Run Function
    get_disk_info
    # Assert
    # Check if output contains "50%"
    ```

### 3.2 Verification Steps (Manual Testing)
For your presentation, focus on these verification methods:
1.  **Syntax Check**: `bash -n monitor.sh` (Checks for syntax errors without running).
2.  **Linting**: Use `shellcheck monitor.sh` (A static analysis tool that finds bugs/bad practices).
3.  **Variable Isolation**: Run individual functions in a terminal:
    ```bash
    source ./scripts/monitor.sh  # Load functions into current shell
    get_cpu_info                 # Run just one function
    ```

---

## 4. Error Handling & Troubleshooting Concepts

Referencing your `manual.md`, here are key concepts to understand about errors:

### 4.1 "Exit 127" (Command Not Found)
*   **Concept**: The script tried to run a command that isn't installed.
*   **Fix**: The script uses `command_exists` to check before running.
*   **Manual Ref**: See table 7.1 in manual ("Container restarting").

### 4.2 Windows Line Endings (`\r`)
*   **Concept**: Windows uses `CRLF` (\r\n) for line breaks; Linux uses `LF` (\n). Using a Windows-edited script in Linux causes "command not found \r" errors.
*   **Fix**: `dos2unix monitor.sh` converts the file format.

### 4.3 Permission Denied
*   **Concept**: Script is not executable.
*   **Fix**: `chmod +x monitor.sh`.

### 4.4 Data Persistence (Volumes)
*   **Concept**: Docker containers are ephemeral (data is lost on restart).
*   **Fix**: We use **Volumes** (in `docker-compose.yml`) to map `reports/` on the container to `reports/` on your host `D:` drive. This ensures reports survive.

---

## 5. What if HWiNFO is NOT Installed? (The Workaround)

If you move this project to a generic machine without HWiNFO:

1.  **The script detects missing CSV**: `if [[ ! -f "$csv" ]]`.
2.  **Fallback 1 (WMI)**: It tries `get_windows_temps`, which queries Windows Management Instrumentation (WMI). This is built-in to Windows, so no app is needed.
    *   *Limitation*: WMI often only shows "ThermalZone1" without specific names like "CPU Core".
3.  **Fallback 2 (Native Linux)**: If not on WSL (e.g., real Ubuntu), it runs `sensors` (lm-sensors).
4.  **Graceful Degeneracy**: The script **will not crash**. It will simply say "Temperature information unavailable" or show the limited WMI data, allowing other sections (CPU, Memory) to work fine.

---

## 6. Key Bash Concepts for Presentation

*   **Piping (`|`)**: Sending output of one command as input to another (e.g., `grep "model" | cut -d:`).
*   **Redirection (`>`)**: Saving output to a file (e.g., `cat ... > report.html`).
*   **Process Substitution (`<(...)`)**: Treating command output like a file (used in `net_snapshot`).
*   **Environment Variables**: used for configuration (`${VAR:-default}` syntax means "use default if VAR is unset").

This deep understanding will allow you to confidently explain *how* the tool works, not just *what* it does.
