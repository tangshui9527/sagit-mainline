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

M0/M1 阶段：CI 编译打通 + `fastboot boot` 内核首启验证（仅临时引导，不触碰持久分区）。
