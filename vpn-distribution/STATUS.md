# VPN Distribution Status

**Last Updated:** 2026-02-09 16:30 CST

## Summary

The VPN configs in this directory are **UP TO DATE** and match the VPN server configuration.

All QR codes have been **regenerated on 2026-02-09** to match the current .conf files.

## Issue Identified (2026-02-09)

**Problem:** Mobile devices (wei-iphone, wei-android-xiaomi-ultra14) were unable to establish VPN handshakes.

**Root Cause:** The QR code PNG files in `qr-codes/` directory were **outdated** and did not match the current .conf files. The config files themselves were correct, but the QR codes needed regeneration.

**Resolution:** All QR codes regenerated on 2026-02-09 16:25 CST. Files updated:
- `qr-codes/wei-iphone.png`
- `qr-codes/wei-iphone.txt`
- `qr-codes/wei-android-xiaomi-ultra14.png`
- `qr-codes/wei-android-xiaomi-ultra14.txt`
- `qr-codes/lisha-iphone.png`
- `qr-codes/lisha-iphone.txt`

## Config Verification (2026-02-09 16:20 CST)

✓ **Private keys in configs match server:** All client private keys in local .conf files match the keys stored on VPN server at `/etc/wireguard/clients/`

✓ **Public keys in Ansible vars match server:** All public keys in `ansible/roles/wireguard_server/defaults/main.yml` match derived public keys from server's private keys

✓ **Server config up to date:** `/etc/wireguard/wg0.conf` last updated Feb 8 15:58, contains all 10 clients

✓ **QR codes regenerated:** Fresh QR codes generated from current .conf files on Feb 9 16:25

## Action Required

**All mobile device users must:**
1. **Delete** the existing VPN profile on your device
2. **Re-scan** the QR code from the updated PNG files in `qr-codes/` directory

The old QR codes will NOT work because they contained different configuration data.

## Devices That Need Re-scanning

1. **wei-iphone** (iOS)
   - File: `qr-codes/wei-iphone.png`
   - IP: 10.66.66.10

2. **wei-android-xiaomi-ultra14** (Android)
   - File: `qr-codes/wei-android-xiaomi-ultra14.png`
   - IP: 10.66.66.14

3. **lisha-iphone** (iOS)
   - File: `qr-codes/lisha-iphone.png`
   - IP: 10.66.66.15

## Current VPN Server Status

- **Endpoint:** 8.222.187.10:51820
- **Server Public Key:** 4utg8R6pINVXmF0EilIQx2LAtndqO0plkv2kdEwf3QE=
- **VPN Network:** 10.66.66.0/24
- **Total Clients:** 10 (all registered on server)
- **Service Status:** Active since Feb 9 16:00:25 CST

## Security Note

The following directories are **correctly excluded** from git (contain private keys):
- `configs/` - All .conf files
- `qr-codes/` - All QR code images
- `keys/` - If it exists

Only public keys and metadata are committed to git in `ansible/roles/wireguard_server/defaults/main.yml`.
