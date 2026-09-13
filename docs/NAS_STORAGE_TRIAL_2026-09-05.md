# Lucian NAS 存储试验

日期：2026-09-05。用户指定使用 Lucian 文件夹，按设备和用途分类，后续这台电脑的相关资料在其中整理。

## 已创建的分类

实测已挂载独立 SMB `/Volumes/Lucian`，约 4.7 TiB 可用。使用这个共享，而不是此前 `codex项目空间` 中同名的子目录；没有修改既有文件。

```text
Lucian/MacBook-Pro-M5-Pro/
├── Games/                 游戏本体，按游戏单独存放
├── Projects/              项目资料与归档
├── Apps/                  应用安装包、运行组件归档
├── Backups/               经核验的备份
├── Media/                 视频、音频、图片
├── Downloads/             临时下载与待整理文件
├── Diagnostics/
│   └── MacGameBridge/     脱敏测试报告
└── README.md              设备标识和使用说明
```

设备：晨曦Lucian的MacBook Pro，Apple M5 Pro；LocalHostName 为 chenxiLuciandeMacBook-Pro。不自动迁移现有源码或本地全部文件，不代表已配置 Time Machine。

## 已完成的基础测试

- 系统卷信息：SMB、可写、非本地、无 APFS 文件克隆支持。
- `script/probe_nas_storage.mjs` 创建唯一临时子目录，写入 512 MiB 随机内容并 fsync，重命名后完整读回并核对 SHA-256。成功后只删除自身测试文件和临时子目录。
- 本次写入 7.390 秒，约 69.28 MiB/s；读回 0.379 秒，约 1351.03 MiB/s，明显可能命中缓存，不能用此数字声称 NAS 实际带宽或游戏加载性能。
- SHA-256 `4b4569ef9d0c87f0215ca0086adeb267d138f1ad50cf1df28a68a3f9bbc29d55` 一致，重命名通过，512 MiB 临时文件已清理；报告已复制到 Diagnostics/MacGameBridge/nas-storage-probe-20260905.json。
- Wine 的独立 HYP prefix 内 `cmd /c dir Z:\Volumes\Lucian\MacBook-Pro-M5-Pro\Games` 可以列出目录。Wine 显示的空闲容量与 macOS statfs 不一致，安装脚本使用目标卷真实 statfs 预算，不信任 Z 盘根容量报告。

## 星铁 NAS 安装试验

实验目标：`/Volumes/Lucian/MacBook-Pro-M5-Pro/Games/StarRail`；运行环境和 prefix 暂留本地，原神未迁移。

`script/hyp_install_trial.mjs` 增加显式 `MGB_TRIAL_ROOT`：仅接受已存在的绝对、规范目录；/Volumes 路径必须匹配实际 SMB 挂载且设备号一致，不允许缺失网络盘时回落到本地同名目录。仍只操作指定游戏子目录，原神卸载仍被拒绝。这是研究脚本，不是原生产品的 NAS 支持交付。

第一次 NAS 预检和随后本地对照均超过脚本原有 12 秒回调窗口。Sophon 日志显示仍逐个处理星铁 4.5.0 的 depot 文件状态，因此不能据此认定 NAS 不支持或下载失败。将 getGameInstallInfo 的单次等待延长至 180 秒，避免立即重复排队；其他接口等待不变。

延长等待后实际预检通过，预算下载 108,846,544,086 bytes，含余量空间 122,310,048,892 bytes，NAS 可用 5,161,088,860,160 bytes。startDownload 返回 null 后，真实目录出现游戏文件、chunk 和 staging，随后 progressing 从 1.917% / 2.065 GB 增长到 3.235% / 3.530 GB，瞬时约 15.94 MB/s，无 errorCode。这证明已开始向 NAS 安装，不代表完成安装或星铁已经修复。

运行中的 watch 最多观察 30 分钟，到时退出不会停止 HYP 下载，必须看当前官方状态决定后续，不要因观察脚本结束而重新 startDownload。下载证据为 hkrpg-nas-install-watch-20260905.jsonl。后续先等 success/ready，再按最终清单独立校验，最后试本地独立 prefix + NAS 游戏路径。

检查：两个 Node 脚本语法通过；3 个非法根目录均在连接后台前拒绝（根目录、非规范路径、缺失卷），没有创建本地假挂载目录；既有 4 项完整清单/校验离线测试通过。未构建或发布新的原生 app。

原始结果：项目忽略目录 LocalRuntimes/Experiments/hoyoplay-20260904/ 下的 nas-storage-probe、hkrpg-nas-preflight、hkrpg-local-preflight-compare、hkrpg-nas-install-start 文件。

## 尚未验收

- NAS 上完整下载安装、读回清单校验、实际游戏启动与游玩。
- 星铁专用 YAAGL 配置的完整复现及崩溃修复；此前三次失败不能视为所有配置都不可用。
- NAS 原地更新和断连恢复。当前原生下载器的已安装游戏更新依赖 APFS 克隆备份，仍会拒绝 NAS 原地更新。
- 不强制卸载或重连共享，不通过破坏当前 NAS 会话模拟断连。
