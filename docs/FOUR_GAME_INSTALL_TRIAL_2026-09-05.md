# 四游戏真实安装试验

日期：2026-09-05。用户授权先删除原游戏，测试四款国服的重新安装。这里只记录实际试验，不代表四游戏原生界面已经交付。

## 环境和恢复情况

- macOS 27 beta / Apple M5 Pro；复用固定 CrossOver Wine 11.0-1 + DXMT 0.80 二进制。
- 官方下载后台：miHoYo Launcher 1.18.0.380；独立 `Experiments/hoyoplay-20260904/prefix`；临时调试口仅监听 `127.0.0.1:19222`。这是研究控制入口，不是厂商承诺的生产 API。
- 原 `/Users/example/Games/MacGameBridge/Genshin Impact` 曾按授权删除，未进入废纸篓，无完整备份。现已完成官方重新下载和独立完整清单校验，用排他原子 rename 从 trial 恢复到该原路径。删除前的配置、pkg_version、managed marker、应用偏好保存在 `LocalRuntimes/Experiments/install-reset-20260905/`。原神 Wine prefix 和账号环境保留；启动验证使用既有环境。
- 新安装均使用 `/Users/example/Games/MacGameBridge/Trials/` 下指定的独立目录；不放进 Wine C 盘，不创建快捷方式，只选官方语音列表中的 zh-cn。
- 四款无法同时容纳在本机剩余空间中。用户已明确选择“分批测试，最终保留原神，清理其他测试安装”；星铁、原神开始前仍须检查余量，不清理范围外目录。

## 验收表（随实际结果更新）

| 游戏 | 官方安装/校验 | 独立完整清单校验 | 实际启动 | 未完成 |
| --- | --- | --- | --- | --- |
| 崩坏 3 国服 9.0.0 | success，下载 31,194,511,779 bytes | 1,056 文件 / 34,815,890,010 bytes，全部 MD5/大小一致 | Steam 入口到中文游戏内资源下载页 | 额外资源、登录、可玩场景、性能 |
| 绝区零国服 3.1.0 | success，下载 81,975,575,634 bytes | 12,199 文件 / 83,300,989,110 bytes，全部 MD5/大小一致 | Steam 入口到真实中文协议页 | 接受协议、登录、可玩场景、性能 |
| 崩坏：星穹铁道国服 4.5.0 | 后台重启续传后 success，下载 108,846,544,086 bytes | 11,208 文件 / 111,236,307,068 bytes，全部 MD5/大小一致 | 未通过，启动很快退出/保护组件崩溃 | 兼容修复、登录、可玩场景、性能 |
| 原神国服 7.0.0 重新安装 | success/ready，事件总下载 138,989,603,579 bytes | 2,848 文件 / 142,503,873,726 bytes，全部 MD5/大小一致 | 原生按钮启动后，用户明确确认“已启动，没啥问题” | 登录/具体可玩场景未单独记录；长期稳定、性能和 NAS 启动未验收 |

## 已实测的机制与问题

### 官方下载不是保存一份完整压缩包再整体解压

现场事件为 `downloadMode=chunk / downloadType=sophon`，同时报告网络下载量和写入量。官方前端安装空间使用游戏与所选语音的 `unzipSpace` 加 `extraStagingSize`，不能额外再把全部下载量重复相加。实验脚本仍额外留 10 GB 磁盘余量。

这是本次新安装路径的证据，不代表已验收差分更新、ldiff 或预下载。

### 暂停回调并不表示已经停止写入

崩坏 3 在 1,812,451,567 bytes / 5.724% 处请求暂停。接口回调立即返回 null，但实际 cancelled 事件迟到；过早 resume 没有恢复进度。收到 cancelled 后再次恢复，保留约 1.9 GB 目录并继续下载至完成。

产品应区分“正在暂停”和“已暂停”，不能回调一到就解锁移动、删除或再次启动。此次证明保留部分文件并成功续传；未抓取网络 Range，因此不宣称零重传。

### 完成需要结合阶段和独立资源校验

崩坏 3 的事件依次为 progressing → verifying → success，进入校验时百分比重新计算，success 的 percent 仍为 99.0448。不能硬等百分比等于 100，也不能把校验阶段当作下载倒退。

官方 `ready` 单独并不能证明资源完整（此前只有 exe/config 的测试目录也返回 ready）。本次同时要求终态成功，并执行读回校验。

本地 `pkg_version` 只覆盖崩坏 3 的 266 文件 / 1.64 GB，不是完整 34.82 GB。另从这个安装目录所绑定的两份 Sophon depot manifest 导出完整文件列表；缓存的 MD5 对应**解压后的 protobuf**，两份分别验证压缩长度、解压长度和 MD5 后才解析。只读取无加密 manifest，不查询口令或令牌字段。完整 1,056 文件大小和 MD5 全通过，耗时 47.38 秒。

### 后台重启后的恢复入口与普通继续不同

星铁在 5,719,190,988 bytes / 5.203% 实际进入 cancelled 后，停止了隔离 HYP prefix，并确认进程与 19222 端口消失。重开相同 prefix 后，游戏目录绑定与约 5.4 GiB 实体文件保留，状态为 need_install，但下载任务事件为空。单独 `resumeDownload` 返回 null，持续观察仍无进度。

检查官方前端：同进程中的 cancelled 状态才走 resumeDownload；其 startInstall 使用 `startDownload({gameBiz,package,isInterrupted})` 重建安装任务。实验脚本新增受限 `continue-install`，只允许精确关联的 trial 目录、need_install 且无活跃下载。调用 `isInterrupted=true` 后进入 progressing，processedBytes 超过原断点（7,488,678,510 bytes），并继续增长。没有重新创建或清空目录；未抓网络层，因此不声称任何字节都没有重传。最终仍需完整清单校验才能验收整个恢复结果。

最终结果：4.5.0 官方 success/ready，独立完整清单 11,208 文件 / 111,236,307,068 bytes 全部一致（148.72 秒），重启续传后的文件完整性已通过。该验证不包含下载中直接断电或网络盘断连。

### 崩坏 3 需要专门的启动入口，游戏内还要补资源

新建 `Experiments/bh3-cn-first-install/prefix`，直接启动 BH3.exe：日志出现 WDFLDR.SYS 缺失 / HoYoProtect 驱动加载失败，Unity 崩溃报告显示 `MHYPBase.dll` 的 `0xc0000005`。这不是下载文件缺失：此前完整清单已验证。

随后仅在该隔离 prefix 安装应用已固定的 32/64 位 Steam/lsteamclient 组件，通过 `C:\windows\system32\steam.exe` 启动同一个未修改的 BH3.exe。游戏成功显示中文加载界面，继而显示游戏内资源下载选择：基础约 13,586 MB，全部约 28,056 MB。没有点击额外下载、没有登录账号、没有进入可玩场景；截图后已关闭该 prefix。

因此，官方启动器报告安装完毕之后，仍可能有游戏内额外资源需求。不能把启动器所报大小当成最终游玩占用，也不能把进入这个页面标为可玩。

### 绝区零安装和首屏

国服 3.1.0 在指定 trial 目录完成官方 verifying→success；重新读取完成后的当前 build/depot 清单，12,199 文件 / 83,300,989,110 bytes 全部 MD5 和大小一致，耗时 112.51 秒。不能用下载中间态的 manifest 列表代替最终完整清单。

使用独立 `Experiments/nap-cn-first-install/prefix` 和同一固定 Steam/lsteamclient 入口，不修改游戏文件，已通过实际窗口截图确认中文用户协议页。未代用户接受新游戏协议、未登录或进入可玩场景，随后关闭该隔离 prefix。证据为 `nap-complete-20260905.json`、`nap-full-verify-20260905.json`、`nap-steam-launch-20260905.log` 和 `nap-first-window-20260905.png`。

### 卸载必须确认真实路径和结果

用户确认分批测试后，已关闭崩坏 3 独立 prefix，保存 config/pkg_version 和校验截图，通过官方 `uninstallGame` 传入精确 trial 路径、`killProcess=false`。返回 success，随后目录实际消失、官方路径清空、状态回到 need_get_game。未删除 Wine 环境或其他目录。资源未保留在废纸篓，要重下才能再测；卸载未打断同时进行的绝区零下载。

清理此前不完整的原神 GameProbe 关联时出现反例：`result=success` 同时带 `errorCode=20103-0-0`，路径关联已清空，但约 878 MiB 实际目录仍存在。此结果只能认定取消关联，不能报告文件已删除。取消关联还把 autoUpdateWpf 恢复为 true，重新安装前已重新请求关闭，必须读回确认。正式界面需要分别验证目录绑定、实体文件和自动下载设置。

绝区零完成首屏验收后同样官方卸载成功，实际目录消失、绑定清空；保留配置/清单/截图，再开始星铁。不是把测试文件留在废纸篓占用空间。

### 星铁运行兼容未通过

4.5.0 文件完整性已通过，但当前固定 CrossOver 11.0-1 + DXMT 0.80 下，独立 prefix 的 Steam 入口很快退出（父进程退出码 231）。参考本地 YAAGL，随后试 Jadeite 4.1.0 默认 explorer 入口与可选 Steam 父进程，并带 `-disable-gpu-skinning`；都没有取得可用首屏。Jadeite 父进程退出码为 0 不代表子游戏成功：子游戏日志存在 WDFLDR.SYS 缺失、HoYoProtect 加载失败，Unity 崩溃报告指向 MHYPBase.dll / 0xc0000005。

这是当前配置的启动兼容阻塞，不是下载损坏证据，也不足以断言由 beta macOS 导致。本轮未继续修改保护模块、hosts 或系统级设置；未安装上游 NV 扩展专用配置，未尝试其他 Wine 版本，不把这三次失败扩大为所有配置都不可能运行。按用户分批测试指示保留诊断后清理测试游戏，先完成原神重装。

补充源码对照：固定 YAAGL `src/clients/mhy/hkrpg/program-launch-game.ts` 的 DXMT 分支还使用 `WINEMSYNC=1`、`DXMT_ENABLE_NVEXT=1`、NVIDIA vendor/device ID 和 `wine.setNVExtension()` 注册表设置。这些并未包含在本轮三次启动试验中；只复用了 Jadeite 入口和禁用 GPU skinning 参数，不能称为完整复现上游成功配置。上述差异是下一轮可验证的候选项，不是已经证实的崩溃原因或修复。

证据：`hkrpg-complete-20260905.json`、`hkrpg-full-verify-20260905.json`、`hkrpg-steam-launch-20260905.log`、`hkrpg-jadeite-launch-20260905.log`、`hkrpg-jadeite-steam-launch-20260905.log`、`hkrpg-jadeite-crash-error-20260905.log`。

星铁随后官方卸载成功，实际目录已消失。三款测试游戏的独立 Wine 环境（bh3/nap/hkrpg-cn-first-install）在确认进程停止、关键崩溃报告已归档后也已删除，约回收 2.2 GiB；不会保留在废纸篓，需要重建才能复现。旧 GameProbe 占位副本保存配置/清单后也已清理。官方 HYP 研究 prefix 保留用于原神下载，原神原有 prefix/运行时/账号环境均未删除。

## 工具和证据

### 原神恢复和原生启动

最新用户验收：“原神已启动，没啥问题”。据此将重装后的启动结果记为通过，保留原成功运行配置，不再把先前游戏内资源下载页或白色定向截图当作当前启动失败证据。这是用户的实际启动反馈，不等同于新增完整游戏内性能测试，也没有证明 NAS 上的原神可运行。

官方最后依次 progressing → verifying → success，终态 percent=99.7611，`getLocalGameInfo` 为 ready / 7.0.0 / autoUpdateWpf=false。停止隔离 HYP prefix 并确认调试端口关闭后，重新导出该目录的最终 Sophon 清单。独立校验 2,848 文件 / 142,503,873,726 bytes，0 失败，176.64 秒。按此结果写新的 complete marker，`renamex_np(RENAME_EXCL)` 从 `Trials/GenshinImpact` 同卷原子移回原 `Genshin Impact`，没有覆盖既有目标或复制第二份游戏。

新 marker SHA-256：`0931ea4092a017210d46422a37c963f1576d729440e38e785b4b4e35070bd6df`；官方 config.ini SHA-256：`3968c857987033067ecbb54d11bfa2006da61000fbca5a761a862e013eaa2ac7`。config 为 7.0.0，附官方 channel/cps 字段，未用旧文件覆盖新配置。原路径偏好、5120×2880 全屏、120 FPS 实验开关、Metal HUD 保留。

重开既有开发 app 后，真实 UI 从“尚未安装”更新为“国服 · 7.0.0 已安装”；实际点击“开始游戏”，日志确认 DXMT、原分辨率/全屏、fps120/HUD，代理报告 FPS 解锁 active。真实窗口截图为中文原神天空场景，随后自动进入约 15,887.77 MB 游戏内资源补充下载；并非已进入可玩世界，也不是 120 FPS 性能验收。游戏内资源写入发生在上述基础安装完整校验之后。

证据：`genshin-complete-20260905.json`、`genshin-full-manifest-20260905.jsonl`、`genshin-full-verify-20260905.json`、`genshin-reinstall-native-window-20260905.png`、`genshin-reinstall-resource-progress-20260905.png`。原生启动日志位于用户 Application Support/MacGameBridge/LocalRuntimes/Diagnostics/launcher-20260905-160441.log；仅窄范围读取阶段信息，未归档含账号内容的完整游戏日志。

### 后续星铁和 NAS 要求

用户追加要求后续重试并修复星铁，尝试 NAS 安装以减轻本地容量压力。只读探测当前 SMB 共享 `/Volumes/codex项目空间`，约 4.7 TiB 可用，系统报告可写、非本地、无文件克隆支持。已询问是否允许新增 `MacGameBridge/Games`，尚未收到目录确认，未往共享写入。`smbutil statshares` 查询失败，但 mount/df/stat 和 Foundation 卷元数据可读，不能因此断言共享不可用。

目前生产代码对已安装的网络盘游戏会拒绝原地更新，原因是更新前强制 APFS 克隆备份。NAS 安装、启动、更新、断连恢复仍待实际验证，不能只做到存文件或显示窗口就标为支持。运行时和 prefix 计划先留本地；无需用游戏搬迁带动整个 Wine 环境迁往网络盘。

- 星铁参考组件仅在隔离试验目录使用：本地固定 YAAGL ca78abc 的 `src/downloadable-resource.ts` 指向 Jadeite 4.1.0，来源 `https://codeberg.org/mkrsym1/jadeite/releases/download/v4.1.0/v4.1.0.zip`。ZIP SHA-256 `12d4c37b09d3e81640536fd68c2c62913fc4b4a90c0183e4dec845e4934a9858`；jadeite.exe SHA-256 `b784e84924ff6e62050bf0d41272cd54a9e71881f77d4bfc8fe1fc52ed81eed9`；附 MIT License、Copyright 2023-2024 mkrsym1，已原样保留。哈希是本地取证值，未验证厂商签名。没有执行随包 hosts/analytics 脚本，也没有把它加入发行包或默认原神环境；旧上游固定版本不等于当前星铁兼容性已经验证。
- `script/hyp_install_trial.mjs`：固定隔离目录的官方后台安装、状态与暂停/恢复试验。
- `script/export_hyp_trial_manifest.py`：只读按指定安装目录选择当前 build/depot，核对缓存 manifest 后输出文件清单。
- `script/verify_hyp_installation.py`：4 MiB 流式 MD5，拒绝路径越界与符号链接；支持 pkg_version 和外部完整清单。
- `script/test_export_hyp_trial_manifest.py`、`script/test_verify_hyp_installation.py`：合计 4 项离线测试通过，含解压后 manifest 校验值、同尺寸损坏、缺失文件和路径越界。
- 原始证据位于忽略目录 `LocalRuntimes/Experiments/hoyoplay-20260904/`：`bh3-complete-20260905.json`、`bh3-full-verify-20260905.json`、`bh3-first-launch-20260905.log`、`bh3-steam-launch-20260905.log`、`bh3-steam-window-later-20260905.png`。

未改生产下载器、未发布新版本，未用本轮脚本测试替代 Swift 应用的一键安装验收。
