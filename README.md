# easi-connector

让希沃视频展台（Seewo EasiCamera 2.1.0.4410）支持第三方 USB 摄像头/展台的桥接方案。
针对悦教 YJZ-B870 壁挂展台开发，适用于任何能出现在 DirectShow 设备列表里的摄像头。

> 背景：希沃视频展台软件内置白名单校验（`CameraExtension.IsSeewoCamera`），只认希沃自家设备，
> 第三方展台接入后软件直接不显示画面。本方案通过 IL 补丁放行第三方设备，
> 并用一条零拷贝管道把任意来源的画面桥接进软件。

## 架构

```
YJZ-B870 (USB/UVC)
   │
   ▼
OBS Virtual Camera            ← 任意 DirectShow 源，OBS 负责采集
   │
   ▼
ffmpeg  (dshow → rawvideo bgr24)
   │  匿名管道，无中间文件
   ▼
AkVCamManager stream          ← 把管道数据喂给虚拟摄像头
   │  共享内存 + IPC
   ▼
AkVCamAssistant 服务          ← AkVCam 9.1.3 + 句柄泄漏补丁
   │
   ▼
AkVCamVideoDevice0            ← DirectShow 虚拟设备 "EASI-Bridge Camera"
   │
   ▼
EasiCamera (IL patched)       ← IsSeewoCamera 强制返回 true，白名单放行
```

数据链路全程内存直通，无落盘、无二次编码。

## 组件

| 路径 | 说明 |
|---|---|
| `tools/Patcher.cs` | IL 补丁器源码（Mono.Cecil）：把 `CameraExtension.IsSeewoCamera(DsDevice)` 方法体替换为 `return true` |
| `tools/patch-business.ps1` | EasiCamera.Business 补丁：停用虚拟摄像头名过滤（见"补丁明细"） |
| `tools/patch-wpfmt.ps1` / `tools/patch-wpfmt2.ps1` | WPFMediaKit 补丁：裸 YUV 接图修复（见"补丁明细"） |
| `tools/verify-patches.ps1` | 核对 `connector/patched/` 三个补丁 DLL 与补丁点一致（`-OrigDir` 可指定原始 DLL 目录） |
| `connector/patched/` | 补丁后的 EasiCamera.Api / Business / WPFMediaKit DLL（**不入库**，见下方"关于版权"） |
| `tools/build-release.ps1` | 把安装所需脚本/文件镜像到 `release\`（自检硬编码路径残留 + PS1 BOM 补齐），zip 后挂 GitHub release |
| `connector/patch-all.ps1` | 一键自动化：编译 Patcher → 生成补丁 DLL → 部署（幂等，克隆即用） |
| `connector/install.ps1` | 把补丁 DLL 覆盖到展台软件安装目录（自动定位，首次备份 `.orig`） |
| `connector/uninstall.ps1` | 还原全部 `.orig` 备份，恢复原版 |
| `connector/bridge.ps1` | 桥链启动器（拉起 run-bridge.cmd，可 `-Hidden` 后台运行） |
| `connector/run-bridge.cmd` | 管道泵：ffmpeg → AkVCamManager stream |
| `tools/deploy-akvcam913.ps1` | AkVCam 9.1.3 一键部署（注册 DLL / 服务 / 建设备） |
| `tools/akvcam913/` | 补丁版 AkVCam 9.1.3 二进制（x86/x64） |
| `tools/monitor-easicam.ps1` | 进程资源监控（CSV：句柄/CPU/内存/GDI/USER/GPU，抓崩溃退出码） |
| `tools/monitor-viewer.py` | 实时图表 GUI（matplotlib，四面板联动） |

## AkVCam 句柄泄漏补丁

上游 [akvirtualcamera](https://github.com/webcamoid/akvirtualcamera) 9.1.3 的
`messageserver.cpp` 中，客户端每发一条消息都用 `CallNamedPipeA` 新建一条管道连接，
服务端则为每条连接新开一个线程实例。帧传输路径下每帧一条消息 → **~63 句柄/秒的持续泄漏**
（实测 20 分钟破 4 万句柄），并伴随 `abort(0x40000015)` 崩溃。

本仓库的补丁（`dshow/PlatformUtils/src/messageserver.cpp`）将客户端改为
**每管道名一条持久连接 + `TransactNamedPipe` 原子收发**，断线自动重连：

- 服务端零改动，协议字节格式零改动
- 补丁后实测：句柄曲线水平（2 小时零增长），CPU 占用同步下降，无延迟无卡顿
- 上游 9.4.1 已将 IPC 整体重写为 TCP 持久连接，本补丁是对 9.1.3 的 backport，
  供被锁死在 9.1.3 的场景使用

补丁文件见 `patches/`：`akvcam-9.1.3-messageserver.cpp` 为补丁后全文件，`akvcam-9.1.3-leak.patch` 为对应 diff。

从源码重新编译补丁版：

```bat
:: 1. 获取上游源码（tag v9.1.3），放到 notes\akvirtualcamera-9.1.3
:: 2. 应用补丁：用 patches\akvcam-9.1.3-messageserver.cpp 覆盖
::    notes\akvirtualcamera-9.1.3\dshow\PlatformUtils\src\messageserver.cpp
:: 3. 编译
cmake -S notes\akvirtualcamera-9.1.3 -B build913-x86 -G "Visual Studio 17 2022" -A Win32
cmake --build build913-x86 --config Release
cmake -S notes\akvirtualcamera-9.1.3 -B build913-x64 -G "Visual Studio 17 2022" -A x64
cmake --build build913-x64 --config Release
```

产物替换 `tools/akvcam913/{x86,x64}/` 后重跑 `deploy-akvcam913.ps1`。

## EasiCamera DLL 补丁明细

需要补丁的 DLL 共 3 个（补丁点 4 处）。`connector/patched/` 下的产物一律从
你自己安装目录的原始 DLL 生成；`tools/verify-patches.ps1` 可随时核对产物完整性。

### 1. EasiCamera.Api.dll — 白名单放行（patch-all.ps1 全自动）

`CameraExtension.IsSeewoCamera(DsDevice)` 方法体整体替换为 `return true`。
软件用它过滤 DirectShow 设备，非希沃设备一律不显示；放行后 EASI-Bridge Camera
及任意第三方摄像头均可被识别。

### 2. EasiCamera.Business.dll — 停用虚拟摄像头名过滤（patch-all.ps1 自动）

`GlobalDeviceViewModel` 的设备枚举私有方法里有两处按设备名剔除虚拟摄像头的逻辑
（一处过滤 DirectShow 枚举结果，一处从列表兜底 Remove；原始反编译见
`analysis/src/EasiCamera.Business/EasiCamera/Business/GlobalDeviceViewModel.cs:1176` 与 `:1220`）：

```csharp
dsDevice.Name.ToLowerInvariant().Contains("virtual")
    || dsDevice.Name.ToLowerInvariant().Contains("smartclass vcamera")
```

OBS Virtual Camera / AkVCam 命中即被剔除。补丁（`tools/patch-business.ps1`）递归
遍历所有类型（含编译器生成的闭包类 `<>c`），把全部 4 处 ldstr 改名：
`"virtual"` → `"virtual_x"`、`"smartclass vcamera"` → `"smartclass vcamera_x"`，
使 Contains 永不命中，虚拟设备得以留在设备列表里。

### 3. WPFMediaKit.dll — 裸 YUV 设备接图修复（patch-all.ps1 自动，两步补丁）

`VideoCapturePlayer.SetupGraph` 按采集格式分支建 Graph：

| 格式分支 | 原行为 | 补丁后 |
|---|---|---|
| MJPG caps | `AddLavDecoder`（LAV 软解） | 保留（B870 真机 MJPG 路径依赖） |
| RGB24/32 | `AddColorSpaceConverter` | 保留 |
| 其他（裸 YUV：NV12/YUY2 等） | `AddLavDecoder` | **改为 `AddColorSpaceConverter`** |

OBS Virtual Camera 输出裸 YUV，LAV 解码器不接受裸 NV12/YUY2 →
`VFW_E_NOT_CONNECTED` 灰屏；WPFMediaKit 自带的 ColorSpaceConverter 软转 filter
支持 raw 输入。`tools/patch-wpfmt.ps1` 替换 SetupGraph 内**最后一个**
AddLavDecoder 调用（MJPG 分支首处不动）。

此外 `SetupGraph` 的本地函数 `g__SetDefaultMediaSubType|132_0` 在
DisableMjpegAsDefault 分支原本传 `Guid.Empty`（沿用设备默认 subtype，裸 YUV
设备多为 NV12，系统 CSC 不认）→ 改为 `MediaSubType.YUY2` 让协商走通
（`tools/patch-wpfmt2.ps1`，替换方法体内第一处 `Guid.Empty`）。B870 真机路径
（EnableForceMjpegDefault → MJPG 分支）不受影响。

### 复现命令

> 日常无需手动执行：`patch-all.ps1` 已集成三个 DLL 的补丁生成（步骤 4b，
> 时间戳增量幂等）。以下命令仅在需要手动重做单步时使用。

原始 DLL 来源：展台安装目录（`install.ps1` 首次部署时自动备份为 `.orig`），
或解包的安装包 `easi-soft\EasiCamera_2.1.0.4410\Main\`。release 解压环境没有
`easi-soft\` 时，给补丁脚本显式传 `-SearchDir <展台安装目录>`（解析依赖程序集用）。

```bat
:: Business：从原始 DLL 生成
powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch-business.ps1 -InDll <原始 EasiCamera.Business.dll> -OutDll connector\patched\EasiCamera.Business.dll

:: WPFMediaKit：两步顺序执行
powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch-wpfmt.ps1 -InDll <原始 WPFMediaKit.dll> -OutDll connector\patched\WPFMediaKit.dll
powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch-wpfmt2.ps1 -InDll connector\patched\WPFMediaKit.dll -OutDll connector\patched\WPFMediaKit.dll.new
move /y connector\patched\WPFMediaKit.dll.new connector\patched\WPFMediaKit.dll

:: 核对三个补丁 DLL
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-patches.ps1
```

补丁脚本自带断言（找不到目标串/调用点即 FAIL），不会产出静默跑偏的补丁 DLL。

## 安装

前提：

- Windows 10/11，管理员权限
- 已安装希沃视频展台 2.1.0.4410
- 已安装 [OBS Studio](https://obsproject.com/)（自带 OBS Virtual Camera）
- 已准备 ffmpeg（`tools/ffmpeg/ffmpeg-9.0.1-essentials_build/`）

一键安装（推荐，自动完成 1-2 步：编译 Patcher → 从原始 DLL 生成补丁 → 覆盖到展台安装目录）：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File connector\patch-all.ps1 -FirstInstall
```

- `-FirstInstall` 表示附带第 3 步部署 AkVCam 9.1.3（需管理员）；日常更新补丁时去掉该开关
- 仅生成补丁 DLL 不部署：加 `-SkipDeploy`
- 幂等：Patcher.exe 与补丁 DLL 按时间戳增量重做，重复运行无副作用

手动分步（等价）：

```bat
:: 1. 生成补丁 DLL（共 3 个）：
::    Api       → 需自行编译 Patcher.cs（引用 Mono.Cecil）：
::      Patcher.exe <原始 EasiCamera.Api.dll> connector\patched\EasiCamera.Api.dll
::    Business / WPFMediaKit → 命令见上方"补丁明细 → 复现命令"

:: 2. 应用 IL 补丁到展台软件
powershell -NoProfile -ExecutionPolicy Bypass -File connector\install.ps1

:: 3. 部署 AkVCam 9.1.3（管理员）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-akvcam913.ps1

:: 4. 启动桥链
powershell -NoProfile -ExecutionPolicy Bypass -File connector\bridge.ps1
```

然后打开希沃视频展台，设备选择 **EASI-Bridge Camera**（AkVCamVideoDevice0）即可出画面。

卸载：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File connector\uninstall.ps1
```

## 监控

```bat
:: 采样写入 logs\easicam-monitor-v2.csv，-IntervalSec 采样间隔，-MaxHours 上限
powershell -NoProfile -ExecutionPolicy Bypass -File tools\monitor-easicam.ps1

:: 另开窗口看实时图表
python tools\monitor-viewer.py
```

停止监控：`type nul > logs\monitor-easicam.stop`

## 已知坑

- **虚拟设备 caps 必须保持 30fps**：25fps caps 会让希沃软件堆损坏
  （`0xc0000374`，表现为窗口透明）。桥链传输帧率默认 19fps（OBS Virtual Camera
  实际产量 ~25fps），与 caps 无关。
- x86 版 `AkVirtualCamera.dll` 需在 MTA 环境注册（脚本已处理）。
- 所有脚本按 `$PSScriptRoot` 相对定位，任意目录解压即可用；仅 `run-bridge.cmd`
  依赖 `tools\ffmpeg\ffmpeg-9.0.1-essentials_build\`（自备 ffmpeg 放入该路径）。

## 关于版权

- 希沃视频展台（EasiCamera）版权归**广州视源电子科技（CVTE/Seewo）**所有。
  本仓库**不包含、不分发**其安装包及任何二进制文件；`connector/patched/` 下的补丁 DLL
  （含 Business / WPFMediaKit）请用 `tools/Patcher.cs` 与 `tools/patch-*.ps1`
  从你自己安装的合法副本生成，仅限个人研究/教学使用。
- [AkVCam/akvirtualcamera](https://github.com/webcamoid/akvirtualcamera) 基于 GPLv3，
  作者 Gonzalo Exequiel Pedone；本仓库的修改同样以 GPLv3 开源。
- ffmpeg、OBS Studio 版权归各自原作者所有。
