# VPN Distribution Status

**Last Updated:** 2026-02-13

## Migration to AmneziaWG (2026-02-13)

The VPN has been **successfully migrated from WireGuard to AmneziaWG**. All client configs and QR codes have been regenerated with AmneziaWG obfuscation parameters.

### What Changed
- **Protocol:** WireGuard → AmneziaWG (adds traffic obfuscation for DPI bypass)
- **Server config:** `/etc/wireguard/wg0.conf` → `/etc/amnezia/amneziawg/awg0.conf`
- **Interface name:** `wg0` → `awg0`
- **Commands:** `wg-quick` → `awg-quick`, `wg show` → `awg show`
- **Client apps:** Users must install AmneziaWG apps instead of WireGuard apps
- **Obfuscation:** All configs now include Jc, Jmin, Jmax, S1, S2, H1-H4 parameters

### Archive
Old WireGuard configs have been archived to `vpn-distribution-wireguard-archive/` (2026-02-13).

## Summary

The VPN configs in this directory are **UP TO DATE** and match the AmneziaWG server configuration.

All client configs and QR codes were **regenerated on 2026-02-13** for the AmneziaWG migration.

## Previous Issues (Historical)

### Issue Identified (2026-02-09) - RESOLVED
**Problem:** Mobile devices were unable to establish VPN handshakes.
**Root Cause:** Outdated QR codes.
**Resolution:** All QR codes regenerated on 2026-02-09 16:25 CST.

## Config Verification (2026-02-13)

✓ **AmneziaWG migration complete:** Server running AmneziaWG on `awg0` interface

✓ **All client configs regenerated:** 10 clients with AmneziaWG obfuscation parameters

✓ **Private keys match server:** All client private keys stored at `/etc/wireguard/clients/` (unchanged location)

✓ **Public keys in Ansible vars:** Updated in `ansible/roles/wireguard_server/defaults/main.yml`

✓ **Server config:** `/etc/amnezia/amneziawg/awg0.conf` contains all 10 clients with obfuscation

✓ **QR codes regenerated:** Fresh QR codes with AmneziaWG parameters generated on 2026-02-13

## Action Required

**ALL USERS must update to AmneziaWG:**

1. **Install AmneziaWG app:**
   - **iOS:** https://apps.apple.com/us/app/amneziawg/id6478942365
   - **Android:** AmneziaWG on Google Play
   - **macOS:** https://github.com/amnezia-vpn/amneziawg-apple/releases
   - **Windows:** https://github.com/amnezia-vpn/amneziawg-windows/releases

2. **Delete old WireGuard profile** on your device

3. **Import new AmneziaWG config:**
   - **Mobile:** Scan new QR code from `qr-codes/` directory
   - **Desktop:** Import new .conf file from `configs/` directory

The old WireGuard configs will NOT work because the server is now running AmneziaWG.

## All Devices Need AmneziaWG Migration

All 10 devices need to migrate to AmneziaWG:

**Mobile (scan QR codes):**
1. **wei-iphone** (iOS) - IP: 10.66.66.10
2. **wei-android-xiaomi-ultra14** (Android) - IP: 10.66.66.14
3. **lisha-iphone** (iOS) - IP: 10.66.66.15

**Desktop (import .conf files):**
4. **wei-macbook-air-m2** (macOS) - IP: 10.66.66.2
5. **wei-mac-mini-m1** (macOS) - IP: 10.66.66.3
6. **wei-windows-legion** (Windows) - IP: 10.66.66.11
7. **lisha-macbook-air** (macOS) - IP: 10.66.66.4
8. **lisha-windows** (Windows) - IP: 10.66.66.12
9. **office-mac-mini** (macOS) - IP: 10.66.66.5
10. **dev-ubuntu-vm** (Linux) - IP: 10.66.66.6

## Current VPN Server Status

- **Protocol:** AmneziaWG (WireGuard with obfuscation)
- **Endpoint:** 8.222.187.10:54321
- **Server Public Key:** 4utg8R6pINVXmF0EilIQx2LAtndqO0plkv2kdEwf3QE=
- **VPN Network:** 10.66.66.0/24
- **Interface:** awg0
- **Config Location:** `/etc/amnezia/amneziawg/awg0.conf`
- **Total Clients:** 10 (all registered on server)
- **Service:** awg-quick@awg0
- **Migration Date:** 2026-02-13

## Security Note

The following directories are **correctly excluded** from git (contain private keys):
- `configs/` - All AmneziaWG .conf files (contain private keys)
- `qr-codes/` - All QR code images (contain full configs)
- `keys/` - If it exists
- `vpn-distribution-wireguard-archive/` - Archived WireGuard configs

Only public keys and metadata are committed to git in `ansible/roles/wireguard_server/defaults/main.yml`.

## Obfuscation Parameters

All AmneziaWG configs include these obfuscation parameters:
- **Jc:** 3 (junk packet count)
- **Jmin:** 50 (min junk packet size)
- **Jmax:** 1000 (max junk packet size)
- **S1, S2:** 0, 0 (init packet junk size)
- **H1, H2, H3, H4:** 1, 2, 3, 4 (header junk)
