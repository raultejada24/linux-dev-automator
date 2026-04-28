#!/bin/bash

################################################################################
# Script: system_monitor.sh
# Purpose: Real-time system resource monitoring
# Description: Monitors CPU load, memory usage, disk space, and active network
#              connections with color-coded warnings
# Author: DevOps Engineering Team
# Version: 1.0
################################################################################

set -e
set -u

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/../logs"
readonly LOG_FILE="${LOG_DIR}/system_monitor.log"
readonly DISK_WARNING_THRESHOLD=80
readonly MEMORY_WARNING_THRESHOLD=80
readonly CPU_WARNING_THRESHOLD=80

# Default refresh interval
REFRESH_INTERVAL=5

################################################################################
# SETUP & UTILITY FUNCTIONS
################################################################################

# Initialize logging directory
init_logging() {
    mkdir -p "${LOG_DIR}"
    {
        echo "======================================"
        echo "System Monitor Started"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================"
    } >> "${LOG_FILE}"
}

# Logging function
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Monitors system resources including CPU, memory, disk space, and network
    connections in real-time.

Options:
    -h, --help              Display this help message and exit
    -i, --interval SECONDS  Set refresh interval (default: 5 seconds)
    -o, --once              Run monitoring once and exit
    -c, --cpu-only          Monitor CPU load only
    -m, --memory-only       Monitor memory usage only
    -d, --disk-only         Monitor disk space only
    -n, --network-only      Monitor network connections only

Examples:
    $(basename "$0")
    $(basename "$0") --interval 10
    $(basename "$0") --once
    $(basename "$0") --disk-only

EOF
    exit "${1:-0}"
}

# Cleanup function for trap
cleanup() {
    echo -e "\n${YELLOW}[INTERRUPT]${NC} Monitoring stopped"
    log_message "INFO" "Monitoring stopped (signal: $?)"
    exit 0
}

# Clear screen and print header
print_header() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       SYSTEM RESOURCE MONITOR${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')\n"
}

# Format percentage with color
format_percentage() {
    local value="$1"
    local threshold="${2:-80}"
    
    if (( $(echo "$value >= $threshold" | bc -l) )); then
        echo -e "${RED}${value}%${NC}"
    elif (( $(echo "$value >= $((threshold - 20))" | bc -l) )); then
        echo -e "${YELLOW}${value}%${NC}"
    else
        echo -e "${GREEN}${value}%${NC}"
    fi
}

################################################################################
# MONITORING FUNCTIONS
################################################################################

# Monitor CPU load
monitor_cpu() {
    echo -e "${BLUE}[CPU LOAD]${NC}"
    
    local load_avg=($(cat /proc/loadavg | awk '{print $1, $2, $3}'))
    local cpu_count=$(nproc)
    
    # Get current CPU usage percentage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    echo "  1-min load:    ${load_avg[0]} (CPUs: ${cpu_count})"
    echo "  5-min load:    ${load_avg[1]}"
    echo "  15-min load:   ${load_avg[2]}"
    echo "  Current usage: $(format_percentage "${cpu_usage%.*}" "$CPU_WARNING_THRESHOLD")"
    echo ""
    
    log_message "INFO" "CPU Usage: ${cpu_usage}%, Load: ${load_avg[0]}"
}

# Monitor memory usage
monitor_memory() {
    echo -e "${BLUE}[MEMORY USAGE]${NC}"
    
    local mem_info=$(free -h | grep Mem)
    local total=$(echo "$mem_info" | awk '{print $2}')
    local used=$(echo "$mem_info" | awk '{print $3}')
    local available=$(echo "$mem_info" | awk '{print $7}')
    
    # Calculate percentage
    local mem_bytes=$(free -b | grep Mem | awk '{print $2}')
    local used_bytes=$(free -b | grep Mem | awk '{print $3}')
    local mem_percentage=$(echo "scale=1; ($used_bytes / $mem_bytes) * 100" | bc -l)
    
    echo "  Total:        ${total}"
    echo "  Used:         ${used}"
    echo "  Available:    ${available}"
    echo "  Usage:        $(format_percentage "${mem_percentage%.*}" "$MEMORY_WARNING_THRESHOLD")"
    echo ""
    
    log_message "INFO" "Memory Usage: ${mem_percentage}% (${used}/${total})"
}

# Monitor disk space
monitor_disk() {
    echo -e "${BLUE}[DISK SPACE]${NC}"
    
    df -h | grep -vE '^Filesystem|tmpfs|cdrom' | while read line; do
        local filesystem=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local available=$(echo "$line" | awk '{print $4}')
        local percent=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')
        
        # Color code the percentage
        local colored_percent=$(format_percentage "$percent" "$DISK_WARNING_THRESHOLD")
        
        printf "  %-20s %8s / %-8s [${colored_percent}] %s\n" "$filesystem" "$used" "$size" "$mount"
        
        log_message "INFO" "Disk: $filesystem - Usage: ${percent}%"
    done
    
    echo ""
}

# Monitor network connections
monitor_network() {
    echo -e "${BLUE}[ACTIVE NETWORK CONNECTIONS]${NC}"
    
    local connection_count=$(netstat -tuln 2>/dev/null | grep ESTABLISHED | wc -l)
    local listening_count=$(netstat -tuln 2>/dev/null | grep LISTEN | wc -l)
    
    echo "  Established connections: ${connection_count}"
    echo "  Listening ports:         ${listening_count}"
    echo ""
    
    echo "  Top connections:"
    netstat -tuln 2>/dev/null | grep ESTABLISHED | head -n 5 | awk '{print "    " $4 " -> " $5}' || echo "    (no established connections)"
    
    echo ""
    
    log_message "INFO" "Network: $connection_count established, $listening_count listening"
}

################################################################################
# DISPLAY & MAIN FUNCTIONS
################################################################################

# Display all monitoring info
display_monitor() {
    print_header
    monitor_cpu
    monitor_memory
    monitor_disk
    monitor_network
}

# Continuous monitoring
continuous_monitoring() {
    while true; do
        display_monitor
        echo -e "${YELLOW}(Refreshing in ${REFRESH_INTERVAL}s - Press Ctrl+C to exit)${NC}"
        sleep "${REFRESH_INTERVAL}"
    done
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local run_once=false
    local monitor_cpu_flag=true
    local monitor_memory_flag=true
    local monitor_disk_flag=true
    local monitor_network_flag=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -i|--interval)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            -o|--once)
                run_once=true
                shift
                ;;
            -c|--cpu-only)
                monitor_memory_flag=false
                monitor_disk_flag=false
                monitor_network_flag=false
                shift
                ;;
            -m|--memory-only)
                monitor_cpu_flag=false
                monitor_disk_flag=false
                monitor_network_flag=false
                shift
                ;;
            -d|--disk-only)
                monitor_cpu_flag=false
                monitor_memory_flag=false
                monitor_network_flag=false
                shift
                ;;
            -n|--network-only)
                monitor_cpu_flag=false
                monitor_memory_flag=false
                monitor_disk_flag=false
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage 1
                ;;
        esac
    done
    
    init_logging
    
    # Set trap for cleanup
    trap cleanup EXIT INT TERM
    
    # Override display functions based on flags
    if [[ "${monitor_cpu_flag}" != "true" ]]; then
        monitor_cpu() { :; }
    fi
    if [[ "${monitor_memory_flag}" != "true" ]]; then
        monitor_memory() { :; }
    fi
    if [[ "${monitor_disk_flag}" != "true" ]]; then
        monitor_disk() { :; }
    fi
    if [[ "${monitor_network_flag}" != "true" ]]; then
        monitor_network() { :; }
    fi
    
    if [[ "${run_once}" == "true" ]]; then
        display_monitor
    else
        continuous_monitoring
    fi
}

# Execute main function
main "$@"
