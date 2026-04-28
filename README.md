# linux-dev-automator

Production-grade Bash scripts for Linux system administration, monitoring, and maintenance.

## Quick Start

```bash
chmod +x scripts/*.sh
```

## Scripts

| Script | Purpose | Key Flags |
|--------|---------|-----------|
| `setup_env.sh` | Dev environment setup | `-h`, `-v/--verbose`, `--skip-docker` |
| `system_monitor.sh` | Real-time system monitoring | `-h`, `-i/--interval SECS`, `-o/--once`, `--cpu-only`, `--disk-only` |
| `backup_manager.sh` | Backup with rotation | `-h`, `-r/--retention DAYS`, `-c/--compress LEVEL`, `--no-rotation` |
| `log_cleaner.sh` | System cache & log cleanup | `-h`, `-d/--days DAYS`, `--dry-run` |
| `security_audit.sh` | Security assessment | `-h`, `-f/--firewall-only`, `-s/--ssh-only`, `-w/--world-writable` |

## Usage Examples

```bash
# Setup development environment (requires sudo)
sudo ./scripts/setup_env.sh

# Monitor system resources
./scripts/system_monitor.sh --interval 10

# Create timestamped backup with 14-day retention
./scripts/backup_manager.sh --retention 14 /source /destination

# Clean system cache and old logs (requires sudo)
sudo ./scripts/log_cleaner.sh

# Run security audit (requires sudo)
sudo ./scripts/security_audit.sh --firewall-only
```

## Features

- **Robust error handling:** `set -e`, `set -u`, signal trapping
- **Color-coded output:** Red (errors), Green (success), Yellow (warnings), Blue (info)
- **Comprehensive logging:** All operations logged to `logs/` directory
- **Production-ready:** Input validation, pre-checks, clean interruption handling
- **Usage functions:** Run any script with `-h` or `--help` for detailed options

## Requirements

- Bash 4.0+
- Debian/Ubuntu-based system
- sudo privileges (for most operations)
- Standard utilities: awk, sed, tar, grep, netstat/ss

## Logs

All scripts write to `logs/` directory:
- `setup_env.log`
- `system_monitor.log`
- `backup_manager.log`
- `log_cleaner.log`
- `security_audit.log`

