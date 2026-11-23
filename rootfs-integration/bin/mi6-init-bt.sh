#!/bin/bash
# Initialize Xiaomi Mi 6 Bluetooth BD address from persist partition or Wi-Fi MAC
set -e

# Try reading factory bt.mac from /mnt/persist
BT_MAC=""
if [ ! -f /mnt/persist/wlan_bt/bt.mac ]; then
    mkdir -p /mnt/persist
    mount -o ro /dev/disk/by-partlabel/persist /mnt/persist 2>/dev/null || true
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

echo "Setting Bluetooth public address to $BT_MAC..."
# Wait up to 10s for hci0 to appear in btmgmt or hciconfig
for i in $(seq 1 20); do
    if hciconfig hci0 2>/dev/null | grep -q "hci0"; then
        break
    fi
    sleep 0.5
done

# Check if already has a valid BD address (not 39:90:...)
CURRENT_ADDR=$(hciconfig hci0 2>/dev/null | awk "/BD Address:/ {print \$3}")
if [ "$CURRENT_ADDR" = "$BT_MAC" ]; then
    echo "hci0 already has BD address $BT_MAC"
    hciconfig hci0 up 2>/dev/null || true
    exit 0
fi

# Set public address via btmgmt
btmgmt --index 0 power off 2>/dev/null || true
btmgmt --index 0 public-addr "$BT_MAC" 2>/dev/null || true
sleep 0.5
btmgmt --index 0 power on 2>/dev/null || true
hciconfig hci0 up 2>/dev/null || true
echo "hci0 initialized successfully: $BT_MAC"
