# 官方米哈游启动器隔离实验

2026-09-05 后续已获用户授权删除原游戏并执行四游戏安装试验，最新状态见 [四游戏安装记录](FOUR_GAME_INSTALL_TRIAL_2026-09-05.md)。下文“未下载/未修改”仅对应此前研究阶段。

日期：2026-09-04 至 2026-09-05。目标：验证由官方启动器负责预下载、更新和修复的可行性；本次不修改现有游戏目录或默认启动链。

## 来源与环境

- 官网：https://launcher.mihoyo.com/ 。Firecrawl 搜索找到官网，抓取失败后使用浏览器实际打开并点击“立即下载”。
- 浏览器下载来源元数据：https://hyp-webstatic.mihoyo.com/hyp-client/miHoYoLauncher_1.18.exe 。
- 安装包：`/Users/example/Downloads/miHoYoLauncher_1.18.exe`，209837072 bytes，PE32+ x86-64。
- SHA-256：`674ff7201b42058cd569889ccbdc15cdd97709b1442876757a0f81785d716517`。这是本地记录哈希，不是厂商发布的校验值；本次未验证 Authenticode 信任链。
- 系统：macOS 27.0，26A5425a；Wine 日志识别 Apple M5 Pro。
- 运行时：现有用户目录中的 CrossOver Wine 11.0-1，只复用运行时文件，不复用游戏 prefix。
- 独立 prefix：`/Users/example/Library/Application Support/MacGameBridge/Experiments/hoyoplay-20260904/prefix`。
- Wine 新建 prefix 默认有 Z: 根目录映射；独立 prefix 不是安全沙箱。未向官方程序指定现有游戏路径，识别实验仅针对下述 GameProbe 测试副本。

## 已验证

1. `wineboot -u` 退出码 0。
2. 官方安装器进程运行，窗口标题为“米哈游启动器 安装程序”，800×480 逻辑尺寸。
3. 窗口截图确认中文界面正常显示：“快速安装”“自定义安装”和未勾选的协议确认框。
4. 用户授权接受协议后，使用自定义安装，路径为 `C:\MacGameBridge\miHoYo Launcher`，关闭桌面快捷方式，开机自启保持关闭。安装完成，实际版本目录 `1.18.0.380`；注册表 InstallPath 与磁盘路径一致。
5. 主程序与内嵌网页运行成功，内部查询能返回国服原神状态；但 macOS 实际窗口白屏，尚未通过用户可见主界面验收。默认日志报 `eglCreateWindowSurface failed with error EGL_BAD_ALLOC`；禁用 CEF GPU 加速以及追加 Qt 软件渲染变量均未修复实际白屏。CEF 自己的截图能显示官方首页，不应冒充桌面窗口显示成功。

日志、截图和脱敏查询结果在忽略目录 `LocalRuntimes/Experiments/hoyoplay-20260904/`。本轮结束已停止独立 prefix，并关闭临时本地调试端口 19222；未停止或修改正常游戏环境。

## 安装位置与关联实验

- macOS 实际安装根：`/Users/example/Library/Application Support/MacGameBridge/Experiments/hoyoplay-20260904/prefix/drive_c/MacGameBridge/miHoYo Launcher`。
- 游戏识别测试目录：同一 prefix 的 `C:\MacGameBridge\GameProbe`。起初只用 APFS clone 复制现有 `YuanShen.exe` 与 `config.ini`，没有复制完整游戏资源，更没有把官方启动器指向现有游戏目录。
- `findGame({gameBiz:"hk4e_cn",dir:"C:\\MacGameBridge\\GameProbe"})` 返回 errorCode=0、pathAvailable=true、version=7.0.0。
- 将返回的对象传给 `linkGame({games:[...]})` 后返回 isLinked=true。`getLocalGameInfo` 随即返回 installPath=测试目录、version=7.0.0、status=ready。
- **重要反例：只有主程序和配置的非完整副本也会被报为 ready。定位／关联不是资源完整性校验，不能据此宣称可以启动。** 本轮未运行该副本。
- 关联产生实际副作用：官方自动安装 WPF 配套内容，新增约 466 MiB 的 `BeyondAssets`、约 938 KiB 的 `beyond_pkg_version`，并在测试 config.ini 加入 uapc 与 wpf_version=7.0.0.47194594。本轮没有调用游戏 startDownload，但不能据此声称没有下载任何内容。
- 已通过 `updateGameSettings({gameBiz:"hk4e_cn",data:{autoUpdateWpf:false}})` 关闭测试环境的 WPF 自动更新。该调用未及时返回回调，以后续状态回读为准，不以请求发送视为成功。
- 停止并重新启动独立 prefix 后，路径、版本、autoUpdateWpf=false 均保持；`gamedata.dat` 中的 persistentInstallPath 也指向测试目录。
- 现有游戏 config.ini 仍是 82 bytes、修改时间 2026-08-22，SHA-256 为 `543a4b4c9cfff03ac214d33f0358b98dd69e0c338afef7bc56782ae37d6b30fc`。测试副本配置发生变化，现有配置未随之变化。未对全部实际游戏文件作前后哈希扫描。

## 机制：来自运行中的官方前端与本地数据库

通过仅监听 `127.0.0.1:19222` 的临时 CEF 调试接口，读取已经加载的官方前端代码，不登录账号、不提取登录凭证。主脚本为 `main_1_18_2_cn_b6cae17046cfdb6ee317.js`，本地 SHA-256：`d309ed3bd208182d50aca1c983dbf19f37a53860f52bf0d4548d149e3b52004e`。原始第三方代码只保留在忽略目录，不复制进产品或公开提交。

界面通过 `CefViewQuery({request:JSON.stringify({action,data}),onSuccess,onFailure})` 调用原生后台，另用 `HYPClient.addEventListener` 接收事件。

| 能力 | 官方前端实际调用 | 本轮验证程度 |
| --- | --- | --- |
| 计算安装空间／语音包 | getGameInstallInfo，传 gameBiz、dir | 实际返回原神资源、语音、暂存与剩余空间字段 |
| 定位／关联已有目录 | findGame → linkGame | 独立非完整测试副本实测，重启后路径仍保持 |
| 查询当前状态 | getLocalGameInfo | 实测路径、版本、WPF、预下载状态 |
| 查询预下载 | checkGamePredownloadInfo | 实测 result=success、needPreDownload=false、size=0 |
| 新安装 | startDownload，带 path、voiceLangList、packageType、快捷方式开关 | 仅确认前端调用结构，未启动游戏资源下载 |
| 更新 | 同一 startDownload 入口，根据已有状态分流 | 未执行真实版本更新 |
| 预下载 | startDownload，isPreDownload=true | 仅确认调用结构，没有开放中的预下载包可验收 |
| 暂停／继续预下载 | pauseDownload／resumeDownload，isPreDownload=true | 仅确认调用结构 |
| 进度／错误 | updateDownloadStatus、updateGameInfo 等事件 | 确认前端消费 status、errorCode、downloadSpeed、writeSpeed、processedBytes 等字段，未做完整下载事件验收 |

官方结构为：CEF 网页界面 → 原生消息接口 → 下载／更新组件。安装目录有 `HYPWorker.exe`、`HYUpdater.exe`、`hpatchz.exe` 等；`HYLauncher.dll` 字符串包含独立的 PredownloadChunkInstallPkgManager 与 PredownloadLdiffInstallPkgManager，表明存在 chunk 与 ldiff 两套预下载实现，但具体路由条件尚未完全核实。

用户状态位于独立 prefix 的 `AppData/Roaming/miHoYo/HYP/1_1`：

- `data/gamedata.dat` 保存每游戏持久路径、版本与预下载标记；该文件不是可以直接安全覆写的普通 JSON，伴随 CRC 文件，应通过接口更新。
- `modules/sophon/sophon_db/chunk_config.db` 的 config 表区分 local/server version 与 build id，并记录 package、branch、depot、matching_field、install_dir。
- `chunk_manifest.db` 保存清单身份、校验值、压缩与加密参数；本轮只读取结构，不输出口令字段值。
- `chunk.db` 的 depot_file_data 记录包／构建／资源／文件版本、file_status、install_dir。
- 现场日志存在 fetch_version、fetch_size、清单获取、目录文件状态查询，证明不是单一全量 ZIP 下载器。日志出现 enable_pcdn 配置不等于本轮已经对外上传游戏资源；P2P 策略仍待验证。

## 对产品接入的结论

安装器目录、游戏目录、预下载缓存应分别管理。最终由我们的原生界面选择游戏位置、显示进度和错误；运行环境与官方工具放 Application Support，不能依赖 Downloads 中的安装包或固定个人路径。

当前证据支持继续做一个受控的“官方后台适配”实验，但**不证明官方支持 headless API，也不能把调试端口当成已验证的生产集成方案**。产品仍保持现有成功链，不替换下载器或自动迁移游戏。要避免两个下载器同时写同一目录，并明确 WPF 等附带下载的开关和目标路径。

## 尚未验证

- 实际桌面主界面白屏的修复、启动器自更新和前端接口变化后的适配。
- 完整游戏资源下载、预下载、版本切换、修复和错误恢复；真实预下载尚不可用。
- 官方启动器拉起游戏时如何接回当前必需的 Steam 兼容入口。
- 无人值守接口和分发许可。即使 UI 能运行，也不代表可以无界面封装或公开内置安装包。

下一步：在已关闭自动 WPF 更新的独立环境中解决显示／稳定后台控制问题；用可恢复完整副本验证官方校验与中断恢复。等真实预下载开放后，验证缓存位置、旧版保持可玩、上线后的差分合成与失败回滚，再决定替换产品下载链。不能把本轮 ready 状态当成这些验收的替代品。
