# sagit-mainline

Xiaomi Mi 6（sagit / Snapdragon 835 MSM8998）→ **Debian 13 ARM64 + 最新主线内核** 移植项目。

## 目标

以最新 Linux 内核（基于 [ilertnost/kernel_xiaomi_msm8998-mainline](https://github.com/ilertnost/kernel_xiaomi_msm8998-mainline) bring-up 树，基线 7.2）重新实现社区移植成果的硬件支持水平：Wi-Fi、蓝牙、LTE、摄像头、音频、传感器、GPU、电源管理；用户空间为 Debian 13；终态为无头主机。

完整规划见 [docs/MASTER_PLAN.md](docs/MASTER_PLAN.md)。

## 构建

GitHub Actions 自动构建（push / 手动触发）：

- 内核：`ilertnost/kernel_xiaomi_msm8998-mainline` @ `ea08c09791cddbfc57c995e154c20d09738339a3` + `patches/*.patch`
- 配置：树内 `sagit_defconfig` + `configs/mi6.fragment`（USB ACM/RNDIS gadget 等）
- 产物：`Image`、`msm8998-xiaomi-sagit.dtb`、`Image-dtb`（内核槽尾随 DTB，sagit bootloader 约定）、busybox 临时 initramfs、`boot.img`（可用 `fastboot boot boot.img` 临时引导，不写分区）

## 安全与许可

- 仓库内**不含专有固件**（Adreno/WCN/modem 固件刷机时从 postmarketOS 软件包获取，见 MASTER_PLAN §1）
- 内核补丁/设备树/脚本遵循 GPL-2.0-only（与内核一致）
- 引用的社区移植包（R6）的自写模块声明 GPL-2.0，其源码不可得处本项目自行重写，不重分发其未附源的二进制

## 当前状态

- **内核版本**：Linux Upstream 7.3.5 V2（内置 `CONFIG_NF_TABLES=y` + `0002-ath10k-persist-split-amsdu.patch`）。
- **用户空间**：Debian 13 (Trixie) ARM64 原生根文件系统。
- **Hexagon 子系统**：Modem (MSS)、Sensors (SLPI)、Audio (ADSP) 全三路 Remoteproc 启动正常。
- **无线网络**：WCN3990 Wi-Fi (`ath10k_snoc`) 自动接入，高并发网络下基带 Hexagon DSP 稳定不崩溃。
- **管理通道**：USB CDC-ACM 串口（`/dev/cu.usbmodem21201` 免密 root 自动登录）+ Wi-Fi SSH（默认 IP `192.168.31.6`）双通道直通。
- **容器环境**：原生 `iptables v1.8.11 (nf_tables)` 支持 Docker 与 Tailscale。
