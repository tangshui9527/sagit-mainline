# sagit-mainline: Xiaomi Mi 6 (sagit) Mainline Linux & Debian 13

[![Kernel Upstream Build](https://github.com/tangshui9527/sagit-mainline/actions/workflows/kernel-upstream.yml/badge.svg)](https://github.com/tangshui9527/sagit-mainline/actions/workflows/kernel-upstream.yml)
[![Rootfs Build](https://github.com/tangshui9527/sagit-mainline/actions/workflows/rootfs.yml/badge.svg)](https://github.com/tangshui9527/sagit-mainline/actions/workflows/rootfs.yml)
[![License: GPL-2.0](https://img.shields.io/badge/License-GPL%202.0-blue.svg)](COPYING)

将 **小米 6（Xiaomi Mi 6 / sagit / 高通骁龙 835 MSM8998）** 移植至 **原生最新主线内核（Linux Upstream 7.3.5+）** 与 **Debian 13 (Trixie) ARM64 原生根文件系统** 的完整工程。终态目标为高性能、低功耗、全硬件加速的 **全功能微型 Linux 无头服务器 / 边缘计算节点**。

---

## 硬件支持与功能状态矩阵

| 硬件子系统 / 功能 | 状态 | 驱动 / 实现机制 | 说明 |
| :--- | :---: | :--- | :--- |
| **CPU / 调频** | ✅ **完全正常** | Kryo 280 (4x Gold + 4x Silver), `cpufreq` | 8 核并发调度正常，动态节能调频已启用 |
| **内存管理** | ✅ **完全正常** | LK 动态保留内存动态映射 | 适配 6GB LPDDR4x，`memory@80000000` 零长度动态解析 |
| **UFS 存储** | ✅ **完全正常** | `ufshcd-qcom` (UFS 2.1) | ext4 根分区，开机自动扩容 (`mi6-grow-rootfs`)，udev 强制 `unmap` TRIM |
| **GPU / 显示** | ✅ **完全正常** | Freedreno Adreno 540 DRM/KMS | 启用 `msm.separate_gpu_kms=1`，支持无头 GPU 计算与渲染 |
| **USB 复合设备** | ✅ **完全正常** | ConfigFS (NCM 网络 + CDC-ACM 串口) | NCM 固定网段 `172.16.42.1` + ACM 终端 `/dev/ttyGS0` (免密 root) |
| **电池 / 充电 / 旁路** | ✅ **完全正常** | `pmi8998-charger` (`qcom_smbx`) + `qcom-battery` | 支持充放电、电量计、`charge_behaviour` 真旁路供电及 `70%–80%` 自动保护 (`mi6-battery-guard`) |
| **无线局域网 (Wi-Fi)**| ✅ **完全正常** | `ath10k_snoc` (WCN3990) | 双频 2.4G/5G，板载定标 `board-2.bin`，防崩溃 AMSDU 补丁 |
| **蓝牙 (Bluetooth)** | ✅ **完全正常** | `hci_uart` / `btqca` (WCN3990) | 固件按序安全加载，固化出厂 MAC，BlueZ 5.82 + BlueALSA |
| **扬声器外放 (Audio)** | ✅ **完全正常** | ASoC (`sdm845-sndcard`) + NXP TFA9888 | QDSP6 AFE/ASM `QUAT_MI2S_RX` -> TFA9888 双 Smart PA 立体声 |
| **双麦克风拾音** | ✅ **完全正常** | Qualcomm WCD9335 Codec | 顶部降噪麦 (`ADC5`) + 底部主麦 (`ADC3`)，硬件偏置与时钟自适应 |
| **音频软件栈 / 路由** | ✅ **完全正常** | ALSA UCM2 + `/etc/asound.conf` | 开机自启 HiFi 配置，免 `-D` 默认播放/录音，蓝牙 A2DP 自动播放 |
| **Hexagon DSPs** | ✅ **完全正常** | `qcom_q6v5_pas` / `qcom_q6v5_mss` | ADSP (音频)、SLPI (传感器)、MSS (基带/Wi-Fi) 三路协同 |
| **容器 / 虚拟化** | ✅ **完全正常** | 原生 `nf_tables` (`iptables v1.8.11`) | 完美支持 Docker、Podman、Tailscale、WireGuard |
| **系统恢复与重启** | ✅ **完全正常** | PON 寄存器直通 (`reboot-fastboot`) | 用户态一键安全进入 fastboot / recovery，绝不依赖物理按键 |

---

## 核心架构与技术创新

### 1. 深度适配的音频硬件架构（ASoC + TFA9888 + WCD9335）
- **TFA9888 Smart PA 驱动**：移植并重构了 NXP TFA9888 Codec 驱动至 Linux 7.3.x，配置 TDM 4 槽位模式 (`0x2c88` 固件校验)，打通 I2C 寄存器映射与声卡 DAPM。
- **独立 TX 录音时钟唤醒**：在设备树中打通 `"AIF1 CAP", "MCLK"` 与 `MIC BIAS` 到 `MCLK` 的级联路由，解决上游内核纯录音时 `divclk1`（19.2MHz 主时钟）与模拟偏置未上电导致录音静音的问题。
- **立体声拾音通路**：精准映射顶部麦克风（`AMIC5` / `MIC BIAS4`）与底部主麦克风（`AMIC3` / `MIC BIAS1`）。
- **ALSA UCM2 现代化配置**：适配 Debian 13 ALSA UCM2 标准，提供 `xiaomi-sagit` HiFi 配置文件，配合 `/etc/asound.conf` 实现免参数直连默认立体声扬声器与双麦拾音。

### 2. 稳定的蓝牙与音频流转系统（BlueZ + BlueALSA）
- **固化 MAC 与时序解耦**：自写系统服务 `mi6-bluetooth.service`，在芯片冷启后从基带/出厂参数提取真实公网蓝牙地址（格式如 `20:47:DA:E9:AA:03`），消除随机地址漂移。
- **蓝牙音箱功能**：预装并调优 `bluealsa` 与 `bluealsa-aplay`，支持手机（如小米 11）免 PIN/自动配对作为 A2DP Source，实时通过米 6 扬声器播放无线高保真音频。

### 3. Wi-Fi 高负载防崩溃补丁（`ath10k_snoc`）
- 在持续高速下载或高并发网络下，原厂固件在解包 AMSDU 时会导致 Hexagon DSP 发生看门狗复位。本项目集成了 `0001-ath10k-persist-split-amsdu.patch`，强制将 A-MSDU 分割转交内核处理，彻底根治基带崩溃。

### 4. 稳健的无头调试与应急救援通道
- **免密物理串口**：USB CDC-ACM 设备自动绑定串口终端 `/dev/cu.usbmodem21201`，无网络状态下插入电脑即可获取 root shell。
- **内置免按键安全重启**：在系统内提供 `/usr/local/bin/reboot-fastboot` 与 `reboot-recovery`，利用 Qualcomm PM8998 PON 软复位寄存器精确跳转，告别长按物理电源键与音量键。

### 5. PMI8998 真·旁路供电与电池保护（Bypass Charging / Idle Mode）
- **内核驱动扩展（`0004-qcom-smbx-bypass-charging.patch`）**：为上游 `qcom_smbx` 驱动新增主线标准的 `charge_behaviour`（`auto` / `inhibit-charge`）与可写 `constant_charge_current_max`（`0–3200000 uA`，`25 mA` 步进）节点。
- **硬件真旁路原理**：切换为 `inhibit-charge` 时，驱动清零 SMB2 寄存器 `CHARGING_ENABLE_CMD`（`0x1042` bit 0）切断电池充电回路，同时保持 `USBIN` 通路开启（`online=1`），继续通过 Buck 直接为主板 `VPH_PWR` 供电；实测电池电流从充电状态降至约 `12–13 mA`（`Not charging`），实现真正意义上的不伤电池旁路运行。
- **7×24 小时自动迟滞保护（`mi6-battery-guard`）**：系统守护进程默认在电量 `>= 80%` 时自动切换至 `inhibit-charge` 旁路供电，在电量 `<= 70%` 时自动恢复 `auto` 充电，避免长期插电导致锂电池鼓包衰减。

---

## 目录结构

```text
├── .github/workflows/          # GitHub Actions CI/CD 工作流
│   ├── kernel-upstream.yml     # 上游 Linux 7.3.x 内核 + 模块 + DTB 构建
│   └── rootfs.yml              # Debian 13 (Trixie) arm64 根文件系统生成
├── configs/
│   └── mi6.fragment            # 针对小米 6 定制的内核功能片段配置
├── dts/
│   └── msm8998-xiaomi-sagit.dts # 完整定制的设备树文件 (音频、GPU、DSPs、电源)
├── patches/
│   ├── 0001-ath10k-persist-split-amsdu.patch         # Wi-Fi 稳定性补丁
│   ├── 0002-pmi8998-fuel-gauge-and-charger.patch    # 充电与电量检测补丁
│   ├── 0003-tfa9888-codec.patch                     # NXP TFA9888 音频功放驱动补丁
│   └── 0004-qcom-smbx-bypass-charging.patch         # PMI8998 SMB2 真旁路供电与限流补丁
└── rootfs-integration/         # 注入 Debian 根文件系统的配置文件与守护脚本
    ├── alsa/                   # asound.conf 及 UCM2 硬件音频配置文件
    ├── bin/                    # 实用脚本 (mi6-init-bt.sh, reboot-fastboot 等)
    ├── systemd/                # 自定义 systemd 服务 (mi6-bluetooth, mi6-battery-guard 等)
    ├── udev/rules.d/           # UFS 存储 UNMAP TRIM 规则 (60-ufs-unmap.rules)
    └── NetworkManager/         # USB NCM 与 Wi-Fi 预设网络连接
```

---

## 快速上手与刷机指南

### 1. 准备工作
- 已解锁 Bootloader 的小米 6 手机一台；
- 电脑已安装 `fastboot` 与 `adb` 命令行工具；
- 从 [Releases](../../releases) 或 [GitHub Actions](../../actions) 下载最新构建产物：
  - `boot-upstream.img`（内核及引导映像）
  - `userdata-debian.simg`（Debian 13 根文件系统稀疏镜像）

### 2. 刷入系统
手机进入 Fastboot 模式（关机状态下长按 `音量下 + 电源键` 或在系统内执行 `adb reboot bootloader`）：

```bash
# 1. 刷入根文件系统到 userdata 分区
fastboot flash userdata userdata-debian.simg

# 2. 刷入内核到 boot 分区
fastboot flash boot boot-upstream.img

# 3. 重启设备
fastboot reboot
```

### 3. 连接与登录
设备开机后，将通过 Type-C 数据线提供复合调试接口：
- **USB 虚拟串口（推荐）**：
  在 macOS / Linux 上直接打开串口终端（免密自动登录 root）：
  ```bash
  screen /dev/cu.usbmodem21201 115200
  ```
- **USB NCM 虚拟网卡**：
  电脑将识别到虚拟以太网卡并自动获取 IP，可通过固定地址访问：
  ```bash
  ssh root@172.16.42.1
  # 初始默认密码: toor (建议首次登录后通过 passwd 修改)
  ```
- **Wi-Fi 局域网 SSH**：
  如配置了本地 Wi-Fi，设备将自动联网，使用局域网分配的 IP 登录：
  ```bash
  ssh root@<PHONE_IP>
  ```

---

## 音频、蓝牙与旁路供电使用示例

### 1. 测试扬声器播放与麦克风录音
系统已内置开机默认音频路由与音量校准，直接使用原生 ALSA 工具即可：
```bash
# 播放测试音频到立体声扬声器
aplay /usr/share/sounds/alsa/Front_Center.wav

# 双麦克风录音 5 秒 (CH0: 顶部麦克风, CH1: 底部主麦克风)
arecord -c 2 -r 48000 -f S16_LE -d 5 /tmp/test.wav

# 回放录制的音频
aplay /tmp/test.wav
```

### 2. 连接蓝牙设备或手机
```bash
# 进入蓝牙交互管理终端
bluetoothctl

# 扫描并连接手机或蓝牙耳机
[bluetoothctl]> power on
[bluetoothctl]> scan on
[bluetoothctl]> pair <DEVICE_MAC>
[bluetoothctl]> trust <DEVICE_MAC>
[bluetoothctl]> connect <DEVICE_MAC>
```
当手机配对成功后，在手机端播放任意音乐，音频流将自动通过 `bluealsa-aplay` 桥接并由米 6 双扬声器高保真输出。

### 3. 查看与控制旁路供电
系统默认由 `mi6-battery-guard` 按 `70%–80%` 自动切换旁路模式：
```bash
# 查看当前电量、旁路模式与实时电池电流 (uA)
cat /sys/class/power_supply/qcom-battery/capacity
cat /sys/class/power_supply/pmi8998-charger/charge_behaviour
cat /sys/class/power_supply/pmi8998-charger/status
cat /sys/class/power_supply/qcom-battery/current_now

# 查看自动保护守护日志
journalctl -u mi6-battery-guard -n 20 --no-pager

# 手动强制启用旁路供电（需先停止自动守护进程，避免在 70% 以下被自动切回充电）
systemctl stop mi6-battery-guard
echo inhibit-charge > /sys/class/power_supply/pmi8998-charger/charge_behaviour

# 恢复自动充电与守护
echo auto > /sys/class/power_supply/pmi8998-charger/charge_behaviour
systemctl start mi6-battery-guard
```

---

## 许可证与致谢

- **内核与驱动**：遵循 [GPL-2.0-only](COPYING)。
- **硬件工程灵感与基线**：致敬 [ilertnost](https://github.com/ilertnost/kernel_xiaomi_msm8998-mainline) 与 postmarketOS 社区开发者在 MSM8998 主线化所作出的先驱探索。
