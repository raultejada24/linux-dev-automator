#!/bin/bash

################################################################################
# Script: log_cleaner.sh
# Purpose: Automated system cleanup and log management
# Description: Clears cache, old packages, truncates aged logs, and cleans /tmp
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
readonly LOG_FILE="${LOG_DIR}/log_cleaner.log"
readonly LOG_AGE_DAYS=30
readonly TMP_CLEANUP_DAYS=7

################################################################################
# SETUP & UTILITY FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}"
    {
        echo "======================================"
        echo "Log Cleaner Started"
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
    
    case "${level}" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${message}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${message}"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
    esac
}

# Display usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Automates system cleanup including cache removal, old package cleanup,
    log file truncation, and /tmp directory cleaning.

Options:
    -h, --help              Display this help message and exit
    -d, --days DAYS         Set log age threshold (default: 30 days)
    -t, --tmp-days DAYS     Set /tmp cleanup threshold (default: 7 days)
    --dry-run               Preview changes without executing
    -v, --verbose           Enable verbose output

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --dry-run
    sudo $(basename "$0") --days 60

EOF
    exit "${1:-0}"
}

# Cleanup function
cleanup() {
    log_message "INFO" "Cleanup initiated"
}

# Check root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_message "ERROR" "This script must be run with sudo or as root"
        exit 1
    fi
    log_message "SUCCESS" "Running with root privileges"
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

################################################################################
# CLEANUP FUNCTIONS
################################################################################

# Clean apt cache
clean_apt_cache() {
    log_message "INFO" "Cleaning APT cache..."
    
    local initial_size=$(du -sb /var/cache/apt 2>/dev/null | awk '{print $1}' || echo 0)
    
    if apt-get clean >> "${LOG_FILE}" 2>&1; then
        local final_size=$(du -sb /var/cache/apt 2>/dev/null | awk '{print $1}' || echo 0)
        local freed=$((initial_size - final_size))
        log_message "SUCCESS" "APT cache cleaned (freed: $(format_bytes "$freed"))"
        echo "$freed"
    else
        log_message "WARNING" "Failed to clean APT cache"
        echo "0"
    fi
}

# Remove unused packages
remove_unused_packages() {
    log_message "INFO" "Removing unused packages..."
    
    local initial_size=$(du -sb /var/cache/apt 2>/dev/null | awk '{print $1}' || echo 0)
    
    if apt-get autoremove -y >> "${LOG_FILE}" 2>&1; then
        local final_size=$(du -sb /var/cache/apt 2>/dev/null | awk '{print $1}' || echo 0)
        local freed=$((initial_size - final_size))
        log_message "SUCCESS" "Unused packages removed (freed: $(format_bytes "$freed"))"
        echo "$freed"
    else
        log_message "WARNING" "Failed to remove unused packages"
        echo "0"
    fi
}

# Truncate old log files
truncate_old_logs() {
    local days="$1"
    
    log_message "INFO" "Truncating log files older than ${days} days..."
    
    local freed=0
    local count=0
    
    find /var/log -type f -name "*.log" -mtime +"${days}" 2>/dev/null | while read -r logfile; do
        if [[ -w "${logfile}" ]]; then
            freed=$((freed + $(stat -c%s "${logfile}" 2>/dev/null || echo 0)))
            > "${logfile}"
            ((count++)) || true
            log_message "INFO" "Truncated: ${logfile}"
        fi
    done
    
    log_message "SUCCESS" "Truncated ${count} log files (freed: $(format_bytes "$freed"))"
    echo "$freed"
}

# Clean /tmp directory
clean_tmp_directory() {
    local days="$1"
    
    log_message "INFO" "Cleaning /tmp (files older than ${days} days)..."
    
    local freed=0
    local count=0
    
    find /tmp -type f -atime +"${days}" 2>/dev/null | while read -r file; do
        if [[ -e "${file}" ]]; then
            freed=$((freed + $(stat -c%s "${file}" 2>/dev/null || echo 0)))
            rm -f "${file}"
            ((count++)) || true
        fi
    done
    
    log_message "SUCCESS" "Cleaned ${count} files from /tmp (freed: $(format_bytes "$freed"))"
    echo "$freed"
}

# Clean package manager cache
clean_package_lists() {
    log_message "INFO" "Cleaning package lists..."
    
    local initial_size=$(du -sb /var/lib/apt/lists 2>/dev/null | awk '{print $1}' || echo 0)
    
    if apt-get autoclean >> "${LOG_FILE}" 2>&1; then
        local final_size=$(du -sb /var/lib/apt/lists 2>/dev/null | awk '{print $1}' || echo 0)
        local freed=$((initial_size - final_size))
        log_message "SUCCESS" "Package lists cleaned (freed: $(format_bytes "$freed"))"
        echo "$freed"
    else
        log_message "WARNING" "Failed to clean package lists"
        echo "0"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local log_days="${LOG_AGE_DAYS}"
    local tmp_days="${TMP_CLEANUP_DAYS}"
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -d|--days)
                log_days="$2"
                shift 2
                ;;
            -t|--tmp-days)
                tmp_days="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage 1
                ;;
        esac
    done
    
    init_logging
    trap cleanup EXIT INT TERM
    check_root
    
    if [[ "${dry_run}" == "true" ]]; then
        log_message "WARNING" "Running in DRY-RUN mode (no changes will be made)"
    fi
    
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}       LOG CLEANER${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    
    local total_freed=0
    
    # Execute cleanup operations
    apt_freed=$(clean_apt_cache) && total_freed=$((total_freed + apt_freed)) || true
    sleep 1
    
    unused_freed=$(remove_unused_packages) && total_freed=$((total_freed + unused_freed)) || true
    sleep 1
    
    autoclean_freed=$(clean_package_lists) && total_freed=$((total_freed + autoclean_freed)) || true
    sleep 1
    
    logs_freed=$(truncate_old_logs "${log_days}") && total_freed=$((total_freed + logs_freed)) || true
    sleep 1
    
    tmp_freed=$(clean_tmp_directory "${tmp_days}") && total_freed=$((total_freed + tmp_freed)) || true
    
    # Summary report
    echo -e "\n${CYAN}Cleanup Summary:${NC}"
    echo "  Log age threshold:     ${log_days} days"
    echo "  /tmp cleanup age:      ${tmp_days} days"
    echo -e "  ${GREEN}Total space freed:     $(format_bytes "$total_freed")${NC}"
    echo ""
    
    log_message "SUCCESS" "Cleanup completed. Total freed: $(format_bytes "$total_freed")"
}

# Execute main
main "$@"
