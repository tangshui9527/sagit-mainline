#!/bin/bash
# Initialize Xiaomi Mi 6 Bluetooth BD address from persist partition or Wi-Fi MAC

BT_MAC=""

# Wait briefly for /dev/disk/by-partlabel/persist at early boot and mount read-only if needed
if [ ! -f /mnt/persist/wlan_bt/bt.mac ]; then
    for _ in $(seq 1 25); do
        [ -e /dev/disk/by-partlabel/persist ] && break
        sleep 0.2
    done
    if [ -e /dev/disk/by-partlabel/persist ] && ! mountpoint -q /mnt/persist 2>/dev/null; then
        mkdir -p /mnt/persist
        mount -o ro /dev/disk/by-partlabel/persist /mnt/persist 2>/dev/null || true
    fi
fi

if [ -f /mnt/persist/wlan_bt/bt.mac ]; then
    # Raw 6 bytes in reverse order
    BT_MAC=$(python3 -c "
with open('/mnt/persist/wlan_bt/bt.mac', 'rb') as f:
    b = f.read()
if len(b) >= 6:
    print(':'.join(f'{x:02x}' for x in reversed(b[:6])))
" 2>/dev/null || true)
fi

# Fallback: derive from wlan0 MAC (subtract 1 from last byte)
if [ -z "$BT_MAC" ]; then
    WLAN_MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null || true)
    if [ -n "$WLAN_MAC" ]; then
        BT_MAC=$(python3 -c "
parts = [int(x, 16) for x in '$WLAN_MAC'.split(':')]
parts[5] = (parts[5] - 1) & 0xff
print(':'.join(f'{x:02x}' for x in parts))
" 2>/dev/null || true)
    fi
fi

if [ -z "$BT_MAC" ]; then
    BT_MAC="20:47:da:e9:aa:03"
fi
BT_MAC=$(echo "$BT_MAC" | tr 'A-F' 'a-f')

run_btmgmt() {
    # BlueZ btmgmt hangs in epoll if stdin is /dev/null (e.g. under systemd); feed an empty pipe for clean EOF.
    printf "" | timeout 5 btmgmt "$@"
}

# Wait up to 10s for hci0 to appear
for _ in $(seq 1 50); do
    if [ -d /sys/class/bluetooth/hci0 ]; then
        break
    fi
    sleep 0.2
done

if [ ! -d /sys/class/bluetooth/hci0 ]; then
    echo "hci0 did not appear within timeout" >&2
    exit 1
fi

CURRENT_ADDR=$(hciconfig hci0 2>/dev/null | awk '/BD Address:/ {print tolower($3)}')
UNCONFIGURED=0
if run_btmgmt --index 0 info 2>/dev/null | grep -qi "missing options:.*public-address"; then
    UNCONFIGURED=1
fi

if [ "$CURRENT_ADDR" = "$BT_MAC" ] && [ "$UNCONFIGURED" -eq 0 ]; then
    echo "hci0 already configured with BD address $BT_MAC"
    run_btmgmt --index 0 power on >/dev/null 2>&1 || hciconfig hci0 up 2>/dev/null || true
    exit 0
fi

echo "Provisioning Bluetooth public address $BT_MAC on hci0..."
run_btmgmt --index 0 power off >/dev/null 2>&1 || true
run_btmgmt --index 0 public-addr "$BT_MAC"

# Setting public-addr forces hci_qca to re-download firmware (~1.0-1.2s) and re-register hci0.
# Poll until controller reports the provisioned address and leaves unconfigured state.
READY=0
for _ in $(seq 1 50); do
    INFO=$(run_btmgmt --index 0 info 2>/dev/null || true)
    if echo "$INFO" | grep -qi "addr $BT_MAC" && ! echo "$INFO" | grep -qi "missing options:.*public-address"; then
        READY=1
        break
    fi
    sleep 0.2
done

if [ "$READY" -ne 1 ]; then
    echo "Timed out waiting for hci0 firmware reload after setting $BT_MAC" >&2
    exit 1
fi

run_btmgmt --index 0 power on >/dev/null 2>&1 || hciconfig hci0 up 2>/dev/null || true
echo "hci0 initialized successfully: $BT_MAC"
