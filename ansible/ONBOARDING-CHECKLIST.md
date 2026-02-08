# VPN Client Onboarding Checklist

Quick reference checklist for onboarding VPN clients.

## Pre-flight Checklist

- [ ] Prerequisites installed: `yq`, `qrencode`, `ansible`
- [ ] SSH access to sg-vpn configured
- [ ] Current directory: `/Users/weixia/axinova/axinova-agent-fleet/ansible`
- [ ] Inventory file reviewed: `inventories/vpn/clients.yml`

### Verify Prerequisites

```bash
yq --version          # Should show version
qrencode --version    # Should show version
ansible --version     # Should show version
ssh sg-vpn 'echo OK'  # Should print OK
```

## Onboarding Steps

### 1. Review/Update Inventory

- [ ] Open `inventories/vpn/clients.yml`
- [ ] Verify all 7 clients are listed
- [ ] Check for unique names and IPs
- [ ] Confirm device types are correct
- [ ] Ensure mobile devices have `generate_qr: true`

**Current clients:**
- m2-pro-agent-2 (10.66.66.2)
- m4-agent-1 (10.66.66.3)
- wei-iphone (10.66.66.10) - QR
- lisha-macbook-air (10.66.66.11)
- wei-macbook-pro (10.66.66.12)
- wei-hp-windows (10.66.66.13)
- wei-android-xiaomi-ultra14 (10.66.66.14) - QR

### 2. Run Batch Onboarding

```bash
cd ansible
./scripts/onboard-vpn-clients.sh
```

- [ ] Script completes without errors
- [ ] All 7 clients processed
- [ ] Keys generated/fetched
- [ ] Configs created
- [ ] QR codes generated (2 mobile)
- [ ] Ansible variables updated
- [ ] Server config deployed
- [ ] Output directory created: `/tmp/vpn-onboarding-YYYYMMDD-HHMMSS/`

**Expected output:**
```
✅ All prerequisites satisfied
✅ Found 7 clients in inventory
✅ Inventory validation passed
✅ Generated X new key pairs, skipped Y existing
✅ Fetched keys for 7 clients
✅ Generated config for all clients
✅ Generated 2 QR codes
✅ Ansible variables updated
✅ Server configuration deployed
✅ Verification complete
✅ Outputs organized by device type
```

### 3. Verify Deployment

```bash
./scripts/verify-vpn-clients.sh
```

- [ ] Server is reachable
- [ ] WireGuard service is active
- [ ] All 7 clients registered
- [ ] No duplicate IPs
- [ ] No duplicate public keys
- [ ] Server public key matches
- [ ] Verification report looks correct

**Expected checks:**
```
✅ Server is reachable
✅ WireGuard service is active
✅ All clients registered (7/7)
✅ No duplicate IP assignments
✅ No duplicate public keys
✅ Server public key matches
```

### 4. Manual Server Check

```bash
ssh sg-vpn 'sudo wg show wg0'
```

- [ ] Shows 7 peer entries
- [ ] Each peer has correct public key
- [ ] AllowedIPs match inventory
- [ ] Interface is up

### 5. Distribute Configurations

#### Interactive Method

```bash
./scripts/distribute-client-configs.sh /tmp/vpn-onboarding-YYYYMMDD-HHMMSS/
```

- [ ] Menu shows all 7 clients
- [ ] Can display QR codes for mobile
- [ ] Can view configs for desktop
- [ ] Distribution instructions shown

#### Manual Distribution

**macOS Clients (4 devices):**

```bash
# For each: m2-pro-agent-2, m4-agent-1, lisha-macbook-air, wei-macbook-pro
scp /tmp/vpn-onboarding-*/configs/<device>.conf <device>:~/Downloads/

ssh <device>
sudo mkdir -p /etc/wireguard
sudo mv ~/Downloads/<device>.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
```

- [ ] m2-pro-agent-2 config copied
- [ ] m4-agent-1 config copied
- [ ] lisha-macbook-air config copied
- [ ] wei-macbook-pro config copied

**Windows Client (1 device):**

- [ ] wei-hp-windows.conf copied to device
- [ ] WireGuard GUI installed
- [ ] Config imported

**Mobile Clients (2 devices):**

```bash
# Display QR codes
cat /tmp/vpn-onboarding-*/qr-codes/wei-iphone.txt
cat /tmp/vpn-onboarding-*/qr-codes/wei-android-xiaomi-ultra14.txt
```

- [ ] wei-iphone QR code scanned
- [ ] wei-android-xiaomi-ultra14 QR code scanned
- [ ] WireGuard app installed on both

### 6. Client Testing

Test from each client after config installed:

**macOS Clients:**

```bash
# On each Mac
sudo wg-quick up wg0
ping 10.66.66.1
curl ifconfig.me  # Should show 8.222.187.10
```

- [ ] m2-pro-agent-2: VPN active, connectivity verified
- [ ] m4-agent-1: VPN active, connectivity verified
- [ ] lisha-macbook-air: VPN active, connectivity verified
- [ ] wei-macbook-pro: VPN active, connectivity verified

**Windows Client:**

- [ ] wei-hp-windows: VPN activated in GUI
- [ ] wei-hp-windows: Can ping 10.66.66.1
- [ ] wei-hp-windows: Public IP shows 8.222.187.10

**Mobile Clients:**

- [ ] wei-iphone: VPN toggled on
- [ ] wei-iphone: Can browse internet
- [ ] wei-android-xiaomi-ultra14: VPN toggled on
- [ ] wei-android-xiaomi-ultra14: Can browse internet

### 7. Final Verification

```bash
# Check all clients connected
ssh sg-vpn 'sudo wg show wg0' | grep -c "latest handshake"
# Should show: 7
```

- [ ] All 7 clients show recent handshake
- [ ] All clients show RX/TX bytes
- [ ] No error messages in server logs

### 8. Cleanup

```bash
# After confirming all clients work
rm -rf /tmp/vpn-onboarding-*
```

- [ ] Temporary directory deleted
- [ ] No private keys remaining in local filesystem
- [ ] Server-side keys remain in `/etc/wireguard/clients/`

### 9. Documentation

- [ ] Note output directory path for reference
- [ ] Save onboarding report if needed
- [ ] Update any internal documentation
- [ ] Mark onboarding as complete

## Troubleshooting

### Keys Already Exist

If you see "Keys exist, skipping":
```bash
# To rotate keys for all clients
./scripts/onboard-vpn-clients.sh --force-regenerate
```

### Client Won't Connect

```bash
# Check server side
ssh sg-vpn 'sudo wg show wg0'
ssh sg-vpn 'sudo journalctl -u wg-quick@wg0 -n 50'

# Check client side
sudo wg show wg0
sudo wg-quick up wg0  # Try reconnecting
```

### Verification Fails

```bash
# Re-run with details
./scripts/verify-vpn-clients.sh

# Check specific issues
ssh sg-vpn 'sudo wg show wg0 dump'
```

## Quick Reference Commands

```bash
# Full onboarding workflow
cd ansible
./scripts/onboard-vpn-clients.sh
./scripts/verify-vpn-clients.sh
./scripts/distribute-client-configs.sh /tmp/vpn-onboarding-*/

# Server status
ssh sg-vpn 'sudo wg show wg0'
ssh sg-vpn 'sudo systemctl status wg-quick@wg0'

# Client connection
sudo wg-quick up wg0     # Start VPN
sudo wg-quick down wg0   # Stop VPN
sudo wg show wg0         # Check status

# Testing
ping 10.66.66.1          # VPN gateway
curl ifconfig.me         # Public IP (should be 8.222.187.10)
```

## Success Criteria

Onboarding is complete when:

- ✅ All 7 clients registered on server
- ✅ All 7 clients can connect to VPN
- ✅ All 7 clients can ping 10.66.66.1
- ✅ All 7 clients show server public IP (8.222.187.10)
- ✅ Server shows 7 active handshakes
- ✅ No errors in server logs
- ✅ Temporary files cleaned up

## Documentation References

- **Full guide**: `docs/vpn/ONBOARDING.md`
- **Script README**: `ansible/scripts/README-VPN.md`
- **Implementation summary**: `ansible/VPN-IMPLEMENTATION-SUMMARY.md`
- **Client inventory**: `ansible/inventories/vpn/clients.yml`

## Notes

- Onboarding is idempotent - safe to re-run
- Server-side keys are preserved unless `--force-regenerate`
- Configs contain private keys - handle securely
- Delete temporary directory after distribution
- Client configs should be deleted from devices after importing to WireGuard

---

**Last Updated:** 2026-02-08
**Script Version:** 1.0.0
**Clients Supported:** 7 devices
