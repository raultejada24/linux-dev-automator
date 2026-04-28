#!/bin/bash

################################################################################
# Script: security_audit.sh
# Purpose: System security audit and vulnerability assessment
# Description: Checks firewall status, open ports, failed SSH attempts, 
#              and identifies world-writable files
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
readonly LOG_FILE="${LOG_DIR}/security_audit.log"
readonly SENSITIVE_DIRS=("/etc" "/root" "/home" "/var")

################################################################################
# SETUP & UTILITY FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}"
    {
        echo "======================================"
        echo "Security Audit Started"
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
    Performs comprehensive security audit including firewall checks, open ports,
    failed SSH attempts, and world-writable file detection.

Options:
    -h, --help              Display this help message and exit
    -f, --firewall-only     Check firewall status only
    -p, --ports-only        Check open ports only
    -s, --ssh-only          Check failed SSH attempts only
    -w, --world-writable    Check world-writable files only
    -v, --verbose           Enable verbose output

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --firewall-only
    sudo $(basename "$0") --ssh-only

EOF
    exit "${1:-0}"
}

# Cleanup function
cleanup() {
    log_message "INFO" "Audit completed"
}

# Check root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_message "ERROR" "This script must be run with sudo or as root"
        exit 1
    fi
    log_message "SUCCESS" "Running with root privileges"
}

################################################################################
# AUDIT FUNCTIONS
################################################################################

# Check UFW firewall status
check_firewall() {
    echo -e "\n${BLUE}[FIREWALL STATUS]${NC}"
    
    if ! command -v ufw &> /dev/null; then
        log_message "WARNING" "UFW not installed"
        echo -e "  ${YELLOW}UFW not installed${NC}"
        return
    fi
    
    local ufw_status=$(ufw status 2>/dev/null || echo "inactive")
    
    if [[ "${ufw_status}" == "Status: active" ]]; then
        echo -e "  ${GREEN}UFW is ACTIVE${NC}"
        log_message "SUCCESS" "UFW is active"
        
        echo ""
        echo "  Firewall Rules:"
        ufw status numbered 2>/dev/null | head -n 10 || true
    else
        echo -e "  ${RED}UFW is INACTIVE${NC}"
        log_message "WARNING" "UFW firewall is not active"
    fi
}

# Check open ports and listening services
check_open_ports() {
    echo -e "\n${BLUE}[OPEN PORTS & SERVICES]${NC}"
    
    local port_count=0
    
    if command -v ss &> /dev/null; then
        echo "  Listening Services:"
        ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "    " $4}' | while read -r port; do
            echo "$port"
            ((port_count++)) || true
        done
    else
        echo "  Listening Services:"
        netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print "    " $4}' || echo "    (unable to retrieve)"
    fi
    
    log_message "INFO" "Open ports checked"
}

# Check failed SSH attempts
check_failed_ssh() {
    echo -e "\n${BLUE}[FAILED SSH LOGIN ATTEMPTS (Last 10)]${NC}"
    
    if [[ ! -f /var/log/auth.log ]]; then
        log_message "WARNING" "auth.log not found"
        echo -e "  ${YELLOW}/var/log/auth.log not found${NC}"
        return
    fi
    
    if [[ ! -r /var/log/auth.log ]]; then
        log_message "WARNING" "auth.log not readable"
        echo -e "  ${YELLOW}/var/log/auth.log not readable${NC}"
        return
    fi
    
    echo "  Last failed attempts:"
    
    local count=0
    grep "Failed password" /var/log/auth.log 2>/dev/null | tail -n 10 | while read -r line; do
        echo "    $(echo "$line" | awk '{print $1, $2, $3}')" | head -c 80
        echo ""
        ((count++)) || true
    done
    
    if grep -q "Failed password" /var/log/auth.log 2>/dev/null; then
        local total_failed=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
        echo "  Total failed attempts in log: ${total_failed}"
        log_message "WARNING" "Found ${total_failed} failed SSH attempts"
    else
        echo "  No failed attempts recorded"
        log_message "SUCCESS" "No failed SSH attempts"
    fi
}

# Check world-writable files
check_world_writable() {
    echo -e "\n${BLUE}[WORLD-WRITABLE FILES IN SENSITIVE DIRECTORIES]${NC}"
    
    local found=0
    
    for dir in "${SENSITIVE_DIRS[@]}"; do
        if [[ -d "${dir}" ]]; then
            local writable_count=$(find "${dir}" -type f -perm -002 2>/dev/null | wc -l || echo 0)
            
            if [[ $writable_count -gt 0 ]]; then
                echo -e "  ${RED}[WARNING] Found ${writable_count} world-writable files in ${dir}${NC}"
                log_message "WARNING" "Found ${writable_count} world-writable files in ${dir}"
                
                echo "  Files:"
                find "${dir}" -type f -perm -002 2>/dev/null | head -n 5 | while read -r file; do
                    echo "    $file"
                done
                
                found=$((found + writable_count))
            fi
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "  ${GREEN}No world-writable files found in sensitive directories${NC}"
        log_message "SUCCESS" "No world-writable files detected"
    else
        echo ""
        echo -e "  ${YELLOW}Total world-writable files found: ${found}${NC}"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local check_firewall_flag=true
    local check_ports_flag=true
    local check_ssh_flag=true
    local check_writable_flag=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -f|--firewall-only)
                check_ports_flag=false
                check_ssh_flag=false
                check_writable_flag=false
                shift
                ;;
            -p|--ports-only)
                check_firewall_flag=false
                check_ssh_flag=false
                check_writable_flag=false
                shift
                ;;
            -s|--ssh-only)
                check_firewall_flag=false
                check_ports_flag=false
                check_writable_flag=false
                shift
                ;;
            -w|--world-writable)
                check_firewall_flag=false
                check_ports_flag=false
                check_ssh_flag=false
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
    
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}       SECURITY AUDIT${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    [[ "${check_firewall_flag}" == "true" ]] && check_firewall
    [[ "${check_ports_flag}" == "true" ]] && check_open_ports
    [[ "${check_ssh_flag}" == "true" ]] && check_failed_ssh
    [[ "${check_writable_flag}" == "true" ]] && check_world_writable
    
    echo ""
    log_message "SUCCESS" "Security audit completed"
}

# Execute main
main "$@"
