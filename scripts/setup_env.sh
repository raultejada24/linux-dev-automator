#!/bin/bash

################################################################################
# Script: setup_env.sh
# Purpose: Comprehensive system setup for development environment
# Description: Checks root privileges, updates system, and installs full
#              development stack with pre-installation verification
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
readonly NC='\033[0m' # No Color

# Logging variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/../logs"
readonly LOG_FILE="${LOG_DIR}/setup_env.log"

# Packages to install
readonly PACKAGES=(
    "git"
    "build-essential"
    "curl"
    "wget"
    "python3"
    "docker.io"
)

################################################################################
# SETUP & UTILITY FUNCTIONS
################################################################################

# Initialize logging directory
init_logging() {
    mkdir -p "${LOG_DIR}"
    {
        echo "======================================"
        echo "Setup Environment Script Started"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "User: $(whoami)"
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
Usage: $(basename "$0") [OPTIONS]

Description:
    Sets up a complete development environment with essential tools and packages.
    Requires root/sudo privileges.

Options:
    -h, --help          Display this help message and exit
    -v, --verbose       Enable verbose output
    -s, --skip-docker   Skip Docker installation

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --skip-docker

EOF
    exit "${1:-0}"
}

# Cleanup function for trap
cleanup() {
    log_message "INFO" "Cleanup initiated (signal: $?)"
}

# Check root privileges
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_message "ERROR" "This script must be run with sudo or as root"
        exit 1
    fi
    log_message "SUCCESS" "Running with root privileges"
}

# Check if package is installed
is_package_installed() {
    local package="$1"
    
    if dpkg -l | grep -q "^ii  ${package}"; then
        return 0
    else
        return 1
    fi
}

# Install package with pre-check
install_package() {
    local package="$1"
    
    if is_package_installed "${package}"; then
        log_message "INFO" "Package '${package}' is already installed"
        return 0
    fi
    
    log_message "INFO" "Installing package: ${package}"
    
    if apt-get install -y "${package}" >> "${LOG_FILE}" 2>&1; then
        log_message "SUCCESS" "Successfully installed: ${package}"
        return 0
    else
        log_message "ERROR" "Failed to install: ${package}"
        return 1
    fi
}

################################################################################
# MAIN SETUP FUNCTIONS
################################################################################

# Update system packages
update_system() {
    log_message "INFO" "Updating system packages..."
    
    if apt-get update >> "${LOG_FILE}" 2>&1; then
        log_message "SUCCESS" "System packages updated successfully"
    else
        log_message "ERROR" "Failed to update system packages"
        exit 1
    fi
    
    log_message "INFO" "Upgrading installed packages..."
    
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "${LOG_FILE}" 2>&1; then
        log_message "SUCCESS" "System packages upgraded successfully"
    else
        log_message "ERROR" "Failed to upgrade system packages"
        exit 1
    fi
}

# Install all required packages
install_dev_stack() {
    log_message "INFO" "Starting development stack installation..."
    
    local failed_packages=()
    
    for package in "${PACKAGES[@]}"; do
        if ! install_package "${package}"; then
            failed_packages+=("${package}")
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_message "ERROR" "Failed to install: ${failed_packages[*]}"
        exit 1
    fi
    
    log_message "SUCCESS" "Development stack installed successfully"
}

# Verify installations
verify_installations() {
    log_message "INFO" "Verifying installed packages..."
    
    local verification_passed=true
    
    # Check git
    if command -v git &> /dev/null; then
        local git_version=$(git --version)
        log_message "SUCCESS" "Git verified: ${git_version}"
    else
        log_message "ERROR" "Git verification failed"
        verification_passed=false
    fi
    
    # Check gcc
    if command -v gcc &> /dev/null; then
        local gcc_version=$(gcc --version | head -n 1)
        log_message "SUCCESS" "GCC verified: ${gcc_version}"
    else
        log_message "ERROR" "GCC verification failed"
        verification_passed=false
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        log_message "SUCCESS" "Curl verified"
    else
        log_message "ERROR" "Curl verification failed"
        verification_passed=false
    fi
    
    # Check wget
    if command -v wget &> /dev/null; then
        log_message "SUCCESS" "Wget verified"
    else
        log_message "ERROR" "Wget verification failed"
        verification_passed=false
    fi
    
    # Check python3
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version)
        log_message "SUCCESS" "Python3 verified: ${python_version}"
    else
        log_message "ERROR" "Python3 verification failed"
        verification_passed=false
    fi
    
    # Check docker
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version)
        log_message "SUCCESS" "Docker verified: ${docker_version}"
    else
        log_message "WARNING" "Docker verification failed"
    fi
    
    if [[ "${verification_passed}" != "true" ]]; then
        log_message "ERROR" "Some installations could not be verified"
        exit 1
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -s|--skip-docker)
                PACKAGES=("${PACKAGES[@]/docker.io/}")
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
    
    check_root
    update_system
    install_dev_stack
    verify_installations
    
    log_message "SUCCESS" "Setup completed successfully"
    log_message "INFO" "Log file: ${LOG_FILE}"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}\n"
}

# Execute main function
main "$@"
