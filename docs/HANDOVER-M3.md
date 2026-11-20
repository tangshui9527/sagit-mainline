# Milestone M3 Handover Report: Qualcomm Remoteproc, Wireless & GPU Userspace

- **Device**: Xiaomi Mi 6 (`sagit`, MSM8998 / Snapdragon 835, Headless Board SN `6f235784`)
- **Kernel**: Linux Mainline 7.2.11 arm64
- **Rootfs**: Debian 13 (Trixie) arm64 on internal UFS `/dev/sda17`
- **Boot Partition**: `/dev/sde40`
- **Date**: 2026-11-20

---

## 1. Executive Summary

Milestone M3 accomplished bringing up the Qualcomm Hexagon DSP remoteprocs, WCN3990 wireless (Wi-Fi 802.11ac and Bluetooth 5.0), and Mesa 3D GPU userspace on Debian 13 arm64 running mainline Linux 7.2.11.

Key achievements:
1. **Qualcomm Remoteproc Bring-Up**:
   - Upstream DTS disabled all three Hexagon remoteprocs by default. Patched DTB enabled `mss-pil` (Modem), `slpi-pas` (Sensors), and `adsp-pas` (Audio DSP).
   - Solved the modem DSP watchdog starvation crash (`fatal error received: dog_hb.c:266:DOG_HB detects starvation`) by diagnosing and fixing `rmtfs`'s hardcoded partition whitelist.
   - Built and installed patched `rmtfs` with Xiaomi-specific `/boot/modem_fsg_oem_1` and `/boot/modem_fsg_oem_2` partition support.
2. **WCN3990 Wi-Fi (`ath10k_snoc`)**:
   - `ath10k_snoc` probed, communicated with QMI WLAN service on Modem DSP over QRTR.
   - Performed wireless scans discovering 26 live 2.4 GHz and 5 GHz networks.
   - Associated with SSID `YYDS` (5 GHz, Channel 48, 80 MHz channel width, txpower 30 dBm).
   - DHCP lease received from access point (`192.168.31.216/24` and IPv6 `2409:8a55:...`).
   - Extracted authentic factory calibration data (`bdwlan.bin`) from Xiaomi OEM UFS `modem` (`/dev/sde41`) and factory MAC addresses from `persist` (`/dev/sda14`).
   - Packaged custom `board-2.bin` via Qualcomm's `ath10k-bdencoder` mapped to `qmi-board-id=0`.
3. **Bluetooth (`hci0`)**:
   - Decompressed all 92 QCA firmware archives in `/lib/firmware/qca/`.
   - Driver `hci_uart_qca` downloaded `crbtfw21.tlv` (177 KB) and `crnv21.bin` in 0.8s.
   - Controller `hci0` active on UART with BD address `39:90:21:64:07:00` and factory address `20:47:da:e9:aa:03`.
4. **Mesa & 3D Userspace**:
   - Mesa 25.0.7 arm64 installed (`mesa-utils`, `mesa-vulkan-drivers`, `libgl1-mesa-dri`).
   - Off-screen surfaceless rendering verified with OpenGL 4.5 Core Profile and OpenGL ES 3.2.

---

## 2. Root Cause Analysis & Deep Technical Insights

### 2.1 Upstream DTS Remoteproc Disabling
In mainline `msm8998.dtsi`, the three remoteprocs are disabled by default:
- `remoteproc@4080000` (`mss-pil` / Modem)
- `remoteproc@5800000` (`slpi-pas` / Low-power Island)
- `remoteproc@17300000` (`adsp-pas` / Audio DSP)

Because WCN3990 Wi-Fi depends on the Modem WLAN DSP power domain via QRTR, `ath10k_snoc` remained dormant until `remoteproc@4080000` was enabled in DTB and repacked into `boot-debian-rproc.img`.

### 2.2 Modem Watchdog Starvation (`DOG_HB`) & RMTFS Whitelist
On boot, the Modem DSP booted up but crashed after ~20 seconds with:
```
qcom-q6v5-mss 4080000.remoteproc: fatal error received: dog_hb.c:266:DOG_HB detects starvation of task 0x...
```
`rmtfs` logs revealed:
```
[RMTFS storage] request for unknown partition '/boot/modem_fsg_oem_1', rejecting
[RMTFS storage] request for unknown partition '/boot/modem_fsg_oem_2', rejecting
```
Upstream `rmtfs` (`storage.c`) uses a static whitelist table `partition_table[]`. Xiaomi modem firmware requests OEM NV partition aliases `/boot/modem_fsg_oem_1` and `/boot/modem_fsg_oem_2`. Because `rmtfs` returned `-EINVAL`, the modem EFS storage task blocked indefinitely until the Qualcomm Hexagon RTOS watchdog (`dog_hb.c`) triggered a Subsystem Restart (SSR).

Adding the two OEM aliases to `partition_table[]` mapped to `fsg` completely resolved the rejection and stopped the crash loop.

### 2.3 WCN3990 Board Calibration (`board-2.bin`)
Mainline `linux-firmware` supplies generic WCN3990 `board-2.bin` containing calibration IDs for reference boards. The sagit modem reports `qmi-board-id=0`, which was absent from `board-2.bin`, triggering `ath10k_snoc: failed to fetch board data for bus=snoc,qmi-board-id=0`.
Extracting factory `bdwlan.bin` from UFS partition `sde41` (`modem`) and encoding it with `ath10k-bdencoder` into `board-2.bin` provides the exact calibrated RF front-end parameters.

---

## 3. Deliverables in Repository

- `patches/0001-dts-enable-msm8998-remoteprocs.patch`: DTB patch enabling remoteprocs.
- `patches/0002-rmtfs-add-xiaomi-sagit-oem-partitions.patch`: `rmtfs` storage fixup patch.
- `patches/0003-ath10k-board-2-sagit-mapping.json`: Board encoder JSON mapping.
- `configs/qualcomm-remoteproc.conf`: Autoload configuration for Qualcomm remoteproc drivers.
- `docs/HANDOVER-M3.md`: This comprehensive handover document.
