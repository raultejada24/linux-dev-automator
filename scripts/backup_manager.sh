#!/bin/bash

################################################################################
# Script: backup_manager.sh
# Purpose: Backup management with compression and rotation
# Description: Creates compressed tar.gz archives with timestamps and
#              implements rotation logic to delete backups older than 7 days
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
readonly LOG_FILE="${LOG_DIR}/backup_manager.log"
readonly BACKUP_RETENTION_DAYS=7

# Temporary directory for cleanup
TEMP_DIR=""

################################################################################
# SETUP & UTILITY FUNCTIONS
################################################################################

# Initialize logging directory
init_logging() {
    mkdir -p "${LOG_DIR}"
    {
        echo "======================================"
        echo "Backup Manager Started"
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

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] SOURCE DESTINATION

Description:
    Creates compressed tar.gz backup archives with timestamps and manages
    backup rotation by deleting archives older than 7 days.

Arguments:
    SOURCE          Source directory to backup
    DESTINATION     Destination directory for backup archives

Options:
    -h, --help              Display this help message and exit
    -r, --retention DAYS    Set backup retention period (default: 7 days)
    -v, --verbose           Enable verbose output
    -c, --compress LEVEL    Set compression level 1-9 (default: 6)
    --no-rotation           Disable automatic rotation of old backups

Examples:
    $(basename "$0") /home/user/documents /backup
    $(basename "$0") --retention 14 /var/www /backups
    $(basename "$0") --compress 9 /data /backup_archive
    $(basename "$0") /home/user /backup --no-rotation

EOF
    exit "${1:-0}"
}

# Cleanup function for trap
cleanup() {
    if [[ -n "${TEMP_DIR}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_message "INFO" "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
    log_message "INFO" "Cleanup completed"
}

# Validate arguments
validate_arguments() {
    local source="$1"
    local destination="$2"
    
    if [[ -z "${source}" ]] || [[ -z "${destination}" ]]; then
        log_message "ERROR" "SOURCE and DESTINATION arguments are required"
        usage 1
    fi
    
    if [[ ! -d "${source}" ]]; then
        log_message "ERROR" "Source directory does not exist: ${source}"
        exit 1
    fi
    
    if [[ ! -d "${destination}" ]]; then
        log_message "WARNING" "Destination directory does not exist, creating: ${destination}"
        mkdir -p "${destination}"
        log_message "SUCCESS" "Destination directory created: ${destination}"
    fi
    
    if [[ ! -w "${destination}" ]]; then
        log_message "ERROR" "Destination directory is not writable: ${destination}"
        exit 1
    fi
}

# Convert seconds to human-readable format
seconds_to_human() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Get human-readable file size
get_file_size() {
    local size=$1
    
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt 1048576 ]]; then
        echo "$((size / 1024))KB"
    elif [[ $size -lt 1073741824 ]]; then
        echo "$((size / 1048576))MB"
    else
        echo "$((size / 1073741824))GB"
    fi
}

################################################################################
# BACKUP FUNCTIONS
################################################################################

# Create backup archive
create_backup() {
    local source="$1"
    local destination="$2"
    local compress_level="$3"
    
    # Generate backup filename with timestamp
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local source_name=$(basename "${source}")
    local backup_file="${destination}/${source_name}_${timestamp}.tar.gz"
    
    # Get source size for estimation
    local source_size=$(du -sb "${source}" | awk '{print $1}')
    local readable_size=$(get_file_size "$source_size")
    
    log_message "INFO" "Starting backup: ${source} -> ${backup_file}"
    log_message "INFO" "Source size: ${readable_size}"
    
    echo -e "${CYAN}Backup Details:${NC}"
    echo "  Source:      ${source}"
    echo "  Destination: ${backup_file}"
    echo "  Size:        ${readable_size}"
    echo ""
    
    # Create tar.gz archive
    if tar -czf "${backup_file}" -C "$(dirname "${source}")" "$(basename "${source}")" 2>> "${LOG_FILE}"; then
        local backup_size=$(stat -c%s "${backup_file}")
        local readable_backup_size=$(get_file_size "$backup_size")
        local compression_ratio=$((100 - (backup_size * 100 / source_size)))
        
        log_message "SUCCESS" "Backup created successfully: ${backup_file}"
        log_message "INFO" "Backup size: ${readable_backup_size}, Compression: ${compression_ratio}%"
        
        echo -e "${GREEN}Backup created successfully${NC}"
        echo "  Archive size:     ${readable_backup_size}"
        echo "  Compression:      ${compression_ratio}%"
        echo "  Created at:       $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        return 0
    else
        log_message "ERROR" "Failed to create backup archive"
        return 1
    fi
}

# Rotate old backups
rotate_backups() {
    local destination="$1"
    local retention_days="$2"
    
    log_message "INFO" "Starting backup rotation (retention: ${retention_days} days)"
    
    local rotation_performed=false
    local total_freed=0
    
    # Find and delete backups older than retention period
    while IFS= read -r backup_file; do
        local file_age=$(($(date +%s) - $(stat -c%Y "${backup_file}")))
        local file_age_days=$((file_age / 86400))
        
        if [[ $file_age_days -gt $retention_days ]]; then
            local file_size=$(stat -c%s "${backup_file}")
            local readable_size=$(get_file_size "$file_size")
            local age_readable=$(seconds_to_human "$file_age")
            
            log_message "INFO" "Deleting old backup: ${backup_file} (age: ${age_readable})"
            
            if rm -f "${backup_file}"; then
                log_message "SUCCESS" "Deleted: $(basename "${backup_file}") - Freed: ${readable_size}"
                rotation_performed=true
                total_freed=$((total_freed + file_size))
            else
                log_message "ERROR" "Failed to delete: ${backup_file}"
            fi
        fi
    done < <(find "${destination}" -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null | sort)
    
    if [[ "${rotation_performed}" == "true" ]]; then
        local readable_total=$(get_file_size "$total_freed")
        echo -e "${GREEN}Backup rotation completed${NC}"
        echo "  Total space freed: ${readable_total}"
        echo ""
        log_message "SUCCESS" "Backup rotation completed, space freed: ${readable_total}"
    else
        log_message "INFO" "No backups to rotate"
        echo -e "${YELLOW}No old backups to rotate${NC}\n"
    fi
}

# List existing backups
list_backups() {
    local destination="$1"
    
    log_message "INFO" "Listing backups in: ${destination}"
    
    echo -e "${CYAN}Existing Backups:${NC}"
    echo ""
    
    local count=0
    local total_size=0
    
    {
        echo "Filename|Size|Created|Age"
        find "${destination}" -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null | while read -r backup; do
            local size=$(stat -c%s "${backup}")
            local created=$(date -d @"$(stat -c%Y "${backup}")" '+%Y-%m-%d %H:%M:%S')
            local age=$(($(date +%s) - $(stat -c%Y "${backup}")))
            local age_readable=$(seconds_to_human "$age")
            echo "$(basename "${backup}")|$(get_file_size "$size")|${created}|${age_readable}"
        done
    } | column -t -s'|'
    
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local source=""
    local destination=""
    local retention_days="${BACKUP_RETENTION_DAYS}"
    local compress_level=6
    local enable_rotation=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -r|--retention)
                retention_days="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -c|--compress)
                compress_level="$2"
                shift 2
                ;;
            --no-rotation)
                enable_rotation=false
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                usage 1
                ;;
            *)
                if [[ -z "${source}" ]]; then
                    source="$1"
                elif [[ -z "${destination}" ]]; then
                    destination="$1"
                fi
                shift
                ;;
        esac
    done
    
    init_logging
    
    # Set trap for cleanup
    trap cleanup EXIT INT TERM
    
    # Validate arguments
    validate_arguments "${source}" "${destination}"
    
    # Validate compression level
    if ! [[ "${compress_level}" =~ ^[1-9]$ ]]; then
        log_message "ERROR" "Compression level must be between 1 and 9"
        exit 1
    fi
    
    # Validate retention days
    if ! [[ "${retention_days}" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Retention days must be a positive number"
        exit 1
    fi
    
    # Print configuration
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       BACKUP MANAGER${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Retention period: ${retention_days} days"
    echo "  Compression level: ${compress_level}/9"
    echo "  Auto-rotation: $([ "${enable_rotation}" == "true" ] && echo "Enabled" || echo "Disabled")"
    echo ""
    
    # Create backup
    if create_backup "${source}" "${destination}" "${compress_level}"; then
        # Rotate old backups if enabled
        if [[ "${enable_rotation}" == "true" ]]; then
            rotate_backups "${destination}" "${retention_days}"
        fi
        
        # List existing backups
        list_backups "${destination}"
        
        log_message "SUCCESS" "Backup operation completed successfully"
        echo -e "${GREEN}Backup operation completed successfully${NC}"
        exit 0
    else
        log_message "ERROR" "Backup operation failed"
        echo -e "${RED}Backup operation failed${NC}"
        exit 1
    fi
}

# Execute main function
main "$@"
