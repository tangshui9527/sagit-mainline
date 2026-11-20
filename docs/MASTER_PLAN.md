# 小米 6 Debian 13 主线移植总体规划（v2）

日期：2026-11-19 · 状态：需求确认版 · 取代 PHASE2_PLAN.md §8 的执行路线
前置：`AUDIT_REPORT.md`（包审计）、`PHASE2_PLAN.md`（内核层证据与验收方法论，继续有效）

## 0. 需求定义（用户确认）

把小米 6（Snapdragon 835 / sagit）改造成 **Debian 13 ARM64 Linux 主机**：

1. **最新内核**：不沿用作者的 6.0 内核，以当前主线/近 LTS 为基线重新移植
2. **作者的 Ubuntu 项目作为参考**：研究并复现其成果，他的内核与驱动作为参照（行为 oracle）
3. **硬件支持对齐作者水平**：Wi-Fi、蓝牙、LTE、GPS、摄像头、音频、传感器、GPU、电源管理
4. **用户空间 = Debian 13 ARM64**，不使用 Ubuntu
5. **渐进验证**：先不破坏原系统构建测试，逐步验证启动和各硬件，全部通过后才持久化
6. **终态**：拆除屏幕，成为无头 Linux 主机

与旧计划的关键差异：6.0 黑盒内核降级为"参考/回退项"；主线内核 bring-up 升级为唯一前进路线；ACM gadget 由"卡点"变成新内核的自然产物。

## 1. 资产盘点（已验证的起点）

| 资产 | 用途 | 证据位置 |
|---|---|---|
| 作者 rootfs 快照（解包，61,034 文件） | 行为 oracle：sysfs 路径、dmesg 预期、用户空间配置 | `analysis/rootfs-x2/` |
| 作者内核 config-6.0.0-mi6-suspend1 | 新内核配置的语义参照（1400 项，显示哪些驱动必须开） | 同上 `/boot/` |
| 作者 DTB（反编译 DTS） | 新内核 DTS 的数值来源（reg/电压/GPIO/pinctrl 事实） | `analysis/dtb/sagit.dts` |
| 作者自写模块二进制（GPL-2.0 声明） | imx386/ak7371/mi6-smgr/extcon 的反汇编参照 + 向作者索源的法律依据 | `rootfs-x2/lib/modules/…/updates,extra/` |
| 完整固件（83 MB，postmarketOS 来源） | 新内核直接复用（固件与内核版本无关） | `rootfs-x2/lib/firmware/` |
| 刷机向导 flash-mi6.py | 安全框架：备份/校验/临时引导逻辑直接复用 | `extracted/…/flash-mi6.py` |
| **ilertnost/kernel_xiaomi_msm8998-mainline**（GitHub，2026-10 活跃） | **新内核 bring-up 基线首选**：真机踩坑记录（cpufreq OSM/PLL、DPU cmd-mode、a540、gpucc、WLED），桌面已在真机跑通 | github.com/ilertnost/… |
| 主线 sagit DTS（v6.3 起合入，后续持续演进） | 新内核设备树起点 | upstream arch/arm64/boot/dts/qcom/ |
| Marekkon5/msm8998-mainline（GitLab，停更于 6.1） | 历史补丁参考（作者 6.0 基线的上游） | gitlab.com/… |
| Debian 13 无头骨架（249 MB） | 用户空间基底（内核无关，直接沿用） | `debian13/rootfs/` |

**关于作者源码**：自写模块按 `docs/THIRD_PARTY.md` 声明为 GPL-2.0-only（sns-reg 为 GPL-3.0-or-later）。分发二进制而无完整对应源码不符合 GPL 义务——**可通过包内联系方式（如有）或发布渠道向作者索取源码**；索取未果则依 GPL 原则不应继续分发其模块，自研重写（本项目计划即为重写路线）。

## 2. 内核基线决策

**推荐：以 ilertnost bring-up 树为起点、主线为主干的双轨合并策略。**

```
主线（追踪 latest LTS，如 6.18.y）
  └─ + ilertnost 的真机修复集（cpufreq/DPU/adreno/gpucc/WLED，按 cherry-pick 引入并逐个真机验证）
  └─ + msm8998-mainline(6.1) 中主线尚未吸收的补丁（逐个评估）
  └─ + 本项目自写驱动（imx386、ak7371、extcon、传感器桥、充电仲裁）
  └─ + xiaomi-sagit DTS 增强（从作者 DTB 反编译提取定制节点）
```

理由：ilertnost 树已用真机验证了最难踩的坑（性能集群 PLL、DPU 命令模式、GPU 抢占），纯主线起点会重复踩一遍；但其仓库不是长期维护承诺，所以主干定为主线 LTS，他的修复作为补丁集管理。内核构建环境用上游推荐方式（Linux 主机 aarch64 交叉 gcc 或 Alpine musl 链均可）。

新内核 bootimg 打包方式不变：`mkbootimg --kernel Image+DTB(尾随) --page_size 4096 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --second_offset 0xf00000 --tags_offset 0x100 --board sagit`；ACM/NCM gadget 直接开 `CONFIG_USB_CONFIGFS_ACM=y`。

## 3. 硬件对齐矩阵（新内核路线）

状态标注：🟢 主线应已有（M0 核实）｜🟡 主线有但需适配/补丁｜🔴 需自研（参照作者二进制/索源）｜❓ 未确认

| 子系统 | 状态 | 新内核路线 | 参照物 |
|---|---|---|---|
| UFS 存储 | 🟢 | 主线 msm8998 ufs+qmp-phy 成熟 | 作者 rootfs 即证 |
| USB host/gadget | 🟢 | 主线 dwc3；configfs 加 ACM/NCM/RNDIS | mi6-usb-gadget 脚本 |
| Wi-Fi（WCN3990 snoc） | 🟡 | 主线 ath10k-snoc 直接用；作者补丁针对 6.0 时代的 RX/A-MSDU bug，**先验证是否已被上游修复，未修再移植** | 作者 ath10k 二进制 + HARDWARE_TEST.json 验收口径 |
| 蓝牙（WCN3990 hci_uart+qca） | 🟢 | 主线 hci_qca + qca/*.zst 固件 | 作者 btqca 配置 |
| LTE（q6v5-mss + IPA + rmnet） | 🟡 | 主线 q6v5/qrtr/rmtfs/pd-mapper；IPA v3（msm8998）主线支持状态 M0 核实，缺则移植/降级为 rmnet 不走 IPA | 作者 usr/local/src/mi6-cellular（含 libqmi/ModemManager 版本锚点） |
| GPS | ❓ | M0 核实主线 gnss 子系统对 Qualcomm GNSS（经 q6/qrtr）支持；缺则经 ModemManager AT/qmi 通道出位置 | 作者包未见 gnss 配置 → 未知项 |
| 显示（DPU+DSI+jdi-fhd-r63452 面板） | 🟡 | 面板驱动主线已有（panel-jdi-fhd-r63452）；DPU cmd-mode 参考 ilertnost 修复 | 作者 DTB 显示节点 + ilertnost 提交 |
| 触摸（Synaptics RMI4） | 🟢 | 主线 rmi4-i2c 直接用 | 作者 DTB |
| GPU（Adreno 540） | 🟡 | 主线 drm/msm a5xx + freedreno 用户空间；参考 ilertnost（preemption/gpucc/OPP） | 作者 graphics-guard 行为 |
| 音频（WCD9335 + TFA9888） | 🟡 | 主线 wcd9335(slimbus)+q6v5 ASP；TFA9888 主线 tfa989x 覆盖度 M0 核实，缺则扩展 | 作者 snd-soc-tfa98xx 二进制 + tfa98xx DSP .cnt 固件 |
| 电池/电量计 | 🟢 | 主线 qcom_fg + rradc | 作者 sysfs 路径 |
| 充电（PMI8998 + QC/HVDCP） | 🟡/🔴 | 主线 charger 驱动对 pmi8998 的覆盖 M0 核实；QC 仲裁逻辑参考作者 mi6-charger-data-mode（用户空间可重写） | 作者脚本 + mi6-hvdcp.conf |
| USB 角色仲裁 extcon | 🔴 | 重写小驱动或简化为 userspace（typec/extcon 节点监控） | mi6-pmi8998-extcon.ko |
| 相机（IMX386+AK7371+CCI+CAMSS） | 🔴 | 主线 camss(msm8998) M0 核实版本；imx386 V4L2 子设备驱动自研（模板：主线 imx355/imx290）；ak7371 对焦参照主线 ak7375 驱动加新 compatible | 作者 imx386.ko/ak7371.ko + DTB 节点 + camera-compat 脚本 |
| IMU（SLPI SNS→IIO） | 🔴 | 最重自研项：qrtr SNS 客户端 + 注册表（sns-reg）+ IIO 桥。降级选项：先不做，IMU 独立里程碑 | mi6-smgr.ko + sns-reg + mi6-imu 监控界面 |
| 传感器其余（接近/光/霍尔） | ❓ | M0 对照作者 DTB 枚举后逐项定 | 作者 DTB |
| 电源管理/休眠 | ❓→🟡 | 6.0 版本名暗示 suspend 是作者重点；新内核 msm8998 suspend 状态未知，作为独立里程碑真机验证 | 作者"两小时观察"记录 |
| 性能（cpufreq/CPR） | 🟡 | 参考 ilertnost OSM/PLL 修复 | 其提交日志含实测数据 |

## 4. 用户空间（Debian 13）

- 基底沿用已组装骨架（`debian13/rootfs/`），内核层随新内核重生成
- 分层原则：内核/固件/DTB 与发行版解耦；发行版只装 Debian 官方包
- 移植期需要显示与桌面调试（GNOME 可选装 Debian 版），**终态无头**：default.target=multi-user、无 gdm
- 需要的 Debian 包补齐：mesa/freedreno、ModemManager/NetworkManager/wpasupplicant、qrtr/pd-mapper/rmtfs/tqftpserv、gpsd（如走独立 gnss）、iio-sensor-proxy、pipewire+alsa（音频验证期）、bluez、qmi 工具
- 作者的集成脚本（usb-gadget/grow-rootfs/charger 仲裁）按需移植为 Debian 版（脚本均无发行版绑定）

## 5. 阶段计划（M0–M7，含验收门槛与回滚）

**M0 主线基线核查（1–2 天，零设备风险）**
- clone 主线 + ilertnost 树，跑 `git log --oneline arch/arm64/boot/dts/qcom/msm8998*`、逐项核实 §3 的 🟡/❓ 项（camss 8998、IPA、gnss、pmi8998 charger、tfa989x 覆盖、面板驱动）
- 产出：子系统主线上下表 v1 + 新内核 config 草案（以作者 config 为语义模板）
- 门槛：每个子系统都有明确"用主线/打补丁/自研"结论

**M1 内核首启（真机，已完成 ✅）**
- 构建 Image+DTB+initramfs，`fastboot boot` 及裸机引导验证通过。
- 验收：内核日志到 switch_root、UFS 可挂载、串口/USB 设备枚举正常。

**M2 基础平台与持久化（真机，已完成 ✅ 100%）**
- UFS 读写、52GB rootfs 自动扩容、boot 分区持久化裸机冷启动。
- 复合 USB gadget（ACM 串口 + NCM + RNDIS）、双用户 SSH 密钥免密登录、sudo 无密码特权。
- 官方 `login` 及 PAM 认证栈安装就绪，串口 `/dev/ttyACM0` 自动登录 root 交互控制台。

**M3 外设与硬件子系统（真机，当前进行中 🚀）**
- Wi-Fi 与蓝牙（WCN3990 / ath10k-snoc / hci_qca）、qrtr / pd-mapper。
- DPU+面板+触摸点亮、freedreno GPU 加速测试。
- 门槛：Wi-Fi 稳定连接，GPU 硬件加速与显示正常

**M4 LTE/GPS 与音频**
- ModemManager 拨号、GPS 定位、音频回路（听筒/扬声器/麦克风，对照作者"用户听到声音"标准）
- 门槛：与作者验收口径对齐

**M5 相机与传感器（自研驱动主战场）**
- camss+CCI 链路 → imx386 出图（对照作者 camera-compat 行为）→ ak7371 对焦 → IMU 桥（如做）
- 每个驱动独立里程碑：先模块加载 → v4l2-ctl 出帧 → 应用集成
- 门槛：后摄拍照 + IMU 数据流；前摄/长焦为 P2（作者也未完成）

**M6 持久化（用户书面确认后）**
- 复用 flash-mi6.py 备份逻辑存原 boot/recovery → mkfs（UUID 固定）→ img2simg → flash
- 冷启动全表回归（M2–M5 全部项目）
- 门槛：冷启动通过 + 原分区备份哈希在手

**M7 无头化交付**
- default.target=multi-user、移除显示管理、验证拔屏后启动不卡（console 回退到 USB gadget 串口/网络）
- 30 天日常运行观察（对照作者"两小时观察未完成"的教训）
- 终态：拆屏，机内仅留 USB-C 供电与数据

**贯穿纪律**（沿用 android-mainline-port skill）：一次只改一个变量；每个结论带内核提交号；失败记录不删；技术债表统一登记；上机当天写结果文档。

## 6. 风险登记

| 风险 | 影响 | 对策 |
|---|---|---|
| 新内核 msm8998 某子系统远落后于作者 6.0 补丁集 | 对齐作者水平延期 | M0 逐项核实后再定里程碑顺序；ilertnost 树缩短踩坑时间 |
| 作者自写驱动无源码 | 相机/IMU/excon 需纯自研 | 向作者 GPL 索源（合法权利）；反汇编二进制作为行为 oracle；imx386 用主线 imx355 模板重写 |
| ath10k 补丁依赖未验证 | Wi-Fi 短板 | M2 真机压力测试优先验证，未修复则 backport 作者补丁思路 |
| suspend 在新内核回归 | 休眠功能缺失 | 独立里程碑；最坏情况登记为已知限制（作者也未完成完整验收） |
| bring-up 周期长（数周至数月） | 预期管理 | M0–M2 独立于相机/IMU，先让"Debian 主机"可用，长尾硬件按里程碑推进 |
| 用户数据丢失 | 不可逆 | M6 前不触碰 userdata；确认流程 + TWRP 备份；原 boot/recovery 哈希留档 |

## 7. 立即可执行的第一步

1. `git clone` 主线内核 + ilertnost 树（Linux 构建主机）
2. M0 核查清单跑完，产出子系统主线上下表
3. 用作者 config 模板 + 主线 defconfig 生成新内核 config，出第一个 Image
4. Debian 骨架已有，等新内核出来重生成 initramfs → `fastboot boot` 首启

（原 6.0 黑盒内核方案作为回退预案保留：若 M1/M2 受阻，可先用它跑通 Debian 无头主机，不影响最终目标。）
