# linux-dev-automator

Bash scripts for Linux system automation.

## Setup

```bash
chmod +x scripts/*.sh
```

## Scripts

**setup_env.sh** - Installs dev environment dependencies. Flags: `-h` help, `-v` verbose, `--skip-docker` skip Docker installation.

**system_monitor.sh** - Displays CPU, memory, disk usage in real-time. Flags: `-i SECS` interval, `-o` show once, `--cpu-only` CPU only, `--disk-only` disk only.

**backup_manager.sh** - Creates compressed backups with automatic rotation. Flags: `-r DAYS` retention period, `-c LEVEL` compression level, `--no-rotation` disable rotation.

**log_cleaner.sh** - Removes old logs and cache files. Flags: `-d DAYS` delete files older than N days, `--dry-run` preview without deleting.

**security_audit.sh** - Checks firewall, SSH configuration, file permissions. Flags: `-f` firewall only, `-s` SSH only, `-w` world-writable files only.

## Examples

```bash
sudo ./scripts/setup_env.sh
./scripts/system_monitor.sh --interval 10
./scripts/backup_manager.sh --retention 14 /source /dest
sudo ./scripts/log_cleaner.sh --days 30
sudo ./scripts/security_audit.sh
```

## Requirements

- Bash 4.0+
- Debian/Ubuntu
- sudo access
- Standard tools: awk, sed, tar, grep, netstat/ss

## Logs

All output saved to `logs/` directory.

