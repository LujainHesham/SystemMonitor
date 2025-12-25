#!/bin/bash

# Zenity Dashboard – With One-Time Intro Splash

SCRIPT_DIR="$(dirname "$0")"

# Force dark/black backgrounds for all dialogs
export GTK_THEME=Adwaita:dark

# Neon Colors
NEON_CYAN="#00FFFF"
NEON_MAGENTA="#FF00FF"
NEON_PINK="#FF0055"
NEON_GREEN="#00FF41"
NEON_YELLOW="#FFFF00"

GLITCH_TEXT="OS Project // ACCESSING SYSTEM CORE"
EXIT_LABEL="Exit"

# One-time intro splash screen
show_intro() {
    zenity --info --title="Zenity Dashboard" --width=700 --height=180 \
        --text="<big><b><span foreground='$NEON_CYAN'>$GLITCH_TEXT</span></b></big>\n\n<span foreground='$NEON_MAGENTA'>$(date '+%Y.%m.%d %H:%M:%S') // UPTIME: $(uptime -p | sed 's/up //')</span>" \
        --ok-label="ENTER THE GRID"
}

# View latest report
view_latest_report() {
    # Find the latest system_report_*.html (exclude index.html)
    LATEST_HTML=$(ls -t "$SCRIPT_DIR/../reports"/system_report_*.html 2>/dev/null | head -n 1)

    if [ -z "$LATEST_HTML" ]; then
        zenity --error --title="ERROR 404" \
            --text="<b><span foreground='$NEON_PINK'>NO REPORTS FOUND IN /reports/</span></b>" \
            --ok-label="Back"
        return
    fi

    # Optional: Show a quick header or confirmation
    # show_intro  # Remove or comment if you don't want splash here

    if grep -qi microsoft /proc/version; then
        explorer.exe "$(wslpath -w "$LATEST_HTML")"
    else
        xdg-open "$LATEST_HTML"
    fi
}

# Live system stats
show_system_stats() {
    STATS=$(top -bn1 | head -n 5 | sed 's/^/    /')
    MEM=$(free -h | awk '/Mem:/ {print "    Used: "$3" / Total: "$2"  (Free: "$4")"}')
    NET=$(ip -br a | sed 's/^/    /')

    zenity --info --title="LIVE SYSTEM METRICS" --width=800 --height=650 \
        --text="<b><span foreground='$NEON_GREEN'>CPU / LOAD / PROCESSES</span></b>\n<span foreground='$NEON_CYAN'>$STATS</span>\n\n<b><span foreground='$NEON_YELLOW'>MEMORY GRID</span></b>\n<span foreground='$NEON_GREEN'>$MEM</span>\n\n<b><span foreground='$NEON_MAGENTA'>NETWORK INTERFACES</span></b>\n<span foreground='$NEON_CYAN'>$NET</span>" \
        --ok-label="Back to Menu"
}

# Disk usage
show_disk_usage() {
    DISK=$(df -h --output=source,size,used,avail,pcent,target | grep -v tmpfs | sed 's/^/    /')

    zenity --info --title="STORAGE GRID" --width=750 --height=550 \
        --text="<b><span foreground='$NEON_PINK'>DISK SPACE STATUS</span></b>\n\n<span foreground='$NEON_YELLOW'>$DISK</span>\n\n<span foreground='$NEON_CYAN'>CRITICAL: >90% = EVACUATE DATA</span>" \
        --ok-label="Back to Menu"
}

# === MAIN PROGRAM ===
# Show intro only once
show_intro

# Main menu loop (no intro inside)
while true; do
    CHOICE=$(zenity --list --title="Zenity Dashboard" --width=600 --height=500 \
        --text="<big><b><span foreground='$NEON_CYAN'>SYSTEM DASHBOARD</span></b></big>\n<span foreground='$NEON_MAGENTA'>Select an option:</span>" \
        --column="ID" --column="ACTION" --hide-column=1 \
        "1" "View Latest Report (HTML)" \
        "2" "Live CPU / Memory / Network Stats" \
        "3" "Disk Usage Summary" \
        "4" "View Report Index" \
        --ok-label="Select" --cancel-label="Exit")

    # If user cancels or closes the menu
    [ $? -ne 0 ] && exit 0
    case "$CHOICE" in
         "1") view_latest_report ;;
         "2") show_system_stats ;;
         "3") show_disk_usage ;;
         "4") 
        INDEX_PATH="$SCRIPT_DIR/../reports/index.html"
        if [ -f "$INDEX_PATH" ]; then
            if grep -qi microsoft /proc/version; then
                explorer.exe "$(wslpath -w "$INDEX_PATH")"
            else
                xdg-open "$INDEX_PATH"
            fi
        else
            zenity --error --title="ERROR" \
                --text="<b><span foreground='$NEON_PINK'>Report Index not found!</span></b>\nGenerate a report first." \
                --ok-label="Back"
        fi
        ;;
         "5")
            zenity --question --title="Exit Dashboard" \
            --text="<b><span foreground='$NEON_PINK'>Are you sure you want to exit?</span></b>" \
            --ok-label="$EXIT_LABEL" --cancel-label="Cancel"
            [ $? -eq 0 ] && exit 0
            ;;
         *) exit 0 ;;
    esac
done
