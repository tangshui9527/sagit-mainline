# 小米 6 (sagit) M2 阶段技术交接文档：Debian 13 rootfs 真机引导与基线确立

**文档版本**：v2.0（M2 阶段 100% 完成验收版）  
**完成日期**：2026-11-20  
**接续文档**：《小米 6 主线 Linux 7.2 移植项目技术交接文档》（HANDOVER.md，M1/M1.5 阶段）  
**代码仓库**：`tangshui9527/sagit-mainline`（master）  
**手机当前状态**：🟢 **正常运行 Debian 13 (Trixie) 裸机系统**。UFS `/dev/sda17`（52GB 自动扩容）、Linux 内核 `7.2.11-gea08c09791cd`、USB Gadget（ACM 串口 + NCM/RNDIS 网络）、SSH 免密登录（root & mi6）及串口控制台全部通过真机物理验证。  
**本机局域网**：手机接在笔记本（Arch Linux，用户 tang，`192.168.31.90`；手机 USB 虚拟网卡 `172.16.42.1/16`，宿主机 `172.16.42.2/16`）。

---

## 1. M2 阶段目标与最终达成度（100% 达成）

| 目标 | 状态 | 验证证据 |
|---|---|---|
| CI 自动构建 Debian 13 rootfs | ✅ 完成 | `rootfs.yml`，生成完整 sparse ext4 rootfs 及 boot-debian.img |
| Debian rootfs 刷入 UFS userdata | ✅ 完成 | `fastboot -S 100M flash userdata userdata-debian.simg` 完整写入 8/8 chunks（620s，0 丢包 0 中断），真机自动扩容至 52GB |
| Debian 内核冷引导（boot-debian.img） | ✅ 完成 | `fastboot flash boot boot-debian.img` 写入 `boot` 分区，手机长按电源键冷启动即直接引导进 Debian 13，无需借助 fastboot tether |
| 复合 USB Gadget 稳定枚举 | ✅ 完成 | dwc3 复合配置（ACM `/dev/ttyACM0` + NCM `usb0` + RNDIS `usb1`），120s 容错重试循环彻底解决异步探测竞态 |
| 局域网与 SSH 双用户登录 | ✅ 完成 | Host `enp0s20f0u5i4` 静态 IP `172.16.42.2/16`，ping 延迟 0.28ms；`root` 与 `mi6` 均通过 SSH 密钥即时登录，`mi6` 享有无密码 sudo 权限 |
| login/PAM 崩溃与串口控制台 | ✅ 完成 | 定位到 mmdebstrap 极简构建缺失 `login` 与 `/etc/pam.d/login`。已通过 apt 官方安装 `login` 包并配齐 PAM，`/dev/ttyACM0` 自动登录 root shell |

---

## 2. 关键产物与验证环境

| 产物 | 规格/属性 | 运行状态 |
|---|---|---|
| **操作系统** | Debian GNU/Linux 13 (trixie) aarch64 | 运行于 `/dev/sda17` (ext4, 52GB 容量，占用 738MB) |
| **主线内核** | Linux 7.2.11-gea08c09791cd | SMP PREEMPT，ilertnost 树基线，boot 分区裸机直接引导 |
| **IP 规划** | 手机端：`172.16.42.1/16` (usb0/usb1) | 宿主端：`172.16.42.2/16` (enp0s20f0u5i4, RNDIS) |
| **串口终端** | 宿主 `/dev/ttyACM0` -> 手机 `/dev/ttyGS0` | 115200 8N1，root autologin 交互式终端 |
| **SSH 密钥** | `/home/tang/sagit-flash/mi6key` | 支持 `root@172.16.42.1` 与 `mi6@172.16.42.1` |

---

## 3. 核心技术攻坚与避坑记录

### 3.1 稀疏镜像（Sparse Image）与 ABOOT 180 秒看门狗
- **现象**：在直接刷写 8GB sparse rootfs 时，ABOOT 在写入第 2 chunk 时断连，报错 `Status read failed (No such device)`。
- **机制机理**：
  - `userdata-debian.simg` 包含 694.9MB 真实数据和 7,497.1MB 零填充块（`CHUNK_TYPE_FILL`）。
  - 小米 6 的高通 Little Kernel (ABOOT) 缺少 UFS discard/trim 支持，在写入填充块时采用纯软件单块写零循环（约 15–20 MB/s），需要 6–8 分钟。
  - ABOOT 对每次 Fastboot Bulk 事务设有 180 秒硬件看门狗。
  - **严重冲突源**：宿主机若运行 `watch -n 1 fastboot devices`，每秒发起 EP0 控制传输，打断了 ABOOT 单线程 USB 状态机与写循环，触发看门狗复位。
- **解决方案**：
  1. 必须彻底杀死宿主机上的所有后台 fastboot 轮询进程。
  2. 使用 `fastboot -S 100M flash userdata userdata-debian.simg`，ABOOT 顺利处理全部 8 个分块，总耗时 620 秒，无看门狗超时。

### 3.2 串口登录崩溃（Login Loop）根本原因与修复
- **现象**：`serial-getty@ttyGS0` 反复重启，提示 `mi6 login: root (automatic login)` 后立刻退出，日志显示退出码 1。
- **排查与根因**：
  1. mmdebstrap 采用极简配置构建，缺少官方 `login` 软件包，系统中根本没有 `/usr/bin/login` 可执行文件。
  2. `/etc/pam.d/login` 配置文件缺失，PAM 认证栈直接返回错误。
  3. `agetty -a root -l /bin/bash` 方式会将 `root` 作为参数传给 bash，导致 bash 报 `root: root: Is a directory` 退出。
- **终局修复**：
  1. 建立临时 `/bin/login` 引导脚本进入交互式 shell。
  2. 通过宿主机搭建轻量 HTTP 代理转发网络流量至手机，运行 `apt-get install -y login util-linux bash-completion` 安装官方 login 包。
  3. 恢复官方 `/etc/pam.d/login`，测试 `/dev/ttyACM0` 交互完全正常。

### 3.3 双网卡反向路径过滤与非对称路由
- **现象**：USB 复合配置同时导出 NCM (`usb0`) 和 RNDIS (`usb1`) 且配置同一子网 `172.16.42.1/16` 时，宿主机偶尔出现 ping 通但 TCP SYN 握手超时。
- **根因**：Linux 内核 `rp_filter`（反向路径过滤）在多网卡同网段时丢弃跨网卡返回的非对称响应包。
- **修复**：宿主机保持 `enp0s20f0u5i4` (RNDIS) 单独配置 `172.16.42.2/16`，断开未使用的 NCM 网卡，网络延迟稳定在 0.28ms，丢包率为 0%。

---

## 4. fastfetch 实测系统信息输出

```
        _,met$$$$$gg.          root@mi6
     ,g$$$$$$$$$$$$$$$P.       --------
   ,g$$P""       """Y$$.".     OS: Debian GNU/Linux 13 (trixie) aarch64
  ,$$P'              `$$$.     Host: Xiaomi Mi 6
',$$P       ,ggs.     `$$b:    Kernel: Linux 7.2.11-gea08c09791cd
`d$$'     ,$P"'   .    $$$     Uptime: 12 mins
 $$P      d$'     ,    $$P     Packages: 202 (dpkg)
 $$:      $$.   -    ,d$$'     Shell: sshd-session: root@notty
 $$;      Y$b._   _,d$P'       Display (Unknown-1): 1080x1920
 Y$$.    `.`"Y$$$$P"'          CPU: msm8998 (8)
 `$$b      "-.__               Memory: 282.13 MiB / 3.54 GiB (8%)
  `Y$$b                        Swap: Disabled
   `Y$$.                       Disk (/): 737.58 MiB / 51.69 GiB (1%) - ext4
     `$$b.                     Locale: C
       `Y$$b.
         `"Y$b._
             `""""
```

---

## 5. M3 阶段工作规划（外设与硬件子系统启用）

M2 基础平台已完全就绪，正式开启 M3 阶段（硬件与外设对齐）：

1. **Wi-Fi 与蓝牙（WCN3990）**：
   - 启用 `qrtr-ns` 与 `pd-mapper`，加载 Modem/WLAN 依赖的远程处理服务。
   - 验证 `ath10k_snoc` 固件加载与 `wlan0` 网卡唤醒，实现手机独立 Wi-Fi 连接。
2. **GPU 与显示输出（Adreno 540）**：
   - 安装 `mesa-va-drivers`, `mesa-vulkan-drivers`, `libgl1-mesa-dri`。
   - 验证 freedreno 与 DRM/KMS 驱动，测试 DSI 命令模式面板刷新。
3. **音频与传感器**：
   - 推进 WCD9335 + TFA9888 音频配置及 SLPI 传感器桥接。
