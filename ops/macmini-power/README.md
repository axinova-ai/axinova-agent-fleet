# Mac Mini Power Management

Scripts to toggle "server mode" on the Mac minis (M4 agent01, M2 Pro focusagent02), ensuring they stay awake 24/7 for reliable remote SSH/VPN access.

## Why

macOS defaults allow the system to sleep when idle, which drops SSH sessions and VPN tunnels. These scripts apply persistent `pmset` settings that survive reboots, with the ability to capture and restore the original state.

## Scripts

| Script | Purpose |
|---|---|
| `server_mode_on.sh` | Apply 24/7 server power settings |
| `server_mode_off.sh` | Restore macOS defaults or saved baseline |
| `verify_status.sh` | Check current settings (PASS/FAIL report) |

## Usage

### Check current status

```bash
bash ops/macmini-power/verify_status.sh
```

### Enable server mode

```bash
# Preview what would change
sudo bash ops/macmini-power/server_mode_on.sh --dry-run

# Apply (saves baseline backup on first run)
sudo bash ops/macmini-power/server_mode_on.sh

# Custom display sleep timeout
sudo bash ops/macmini-power/server_mode_on.sh --display-minutes 5
```

### Disable server mode

```bash
# Preview
sudo bash ops/macmini-power/server_mode_off.sh --dry-run

# Restore (prompts to use backup if one exists)
sudo bash ops/macmini-power/server_mode_off.sh
```

### Run remotely via SSH

```bash
ssh agent01 'sudo bash -s' < ops/macmini-power/server_mode_on.sh
ssh agent01 'bash -s' < ops/macmini-power/verify_status.sh
```

Note: `server_mode_off.sh` requires interactive input (backup restore prompt), so run it in an interactive SSH session:

```bash
ssh agent01
sudo bash /path/to/ops/macmini-power/server_mode_off.sh
```

## Settings Explained

| Setting | Server Mode | Default | Purpose |
|---|---|---|---|
| `sleep` | 0 | 1 | Minutes until system sleeps (0 = never) |
| `disablesleep` | 1 | 0 | Hard-disable sleep entirely |
| `displaysleep` | 10 | 10 | Minutes until display sleeps (headless, so cosmetic) |
| `womp` | 1 | 1 | Wake on LAN — allows remote wake via magic packet |
| `autorestart` | 1 | 0 | Auto-restart after power failure |
| `networkoversleep` | 1 | 0 | Keep network active during display sleep (macOS 14+) |
| `tcpkeepalive` | 1 | 1 | Maintain TCP connections during sleep |
| `powernap` | 0 | 1 | Disable Power Nap (prevents random wake cycles) |
| `proximitywake` | 0 | 1 | Disable proximity wake (no Apple Watch wake) |

## Backup & Restore

On first run, `server_mode_on.sh` saves the current `pmset` configuration to:

```
~/.config/axinova/pmset-backup-<timestamp>.txt
```

This backup is machine-specific and not stored in the repo. Subsequent runs skip the backup to preserve the original baseline. `server_mode_off.sh` offers to restore from this backup.

## Notes

- All settings are applied via `pmset -a` (all power sources) and persist across reboots
- No `caffeinate` daemon needed — `pmset` settings are permanent
- `networkoversleep` requires macOS 14+; silently skipped on older versions
- Scripts require `sudo` for `pmset` write access; `verify_status.sh` does not
