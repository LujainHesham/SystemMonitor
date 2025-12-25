#!/usr/bin/env bash
# ============================================
# System Monitoring Tool - Stage 1 (v8: fix syntax, CSV temps fallback, Windows integration default)
# AASTMT Project - Member 1
# ============================================

set -euo pipefail

# --------------------------------------------
# Configuration (overridable via environment)
# --------------------------------------------
# Resolve absolute paths to ensure reports/logs go to Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
REPORT_DIR="${REPORT_DIR:-$PROJECT_ROOT/reports}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/system_monitor.log}"

GENERATE_HTML=${GENERATE_HTML:-true}           # true|false
BRIEF_MODE=${BRIEF_MODE:-false}                 # true|false
RUN_INTERVAL_SECONDS=${RUN_INTERVAL_SECONDS:-0} # 0 = run once; >0 = loop mode
CPU_SAMPLE_SECONDS=${CPU_SAMPLE_SECONDS:-1}     # sampling window for CPU usage
VERBOSE=${VERBOSE:-false}                       # enables verbose sections (e.g., SMART in WSL)


# New toggles for PDF/QR/HTTP server
ENABLE_PDF="${ENABLE_PDF:-true}"
ENABLE_QR="${ENABLE_QR:-true}"
ENABLE_HTTP_SERVER="${ENABLE_HTTP_SERVER:-true}"
HTTP_PORT="${HTTP_PORT:-8088}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"


# Enable Windows integration by default (can be disabled with USE_WINDOWS_INTEGRATION=false)
USE_WINDOWS_INTEGRATION=${USE_WINDOWS_INTEGRATION:-true} # If true and WSL, call PowerShell/HTTP for host metrics


# CSV fallback for temps (HWiNFO/HWMonitor CSV)
WINDOWS_TEMPS_CSV="${WINDOWS_TEMPS_CSV:-}"    # e.g., /mnt/c/Users/<you>/Documents/hwinfo_temps.csv or D:\...\hwinfo_temps.csv
CSV_MAX_CORES="${CSV_MAX_CORES:-6}"           # how many core temps to print from CSV
CSV_DELIM="${CSV_DELIM:-}"                    # optional delimiter override ("," or ";"), auto-detected if unset

# JSON exported by Windows PowerShell (mounted into the container)
HOST_METRICS_JSON="${HOST_METRICS_JSON:-/data/host_metrics.json}"

# Detect Docker
is_docker() { [[ -f /.dockerenv ]]; }


# Create directories if they don't exist
mkdir -p "$REPORT_DIR" "$LOG_DIR"


# --------------------------------------------
# Utilities
# --------------------------------------------
log_message() {
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    printf "[%s] %s\n" "$ts" "$1" | tee -a "$LOG_FILE"
}

error() {
    log_message "ERROR: $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_wsl() {
    grep -qi "microsoft" /proc/version 2>/dev/null
}

normalize_percent() {
    local val="$1"
    if [[ "$val" == .* ]]; then
        printf "0%s" "$val"
    else
        printf "%s" "$val"
    fi
}

to_wsl_path() {
    local p="$1"
    if [[ -z "$p" ]]; then
        echo ""
        return 0
    fi
    # If it looks like C:\... and wslpath exists, convert
    if [[ "$p" =~ ^[A-Za-z]:\\ ]] && command -v wslpath >/dev/null 2>&1; then
        wslpath "$p"
    else
        echo "$p"
    fi
}

strip_quotes() {
    # removes leading/trailing double quotes
    echo "$1" | sed 's/^"//; s/"$//'
}

ALERT_COUNT=0



# --- Network throughput and errors ---
net_read_dev() {
    # Print cleaned /proc/net/dev lines: iface rx_bytes rx_packets rx_errs rx_drop tx_bytes tx_packets tx_errs tx_drop
    awk -F'[: ]+' '
      NR>2 && $1 != "" {
        iface=$1
        rx_bytes=$3; rx_packets=$4; rx_errs=$5; rx_drop=$6
        tx_bytes=$11; tx_packets=$12; tx_errs=$13; tx_drop=$14
        printf "%s %s %s %s %s %s %s %s %s\n", iface, rx_bytes, rx_packets, rx_errs, rx_drop, tx_bytes, tx_packets, tx_errs, tx_drop
      }
    ' /proc/net/dev
}

net_snapshot() {
    # Capture a snapshot keyed by iface
    declare -A SNAP
    while read -r iface rx_b rx_p rx_e rx_d tx_b tx_p tx_e tx_d; do
        SNAP["$iface"]="$rx_b $rx_p $rx_e $rx_d $tx_b $tx_p $tx_e $tx_d"
    done < <(net_read_dev)
    # Print as iface:values one per line for process substitution consumption
    for k in "${!SNAP[@]}"; do
        echo "$k ${SNAP[$k]}"
    done
}

print_net_throughput() {
    local interval="${CPU_SAMPLE_SECONDS:-1}"

    # Build interface list (skip lo by default)
    local ifaces=()
    for d in /sys/class/net/*; do
        local iface; iface=$(basename "$d")
        [[ "$iface" == "lo" ]] && continue
        local state; state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo down)
        [[ "$state" != "up" && "$state" != "unknown" ]] && continue
        ifaces+=("$iface")
    done

    # First snapshot
    declare -A RX1 TX1 RXE1 TXE1
    for iface in "${ifaces[@]}"; do
        RX1["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX1["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        RXE1["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo 0)
        TXE1["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo 0)
    done

    sleep "$interval"

    # Second snapshot
    declare -A RX2 TX2 RXE2 TXE2
    for iface in "${ifaces[@]}"; do
        RX2["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX2["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        RXE2["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo 0)
        TXE2["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo 0)
    done

    echo "Throughput over ${interval}s:"
    printf "%-16s %-12s %-12s %-10s %-10s\n" "Interface" "RX (Mb/s)" "TX (Mb/s)" "RXerrs" "TXerrs"

    for iface in "${ifaces[@]}"; do
        local drx=$(( ${RX2[$iface]} - ${RX1[$iface]} ))
        local dtx=$(( ${TX2[$iface]} - ${TX1[$iface]} ))
        local rx_mbps tx_mbps
        rx_mbps=$(echo "scale=2; ($drx / $interval) * 8 / 1000000" | bc 2>/dev/null || echo "0")
        tx_mbps=$(echo "scale=2; ($dtx / $interval) * 8 / 1000000" | bc 2>/dev/null || echo "0")
        local rxerrs="${RXE2[$iface]}" txerrs="${TXE2[$iface]}"
        printf "%-16s %-12s %-12s %-10s %-10s\n" "$iface" "$rx_mbps" "$tx_mbps" "$rxerrs" "$txerrs"
    done
}

print_net_errors_detail() {
    # Use ip -s link if available for detailed stats
    if command_exists ip; then
        echo ""
        echo "Interface error counters (ip -s link):"
        ip -s link | sed -n '1,200p'
    else
        echo ""
        echo "Detailed error counters unavailable (ip command missing)."
    fi
}


ensure_http_server() {
    if [[ "$ENABLE_HTTP_SERVER" == "true" ]]; then
        # Start once; serve the reports directory on HTTP_PORT
        if ! pgrep -f "http.server.*${HTTP_PORT}" >/dev/null 2>&1; then
            nohup python3 -m http.server "$HTTP_PORT" --directory "$REPORT_DIR" >/dev/null 2>&1 &
            log_message "HTTP server started on port ${HTTP_PORT}, serving ${REPORT_DIR}"
        fi
    fi
}

# Call HTTP server setup early
ensure_http_server
# --------------------------------------------
# Argument parsing
# --------------------------------------------
show_help() {
    cat << 'EOF'
Usage: monitor.sh [OPTIONS]

Options:
  --html            Generate HTML report in addition to text
  --brief           Show only critical information and top-line metrics
  --interval N      Run repeatedly every N seconds (container-friendly)
  --help            Show this help message

Environment overrides:
  LOG_DIR, REPORT_DIR, LOG_FILE
  GENERATE_HTML=true|false
  BRIEF_MODE=true|false
  RUN_INTERVAL_SECONDS=N
  CPU_SAMPLE_SECONDS=N
  VERBOSE=true|false
  USE_WINDOWS_INTEGRATION=true|false   # In WSL, query Windows host for GPU/disk/etc. (default: true)
  CSV_MAX_CORES=6                      # how many core temps to print from CSV
  CSV_DELIM=","                        # optional delimiter override ("," or ";"), auto-detected if unset
  WINDOWS_TEMPS_CSV="D:\My_Documents\hwinfo_temps.CSV"    # Windows path accepted; auto-converted to /mnt/d/...
Examples:
  ./scripts/monitor.sh
  USE_WINDOWS_INTEGRATION=false ./scripts/monitor.sh
  WINDOWS_TEMPS_CSV="/mnt/d/Documents/hwinfo_temps.csv" ./scripts/monitor.sh
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --html) GENERATE_HTML=true; shift ;;
            --brief) BRIEF_MODE=true; shift ;;
            --interval)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    RUN_INTERVAL_SECONDS="$2"; shift 2
                else
                    error "Invalid --interval value. Must be an integer seconds."
                    exit 2
                fi
                ;;
            --help)
                show_help; exit 0 ;;
            *)
                error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# --------------------------------------------
# CSV temps fallback (no nested functions)
# --------------------------------------------
print_csv_temps() {
    # Reads temperatures from a CSV produced by HWiNFO/HWMonitor.
    # Typical headers: "CPU Package [°C]", "Core #1 [°C]", "GPU Temperature [°C]"
    local csv
    csv="$(to_wsl_path "$WINDOWS_TEMPS_CSV")"
    [[ -z "$csv" ]] && { echo "CSV path not set (WINDOWS_TEMPS_CSV)."; return 1; }
    [[ ! -f "$csv" ]] && { echo "CSV file not found: $csv"; return 1; }

    # Read header and last non-empty row
    local header_raw last_raw
    header_raw=$(head -n 1 "$csv")
    last_raw=$(tail -n 200 "$csv" | awk 'NF' | tail -n 1)
    [[ -z "$header_raw" || -z "$last_raw" ]] && { echo "CSV header or data missing."; return 1; }

    # Determine delimiter: prefer CSV_DELIM if set, else auto-detect
    local delim="$CSV_DELIM"
    if [[ -z "$delim" ]]; then
        if [[ "$header_raw" == *";"* && "$header_raw" != *","* ]]; then
            delim=";"
        else
            delim=","
        fi
    fi

    # Split into arrays
    local IFS="$delim"
    # shellcheck disable=SC2206
    read -r -a cols <<< "$header_raw"
    # shellcheck disable=SC2206
    read -r -a vals <<< "$last_raw"

    # Find CPU package and GPU temperature indices with broad patterns
    local idx_pkg="" idx_gpu="" i
    for i in "${!cols[@]}"; do
        # CPU package or CPU temperature variants
        if echo "${cols[$i]}" | grep -Eiq 'CPU *Package|Tctl|CPU .*Temperature|Processor .*Temperature'; then
            idx_pkg="$i"; break
        fi
    done
    for i in "${!cols[@]}"; do
        # GPU temperature variants: Temperature, Hotspot/Hot Spot, Edge
        if echo "${cols[$i]}" | grep -Eiq 'GPU .*Temperature|GPU .*Hot[[:space:]]*Spot|GPU .*Edge|Graphics .*Temperature'; then
            idx_gpu="$i"; break
        fi
    done

    # Print CPU package temp if found
    if [[ -n "$idx_pkg" ]]; then
        local v
        v=$(strip_quotes "${vals[$idx_pkg]}")
        echo "CPU Package Temp (CSV): ${v}°C"
    fi

    # Print up to CSV_MAX_CORES core temps
    local printed=0 name vclean
    for i in "${!cols[@]}"; do
        if echo "${cols[$i]}" | grep -Eiq '(^| )Core #[0-9]+( |$)|CPU Core #[0-9]+'; then
            name=$(echo "${cols[$i]}" | sed 's/\[°C\]//; s/ Temperature//; s/"//g')
            vclean=$(strip_quotes "${vals[$i]}")
            echo "${name}: ${vclean}°C"
            printed=$((printed+1))
            [[ $printed -ge ${CSV_MAX_CORES:-6} ]] && break
        fi
    done

    # Print GPU temperature if found
    if [[ -n "$idx_gpu" ]]; then
        local vg
        vg=$(strip_quotes "${vals[$idx_gpu]}")
        echo "GPU Temperature (CSV): ${vg}°C"
    fi

    if [[ -z "$idx_pkg" && -z "$idx_gpu" && $printed -eq 0 ]]; then
        echo "No temperature columns matched in CSV. Check logging settings and delimiter."
        return 1
    fi

    return 0
}

# --------------------------------------------
# CPU usage helper
# --------------------------------------------
cpu_usage_percent() {
    local s1 s2 u1 n1 s1c i1 w1 irq1 sirq1 st1 u2 n2 s2c i2 w2 irq2 sirq2 st2
    # shellcheck disable=SC2206
    s1=($(grep -m1 '^cpu ' /proc/stat))
    sleep "$CPU_SAMPLE_SECONDS"
    # shellcheck disable=SC2206
    s2=($(grep -m1 '^cpu ' /proc/stat))
    u1=${s1[1]}; n1=${s1[2]}; s1c=${s1[3]}; i1=${s1[4]}; w1=${s1[5]}; irq1=${s1[6]}; sirq1=${s1[7]}; st1=${s1[8]}
    u2=${s2[1]}; n2=${s2[2]}; s2c=${s2[3]}; i2=${s2[4]}; w2=${s2[5]}; irq2=${s2[6]}; sirq2=${s2[7]}; st2=${s2[8]}
    local idle_delta total_delta used_delta
    idle_delta=$(( (i2 + w2) - (i1 + w1) ))
    total_delta=$(( (u2 - u1) + (n2 - n1) + (s2c - s1c) + (i2 - i1) + (w2 - w1) + (irq2 - irq1) + (sirq2 - sirq1) + (st2 - st1) ))
    used_delta=$(( total_delta - idle_delta ))
    if (( total_delta > 0 )); then
        if command_exists bc; then
            local pct
            pct=$(echo "scale=2; ($used_delta*100)/$total_delta" | bc)
            normalize_percent "$pct"
        else
            printf "%s" $(( (used_delta * 100) / total_delta ))
        fi
    else
        printf "0"
    fi
}

# --------------------------------------------
# Windows host integration helpers (WSL-only)
# --------------------------------------------
powershell() {
    command -v powershell.exe >/dev/null 2>&1 || return 1
    powershell.exe -NoProfile -ExecutionPolicy Bypass "$@" 2>/dev/null | tr -d '\r'
}

get_windows_temps() {
    if ! is_wsl || [[ "$USE_WINDOWS_INTEGRATION" != "true" ]]; then
        return 1
    fi
    powershell '
$zones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
if (!$zones) { Write-Output "No Windows thermal zones available"; exit }
foreach ($z in $zones) {
  $c = [math]::Round(($z.CurrentTemperature/10 - 273.15),2)
  Write-Output ("Zone: {0}, TempC: {1}" -f $z.InstanceName, $c)
}
' || true
}

get_windows_gpu_info() {
    if ! is_wsl || [[ "$USE_WINDOWS_INTEGRATION" != "true" ]]; then
        return 1
    fi

    # Prefer host JSON when running inside Docker
    if is_docker && [[ -f "$HOST_METRICS_JSON" ]] && command_exists jq; then
        print_windows_gpu_from_json && return 0
    fi

    # Fallback to PowerShell when running in WSL (non-container)
    powershell '
$gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
if (!$gpus) { Write-Output "No Windows GPUs found"; exit }
foreach ($g in $gpus) {
  Write-Output ("Adapter: {0} | DriverVersion: {1} | VideoProcessor: {2}" -f $g.Name, $g.DriverVersion, $g.VideoProcessor)
}
Write-Output ""

# GPU Engine Utilization (Windows counters)
$ctr = Get-Counter -Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue
$showPids = $env:SHOW_GPU_PIDS
if ([string]::IsNullOrEmpty($showPids)) { $showPids = "true" }

if ($ctr) {
  Write-Output "GPU Engine Utilization (Windows counters):"
  if ($showPids -eq "false") {
    Write-Output "(per-PID lines suppressed)"
  } else {
    foreach ($s in $ctr.CounterSamples) {
      Write-Output ("{0}: {1}%" -f $s.InstanceName, [math]::Round($s.CookedValue,2))
    }
  }
} else {
  Write-Output "GPU Engine counters not available."
}

Write-Output ""
Write-Output "GPU Memory (if exposed by counters):"
$memCtrs = Get-Counter -Counter "\GPU Adapter Memory(*)\Dedicated Usage" -ErrorAction SilentlyContinue
if ($memCtrs) {
  foreach ($s in $memCtrs.CounterSamples) {
    Write-Output ("{0}: {1} MB" -f $s.InstanceName, [math]::Round($_.CookedValue/1MB,2))
  }
} else {
  Write-Output "GPU Adapter Memory counters not available."
}
' || true
    return 0
}

get_windows_disk_health() {
    if ! is_wsl || [[ "$USE_WINDOWS_INTEGRATION" != "true" ]]; then
        return 1
    fi

    # Prefer host JSON when running inside Docker
    if is_docker && [[ -f "$HOST_METRICS_JSON" ]] && command_exists jq; then
        print_windows_disk_health_from_json && return 0
    fi

    # Fallback to PowerShell when running in WSL (non-container)
    powershell '
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
if (!$disks) { Write-Output "No Windows physical disks found"; exit }
$disks | Select-Object FriendlyName, HealthStatus, OperationalStatus, Size | Format-Table -AutoSize | Out-String
' || true
    return 0
}

# ---------- JSON readers for Windows metrics (Docker-friendly) ----------
print_windows_disk_health_from_json() {
    local f="${HOST_METRICS_JSON}"
    [[ ! -f "$f" ]] && return 1
    command_exists jq || { echo "Host metrics JSON present but jq missing."; return 1; }

    # Normalize disks to an array: wrap object in an array if needed, filter only objects
    local count
    count=$(jq '
      .disks
      | if type=="object" then [.] elif type=="array" then . else [] end
      | map(select(type=="object"))
      | length
    ' "$f" 2>/dev/null || echo 0)

    (( count == 0 )) && { echo "No Windows physical disks found (JSON)."; return 1; }

    printf "%-30s %-12s %-18s %-10s\n" "FriendlyName" "Health" "OperationalStatus" "SizeGB"
    jq -r '
      .disks
      | if type=="object" then [.] elif type=="array" then . else [] end
      | map(select(type=="object"))
      | .[]
      | [
          (.FriendlyName // "N/A"),
          (.HealthStatus // "Unknown"),
          (.OperationalStatus // "Unknown"),
          ((.Size // 0) | tonumber / 1024 / 1024 / 1024)
        ] | @tsv
    ' "$f" \
    | awk -F'\t' '{ printf "%-30s %-12s %-18s %-10.2f\n", $1, $2, $3, $4 }'
    return 0
}

print_windows_gpu_from_json() {
    local f="${HOST_METRICS_JSON}"
    [[ ! -f "$f" ]] && return 1
    command_exists jq || { echo "Host metrics JSON present but jq missing."; return 1; }

    # Normalize gpus to an array: wrap object in an array if needed, filter only objects
    local gcount
    gcount=$(jq '
      .gpus
      | if type=="object" then [.] elif type=="array" then . else [] end
      | map(select(type=="object"))
      | length
    ' "$f" 2>/dev/null || echo 0)

    if (( gcount > 0 )); then
        echo "Adapters:"
        jq -r '
          .gpus
          | if type=="object" then [.] elif type=="array" then . else [] end
          | map(select(type=="object"))
          | .[]
          | "  Name: " + (.Name // "N/A")
            + " | Driver: " + (.DriverVersion // "N/A")
            + " | Processor: " + (.VideoProcessor // "N/A")
        ' "$f"
    else
        echo "No Windows GPUs found (JSON)."
    fi

    echo ""
    echo "GPU Engine Utilization:"
    local ucount
    ucount=$(jq '.gpuCounters.Utilization | length' "$f" 2>/dev/null || echo 0)
    if (( ucount > 0 )); then
        jq -r '.gpuCounters.Utilization[] | "  " + (.Instance // "Unknown") + ": " + ( .Value | tostring ) + "%"' "$f"
    else
        echo "  GPU Engine counters not available."
    fi

    echo ""
    echo "GPU Memory (Dedicated Usage):"
    local mcount
    mcount=$(jq '.gpuCounters.Memory | length' "$f" 2>/dev/null || echo 0)
    if (( mcount > 0 )); then
        jq -r '.gpuCounters.Memory[] | "  " + (.Instance // "Unknown") + ": " + ( .MB | tostring ) + " MB"' "$f"
    else
        echo "  GPU memory counters not available."
    fi

    return 0
}

# --------------------------------------------
# Monitoring functions
# --------------------------------------------
get_cpu_info() {
    log_message "Collecting CPU information..."
    echo "========== CPU INFORMATION =========="
    if [[ -f /proc/cpuinfo ]]; then
        local model cores
        model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ \+//')
        cores=$(grep -c "^processor" /proc/cpuinfo)
        echo "CPU Model: ${model:-Unknown}"
        echo "CPU Cores: ${cores:-Unknown}"
    else
        echo "CPU Model: Information not available"
    fi
    if command_exists uptime; then
        local load
        load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ \+//')
        echo "Load Average:${load}"
    fi
    if [[ -f /proc/stat ]]; then
        local s1 s2 u1 n1 s1c i1 w1 irq1 sirq1 st1 u2 n2 s2c i2 w2 irq2 sirq2 st2
        # shellcheck disable=SC2206
        s1=($(grep -m1 '^cpu ' /proc/stat))
        sleep "$CPU_SAMPLE_SECONDS"
        # shellcheck disable=SC2206
        s2=($(grep -m1 '^cpu ' /proc/stat))
        u1=${s1[1]}; n1=${s1[2]}; s1c=${s1[3]}; i1=${s1[4]}; w1=${s1[5]}; irq1=${s1[6]}; sirq1=${s1[7]}; st1=${s1[8]}
        u2=${s2[1]}; n2=${s2[2]}; s2c=${s2[3]}; i2=${s2[4]}; w2=${s2[5]}; irq2=${s2[6]}; sirq2=${s2[7]}; st2=${s2[8]}
        local idle_delta total_delta used_delta usage_percent
        idle_delta=$(( (i2 + w2) - (i1 + w1) ))
        total_delta=$(( (u2 - u1) + (n2 - n1) + (s2c - s1c) + (i2 - i1) + (w2 - w1) + (irq2 - irq1) + (sirq2 - sirq1) + (st2 - st1) ))
        used_delta=$(( total_delta - idle_delta ))
        if (( total_delta > 0 )); then
            if command_exists bc; then
                usage_percent=$(echo "scale=2; ($used_delta*100)/$total_delta" | bc)
                usage_percent=$(normalize_percent "$usage_percent")
                echo "CPU Usage: ${usage_percent}% (sample ${CPU_SAMPLE_SECONDS}s)"
            else
                usage_percent=$(( (used_delta * 100) / total_delta ))
                echo "CPU Usage: ${usage_percent}% (bc not installed, ${CPU_SAMPLE_SECONDS}s sample)"
            fi
        fi
    fi
    echo ""
}

get_memory_info() {
    log_message "Collecting Memory information..."
    echo "========== MEMORY INFORMATION =========="
    if command_exists free; then
        free -h
    else
        echo "Memory information not available (free command missing)"
    fi
    echo ""
}

get_disk_info() {
    log_message "Collecting Disk information..."
    echo "========== DISK INFORMATION =========="
    if command_exists df; then
        echo "Key Filesystems:"
        df -h --output=source,fstype,size,used,avail,pcent,target / 2>/dev/null | head -1
        df -h --output=source,fstype,size,used,avail,pcent,target / 2>/dev/null | tail -n +2
        [[ -d /mnt/c ]] && df -h --output=source,fstype,size,used,avail,pcent,target /mnt/c 2>/dev/null | tail -n +2 || true
        [[ -d /mnt/d ]] && df -h --output=source,fstype,size,used,avail,pcent,target /mnt/d 2>/dev/null | tail -n +2 || true
        echo ""
        echo "All Filesystems (WSL includes overlays and tmpfs):"
        df -h --output=source,fstype,size,used,avail,pcent,target | grep -vE '^none +overlay|^none +tmpfs|^rootfs +rootfs' | head -50
    else
        echo "Disk information not available (df command missing)"
    fi

    if is_wsl && [[ "$USE_WINDOWS_INTEGRATION" == "true" ]]; then
        echo ""
        echo "--- Windows Disk Health (Host) ---"
        local wh
        wh=$(get_windows_disk_health || true)
        [[ -n "$wh" ]] && echo "$wh" || echo "Windows disk health information unavailable."
    fi
    echo ""
}

get_temperature_info() {
    log_message "Collecting Temperature information..."
    echo "========== TEMPERATURE INFORMATION =========="

    if is_wsl; then
        echo "WSL Environment Detected"
        if [[ "$USE_WINDOWS_INTEGRATION" == "true" ]]; then
            # CSV ingestion (HWiNFO/HWMonitor) FIRST
            if [[ -n "$WINDOWS_TEMPS_CSV" ]]; then
                echo "--- CSV Temperatures (Windows) ---"
                if print_csv_temps; then
                    :
                else
                    echo "CSV fallback failed or no matching columns."
                fi
            else
                echo "CSV path not set (WINDOWS_TEMPS_CSV). Skipping CSV temps."
            fi

            # Windows thermal zones as a last resort
            echo "--- Windows Host Thermal Zones ---"
            local tz
            tz=$(get_windows_temps || true)
            [[ -n "$tz" ]] && echo "$tz" || echo "No Windows thermal zones available or access denied."
            echo "Tip: Best results from HWiNFO64 CSV logging. Set WINDOWS_TEMPS_CSV to the CSV path."
        else
            echo "Tip: Use Windows tools like HWMonitor or Task Manager (Performance tab) for temperatures."
            echo "Enable host integration: USE_WINDOWS_INTEGRATION=true"
        fi
    else
        if command_exists sensors; then
            local sensors_output
            sensors_output=$(sensors 2>/dev/null || true)
            if [[ -n "$sensors_output" ]]; then
                echo "Using lm-sensors:"
                echo "$sensors_output" | head -40
            else
                echo "  No temperature sensors detected"
                echo "  Run: sudo sensors-detect (then load suggested modules)"
            fi
        elif [[ -d /sys/class/thermal ]]; then
            echo "Using sysfs thermal zones:"
            local count=0
            for zone in /sys/class/thermal/thermal_zone*; do
                if [[ -f "$zone/temp" ]]; then
                    local temp type temp_c
                    temp=$(cat "$zone/temp" 2>/dev/null || echo "")
                    type=$(cat "$zone/type" 2>/dev/null || echo "unknown")
                    if [[ -n "$temp" && "$temp" != "0" ]]; then
                        temp_c=$((temp / 1000))
                        echo "  $type: ${temp_c}°C"
                        count=$((count + 1))
                    fi
                fi
            done
            (( count == 0 )) && echo "  No active thermal zones found"
        else
            echo "Temperature monitoring not available"
            echo "Install lm-sensors: sudo apt install lm-sensors"
        fi
    fi
    echo ""
}


get_network_info() {
    log_message "Collecting Network information..."
    echo "========== NETWORK INFORMATION =========="
    if command_exists ip; then
        echo "Network Interfaces:"
        ip -brief addr show | head -20
    elif command_exists ifconfig; then
        echo "Network Interfaces:"
        ifconfig | grep -A1 "^[a-z]" | head -40
    else
        echo "Network information not available (ip/ifconfig commands missing)"
    fi

    if command_exists ip; then
        echo ""
        echo "Default Gateway:"
        ip route | grep "^default" | head -5
    fi

    echo ""
    print_net_throughput
    print_net_errors_detail
    echo ""
}

get_gpu_info() {
    log_message "Collecting GPU information..."
    echo "========== GPU INFORMATION =========="

    if is_wsl && [[ "$USE_WINDOWS_INTEGRATION" == "true" ]]; then
        echo "--- Windows Host GPU (Intel/Generic) ---"
        local gpu
        gpu=$(get_windows_gpu_info || true)
        if [[ -n "$gpu" ]]; then
            echo "$gpu"
        else
            echo "Windows GPU information unavailable."
        fi
        echo "Note: For deeper Intel GPU telemetry on Windows, use Intel Graphics Command Center."
    else
        if is_wsl; then
            echo "WSL Detected: Enable USE_WINDOWS_INTEGRATION=true for Windows GPU counters."
            echo "Intel GPUs have limited exposure inside WSL."
        fi
        if [[ -d /sys/class/drm ]] && ls /sys/class/drm/card*/device/vendor 2>/dev/null | grep -q "0x8086"; then
            echo "Intel GPU detected via DRM (limited metrics in WSL)."
        else
            echo "No GPU information available"
        fi
    fi
    echo ""
}

get_smart_status() {
    log_message "Collecting SMART status..."
    echo "========== SMART STATUS =========="
    if is_wsl && [[ "$USE_WINDOWS_INTEGRATION" == "true" ]]; then
        echo "--- Windows Host Disk Health ---"
        local wh
        wh=$(get_windows_disk_health || true)
        if [[ -n "$wh" ]]; then
            echo "$wh"
        else
            echo "Windows disk health information unavailable."
        fi
        echo ""
        return 0
    fi
    if is_wsl && [[ "$VERBOSE" != "true" ]]; then
        echo "WSL Detected: SMART access limited. Enable USE_WINDOWS_INTEGRATION=true or use Windows tools."
        echo ""
        return 0
    fi
    if ! command_exists smartctl; then
        echo "smartctl not installed. Install: sudo apt install smartmontools"
        echo ""
        return 1
    fi
    echo "Scanning for storage devices..."
    local scan_result
    scan_result=$(smartctl --scan 2>/dev/null || true)
    if [[ -n "$scan_result" ]]; then
        echo "$scan_result"
        echo ""
        while read -r line; do
            local device
            device=$(echo "$line" | awk '{print $1}')
            [[ -z "$device" ]] && continue
            echo "Checking $device:"
            local info health
            info=$(smartctl -i "$device" 2>/dev/null | grep -E "(Model|Serial|Capacity|SMART support)" | head -10 || true)
            [[ -n "$info" ]] && echo "$info" | sed 's/^/  /' || echo "  Could not read device info"
            health=$(smartctl -H "$device" 2>/dev/null | grep "SMART overall-health" || true)
            [[ -n "$health" ]] && echo "  $health" || echo "  Health status unavailable"
            echo ""
        done <<< "$scan_result"
    else
        echo "No devices found via smartctl scan"
        echo "WSL virtualization may hide devices."
    fi
    echo ""
}

check_alerts() {
    log_message "Checking for critical conditions..."
    echo "========== SYSTEM ALERTS =========="

    local alerts=0

    # Memory usage
    if command_exists free; then
        local mem_total mem_available mem_percent
        mem_total=$(free -b | awk '/Mem/ {print $2}')
        mem_available=$(free -b | awk '/Mem/ {print $7}')
        if [[ "${mem_total:-0}" -gt 0 ]]; then
            mem_percent=$((100 - (mem_available * 100) / mem_total))
            if [[ $mem_percent -gt 90 ]]; then
                echo "⚠️  CRITICAL: Memory usage at ${mem_percent}%"
                alerts=$((alerts + 1))
            elif [[ $mem_percent -gt 75 ]]; then
                echo "⚠️  WARNING: Memory usage at ${mem_percent}%"
                alerts=$((alerts + 1))
            fi
        fi
    fi

    # Root filesystem usage
    if command_exists df; then
        local root_usage
        root_usage=$(df --output=pcent / | tail -1 | tr -d '% ')
        if [[ -n "$root_usage" ]]; then
            if [[ $root_usage -gt 90 ]]; then
                echo "⚠️  CRITICAL: Root filesystem at ${root_usage}%"
                alerts=$((alerts + 1))
            elif [[ $root_usage -gt 80 ]]; then
                echo "⚠️  WARNING: Root filesystem at ${root_usage}%"
                alerts=$((alerts + 1))
            fi
        fi
    fi

    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load1 cores load_per_core
        load1=$(cut -d' ' -f1 /proc/loadavg)
        cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
        if command_exists bc; then
            load_per_core=$(echo "scale=2; $load1 / $cores" | bc 2>/dev/null || echo 0)
            if (( $(echo "$load_per_core > 1.5" | bc -l 2>/dev/null || echo 0) )); then
                echo "⚠️  CRITICAL: High load average: ${load1} (${load_per_core} per core)"
                alerts=$((alerts + 1))
            elif (( $(echo "$load_per_core > 1.0" | bc -l 2>/dev/null || echo 0) )); then
                echo "⚠️  WARNING: Elevated load average: ${load1} (${load_per_core} per core)"
                alerts=$((alerts + 1))
            fi
        else
            local load_int
            load_int=${load1%.*}; [[ -z "$load_int" ]] && load_int=0
            if (( load_int > (cores + cores/2) )); then
                echo "⚠️  CRITICAL: High load average: ${load1} (~per core calc, bc missing)"
                alerts=$((alerts + 1))
            elif (( load_int > cores )); then
                echo "⚠️  WARNING: Elevated load average: ${load1} (~per core calc, bc missing)"
                alerts=$((alerts + 1))
            fi
        fi
    fi

     # Network throughput and errors alerts (simple thresholds)
    # Alert if any interface exceeds 100 Mb/s RX or TX, or if errors increase
    # Network throughput and errors alerts (sysfs, simple thresholds)
    if [[ -d /sys/class/net ]]; then
    local interval="${CPU_SAMPLE_SECONDS:-1}"
    declare -A RX1 TX1 RXE1 TXE1
    local ifaces=()
    for d in /sys/class/net/*; do
        local iface; iface=$(basename "$d")
        [[ "$iface" == "lo" ]] && continue
        
        local state; state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo down)
        [[ "$state" != "up" ]] && continue
        
        ifaces+=("$iface")
        RX1["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX1["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)   # FIXED: added '='
        RXE1["$iface"]=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo 0)
        TXE1["$iface"]=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo 0)
    done
    sleep "$interval"
    for iface in "${ifaces[@]}"; do
        # Use defaults to avoid unbound variables with set -u
        local rx2 tx2 rxe2 txe2
        rx2=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx2=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        rxe2=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo 0)
        txe2=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo 0)
        local rx1="${RX1[$iface]:-0}" tx1="${TX1[$iface]:-0}" rxe1="${RXE1[$iface]:-0}" txe1="${TXE1[$iface]:-0}"
        local drx=$(( rx2 - rx1 ))
        local dtx=$(( tx2 - tx1 ))
        local rx_mbps tx_mbps
        rx_mbps=$(echo "scale=2; ($drx / $interval) * 8 / 1000000" | bc 2>/dev/null || echo "0")
        tx_mbps=$(echo "scale=2; ($dtx / $interval) * 8 / 1000000" | bc 2>/dev/null || echo "0")
        if (( $(echo "$rx_mbps > 100" | bc -l 2>/dev/null || echo 0) )); then
            echo "⚠️  WARNING: High RX throughput on $iface: ${rx_mbps} Mb/s"
            alerts=$((alerts + 1))
        fi
        if (( $(echo "$tx_mbps > 100" | bc -l 2>/dev/null || echo 0) )); then
            echo "⚠️  WARNING: High TX throughput on $iface: ${tx_mbps} Mb/s"
            alerts=$((alerts + 1))
        fi
        local drxerr=$(( rxe2 - rxe1 ))
        local dtxerr=$(( txe2 - txe1 ))
        if [[ $drxerr -gt 0 || $dtxerr -gt 0 ]]; then
            echo "⚠️  WARNING: Interface $iface errors increased (RX:+$drxerr TX:+$dtxerr)"
            alerts=$((alerts + 1))
        fi
    done
fi

    # Final summary
    if [[ $alerts -eq 0 ]]; then
        echo "✅ All systems normal"
    else
        echo "Total alerts: $alerts"
    fi
    echo ""

    ALERT_COUNT=$alerts
}

# --------------------------------------------
# HTML report
# --------------------------------------------
generate_html_report() {
    local report_file="$1"
    local html_file="${report_file%.txt}.html"
    log_message "Generating HTML report: $html_file"

    # Collect sections
    local cpu_output memory_output disk_output smart_output temp_output net_output gpu_output alerts_output
    cpu_output=$(get_cpu_info)
    memory_output=$(get_memory_info)
    disk_output=$(get_disk_info)
    smart_output=$(get_smart_status)
    temp_output=$(get_temperature_info)
    net_output=$(get_network_info)
    gpu_output=$(get_gpu_info)
    alerts_output=$(check_alerts)

    local csv_src
    csv_src="$(to_wsl_path "$WINDOWS_TEMPS_CSV")"
    [[ -z "$csv_src" ]] && csv_src="Not set"

    # Escape HTML special chars
    cpu_output=$(echo "$cpu_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    memory_output=$(echo "$memory_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    disk_output=$(echo "$disk_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    smart_output=$(echo "$smart_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    temp_output=$(echo "$temp_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    net_output=$(echo "$net_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    gpu_output=$(echo "$gpu_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    alerts_output=$(echo "$alerts_output" | sed 's/</\&lt;/g; s/>/\&gt;/g')

    # Ensure assets exist
    mkdir -p "${REPORT_DIR}/assets"
    [[ -f "style.css" && ! -f "${REPORT_DIR}/assets/style.css" ]] && cp "style.css" "${REPORT_DIR}/assets/style.css"
    [[ -f "report.js" && ! -f "${REPORT_DIR}/assets/report.js" ]] && cp "report.js" "${REPORT_DIR}/assets/report.js"

    # Cyberpunk Neon CSS
    cat > "${REPORT_DIR}/assets/style.css" <<'CSS'
body {
    background: #000000;
    color: #00FFFF;
    font-family: 'Courier New', monospace;
    margin: 0;
    padding: 0;
}
.container { max-width: 1200px; margin: 20px auto; padding: 20px; }
.header {
    background: #111;
    border: 2px solid #00FFFF;
    box-shadow: 0 0 20px #00FFFF;
    padding: 15px;
    margin-bottom: 30px;
    text-align: center;
}
.title {
    font-size: 2.2em;
    color: #FF00FF;
    text-shadow: 0 0 15px #FF00FF, 0 0 30px #FF00FF;
    animation: glitch 3s infinite;
    letter-spacing: 3px;
}
.controls { margin: 15px 0; display: flex; justify-content: center; gap: 15px; flex-wrap: wrap; }
.btn {
    background: #000;
    color: #FFFF00;
    border: 2px solid #00FFFF;
    padding: 10px 20px;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
    box-shadow: 0 0 10px #00FFFF;
    text-decoration: none;
    display: inline-block;
}
.btn:hover { background: #00FFFF; color: #000; box-shadow: 0 0 20px #00FFFF; }
.stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 10px;
    margin: 20px 0;
    color: #00FF41;
}
.stat {
    background: #111;
    border: 1px solid #00FFFF;
    padding: 12px;
    border-radius: 8px;
    text-align: center;
    box-shadow: 0 0 10px #00FFFF30;
}

/* Tabs */
.tab {
    overflow: hidden;
    border: 2px solid #00FFFF;
    background: #111;
    margin-bottom: 20px;
    box-shadow: 0 0 15px #00FFFF;
}
.tab button {
    background: #000;
    color: #FFFF00;
    float: left;
    border: none;
    outline: none;
    cursor: pointer;
    padding: 14px 20px;
    font-size: 1.1em;
    font-weight: bold;
}
.tab button:hover { background: #FF00FF; color: #000; }
.tab button.active { background: #00FFFF; color: #000; }

/* Tab content */
.tabcontent {
    display: none;
    padding: 30px;
    background: #111;
    border: 2px solid #00FFFF;
    border-top: none;
    min-height: 400px;
}
.tabcontent h2 {
    color: #FF00FF;
    text-shadow: 0 0 10px #FF00FF;
    margin-top: 0;
}
pre {
    background: #000;
    color: #00FF41;
    padding: 20px;
    border: 1px solid #00FFFF;
    border-radius: 8px;
    overflow-x: auto;
    box-shadow: inset 0 0 15px #00FFFF30;
    font-size: 0.95em;
}
.footer {
    margin: 50px 0 30px;
    text-align: center;
    color: #FF0055;
    font-size: 1em;
}
.qr {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 12px 16px;
    justify-content: center;
}
.qr img {
    border: 2px solid #00FFFF;
    border-radius: 8px;
    background: #000;
    box-shadow: 0 0 15px #00FFFF;
}
.qr-info {
    color: #00FF41;
}
.qr-info strong {
    color: #FFFF00;
}
.qr-info a {
    color: #FF00FF;
    text-decoration: none;
    font-weight: bold;
}
.qr-info a:hover {
    text-shadow: 0 0 10px #FF00FF;
}

/* Glitch animation */
@keyframes glitch {
    0% { text-shadow: 0 0 10px #FF00FF; }
    20% { text-shadow: 5px 0 15px #00FFFF, -5px 0 15px #FF0055; }
    40% { text-shadow: -5px 0 20px #FFFF00, 5px 0 20px #00FF41; }
    100% { text-shadow: 0 0 10px #FF00FF; }
}
CSS

    # Cyberpunk Neon JavaScript with Tab Functionality
    cat > "${REPORT_DIR}/assets/report.js" <<'JS'
(function(){
  // Tab switching logic
  const tabs = document.querySelectorAll('.tablinks');
  const contents = document.querySelectorAll('.tabcontent');
  
  function openTab(tabName) {
    contents.forEach(c => c.style.display = 'none');
    tabs.forEach(t => t.classList.remove('active'));
    
    const target = document.getElementById(tabName);
    if (target) {
      target.style.display = 'block';
      const btn = document.querySelector(`[data-tab="${tabName}"]`);
      if (btn) btn.classList.add('active');
    }
  }
  
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const tabName = tab.getAttribute('data-tab');
      openTab(tabName);
    });
  });
  
  // Open first tab by default
  if (tabs.length > 0) {
    openTab(tabs[0].getAttribute('data-tab'));
  }
})();
JS

    cat > "$html_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>CYBERKONSOLE v2077 // SYSTEM MONITOR</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="assets/style.css">
</head>
<body>
    <div class="header">
        <div class="title">⚡ SYSTEM MONITORING REPORT ⚡</div>
        <div class="stats">
            <div class="stat"><strong>SYSTEM:</strong> $(uname -srmo)</div>
            <div class="stat"><strong>HOST:</strong> $(hostname)</div>
            <div class="stat"><strong>UPTIME:</strong> $(uptime -p 2>/dev/null || echo "N/A")</div>
            <div class="stat"><strong>GENERATED:</strong> $(date "+%Y-%m-%d %H:%M:%S")</div>
            <div class="stat"><strong>TEMP CSV:</strong> ${csv_src}</div>
        </div>
        <div class="controls">
            <a class="btn" href="index.html">📊 REPORT INDEX</a>
        </div>
    </div>

    <div class="container">
        <!-- Tabs -->
        <div class="tab">
            <button class="tablinks" data-tab="QR">📱 QR & PDF</button>
            <button class="tablinks" data-tab="CPU">🔥 CPU</button>
            <button class="tablinks" data-tab="Memory">💾 MEMORY</button>
            <button class="tablinks" data-tab="Disk">💿 DISK</button>
            <button class="tablinks" data-tab="SMART">🔍 SMART</button>
            <button class="tablinks" data-tab="Temp">🌡️ TEMPERATURE</button>
            <button class="tablinks" data-tab="Network">🌐 NETWORK</button>
            <button class="tablinks" data-tab="GPU">🎮 GPU</button>
            <button class="tablinks" data-tab="Alerts">⚠️ ALERTS</button>
        </div>

        <div id="QR" class="tabcontent">
            <h2>📱 QR CODE & PDF DOWNLOAD // MOBILE ACCESS</h2>
            <div class="qr">
                <div class="qr-info">
                    <p><strong>PDF REPORT:</strong> <span id="pdfLinkText">(generating...)</span></p>
                    <p style="color: #00FFFF;">💡 Scan the QR code from your phone to open the PDF report</p>
                </div>
                <img id="qrImage" src="" alt="QR code" width="200" height="200" />
            </div>
        </div>

        <div id="CPU" class="tabcontent">
            <h2>🔥 CPU INFORMATION // NEURAL CORE</h2>
            <pre>${cpu_output}</pre>
        </div>

        <div id="Memory" class="tabcontent">
            <h2>💾 MEMORY GRID // RAM MATRIX</h2>
            <pre>${memory_output}</pre>
        </div>

        <div id="Disk" class="tabcontent">
            <h2>💿 STORAGE GRID // DISK DRIVES</h2>
            <pre>${disk_output}</pre>
        </div>

        <div id="SMART" class="tabcontent">
            <h2>🔍 SMART STATUS // HEALTH SCAN</h2>
            <pre>${smart_output}</pre>
        </div>

        <div id="Temp" class="tabcontent">
            <h2>🌡️ TEMPERATURE SENSORS // HEAT MAP</h2>
            <pre>${temp_output}</pre>
        </div>

        <div id="Network" class="tabcontent">
            <h2>🌐 NETWORK INTERFACES // DATA STREAM</h2>
            <pre>${net_output}</pre>
        </div>

        <div id="GPU" class="tabcontent">
            <h2>🎮 GPU ACCELERATOR // GRAPHICS CORE</h2>
            <pre>${gpu_output}</pre>
        </div>

        <div id="Alerts" class="tabcontent">
            <h2>⚠️ SYSTEM ALERTS // CRITICAL WARNINGS</h2>
            <pre>${alerts_output}</pre>
        </div>

        <div class="footer">
            <p>Report generated by <strong>CYBERKONSOLE v2077</strong> 🚀</p>
            <p>Arab Academy for Science, Technology & Maritime Transport</p>
        </div>
    </div>

    <script src="assets/report.js"></script>
</body>
</html>
EOF

    # Generate PDF (wkhtmltopdf) and QR (qrencode)
    local pdf_file="${html_file%.html}.pdf"
    local pdf_url="" qr_file=""

    if [[ "$ENABLE_PDF" == "true" ]] && command_exists wkhtmltopdf; then
        wkhtmltopdf "$html_file" "$pdf_file" >/dev/null 2>&1 || true
        if [[ -f "$pdf_file" ]]; then
            log_message "PDF generated: $pdf_file"
        else
            log_message "PDF generation failed for $html_file"
        fi
    fi

    # Construct the external URL to the PDF for QR
    if [[ -n "$REPORT_BASE_URL" && -f "$pdf_file" ]]; then
        local pdf_name; pdf_name=$(basename "$pdf_file")
        pdf_url="${REPORT_BASE_URL%/}/${pdf_name}"
        qr_file="${REPORT_DIR}/assets/qr_${pdf_name%.pdf}.png"
    fi

    if [[ "$ENABLE_QR" == "true" && -n "$pdf_url" ]] && command_exists qrencode; then
        qrencode -o "$qr_file" -s 6 -m 2 "$pdf_url" >/dev/null 2>&1 || true
        [[ -f "$qr_file" ]] && log_message "QR generated: $qr_file"
    fi

    # Patch the HTML to show the PDF link and QR image if available
    if [[ -f "$html_file" ]]; then
        local qr_rel=""
        [[ -n "$qr_file" && -f "$qr_file" ]] && qr_rel="assets/$(basename "$qr_file")"

        # Inject link and image by replacing placeholder text
        # Update the "Download & QR" card content
        if [[ -n "$pdf_url" ]]; then
            sed -i "s|(generating...)|<a href=\"${pdf_url}\" target=\"_blank\">${pdf_url}</a>|" "$html_file"
        else
            sed -i "s|(generating...)|PDF URL not available. Set REPORT_BASE_URL.|" "$html_file"
        fi
        if [[ -n "$qr_rel" ]]; then
            sed -i "s|src=\"\"|src=\"${qr_rel}\"|" "$html_file"
        else
            sed -i "s|<img id=\"qrImage\"[^>]*>|<p class=\"muted\">QR not available.</p>|" "$html_file"
        fi
    fi

    echo "✅ HTML report generated: $html_file"
}


generate_reports_index() {
    local index_file="$REPORT_DIR/index.html"
    log_message "Updating cyberpunk report index: $index_file"

    {
        cat <<'HEAD'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CYBERKONSOLE v2077 // REPORT INDEX</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            background: #000000;
            color: #00FFFF;
            font-family: 'Courier New', monospace;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            padding: 20px;
            border: 2px solid #00FFFF;
            box-shadow: 0 0 30px #00FFFF;
            background: #111;
        }
        h1 {
            text-align: center;
            font-size: 2.5em;
            color: #FF00FF;
            text-shadow: 0 0 15px #FF00FF, 0 0 30px #FF00FF;
            animation: glitch 3s infinite;
            letter-spacing: 4px;
            margin-bottom: 10px;
        }
        .subtitle {
            text-align: center;
            color: #00FF41;
            font-size: 1.2em;
            margin-bottom: 40px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th {
            background: #00FFFF;
            color: #000;
            padding: 15px;
            text-align: left;
            font-weight: bold;
            font-size: 1.1em;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #00FFFF;
        }
        tr:hover {
            background: #222;
            box-shadow: 0 0 15px #FF00FF30;
        }
        a {
            color: #FFFF00;
            text-decoration: none;
            font-weight: bold;
        }
        a:hover {
            color: #FF00FF;
            text-shadow: 0 0 10px #FF00FF;
        }
        .footer {
            margin-top: 50px;
            text-align: center;
            color: #FF0055;
            font-size: 1em;
        }
        .updated {
            text-align: center;
            color: #00FF41;
            margin-top: 30px;
            font-size: 1.1em;
        }

        @keyframes glitch {
            0% { text-shadow: 0 0 10px #FF00FF; }
            20% { text-shadow: 5px 0 15px #00FFFF, -5px 0 15px #FF0055; }
            40% { text-shadow: -5px 0 20px #FFFF00, 5px 0 20px #00FF41; }
            100% { text-shadow: 0 0 10px #FF00FF; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ NEON GRID ONLINE // REPORT INDEX ⚡</h1>
        <p class="subtitle">All System Reports // Night City Archives</p>

        <table>
            <thead>
                <tr>
                    <th>TIMESTAMP</th>
                    <th>TEXT REPORT</th>
                    <th>HTML REPORT</th>
                </tr>
            </thead>
            <tbody>
HEAD

        # Generate rows for each report
        for f in "$REPORT_DIR"/system_report_*.txt; do
            [[ -f "$f" ]] || continue
            ts=$(echo "$f" | sed -E 's/.*system_report_([0-9]{8}_[0-9]{6}).txt/\1/' | tr '_' ' ')
            txt_name=$(basename "$f")
            html="${f%.txt}.html"
            html_name=$(basename "$html")

            printf '<tr><td>%s</td><td><a href="%s">%s</a></td><td>' "$ts" "$txt_name" "$txt_name"
            if [[ -f "$html" ]]; then
                printf '<a href="%s">%s</a>' "$html_name" "$html_name"
            else
                printf '<span style="color:#FF0055;">(generating...)</span>'
            fi
            printf '</td></tr>\n'
        done

        cat <<'FOOT'
            </tbody>
        </table>

        <p class="updated">Index updated: 
FOOT
        date '+%Y-%m-%d %H:%M:%S'
        cat <<'FOOT'
</p>

        <div class="footer">
            <p><strong>CYBERKONSOLE v2077</strong> 🚀 // System Monitoring Tool</p>
            <p>Arab Academy for Science, Technology & Maritime Transport</p>
        </div>
    </div>
</body>
</html>
FOOT
    } > "$index_file"

    echo "✅ CYBERPUNK report index updated: $index_file"
}

# --------------------------------------------
# Main execution
# --------------------------------------------
run_once() {
    local ts mode_tag=""
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    [[ "$BRIEF_MODE" == "true" ]] && mode_tag="_brief"
    local REPORT_FILE="$REPORT_DIR/system_report_$(date +%Y%m%d_%H%M%S)${mode_tag}.txt"
    : > "$REPORT_FILE"

    log_message "Starting system monitoring..."

    {
        echo "System Monitoring Report${BRIEF_MODE:+ (Brief Mode)}"
        echo "Generated: $ts"
        echo "System: $(uname -srmo)"
        echo "Hostname: $(hostname)"
        echo "Uptime: $(uptime -p 2>/dev/null || echo 'Not available')"
        echo "======================================"
        echo ""

        local summary_cpu summary_load summary_mem summary_root
        summary_cpu=$(cpu_usage_percent)
        summary_load=$(uptime | awk -F'load average:' '{gsub(/^ +/, "", $2); print $2}')
        summary_mem=$(free -h | awk '/Mem:/ {print $3" used / "$2" total"}')
        summary_root=$(df --output=pcent / | tail -1 | tr -d ' %')
        echo "Summary: CPU ${summary_cpu}% (sample ${CPU_SAMPLE_SECONDS}s), Mem ${summary_mem:-N/A}, Root ${summary_root:-N/A}%, Load ${summary_load:-N/A}"
        echo ""

        if [[ "$BRIEF_MODE" == "true" ]]; then
            get_cpu_info
            get_memory_info
            get_disk_info
            check_alerts
            echo "Alert count: $ALERT_COUNT"
        else
            get_cpu_info
            get_memory_info
            get_disk_info
            get_smart_status
            get_temperature_info
            get_network_info
            get_gpu_info
            check_alerts
            echo "Alert count: $ALERT_COUNT"
        fi

        echo "======================================"
        echo "Report saved to: $REPORT_FILE"
    } | tee "$REPORT_FILE"

    log_message "Monitoring complete. Report saved to $REPORT_FILE"

    if [[ "$GENERATE_HTML" == "true" ]]; then
        generate_html_report "$REPORT_FILE"
    fi

    generate_reports_index

    return "$ALERT_COUNT"
}

run_loop() {
    local interval="$1"
    log_message "Entering loop mode (interval=${interval}s)"
    while true; do
        if ! run_once; then
            error "run_once encountered an error"
        fi
        local exit_code=$?
        log_message "Run completed with alert count: $exit_code"
        sleep "$interval"
    done
}

trap 'error "Script interrupted"; exit 130' INT TERM
trap 'error "An unexpected error occurred"; exit 1' ERR

parse_args "$@"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$RUN_INTERVAL_SECONDS" -gt 0 ]]; then
        run_loop "$RUN_INTERVAL_SECONDS"
        exit 0
    else
        run_once
        exit "$ALERT_COUNT"
    fi
fi