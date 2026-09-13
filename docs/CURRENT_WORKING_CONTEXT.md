# 星桥 HoYoBridge 当前工作上下文

- 2026-09-13 发布完成：仓库已公开，v0.1.0 为未公证普通测试发布，含安装 ZIP 与校验附件。README 加入用户提供的截图。441 项本机测试通过，优化构建和解压验证通过；ZIP SHA256 为 `280172895a24f705ad9eb9e00e9cb27996411bed67ce68d935cdba8b14388541`，与 GitHub digest 一致。自动更新未开放；当前凭证缺 workflow scope，CI 暂存 `.github/ci-reference.yml`，未启用。下方“私有／未发布”记录为历史状态，不代表当前状态。
- 2026-09-13 GitHub 收尾：仓库描述、主页、主题、Discussions、Issue 模板、贡献指南、安全策略与漏洞报告均已配置；Dependabot 告警及自动安全修复已启用，合并后自动删除分支已启用。首页截图中“Packages”为空属正常：macOS 应用 ZIP 位于 Releases，而非 GitHub Packages。CI 仍因当前发布凭证缺少 `workflow` 写入权限而未启用。

- 2026-09-13 发布含义纠正（覆盖下方旧解释）：用户通过 GitHub Releases 截图澄清，并确认允许未公证测试版和自更新。已撤销 README、AGENTS、第三方声明及交接文档中“公证前禁止所有 Release”的错误限制。未公证需显著标注，不冒充稳定版；源码公开不自动获授权，现有组件／素材分发缺口及真实更新验证仍须处理。测试 feed 不依赖 latest 路径发现测试版。本轮仅修正文档，没有上传或公开仓库。

- 2026-09-13 文档与发布政策：用户明确公证前不发 Release。中文 README 已明确 Developer ID+公证前不发布含预发行在内的安装包、不开放玩家更新源；仅四款国服官服，不支持国际服／渠道服；区分源码公开与二进制发布。更新功能现状、开发构建、非官方声明、实际借鉴项目及美术权利范围已补充。THIRD_PARTY_NOTICES 改中文并补 Wine/DXMT/Steam 资产等待核对项、纠正 Jadeite 仅星铁的旧说法；新增 Sparkle/Jadeite/7-Zip 许可副本，原文不翻译。AGENTS 与发行交接、自更新文档同步规则。本次 gh 只读确认仓库 PRIVATE、Release 为空；没有发布、推送或运行游戏。

- 2026-09-09 启动器自更新：用户明确反馈功能延后；FeedbackReport/FeedbackView 草稿保留但没有场景或菜单入口，未建立反馈后台。已接入固定 Sparkle 2.9.6、应用菜单与设置「应用更新」、默认关闭的自动检查、忙碌任务检查/重启暂缓及退出保护，更新不改游戏目录。打包嵌入 Sparkle.framework、rpath 和 MIT 许可；build_and_run 接受 HTTPS feed/Ed25519 公钥，prepare_appcast.sh 从独立钥匙串账户生成签名 XML（不发布）。16 项更新/维护测试通过，debug app/ZIP 已重建，深度严格签名和 ZIP SHA256 验证通过；CUA 实际验证设置页、关闭状态及未配置提示，应用已打开。没有真实 feed/公钥，没有发布 Release，正式签名公证及两版本完整自更新仍未验收；不能称线上功能已开放。配置与发布步骤见 docs/LAUNCHER_SELF_UPDATE.md。未下载/删除/启动游戏。

- 2026-09-09 全项目检查：结果见 docs/PROJECT_AUDIT_2026-09-09.md。修复未完成卸载的 ready 恢复、后台归属检查（WINEPREFIX 或精确专用 HYP 路径）、监听去重、原神准备取消、其他游戏进程生命周期、双管道大输出死锁、设置适用范围与通用 HUD/全屏/隐藏、并行 FD 测试噪声，以及现场复现的后台冷启动记录未就绪误报。438 项/57 套全量测试通过，后续维护修复13项回归通过，debug应用构建成功；真实冷后台检查崩铁返回最新，四游戏切换与设置标签已验证。未下载/删除/启动游戏，未更新Release ZIP，正式签名公证、自更新、干净Mac验收仍是缺口。

- 2026-09-09 任务恢复与后台诊断：新增“结束任务，保留文件”，只对 Installer/prefix 执行 wineserver -k/-w 并确认退出后释放跨游戏锁，保留 pending 续传记录；新任务清除 detached 标记。后台记录固定事件、退出码、重连和端口冲突，不记录原始页面地址或令牌；菜单可查看限长诊断文件。11 项维护测试通过，debug 应用已构建启动。真实检查崩铁返回最新版本、重连日志已落盘；临时进程参数模拟绝区零待恢复任务，实际点击结束后专用后台停止成功，崩铁按钮由禁用恢复可用。随后清除测试 detached 偏好并正常重开。未下载或删除游戏；真实下载中的中断续传、非 HYP 端口冲突分支尚未实测，Release ZIP 未更新。

- 2026-09-08 菜单和磁盘离线修复：无主程序时禁用维护菜单；外置盘依据系统挂载列表判断离线，保留路径并显示重新检查磁盘，不提供误导的一键安装。关联缺失文件时返回明确提示。11 项针对性测试通过，最新 debug 应用构建并启动；CUA 确认崩坏 3 五项维护菜单禁用、崩铁启动入口可用。通过仅进程有效的参数模拟不存在的磁盘，实际确认离线提示及重新检查按钮，随后退出并正常重开，持久路径未改变。没有真实拔盘、下载或删除游戏。旧 Release ZIP 未重新生成，自更新仍待实现。

- 四项修复最终验证：434测试通过，Release包校验通过。通过仅进程生效的NSArgumentDomain模拟 pendingInstall/pendingUninstall（不写持久偏好、不调用下载/删除），CUA确认其他游戏安装/启动禁用及阻塞说明，原任务显示重新连接，卸载显示检查结果；退出模拟进程并正常重开后崩铁开始游戏可用，持久偏好未留下测试任务。真实后台断线/恢复未做游戏下载实测，按用户要求仅本地状态回归；未知后台状态继续保留任务锁，不宣称恢复已全面实测。

- 2026-09-08 四项审计修复：安装/更新/修复显示各自暂停文字，卸载和任务准备只显示进度；controllableDownloads 防止准备/卸载时误发暂停。isOccupied 统一忙碌/检查/持久未完成任务，跨游戏显示阻塞游戏名并禁用操作。断线不清 pendingInstall，恢复先请求暂停并等待 cancelled/failed 事件后才重新提交；success事件或官方精确目录ready+本机主程序可解除任务，未知保持锁。卸载也持久保留 pendingUninstall，提供只读结果核对，不确定时不重复删除。原神环境失败原始原因保留。434项/56套测试通过，本轮未执行实际游戏下载或卸载。

- 关联修复最终验收：6项维护回归测试通过；Release包校验通过。新版应用实点崩铁“检查更新”，页面返回“当前游戏已是最新版本”，开始游戏仍可用。未发起游戏整包下载、更新或修复；本轮只完成旧安装识别与版本检查。

- 2026-09-08 崩铁“检查更新”报后台路径空：官方 getLocalGameInfo 返回 need_get_game/path空，而本机游戏完整。旧 linkGame 仅传 gameBiz/path 返回 errorCode=-3/isLinked=false；改用官方 findGame 精确识别后完整回传候选（含 package/version 等），实际返回 isLinked=true/errorCode=0，识别版本4.5.0。未重新下载游戏。更新/修复前仅对明确未登记状态自动关联，已有不同路径、未就绪和错误游戏记录不覆盖；卸载仍严格匹配、不自动关联。手动关联共用 findGame→linkGame→重读目录链路。

- 最终包验证：428项/56套测试通过；Release构建、ZIP SHA/内部签名/架构检查通过，包内 GameDownloader 不存在。CUA逐页点击四款游戏；崩铁显示旧实际目录和开始游戏，崩坏3显示尚未安装。真实点击卸载菜单并检查完整路径/永久删除提示后取消，确认崩铁仍保留。原神新官方下载完整安装仍因空间不足阻塞。

- 2026-09-08 用户要求四游戏全部改为官方后台下载，不保留 YAAGL 下载路线。主页统一为 MiHoYoGameDetailView，原神仍委托原 GameLaunchService/RuntimePreparationService 启动；应用不再实例化旧安装器，不打包 GameDownloader/Python/YAAGL 下载组件。兼容运行所用 Steam/7-Zip 资产仍保留，不等于旧下载器回退。
- 新增统一卸载确认与 OfficialGameInstaller.uninstall；先核对目录、拒绝链接、匹配官方记录，killProcess=false，不自动强退。通过显式路径 opt-in 集成测试真实卸载 Trials/HonkaiImpact3，BH3.exe 消失，StarRail.exe 保留，空闲约15GiB→47GiB。原安装记录曾暂未就绪而被安全拦截，之后匹配成功。永久卸载不可从废纸篓恢复；游戏环境保留。
- 原神官方下载 UI 实测：原神→一键安装→推荐 ~/Games/HoYoBridge/Genshin Impact→官方资源空间预检，返回需求149.49GB/可用50.94GB，未提交整包下载。无官方窗口/安装向导出现；完整下载因容量不足未验证，不允许删除保留的崩铁以凑空间。旧崩铁无持久路径，新增只读 legacy 探测恢复识别。

- 2026-09-08 经用户明确同意，已创建私有 GitHub 仓库 https://github.com/huaye37/HoYoBridge 并配置 origin。尚未推送源码、上传发行包或公开仓库；源码本机信息与分发素材仍需审查。

- 默认路径回归：原神默认磁盘预览优先保留 savedRoot，避免刷新后误指向新目录。GameStorageTests 与 OfficialGameMaintenanceTests 共16项通过；本轮未触发任何游戏安装。新建 GitHub 仓库的可见性已向用户询问，未擅自创建或推送。

- 新用户安装推荐 ~/Games/HoYoBridge 下四个独立游戏目录，不再推荐 Trials。三款官方引擎安装先确认推荐位置或更改；已有保存路径和中断路径保持不变，不移动旧安装。原神无配置时保留旧可执行文件发现，否则采用新默认路径。发行包增加 script/verify_release.sh 本地/公开验收分级；公开模式要求 Gatekeeper 与 stapler，不能替代分发许可和游戏验收。

- 2026-09-08 对外名称改为星桥 HoYoBridge，发行文件 HoYoBridge.app / HoYoBridge-macOS-arm64.zip。内部 cn.yeutech.MacGameBridge、可执行文件及数据路径保留，避免迁移现有游戏和设置。当前本地无 Git remote；已检查 huaye37 账号仓库列表，GenshinMeta 是伤害计算网页而非本项目，未修改该仓库或创建远程仓库。

- 维护恢复补强：pendingOperation与pendingInstall共同记录任务；首页中断时显示继续安装/更新/修复，安装续传复用原目录，离线父目录拒绝本机回退。更新续传传isInterrupted，修复重启官方repairGame扫描；失败检查与关联清理失效连接。新增隔离UserDefaults测试验证重建后操作类型保留、不同游戏隔离、旧安装标记兼容。未进行真实游戏更新/修复或断电试验，不能将持久化单测视为引擎中断恢复验收。

- 新增三款游戏维护菜单：检查更新、更新、校验修复、关联当前目录。按官方前端已确认的 checkGameUpdate/startDownload/repairGame/linkGame 接口接入，复用下载状态与暂停；修改前核对后台目录、空间并持久化未完成标记。实际只读 checkGameUpdate bh3_cn 返回 success/ready/9.0.0；未触发真实更新、修复或关联，未重新下载安装任何游戏。后台仅登记崩坏3，旧星铁安装需用户通过新关联入口登记，关联不等于校验通过。82项现有启动器测试通过，新增状态测试另行运行；新菜单运行验收和真实版本更新/修复需分别记录，不宣称四游戏维护已全面验收。

- 2026-09-07 新图标改为四游戏统一蓝白标识，撤下原神星门方向；Assets/AppIcon.png为生成原图，提示词在docs/APP_ICON.md。官方引擎专用MGB_BACKGROUND_ENGINE=1分支将AppKit设为accessory并抑制窗口order-front，仅注入Installer/prefix进程，游戏分支不启用。实测后台policy=accessory，getGameInstallInfo nap_cn返回success及当前资源大小，未启动下载；不再只依赖前端hideWindow。图标和后台设置随新包构建。CUA Dock访问超时，Dock隐藏依据为运行时activationPolicy而非截图。

- 2026-09-07 四游戏原生窗口接入：新增NativeGameWindowSupport，原神/绝区零/崩坏3启动时启用同一AppKit适配器与按精确标题匹配的Win32样式watcher；崩铁原成功路径未改。原神以窗口模式启动并将全屏偏好交给MGB_NATIVE_FULLSCREEN进入独立Space，退出恢复窗口。watcher支持以竖线分隔的精确中英文标题，不处理弹窗。崩坏3实机日志honkaiImpact3-20260907-174048.log确认style修正、attached、entered_fullscreen、controls_shown、command=toggle、restored=2558x1440；未声称用CUA点击，CUA无法解析Wine应用，证据来自运行时事件。423测试/54套通过，原生几何/代理测试通过。未下载/删除游戏；原神/绝区零新接入未实机复测。游戏目前保持运行，不为打包停止它；dist ZIP从已运行的新app直接更新。

- 2026-09-07 收尾验收：修复工作目录后的应用按钮实测BH3进程持续运行数分钟，游戏日志出现协议流程，随后通过应用“退出游戏”正常关闭；未代接受协议、未登录，不能标成游戏内可玩验收。启动产品测试8项通过；此前完整421项串行通过。ZIP约516MiB，SHA256和ad-hoc签名验证通过。另补暂停/恢复等待实际事件确认（不把接口回调当停止写入），本轮最终包为dist/MacGameBridge-macOS-arm64.zip。崩铁与崩坏3安装均保留，NAS未写入；星铁/绝区零新下载入口未重复完整下载，GitHub发布/Developer ID公证/干净Mac仍未完成。

- 2026-09-07 本轮新结果：崩坏3已通过产品安装按钮完成下载，官方success后自动切为开始游戏，重开应用保存目录正确。独立Sophon完整清单1,056文件、34,815,890,010字节全部MD5/大小一致，耗时46.53秒；421测试串行全通过。首次按钮启动退出码5，定位到MiHoYoGameLaunchService未设置游戏工作目录；相同Steam/Wine/prefix仅切换cwd后持续运行并在游戏日志进入协议流程。已加入launched.currentDirectoryURL修复并重打包；不宣称已登录/可玩。最终打包及按钮回归在本轮继续，原有崩铁未改动。

- 2026-09-07 下载产品接入进行中：新增 OfficialGameInstaller，三款非原神游戏首页直接一键安装，独立选目录；引擎在 Installer/prefix 自动下载官方1.18安装包、校验固定SHA并用7zz解包，不依赖旧Experiments目录。已在实机移走引擎后通过产品按钮自动恢复，并进行崩坏3真实下载；暂停、冷启动续传实测。修复启动时状态未就绪误判非空目录、官方页面重载丢失事件监听。完整下载/校验/启动仍在本轮继续，不能提前标完成。原有崩铁保留。421项测试串行通过；此前并发FD计数测试波动，单套及串行全套通过。GitHub发布与新Mac公证验收仍未完成。

- 2026-09-07 首发整体处理尚未完成：新增源码 CI、Rosetta/系统启动预检、正确最低系统26.0、应用版本号和可选release构建/ZIP打包。实际生成约513MiB开发ZIP及SHA256，plist/签名/构建/实机打开通过。没有发布、没有自身更新、没有补齐三款游戏下载。官方实时分支星铁4.5/崩坏3 9.0与getGamePackages旧包4.4/8.4不一致，不能直接集成旧包。git remote为空，已异步询问发布仓库；钥匙串只有Apple Development，无Developer ID。完整缺口见FIRST_RELEASE_GAPS.md。打包仍依赖本地固定资产，CI仅构建源码和测试，尚未云端运行。

- 2026-09-06 自动封面：LauncherArtworkStore 在启动及回到前台时查询官方 getGames（同进程一小时节流），按四款国服 biz 获取 display.background.url。仅新 URL 下载，验证图片后原子写入 ~/Library/Caches/MacGameBridge/Artwork；失败保留缓存，无缓存使用内置图。四款缓存已由实际应用联网生成，原神截图确认从内置风景切为官方最新角色封面。构建与打包通过；未模拟离线故障，未来官方换图仍需届时观察。更新依据是官方当前展示图而非本机游戏版本，不包含运行时或游戏数据更新。

- 2026-09-06 最新视觉要求已实施：去掉“游戏库”标签和上下整块底色，背景覆盖全窗口，保留文字游戏切换和浮动操作。原神保留原图；星铁、绝区零、崩坏3使用官方 getGames 的 display.background 静态 WebP，来源记录于 LAUNCHER_ARTWORK.md，公开素材分发许可未确认。实机逐页点击及截图确认三张官方角色图、原神原图均正常显示且铺满窗口。标题下移减少遮挡，原神提示区缩短；构建和开发包验证通过。本轮未启动游戏。

- 2026-09-06 导航视觉重构：删除宽侧栏和重复的文字分段器，改为主视觉顶部居中的单一悬浮游戏坞，四游戏使用紧凑图标、选中高亮和 tooltip，设置收为右上角独立圆形按钮，背景图完整铺满窗口。底层仍是最小 AppKit `NSViewRepresentable` 按钮桥接，SwiftUI 继续持有选择状态。重打包 PID 5673 运行稳定，已从实际界面逐项点击原神／星铁／绝区零／崩坏 3，标题、状态和主按钮全部随选择正确变化，最后恢复星铁。构建、开发包 `--verify` 和 `git diff --check` 通过，本轮没有启动游戏。

- 2026-09-06 鼠标切换最终修复：保留左侧四游戏库，另在与“开始游戏”相同的主内容层右上角新增 AppKit `NSSegmentedControl` 切换器，四段均覆写 `acceptsFirstMouse=true`。重打包后 PID 14373 稳定运行；在第二屏用 macOS 系统坐标鼠标事件依次点击四段，System Events 分别命中 radio button 1/2/3/4，页面回读随后正确切为崩坏 3，最后已恢复星穹铁道。`swift build`、开发包 `--verify`、严格签名和 `git diff --check` 通过；应用运行无崩溃，日志仅有系统 AppIntents/linkd 无关连接噪声。

- 2026-09-06 侧栏鼠标修复：用户实测旧 SwiftUI 侧栏只能经辅助功能切换，真实鼠标不能点，而主区“开始游戏”可点。已将四个游戏项替换为 AppKit `NSButton`，按钮显式 `acceptsFirstMouse=true`；运行状态新增 `stateGame`，星铁失败不再串到其他游戏页面。首版原生按钮因在加入 `NSStackView` 前激活跨视图宽度约束触发 `NSGenericException`，已按日志堆栈修正约束顺序并重打包。修正版 PID 4120 稳定运行、无该异常，窗口实际恢复在第二屏 X=2651；对第二屏绝区零按钮真实坐标 `{2739,989}` 发送系统鼠标点击后，页面回读切为绝区零，随后真实点击恢复星铁。严格签名与 diff 检查通过。不要再用主屏旧坐标或 AXPress 冒充鼠标验收。

- 2026-09-06 四游戏切换与背景验收：侧栏从仅图标 82pt 改为 176pt 的“图标＋中文游戏名”固定游戏库，选中项有白色底和蓝色指示条；原神／星铁／绝区零／崩坏 3 分别绑定独立 1672×941 本地背景。重新打包的 `dist/MacGameBridge.app` 已逐项点击：标题、文案、安装状态和主按钮均随选择切换；星铁显示已安装与“开始游戏”，绝区零和崩坏 3 显示未定位，原神进入原有安装页。星铁与绝区零页面截图确认背景不同，四个资源均进入 SwiftPM bundle，哈希互异且应用严格签名校验通过。本轮只验收启动器切换，没有点击“开始游戏”，不新增游戏启动结论。全量 421 项测试首次仅既有文件描述符计数测试因并发波动失败 1 项，单独复跑通过；不是零失败全量复跑。

- 2026-09-06 启动器集成：用户明确四款游戏均已测试，星铁暂不删除。主界面已从原神单页改为原神／星铁／绝区零／崩坏 3 固定侧栏；星铁自动识别 `/Users/example/Games/MacGameBridge/Trials/StarRail`，未安装游戏可定位本地、外置盘或已挂载网络盘目录，不伪装成可启动。`MiHoYoGameLaunchService` 已把星铁实测的 Jadeite + NV/DXMT + 15 秒临时 dispatch 窗口、原生全屏 adapter 和 Win32 窗口样式 watcher 接入“开始游戏”。发行构建已捆绑 adapter／watcher／Jadeite 及 MIT 许可，移除旧 GPTK 二进制；新机星铁 profile 可从应用资源创建独立 prefix。`swift build` 与 BridgeStatus 80 项测试通过，`dist/MacGameBridge.app` 签名、启动存活和真实 UI 检查通过。本轮未再次点击星铁，不新增从正式 UI 到游戏的运行验收；当前仍只有原神内建下载器，其他三款需定位已有目录，不宣称四游戏一键下载已交付。

更新时间：2026-09-05。后续工作从本页恢复，不再携带完整历史日志。

## 当前产品收敛（优先于下方历史记录）

- 2026-09-06 最终窗口实验状态（优先于下方此前失败/授权等待记录）：Star Rail 当前隔离 PID 48717，`starrail-panel.log`。仅开启 AutoHideToolbar 曾去除白边，但系统 detached toolbar 仍屏外透明，直接搬动它无效；现改为跟随游戏的非激活 NSPanel，使用 macOS 标准按钮并路由到游戏，顶部悬停显示、离开隐藏。实机 `starrail-panel-hidden-top.png` / `starrail-panel-hidden-bottom.png` 显示上下无白边，`starrail-panel-buttons.png` 显示原生按钮；实际点击绿色按钮成功退出，黄色按钮完成退出全屏后最小化，Win32 IsIconic 回读 1，恢复后为 0。游戏恢复到窗口并保持运行。原自动隐藏版本进入过游戏世界，当前 panel 版验证位于登录后的点击进入页面；不新增持续游玩/性能结论。当前 panel 标题文字未激活时灰色、绿色悬停符号为原生缩放加号，动作已路由全屏退出，尚不声称与标准主窗口外观完全一致。重启的临时 hosts 已恢复原始 SHA。代码/几何/代理转发测试及签名通过，尚未集成正式启动器。后续不再反复试 compact toolbar 常驻白条或直接操纵 AppKit 隐藏 toolbar 的路线。

- 授权等待状态续记：PID 37345 的验证后来完成，但发生在旧启动等待超时之后，未启动游戏，hosts 已恢复。已重新发起同一隔离实验启动（exec session 28599），启动等待改为不在管理员验证期间超时；取消验证会终止该等待。当前再次显示 SecurityAgent 弹窗，白边自动隐藏新版仍未进行真实游戏验收。不要把前一版截图当本次修复证据。

- 最新用户反馈优先：上述 compact toolbar 在不悬停时留下常驻白边，不能认定完整修复。已新增仅覆盖 `willUseFullScreenPresentationOptions` 的代理，转发 Wine 原 delegate 其他回调，启用系统 `AutoHideToolbar`。几何/代理转发/选项测试、universal 构建签名及 `autohide-cycle-test.log` 的 Retina 窗口全屏往返 PASS。旧星铁实验进程已退出；新的实机启动目前等待 macOS SecurityAgent 管理员弹窗，尚无 `starrail-autohide.log`，不得说新版白边已在游戏中消失。临时 dispatch 的原 90 秒 watcher 已超时，后续等待者改为跟随本次 osascript PID 37345 存活状态，确认后启动同一隔离 prefix；取消验证则不启动。hosts 检查仍为原始哈希。恢复工作先检查该授权及游戏实际 PID，不复用 30740。

- 2026-09-06 原生窗口适配最新实测：新增 `script/native-window/MGBWindowAdapter.m`、Win32 `window-flags.c` 和构建脚本，均仅用于 `LocalRuntimes/Experiments/native-window-adapter/starrail-prefix` 隔离副本。AppKit compact toolbar 修复全屏顶部布局；`starrail-hover-top.png` 确认系统菜单栏下面单独显示标题栏和红黄绿按钮，内容不再直接顶到菜单栏。真实点击绿色按钮退出成功，随后三次 Ctrl-Cmd-F 往返均恢复 1919×1135 points。`starrail-toolbar.log` 和 `style-watch.log` 留存证据；模拟游戏样式被重写为 16ca0000 后 watcher 两秒内恢复 16cf0000。watcher 绑定所发现游戏 PID，每秒检查但只在缺标志时写入，游戏退出自行结束。当前快照游戏 PID 30740、窗口 14688；不可把这些编号当未来固定值。
- 当前用户确认显示器硬件为 3840×2160；系统 logical=2560×1440/backing=5120×2880 不代表 5K 面板。隔离实验设 3840×2160 窗口启动和 RetinaMode=y，但原生全屏会改变 backing surface，尚未实现硬件 4K 渲染上限。原适配器进入过实际游戏，toolbar 新版到已登录的点击进入页；不宣称新版持续游玩/性能/多屏验收。原始 runtime、游戏资产和原 prefix 未替换；两次临时 dispatch 设置后 hosts 哈希均恢复 c7dd0e2ed261ce76d76f852596c5b54026b9a894fa481381ffd399b556c0e2da。构建/签名/几何测试及 Retina 测试窗口全屏恢复通过，产品启动器尚未集成；可复现和回退说明见 `script/native-window/README.md`。后续应接入真实四游戏启动链并验证游戏内输入/切换显示器，不能把实验已运行当成发布完成。

- 最新窗口实验（用户反馈优先）：window-style.c/helper 在独立 prefix 内，原 UnityWndClass HWND 0x30054 样式 0x16ca0000 缺 WS_THICKFRAME/WS_MAXIMIZEBOX，临时加到 0x16cf0000 后绿色按钮出现；点击后系统 SLSCopySpacesForWindows 确认窗口 13861 位于 Space 181 / type 4，Ctrl 左/右切到 Space 137 再返回 181，截图无黑屏。但用户实际反馈无法缩小、窗口高分辨率不足，故不得认定原生全屏方案验收。已恢复原样式 0x16ca0000，退出该实验全屏并用 SetWindowPos 恢复屏幕内窗口 rect=80,80,1680,980；截图 window-recovered.png 确认游戏仍运行。未修改固定 runtime 或产品代码，helper 有 restore 参数；后续需要解决 window resize/退出可靠性和 Retina logical-vs-backing 分辨率，不反复干扰正在游玩的用户。
- macOS 原生全屏 Space 初测：用户要求尝试；游戏原先已退出，使用独立 launch-window-test.bat 添加 -screen-fullscreen 0，并沿用已验证的 15 秒 dispatch 临时屏蔽，hosts 恢复原哈希。星铁 PID 4805（快照）重新到中文已登录的“点击进入”页面，窗口 13861，2560×1440 / layer 26，仍为桌面覆盖式全屏。最初 AXFullScreen=false 且不可写、无全屏/缩放按钮；尝试 Alt+Enter 后未验证获得普通窗口或原生 Space，不能宣称成功。本地 Wine 11.8 源码 cocoa_window.m adjustFullScreenBehavior 只对可调整大小、非最大化、非子窗口赋予 FullScreenPrimary；仅是参考，当前固定 CrossOver binary 不等同这份源码。实验没有改运行时或产品默认设置，后续应验证游戏设置里的真正窗口模式/Win32 窗口样式，不把 command-line window flag 当已生效。画面截图 native-fullscreen-test.png 在忽略实验目录。用户已确认星铁实际游玩暂无问题、PS5 DualSense 蓝牙手柄正常，其他游戏及触觉反馈/自适应扳机仍未验收。
- 最新 WebView 显示修复实验：用户报告发送验证码后验证窗口显示异常，授权清理。关闭已确认的星铁 PID 94246 后，reset-webview.rb 仅备份并删除 MIHOYOSDK_WEBVIEW_RENDER_METHOD_h1573598267 和实际存在的 HOYO_WEBVIEW_RENDER_METHOD_ABTEST_* 共 2 项，回读确认删除；备份 webview-render-backup.json 在忽略的 hkrpg-dxmt-nv-20260905 实验目录，可按原 name/type/data 用 wine reg add 恢复，未删其余注册表/游戏文件。沿用 15 秒 dispatch 域名屏蔽重启，/etc/hosts 完整哈希再次恢复，PID 96587 / 窗口 13592 到达中文登录页。截图 webview-reset-window.png 已查看；手机号框为空（上次未完成登录），尚需用户重新输入并触发验证码后验证显示是否修复，不能宣称验证码已正常。此次日志 launch-webview-reset.log 关闭 +seh，避免之前调试日志大量增长。产品启动器尚未集成此实验。
- 最新星铁 4.5 启动网络对照取得登录页结果（2026-09-05）：独立 hkrpg-dxmt-nv-20260905 runtime/prefix，Jadeite 4.1.0 复制至 prefix/drive_c/mgb-jadeite 英文路径，用 launch.bat 经 wine cmd /c 启动。相同入口在线对照 launch-batch-control-ascii.log 仍 MHYPBase/0xc0000005；仅对 globaldp-prod-cn01.bhsr.com 增加带唯一标记的 hosts 条目 15 秒，launch-batch-block-ascii.log 则到达中文 miHoYo 登录页，窗口 Honkai: Star Rail / 13470，游戏 PID 94246（仅当时快照）。WDFLDR/HoYoProtect 报错仍存在，但不再阻止此次到达登录页，不能继续把它本身当致命根因。临时脚本 ensure 恢复并返回 restored_original=true；/etc/hosts 前后 SHA256 均 c7dd0e2ed261ce76d76f852596c5b54026b9a894fa481381ffd399b556c0e2da。未改游戏文件、NAS 或产品默认配置；未登录、未游玩、未性能验收，尚需重复性和登录后验证。初次直接执行 Jadeite 的实验只记录中间启动进程，不计有效网络对照；初版批处理中文路径无法识别，改英文辅助程序路径后才复现基线。窗口截图仅保留在忽略的实验目录，含登录界面私人信息，不纳入报告或提交。参考 YAAGL issue 734 comment 5226819817 与 Jadeite issue 104。无需再次下载游戏，nas 自动任务仍暂停。
- 21:33–21:36 星铁本机启动补测仍失败。创建独立 `LocalRuntimes/Experiments/hkrpg-dxmt-nv-20260905/{wine,prefix}`：原固定 CrossOver 11 runtime APFS clone，原 runtime 未改。确认原 nvngx.dll SHA 756eb5cf… 并非 DXMT 0.80 版本；独立 wine 与 prefix System32 均换为 DXMT nvngx SHA 18d5847e…，d3d11 与 DXMT 0.80 hash 一致。配置 YAAGL 三项 NV 注册表、WINEMSYNC=1、DXMT_ENABLE_NVEXT=1、NVIDIA vendor/device、GST rank、空 WINEDLLOVERRIDES，Jadeite 4.1.0 + -disable-gpu-skinning。图形设备初始化后子游戏退出，minidump=0xc0000005 / MHYPBase.dll+0x1872792，同时 WDFLDR.SYS 缺失、HoYoProtect c0000142。第二次对照按固定上游 HKRPG_REMOVED 临时移开 crashreport.exe 与 vulkan-1.dll，仍同址崩溃。两文件已恢复并逐一与最终官方清单大小/MD5 核对通过；游戏无临时替换残留、无 StarRail/jadeite 进程；未触碰 hosts/NAS，不是启动成功。日志 launch.log、launch-upstream-files.log，配置 configure.bat 均在该独立实验目录；崩溃 dump 在该 prefix 的 AppData/Local/Temp/miHoYo 子目录。下一步应继续保护链/适用上游兼容版本调查，不再把 NV 配置或下载损坏当未排除主因。
- 星铁本机重装完整校验已通过：hkrpg-local-reinstall-final-verify.json 返回 complete=true、11,208 文件、111,236,307,068 bytes、failedFiles=0，用时 162.97 秒；exec 13409 已正常退出。官方 success/ready 4.5.0 与独立文件完整性两层均通过，本轮尚未启动游戏/登录/性能验收。安装目标仍 `/Users/example/Games/MacGameBridge/Trials/StarRail`，NAS 不迁移，原神按用户授权已删除，定时任务 nas 不恢复。
- 21:17 用户要求继续关注、不暂停，保持轻量模式、不重开定时任务。星铁本机官方状态已 success/ready 4.5.0，108,846,544,086 bytes 下载完成，monitor 96004 已正常终态退出。已导出当前最终完整 Sophon 清单 11,208 条到 hkrpg-local-reinstall-final-manifest.jsonl，并启动唯一完整大小/MD5 校验（exec 13409 / PID 82314，结果 hkrpg-local-reinstall-final-verify.json）；尚待校验完成，不重复启动校验。目标仍本机 Trials/StarRail，NAS 暂缓。
- 2026-09-05 20:54 用户明确授权删除原神腾空间：确认没有 YuanShen/Genshin 进程和目录占用、规范本地路径后删除唯一 `/Users/example/Games/MacGameBridge/Genshin Impact`（约 150 GiB，未进废纸篓、无完整备份）；保留启动器、Wine/runtime、prefix 和设置。删除后可用约 176 GiB。按用户上一条要求立即在本机下载安装星铁、NAS 迁移暂缓：重启既有隔离 HYP（exec 46038），官方 uninstallGame 清除旧缺失 NAS 路径绑定后读回 need_get_game/空路径，再 install 到 `/Users/example/Games/MacGameBridge/Trials/StarRail`。官方预算 108.85 GB 下载、122.31 GB 含余量，可用 188.92 GB；真实绑定与设备号均为本地，progressing 0.30%→1.86% / 2.00 GB，瞬时约 102.40 MB/s、无错误。尚未安装完成/最终校验/启动验收，不将短时速度当长期 A/B 结论。轻量 monitor exec 96004 每 30 秒终端一行，nas 定时任务仍 PAUSED；不写 NAS、不重建重型监控。最终完成后仍需完整 Sophon 清单校验，再独立启动实验。证据 hkrpg-local-reinstall-{start-20260905.jsonl,status.json}；旧“保留原神/本地空间不足/不开始本机下载”均已过时。
- 用户最新要求立即在本机下载并安装星铁，迁移 NAS 暂缓，覆盖下方“等待升级后才下载”。本轮实时 df 本地仅剩 27 GiB；此前同版官方安装预算含余量为 122,310,048,892 bytes（约 122.31 GB），当前明显不足，约需再释放 95 GB。尚未启动下载，也未修改旧 HYP 绑定；不删除原神或用户文件，待用户指定可清理内容/其他本地存储。NAS 和定时监控继续保持不操作。
- 18:56 最终清理验收：官方卸载已开始删除，但 NAS 小文件逐个清理过慢；关闭已核对的隔离 HYP PID 13493，确认该进程退出且 lsof +D 无目录占用后，用 macOS 对真实 SMB 卷上唯一规范 StarRail 目录递归清理。命令成功、目录实际消失；不是移入废纸篓，无完整备份，后续需重下载。监控进程和 19222 监听均已结束，nas 定时任务保持 PAUSED；原神目录与既有诊断保留，未卸载 NAS 共享。官方卸载回调未完成，旧实验 prefix 可能仍有路径绑定，下次重建下载前需重新检查/清除绑定，不能把旧 waiting 当作在安装。当前等待用户 NAS 升级后继续，不启动本地下载。
- 用户最新决定停止 NAS 下载并删除星铁半成品，NAS 即将升级；以后改为先本机下载再移动 NAS，暂不开始新下载。已确认暂停到 cancelled（约 68.74% / 74.85 GB），轻量监控 67458 已自行结束，定时任务 nas 仍 PAUSED。通过当前隔离官方 HYP 对唯一绑定 StarRail 路径发起 uninstallGame，killProcess=false；清理结果待下方最新验收补充。原神和诊断资料保留。不自动恢复下载或挂载、不因为下方旧进度继续安装。
- 18:15 用户要求降低监控开销：已用产品工具将 nas 定时任务暂停并读回 PAUSED，覆盖下方历史 ACTIVE 描述。改为 script/hyp_install_trial.mjs monitor hkrpg_cn 常驻只读监控，每 30 秒输出一行进度，终态自动结束、超 90 秒旧状态明确标注，不唤醒模型、不周期重读文档。exec 会话 67458，首次真实输出 progressing 61.90% / 67.30 GB。原下载不暂停、不重建；轻量进程只显示进度，不会自动执行校验或修复。后续用户继续时检查该会话/实际状态再接续完成校验和启动。脚本 node --check 通过。
- 17:52 下载瓶颈只读诊断及独立临时测试：HYP 实时限速关闭；同一星铁资源原生 curl 丢弃输出，固定旧节点约 15.31 MB/s、新解析节点约 20.60 MB/s；NAS 512 MiB 顺序写入/fsync 实测 60.70 MiB/s、校验通过，临时文件已删除。主进程没有 CPU 跑满、NAS 空间充足。问题收窄为 HYP/Sophon 经 Wine 的下载调度/分块落盘链路，但还没证明 SMB 小文件等待或某个系统调用是主因；fs_usage 需要管理员权限，未使用密码。未暂停/重启下载、换 DNS、关 SMB 签名或修改原神。详情 docs/HSR_DOWNLOAD_BOTTLENECK_2026-09-05.md；监控继续。
- 用户最新要求“持续去监控，别停”：已通过 Codex 产品工具在当前任务创建并读回 ACTIVE 的 heartbeat，名称“星铁 NAS 下载与启动修复跟进”，automation ID `nas`，每 5 分钟检查。仅阶段完成、明确异常、需用户操作或实质修复结果时通知；正常进展保持安静。任务覆盖星铁 NAS 下载 → 最终清单完整校验 → 独立 prefix 启动修复与实际首屏验证，不只是轮询下载；原神已由用户确认正常，不关闭或改其配置。成功验收或用户要求停止后才暂停此跟进，避免完成后空转。不要再创建重复自动化；后续更新用该 ID 并保留其他字段。Mac 和桌面 app 必须运行、NAS 可达，本轮未修改系统电源设置。
- 监控最近实时检查（2026-09-05 18:10，事件时间 18:10:08 +08:00）：Lucian SMB 挂载正常；星铁 NAS 为 progressing，60.88% / 66,185,062,622 bytes，约 4.49 MB/s，无 errorCode，较 18:04:40 的 64,898,928,476 bytes 持续增长。官方安装状态仍 need_install，绑定目标仍为 Lucian/MacBook-Pro-M5-Pro/Games/StarRail；未开始最终校验或启动试验。监控 nas 保持 ACTIVE，没有重复启动下载或打断原神。基线快照 hkrpg-monitor-baseline-20260905.json 后续可能被最新检查替换；判断必须用事件时间戳，不将旧日志当实时状态。
- 16:29 后 NAS 最新状态：用户已指定独立 `Lucian` 共享，已实测挂载 `/Volumes/Lucian`，不是 codex项目空间/Lucian。建立 `/Volumes/Lucian/MacBook-Pro-M5-Pro/{Games,Projects,Apps,Backups,Media,Downloads,Diagnostics/MacGameBridge}` 和 README；规则写入 AGENTS.md。512 MiB 随机文件写入/重命名/SHA-256 读回通过，写入 69.28 MiB/s，缓存读回不当作实际网速；仅自身临时文件已删除，报告已存 NAS。未迁移原神、源码或原账号环境。
- 星铁已开始直接下载到 `/Volumes/Lucian/MacBook-Pro-M5-Pro/Games/StarRail`：约 108.85 GB、4.5.0，progressing 1.917%→3.235%，NAS 文件实际出现，无错误。脚本新增 `MGB_TRIAL_ROOT` 显式已有根目录及 SMB 挂载防假路径检查；NAS 预检实际超过原 12 秒，改为单次 180 秒后成功，不要重复排队。官方 HYP 隔离后台现运行，日志 launcher-nas-trial-20260905.log，仅本机 19222；launch exec 会话 84834，watch 会话 2644（最长 30 分钟，结束不等于下载结束）。后续先查 hkrpg-nas-install-watch-20260905.jsonl / 真实状态，完成后独立最终清单校验，再试完整 YAAGL 配置；不要重复新建安装。详情 docs/NAS_STORAGE_TRIAL_2026-09-05.md。NAS 原地更新尚不支持，星铁尚未修好。
- 用户最新确认：“原神已启动，没啥问题”。原神重装后的启动按用户实际反馈记为通过，保留当前成功配置，不因此前定向截图为白色就判断游戏故障。用户未单独说明登录、具体可玩场景、持续时长或性能，因此不扩大为性能/长期稳定/NAS 启动验收。没有退出或重启用户当前游戏。同期星铁 NAS 下载为 progressing，约 21.64% / 23.80 GB，约 30.65 MB/s，无 errorCode；仍未安装完成或开始本轮兼容启动试验。
- 原神重装最新结果（16:04 起）：官方安装 success/ready 7.0.0，总下载事件 138,989,603,579 bytes；关闭隔离 HYP 后独立完整清单 2,848 文件 / 142,503,873,726 bytes 大小/MD5 全通过（176.64 秒）。新 complete marker 已写，使用 `renamex_np(RENAME_EXCL)` 从 `Trials/GenshinImpact` 移回原 `/Users/example/Games/MacGameBridge/Genshin Impact`，不再缺失原目录。原生 app 重开正确显示已安装，实际点击“开始游戏”，使用原 DXMT + Steam、既有 prefix 和 5120×2880 全屏/fps120/HUD 偏好，进入真实中文启动场景。游戏内又自动开始约 15,887.77 MB 资源补充，当前仍在下载，尚未进入可玩场景；不要把基础安装完整校验当成热资源已完成。当前游戏 PID 6476、原生 app PID 6429、窗口 ID 12101（使用前须重新确认）；日志 `~/Library/Application Support/MacGameBridge/LocalRuntimes/Diagnostics/launcher-20260905-160441.log`。官方 HYP 和 19222 调试口已关闭。最新证据及 marker/config SHA 见四游戏试验报告；下方“原神下载中/原目录已删除”是本次试验前阶段。
- 最新追加要求：用户要求后续再次测试并修复星铁，并尝试 NAS 安装以释放本地空间。原神重装仍在进行，不中断重下；之后增加 NAS 存储试验。只读发现已挂载 SMB `/Volumes/codex项目空间`，约剩 4.7 TiB，已异步询问能否使用新的 `MacGameBridge/Games` 子目录，未获答复前不往该共享写游戏。Wine/prefix 先留本地，游戏资源可考虑 NAS。当前产品 `GameInstallationService.startOrResume` 对已安装网络盘游戏仍禁止原地更新，因为依赖 APFS 克隆备份；NAS 启动、更新、断连恢复应分别验收，不能把迁移成功算全流程可用。`smbutil statshares` 对该已挂载共享返回查找失败，但 `mount`/`df`/`stat` 可读，尚未证明 SMB 会话诊断失败等于目录不可用。
- 2026-09-05 用户最新授权：先删除游戏重下，实测原神、崩坏：星穹铁道、绝区零、崩坏 3 四款的安装链。当前优先级从更新容量预算修正切换为真实安装试验；预算修正本轮尚未实现。`AGENTS.md` 已同步四游戏管理范围，但现有 SwiftUI 产品仍只有原神，不把试验脚本算成多游戏界面交付。
- 已按明确授权删除唯一原游戏目录 `/Users/example/Games/MacGameBridge/Genshin Impact`（约 136 GiB），未进废纸篓，需要重新下载。删除前确认无运行游戏、无目录符号链接，保留 `config.ini`、managed marker、`pkg_version` 和启动器偏好至 `LocalRuntimes/Experiments/install-reset-20260905/`。原 Wine 运行时、原神 prefix 和登录环境未改动。下方“原神仍已安装/未触碰真实游戏”仅是此前轮次历史。
- 隔离官方启动器 1.18.0.380 的 prefix 为 `~/Library/Application Support/MacGameBridge/Experiments/hoyoplay-20260904/prefix`，仅监听本机 127.0.0.1:19222 的临时调试端口。`script/hyp_install_trial.mjs` 通过该实例真实 CefViewQuery 控制指定 `~/Games/MacGameBridge/Trials` 子目录安装；不是生产下载接口，也不是原生窗口可用证据。发现默认语音为英文，试验明确只选 zh-cn。暂停回调早于实际停止，必须等 cancelled 后再恢复；已实际保留部分数据并续传，未证明网络请求零重传。
- 崩坏 3 国服 9.0.0 已完成官方 31.19 GB 下载和 verifying→success。完整 Sophon 清单 1,056 文件/34.82 GB 大小与 MD5 全通过。直接启动在 MHYPBase.dll 崩溃；隔离 prefix 加入现有固定 Steam/lsteamclient 入口后，真实窗口到中文游戏内资源下载页（基础约 13,586 MB / 全部约 28,056 MB）。没有继续额外资源、登录或可玩场景。用户已选择分批测试最终保留原神，故关闭该独立 prefix 后通过官方 uninstallGame 清理了 `Trials/HonkaiImpact3`；返回 success，目录已消失，状态恢复 need_get_game。完整清单、校验报告和截图均保留；再次运行需重下载。
- 绝区零 3.1.0 完成 81.98 GB 官方下载及 verifying→success，独立完整清单 12,199 文件/83.30 GB 大小与 MD5 全通过。独立 `Experiments/nap-cn-first-install/prefix` + 固定 Steam 入口已实测到中文协议页；未接受新协议、未登录或进入可玩场景。已关闭该 prefix，并通过官方卸载清理 `Trials/ZenlessZoneZero`，实际目录消失、状态 need_get_game；config/pkg_version 和完整证据保留。星铁现已在 `Trials/StarRail` 开始下载，原神重装尚未开始。
- 用户确认分批测试、最终保留原神，其他测试安装完成记录后清理。进度、校验和日志在 `LocalRuntimes/Experiments/hoyoplay-20260904/`；原神最终将从隔离 trial 完整校验后恢复到原位置，防止早期 exe 导致现有 UI 误报已安装。旧 GameProbe 关联已取消，曾遗留的约 878 MiB 占位副本也已单独清理；autoUpdateWpf=false 已重新读回确认。三款测试游戏的临时 Wine prefix 已在停止进程、归档关键诊断后删除（约 2.2 GiB），原神原环境未改动。详见 `docs/FOUR_GAME_INSTALL_TRIAL_2026-09-05.md`。
- 星铁暂停到实际 cancelled（5,719,190,988 bytes）后已停止并重开 HYP 隔离 prefix。目录绑定保留，但 resumeDownload 不恢复；已根据官方前端 startInstall 接口改用受限 `continue-install` → startDownload/isInterrupted=true，进度实际超过原断点并最终完成。不要再把新后台的 need_install 当成可直接 resumeDownload 的内存暂停任务。HYP 当前日志为 `launcher-resume-trial-20260905.log`，星铁完整过程 `hkrpg-resumed-watch-20260905.jsonl`，最终完整校验见下一条。
- 星铁后续结果：4.5.0 下载 108.85 GB 官方 success/ready，独立 11,208 文件 / 111.24 GB MD5/大小全通过，重启续传完整性已验收。启动未通过：Steam 入口很快退出 231；Jadeite 4.1.0 的默认 explorer 与可选 Steam 父进程也失败，子游戏在 MHYPBase.dll 崩溃 0xc0000005，含 WDFLDR.SYS/HoYoProtect 加载失败。未做登录、性能或其他 Wine/NV 扩展配置，不能归因于 macOS beta，也不标为可玩。已保留完整诊断并清理 StarRail 测试安装；原神现开始在 `Trials/GenshinImpact` 重新下载，完成独立校验后恢复至原目录，最后只保留原神。原神进度文件 `genshin-install-watch-20260905.jsonl`。

- 2026-09-05 本轮继续补更新中断恢复。新增 `GameInstallationRecord`，先判持久化 marker，再判主文件；downloading、损坏标记、complete/config 版本冲突、主文件缺失均不再误报可启动。写入前原子标记 downloading；Python 完成校验后原子提交 complete。暂停／错误必须等待自有子进程退出后才解除忙碌；无输出卡住时仍会发停止信号，10 秒后仅强制结束该下载子进程。入口和 `GameRuntimePaths` 均检查恢复状态。
- 续传不重新克隆中断目录、不覆盖原安全备份；备份层拒绝用未完成目录创建回滚点。主文件丢失但目录仍存在时可恢复旧备份；原子交换后保留的半成品明确标为不可回滚，不能再次切回当作完整版本。旧版本能否登录由服务器决定。首页增加“继续更新或修复”，恢复页明确无备份／半成品状态，不再给中断更新展示初装全量空间提示。
- 更新、备份、回滚和迁移使用与 Python 一致的 flock；更新锁经 stdin 继承给子进程，启动器关闭也不会提前释放下载锁。重开时只读检测到仍有写入者会阻止冲突操作。版本检查结果用请求 ID 隔离，取消的旧请求不再覆盖恢复状态。未把备份/恢复操作改成自动覆盖整个真实游戏。
- 本轮隔离验证：全项目 `env -u PROTOC_PATH swift test` 421 项 / 53 套件通过；其中启动器 80 项含新增 12 项恢复测试（损坏标记参数化），使用临时 APFS 小文件、独立 UserDefaults 和实际测试子进程，覆盖失败→重建服务→续传、备份不变、缺主文件回滚、半成品反向回滚拒绝、暂停等待写入者、继承锁父句柄关闭后仍排他、完成标记和版本一致性。Python 4 项离线测试覆盖原子提交失败不破坏旧记录、0600 权限与继承锁。严格 Swift 格式与 diff 检查通过；原始日志 `/tmp/mgb-recovery-full-tests.log`、`/tmp/mgb-recovery-lint.log`。
- 开发包 `./script/build_and_run.sh --verify` 构建并启动，深度严格签名检查通过。实际 GUI 核对首页仍显示国服 7.0.0／开始游戏，进入管理菜单、备份页（尚未创建回滚点）、安装更新页（7.0.0 最新）后返回首页；没有点击创建备份、校验或开始游戏。真实 marker/config 只读 SHA-256 为 `aeb1c5da64db6229fdd20b763f78e7d6eabcd832a107677bcb44e29651308537` / `543a4b4c9cfff03ac214d33f0358b98dd69e0c338afef7bc56782ae37d6b30fc`；既有安装路径和实验/分辨率偏好保留。恢复错误页由状态测试覆盖，未把真实游戏做成损坏状态进行 GUI 演示。包日志 `/tmp/mgb-recovery-package.log`；未发布到 GitHub、未做公证或全新 Mac 验收。
- 剩余更新验收：没有对真实 7.0 游戏更新／备份／回滚，没有完成 7.1 可玩兼容验证或真实预下载。下载器仍在原目录更新，恢复靠继续校验或用户选择回滚，并非完整 staging 事务；容量预检仍按全量安装大小保守计算，需后续按实际变化文件／缓存／APFS 增量占用修正。断电 durability、网络盘中断恢复和强制结束整个 GUI 的真实大文件实验尚未验收。下方 68 项测试及“失败仍可启动”是此前 UI 轮次历史，本轮已修正状态问题。

- 2026-09-05 用户提供米哈游启动器截图，要求借鉴逻辑而非照搬外观，随后授权继续。首页现采用单一主按钮 + 相邻原生“游戏管理”菜单；不新增多游戏侧栏、活动新闻或社交入口。运行组件版本从首页移到已有运行环境设置。主按钮由 `Models/GamePrimaryAction.swift` 统一结合安装、运行环境、游戏运行、更新、磁盘可达性、迁移和备份状态计算：新版本→更新、下载中→暂停、迁移中→取消、离线磁盘→重新检查、备份/回滚中→查看进度、运行中→禁用重复启动。自动准备环境完成后也会重新检查主动作，避免已发现更新或正在迁移时自动启动。
- “游戏管理”菜单包含安装与更新、安装位置与迁移、检查更新、校验修复、备份回滚、目录和已有日志；运行时才出现退出游戏。管理弹层改为安装／存储／恢复三个分页，按入口直接选择页，恢复按钮继续沿用原 APFS 机制；不把 UI 调整当成新版更新事务或预下载实现。校验菜单在执行前说明会按官方当前版本补文件，也可能更新；游戏活跃或任务忙碌时禁止冲突操作。窗口重新活跃时只读刷新磁盘状态。
- 本轮状态与界面验证：`env -u PROTOC_PATH swift test --filter BridgeStatusTests` 68 项 / 6 套件通过，包含新增 11 项主动作测试（部分参数化），跨卷测试因未挂验证卷跳过，本轮未重复跨卷实验。严格 Swift 格式与 diff 检查、最终 `build_and_run.sh --verify` 和 `codesign --verify --deep --strict` 通过。已在开发包实际打开首页、原生管理菜单、三个管理分页、修复确认框并取消返回；最终包重新核对首页与菜单，安装路径、5120×2880、fps120、HUD=1 均未变。没有点击开始游戏或开始校验，没有下载、更新或迁移真实游戏。底层“更新中断后仍判已安装”的历史问题及新版预下载事务本轮未修改，继续作为独立待办，不能把统一按钮测试当成更新失败恢复验收。
- 2026-09-05 最新取舍：用户以“完全可控”为先，多游戏不可稳控时接受只做原神。本轮保留原神产品范围，实际补齐存储管理，没有替换为官方 HYP 后台或增加其他游戏入口。安装位置可持久保存；“定位已有游戏”接受任意目录名的 YuanShen.exe + YuanShen_Data 根目录；修复此前刷新会重新拼接 Genshin Impact、丢失自定义根目录的问题。
- 新增“迁移游戏”：选择目标父目录，4 MiB 流式复制，逐文件 SHA-256 读回校验，检查源清单大小/修改时间未变，以排他 rename 发布后才切换偏好。目标同名目录、符号链接、空间不足、取消、复制/校验错误不覆盖原目录。迁移期间禁止应用内启动、更新、备份和改路径；原游戏、原下载缓存与原 APFS 备份不自动删除，提供 Finder 旧副本检查入口。旧副本入口目前仅保留于本次应用会话；突然退出或断连留下的隐藏 staging 尚无跨启动恢复/清理 UI，网络盘不标为正式支持。
- 存储能力根据实际卷探测显示文件系统、网络/本地、写权限与克隆备份能力。APFS 可继续沿用现有更新与回滚；网络盘/非克隆卷明确提示：可以尝试存放，直接运行未实测，更新前需迁回本地 APFS。/Volumes 下离线安装目标不会向上回退到内置磁盘创建下载目录。兼容 runtime/prefix 仍在本机 Application Support，不承诺内置盘零占用。
- 本轮验证：58 项启动器相关测试 / 5 套件通过，含 12 项存储测试；额外创建并挂载独立 2 GiB APFS 稀疏磁盘映像，真实验证跨卷复制和 SHA-256 校验，通过后卸载并删除仅本次生成的 15 MiB 映像。严格格式与 diff 检查、最终 `build_and_run.sh --verify` 和深度严格签名校验通过。开发包实机检查了存储页布局、迁移选择器、APFS 目标确认和取消不改路径，并重新定位原来的完整游戏目录，仍识别为 7.0.0；未触发下载、更新或真实游戏迁移。回读安装路径、5120×2880、fps120、HUD=1 未变，语言仍沿用未覆盖时的中文默认值。尚未验收实体外置盘游戏运行、SMB/NFS 复制/断连恢复、迁移中强制退出、正式分发。
- 用户最新目标扩大为米哈游四游戏统一启动器，并要求先核查可行性；本轮未改产品代码或 AGENTS.md 的旧原神范围，实施扩大范围时需同步项目规则。可行性报告见 `docs/MULTI_GAME_LAUNCHER_FEASIBILITY.md`：在独立 HYP 环境中，以相同 getGameInstallInfo 接口分别查询 hk4e_cn／bh3_cn／hkrpg_cn／nap_cn，四款均返回 success、安装空间与语音信息；一次 getLocalGameInfo 能分别返回四款状态。证明共用管理模块可行，不证明完整下载／更新或四款在 Mac 上可玩。建议原生 UI + 共用安装协调层，优先验证官方后台适配，Sophon 自有实现保留为备选；不把调试口当生产 API。本轮未启动整包下载，实验进程及 19222 端口已关闭。
- 官方启动器机制实测已推进，见 `docs/OFFICIAL_LAUNCHER_EXPERIMENT.md`：用户授权协议后，自定义安装 1.18.0.380 到独立 prefix 的 `C:\MacGameBridge\miHoYo Launcher`，无桌面快捷方式／开机自启。CEF 前端与后台查询可用，但实际窗口白屏；关闭 CEF GPU／Qt 软件渲染未修好，CEF 内部截图正常不能当作桌面可见验收。已从运行中官方前端确认 CefViewQuery + HYPClient 的安装／关联／更新／预下载／进度接口，并实测目录关联和重启持久化。
- 仅含 YuanShen.exe + config.ini 的 `C:\MacGameBridge\GameProbe` 测试副本也被官方报 ready，不能当作可玩或校验成功。关联会自动下载 WPF：测试副本新增约 466 MiB BeyondAssets，配置 wpf_version=7.0.0.47194594；随后已通过接口关闭 autoUpdateWpf 并重启回读保持。正式游戏和默认 prefix 未改，未下载完整游戏／执行版本更新。官方预下载查询当前 needPreDownload=false；预下载、合成与恢复仍待真实窗口验收。临时调试口仅绑定 127.0.0.1:19222，结束已停实验 prefix 并关闭端口；实验环境保留，产品下载链未替换。
- 预下载研究已完成首轮只读核查，见 `docs/PREDOWNLOAD_RESEARCH.md`：官方国服接口当前 main=7.0.0、pre_download=null；YAAGL 固定版及上游所读默认分支的国服 ldiff 更新 URL 仍 TODO。Collapse 示例有旧／新清单差异块预下载与缓存合成路线，建议作为先验证方向。未实现预下载、未下载资源、未修改游戏目录；等待真实 7.1 预下载窗口才能验收版本数据。无需用户提供账号密码或整包文件。
- 用户否定深青重金配色，提供原神天空之门登录截图作为参考。当前视觉改为云白／暖象牙面板、蓝灰文字和天空蓝强调；主视觉风景保留。新版天空之门图标已生成预览，但生成工具连续输出假透明棋盘格，正在等待用户授权本地去背景处理；不能宣称新图标已装入应用。
- 用户询问换机和 7.1：已完成包签名／依赖和更新源码核查，详见 `docs/DISTRIBUTION_AND_GAME_UPDATES.md`。关键未完成项为 Developer ID／公证、默认 Gatekeeper 干净机器验收、Rosetta 引导、更新事务／失败恢复。当前失败后“旧版本仍可启动”的提示没有文件事务保障，不能当作事实。仅做核查，未改下载／运行链。
- 第二轮整体视觉：保留静态风景，改为延伸到标题栏的整窗背景、深色底部启动栏和浅金主按钮；原生交通灯保留，标题区域增加 WindowDragGesture。设置改为游戏／运行环境／实验功能三段切换，安装更新页去掉重复标题与多层彩色卡片，统一深色主题。未改启动、下载、偏好持久化逻辑；启动器相关 46 项测试通过。
- 首页视觉重做：静态生成风景主视觉、原生启动操作栏、紧凑运行环境信息和设置入口；保留全部原有安装／启动状态处理和错误提示。图片在 SwiftPM 资源包中，并由开发打包脚本复制到应用 Resources；素材来源及提示词见 `docs/LAUNCHER_ARTWORK.md`。本轮不改游戏文件、运行组件或持久化偏好。
- 视觉修改验证：Swift 构建、严格格式检查及启动器相关 46 项测试 / 4 个套件通过；未重跑核心下载全量测试，未启动游戏。首次打包窗口检查发现命名图片未显示，改为缓存 NSImage 从资源 URL 显式加载。
- 最终开发包已重新构建启动，实机确认背景、标题、启动操作栏显示正常；安装更新页可打开并返回，设置入口可打开。实机回读原有 5120×2880、简体中文／汉语、120 FPS 开启及 HUD 开启均保持。窗口仍保留用户之前的尺寸，未进行所有尺寸或深色模式验收。
- 用户要求只做原神国服启动器：首页只有安装／续传／启动、进度、错误和安装更新入口；移除通用游戏库、添加游戏、开发工具、路线图和性能基准 UI，底层安装、校验、恢复能力保留。
- 设置使用原生独立窗口，分为游戏、运行环境、实验功能。实验只保留手动启用的 120 FPS 和 Metal HUD；旧 fps144 值读取时失效为关闭，隐藏的旧详细日志设置不再影响普通启动。
- 用户随后要求去掉 GPTK：运行环境固定为 CrossOver 11.0-1 + DXMT 0.80，Steam 兼容入口保留。已移除设置导入／切换 UI、GPTK 服务实例、启动分支及早崩回退流程；旧偏好和直接传入的旧组合均按 DXMT 启动。历史报告模型、共用解帧 shim 和本地已导入文件保留，不做磁盘删除。独立 Wine 升级管理器尚未实现。
- GPTK 移除验证：构建、开发包启动、严格签名和实际运行环境页检查通过；最终全量复跑 387 项 / 50 套件通过。首次全量和单例复跑中，既有 interruptedTransferCheckpointsThenResumesWithStrict206 因未生成 partial/checkpoint 失败，后续全量复跑通过；记录为未修复的间歇性测试失败，不修改无关下载模块。未重新启动游戏。
- 新增安装／运行环境／启动／版本检查的显式错误卡；运行组件错误带失败步骤和退出码，异常退出不再直接回到就绪。
- 本轮不更换实际 Wine、DXMT、GPTK 或游戏文件，不开启实验功能、不登录账号；GitHub 公开发行的 Developer ID、公证与全新 Mac 一键安装验收仍未完成。
- 本轮验证：386 项测试 / 50 个套件通过；严格 Swift 格式与 diff 检查通过；最终开发包构建、启动与 ad-hoc 签名检查通过。已实际打开首页、游戏设置、仅两项实验设置、运行组合菜单、安装更新页，并从安装页返回首页。保留用户已有的 5120×2880、120 FPS 和 HUD 选择；全新偏好默认关闭两项实验功能的行为由隔离 UserDefaults 测试覆盖。未进行新一轮游戏启动或全新 Mac 下载验收。

## 当前结论

- 用户已实际确认：国服《原神》7.0.0 原版客户端可以打开。
- 当前成功主路径是 `CrossOver 11.0-1 + DXMT 0.80 + Steam 兼容入口`，不是此前直接加载保护驱动的 Wine/WDF 实验路径。
- 用户已进入游戏并反馈“内存占用高、画质不高但掉帧”；持续运行、画面正确性和性能仍要分别验收。
- 2026-08-22 最新验收已从原生 App 真正拉起 `wineserver`、`services.exe`、`YuanShen.exe`、`explorer.exe` 和 `rpcss.exe`；验收结束后已由启动器停止。

## 已验证运行资产

- 游戏：`~/Games/MacGameBridge/Genshin Impact/YuanShen.exe`
- 正式用户 runtime：`~/Library/Application Support/MacGameBridge/Runtimes/genshin-cn-crossover11-steam`
- 正式用户 prefix：`~/Library/Application Support/MacGameBridge/Prefixes/genshin-cn-crossover11-steam`
- 项目内 `LocalRuntimes` 只保留为开发回退，不再作为当前 App 启动主路径。
- 图形后端：DXMT 0.80
- 启动入口：prefix 内的 Steam compatibility stub
- `LocalRuntimes/` 被 git 忽略；二进制、prefix 和诊断日志不会提交。

## 原生启动器现状

- SwiftPM 产品和 `.app` 均已改名为 `MacGameBridge`。
- 原生游戏库默认包含《原神》国服，也可通过文件面板添加其他 Windows `.exe`。新增游戏使用 `generic-crossover11-dxmt-r1` 实验 profile，首次启动自动建立独立 Prefix；需要专用启动器、DRM 或游戏特定补丁时仍会明确报失败。
- 原神详情页已有一键启动、停止、打开游戏目录、查看诊断日志、运行状态与自动化准备检查。
- 分辨率不再只有 4 个写死档位；启动器现在通过 CoreGraphics 汇总所有在线显示器的可用逻辑/像素模式，去重并排除短边低于 600 的内部缩略模式。当前机器实测得到 100 个可用尺寸，包含主屏 `2560×1440 / 5120×2880`、内屏 `1512×982 / 3024×1964` 和竖屏 `1440×2560 / 2880×5120`；菜单按“当前桌面、原生像素、常用窗口、其余模式”排序并标出宽高比。
- 原神详情页基准流程改为两阶段：先启动游戏并等待玩家进入大世界固定场景，再手动确认开始，稳定 10 秒后采集 60 秒 Metal HUD 逐帧数据并自动生成报告；普通启动不启用 HUD。旧的 75/30 秒数据只是启动/登录界面基准，不得当作游戏内性能结论。
- 启动器直接使用 `Foundation.Process` 调用固定 Wine/Steam 路径，不再要求用户复制终端命令。
- macOS 27 beta 上，GUI App 派生的 Rosetta Wine 从 `Documents` 开发目录启动会停在 dyld、无法生成 `wineserver`；相同命令从普通进程可成功。将 managed runtime/prefix 发布到 Application Support 后，原生 App 的 Wine 直启立即恢复。根因是开发目录/TCC 路径，不是游戏、Prefix、DXMT、环境变量或 `Process` API。
- 启动前设置不再逐条执行 `wine reg`，而是在 Wine 停止后原子更新独立 Prefix 的 `user.reg`，规避 macOS 27 GUI 子进程等待异常。
- 每次启动前自动停止 prefix、应用设置、再启动游戏；退出或“停止游戏”通过该 prefix 的 `wineserver` 收口。
- 当前界面实测可见，默认显示“可以启动”，游戏文件、runtime、Steam 入口和语言/窗口配置四项均就绪。
- 最新直启 smoke test 使用用户 runtime/prefix、DXMT 0.80、窗口 `1600 × 900`：15 秒内出现完整 Wine/原神进程链，HUD 持续输出 16.67 ms 帧记录；这是启动验收，不是已进入大世界或游戏内性能验收。

## 窗口与语言原因

当前 prefix 的原始状态已经确认：

- `Screenmanager Is Fullscreen` 为 `1`，分辨率为 `2560 × 1440`，所以此前不能小窗是配置导致，不是 Wine 强制。
- Wine Windows 区域为 `en-US`。
- 游戏文本 `deviceLanguageType=2`，对应简体中文。
- SDK 语言为 `zh-cn`。
- 语音 `deviceVoiceLanguageType=1`，对应英语。

启动器默认改为窗口 `1600 × 900`、简体中文界面、汉语语音，并将 prefix 的 Windows 区域切到 `zh-CN`。这些设置只写独立 Wine prefix，不修改 macOS 系统语言。

## 本轮性能定位

- 最新两次游戏日志确认 DXMT 0.80 DLL 已正确加载，不是 WineD3D 回退。
- DXMT 持久 shader cache 默认开启且已有约 72 MB 本地数据；不能简单归因为“没开缓存”。
- 原 prefix 是 `1600 × 900` 输出，但 `graphicsData` 仍使用最高内部渲染值 8，阴影/视觉/SFX/环境为高档，雾、反射、Bloom 和高人群也在开启；这解释了“输出看起来不高，实际显存/统一内存负载很高”。
- 游戏 VSync 和 DXMT 60 FPS Metal 帧率控制同时开启，且进入场景后仍持续出现 shader load；这是当前帧时间尖峰的主要假设。
- 启动器新增默认“平衡性能”档：60 FPS、1.0 内部渲染、中等环境/特效、低阴影，关闭游戏 VSync/雾/反射/动态模糊；仍可选“保留游戏设置”回退。
- 每 2 秒采集该 runtime 的 RSS、CPU 和进程数，界面显示当前/峰值内存，同时以 `MGB_PERF` 写入 launcher 诊断日志。
- 2026-08-22 的首轮平衡档实测产生 525 个采样点，约 17.5 分钟；峰值 RSS 5,900,636,160 bytes，结束前约 3.04 GB。游戏日志仍有 shader load，launcher 日志有 2 次 DXMT stream-output 警告。
- 原神页现会在后台解析最近一次 launcher log，显示运行时长、峰值/平均内存、CPU、逐帧统计与图形兼容事件，不需要用户手工抓日志。诊断统一写入 `~/Library/Application Support/MacGameBridge/LocalRuntimes/Diagnostics`，不再枚举受 macOS 26 访问控制影响的源码目录或开发 Prefix。

“安装与更新”页已从只读空间预览升级为原生任务入口：能识别已安装和未完成任务，选择安装卷后启动/继续固定国服下载，显示进度、速度、预计时间，并支持取消和查看日志。

更新中心会在已安装状态下用独立临时目录只查询一次国服 main 目标版本，不触碰实际 `config.ini`/marker，也不下载 manifest 或游戏内容。发现新版本后，现有下载器会按目标清单逐文件 MD5 复用正确文件，只补齐变化内容；当前版本也可手动执行同一路径校验修复。2026-08-22 实测目标仍为 7.0.0，两个本地状态文件前后 SHA 不变。

更新或校验已安装游戏前，`GameInstallationService` 现在必须先用 `/bin/cp -cR` 在游戏目录同一 APFS 卷创建 clone-on-write 安全备份；备份失败时下载器不会启动。界面可手动创建回滚点，也可用 `renamex_np(RENAME_SWAP)` 将当前目录和备份原子交换，刚替换下来的版本继续作为反向回滚点。小型真实 APFS 目录已经验证克隆隔离、连续双向回滚和回滚点替换；尚未对正在更新的 136 GiB 实际游戏目录执行备份或回滚。

主游戏页现在把安装、续传、运行环境准备和启动收口到同一个主按钮。开始安装时会并行准备 CrossOver/DXMT/Steam Prefix；游戏已经存在但用户运行环境缺失时，会在环境发布后自动继续启动。自定义安装目标会写入用户偏好，后续 `GameRuntimePaths` 和启动器使用同一路径。

当前开发 `.app` 已把可迁移 Python 3.11、`script/download_genshin_cn_full.py`、pinned YAAGL `ca78abc`、Protobuf/Zstandard/PycURL/psutil 与 hpatchz 打入 Resources。安装任务优先使用 bundle toolchain，日志写入用户 `Library/Logs/MacGameBridge`，离开源码目录也不要求用户安装 Python；项目内环境只作开发回退。构建已验证解释器 SHA、模块版本/import 和固定 YAAGL 文件哈希。正式发行仍需完成第三方二进制许可审计、签名和全新 Mac 真实下载验收。

开发 `.app` 现已内置六个固定运行时资产：CrossOver 11.0-1、DXMT 0.80 以及 32/64 位 Steam/lsteamclient。安装中心可校验大小和 SHA-256，在 staging 中解包并覆盖 DXMT，调用 `wineboot` 创建独立 Prefix，再发布到 `~/Library/Application Support/MacGameBridge`。启动路径优先使用这一用户安装，项目内 `LocalRuntimes` 只作为开发兼容回退。

GPTK 4 试验路径也已接通：应用已经真实导入 Apple 官方 `Game Porting Toolkit 4.0 beta 2` DMG，只读挂载内层 Evaluation image，拷贝 `redist/lib`，去隔离属性后复验 D3DMetal 签名并记录关键 SHA-256。启动 GPTK 时会克隆当前 CrossOver runtime 和 Prefix，仅在独立副本中覆盖 D3DMetal 模块；原 DXMT 运行时仍是默认且不受修改。

2026-08-22 已定位此前 GPTK 早崩的具体调用：Wine `+seh,+unwind` 栈和静态调用点共同指向 `ID3D11Device` vtable 偏移 `0xf0`，即 slot 30 的 `CheckMultisampleQualityLevels`。调整 Metal 版本、feature level、Unity threading、GPU ID 和 VRAM 报告均不能改变崩溃，已排除显卡身份与 38 GB VRAM 报告是根因。

应用现内置一个由本项目维护的 64 位 Windows `version.dll` 兼容 shim。它在游戏主模块中拦截 `D3D11CreateDevice`，保留 GPTK 返回的其余 42 个 device 方法，只把 slot 30 替换为保守的 MSAA 能力查询：sample count 1 返回可用，其余返回 0。原 `version.dll` 的 16 个 API 全部转发到准备阶段自动改名的 Wine builtin `versi0n.dll`，不要求用户安装 Zig、编辑注册表或复制 DLL。

隔离运行时 marker 已升级到 `schema=3 / genshin-cn-gptk4-v3`，记录 shim SHA-256。应用会自动安装 `version.dll`/`versi0n.dll`，缓存命中时重新校验 shim 和转发模块；文件缺失或被修改会重建独立 GPTK runtime/prefix。此前手工试验留下的 `d3x11`、AppInit 和备份 DLL 已通过这次重建清除。

最终打包 shim 和应用自动生成的纯净环境分别连续运行 60 秒，均没有再次出现 `0xc0000005`、VERSION API 缺失或进程退出。Unity 日志到达 `Home LoadScene`、`LoginMainPageContext`、`CNRELWin7.0.0`、资源校验、shader warm-up 和 `AfterOnBundleLoadFinish`；这证明 GPTK 4 已达到原神国服登录页启动 smoke gate，但还不是持续游戏或性能验收。启动器的 GPTK 早崩自动回退仍保留，DXMT 仍为已验证默认后端。

真实一键回退已在 2026-08-22 验证：GPTK launcher 写入 `MGB_FALLBACK reason=gptk_early_d3d11_crash target=dxmt`，约 16 秒后 DXMT launcher 自动启动；DXMT 游戏日志继续到 `LoginMainPageContext`、shader warm-up 和音频加载，证明不是只生成了一个 Wine 进程。

2026-08-22 已通过原生按钮分别完成 GPTK 4.0b2 / DXMT 0.80 同配置启动/登录界面采样。两边均为窗口 `1600 × 900`、平衡档，启动 75 秒后各采 30 秒并自动关闭。DXMT 1,830 帧：平均 60.0 FPS、1% Low 60.0 FPS、P99 16.67 ms、CPU 162%、峰值 RSS 约 2.3 GB；GPTK 1,831 帧：平均 60.4 FPS、1% Low 40.0 FPS、P99 25.00 ms、CPU 253%、峰值 RSS 约 2.3 GB。这些数据不是游戏内性能证据；已从游戏内后端对比卡中排除。

随后由用户分别确认已进入同一游戏场景，启动器各采集约 60 秒真实游戏内数据。DXMT 3,567 帧：平均 57.40 FPS、P99 16.67 ms、27 个大于 33.34 ms 的慢帧、最大帧时间 516.66 ms、采样窗口平均/峰值 RSS 约 4.51/4.64 GiB；GPTK 3,164 帧：平均 53.45 FPS、P99 91.67 ms、103 个慢帧、最大帧时间 425 ms、平均/峰值 RSS 约 5.87/6.16 GiB。GPTK 慢帧数约为 DXMT 的 3.8 倍且多占约 1.2 GiB 内存，因此 DXMT 已恢复为默认。用户场景由用户口头确认，Wine 窗口未暴露 Accessibility，画面正确性仍需用户反馈。详见 `docs/PERFORMANCE_GPTK4_VS_DXMT_2026-08-22.md`。

原神启动设置新增可折叠的“实验功能”，通过 `@AppStorage` 自动保存：关闭/120/144 FPS 解锁、详细 Wine 诊断日志、Metal 性能 HUD、GPTK 已知早崩时自动回退 DXMT。解帧默认关闭；正常启动默认使用 `WINEDEBUG=-all` 减少日志开销；基准测试仍强制记录隐藏的 Metal HUD 帧数据。Steam 兼容入口是当前成功链的必要条件，仅显示状态，不提供已知会破坏启动的开关。

YAAGL `ca78abc / 0.3.18` 虽有“不解锁、120、144”的持久设置 UI，但全仓只有设置定义与保存，原神启动流程没有读取 `fpsUnlock`；其官方 FAQ 也说明超过 60 需要修改游戏且可能触发异常行为检测。因此实现参考 MIT 项目 `34736384/genshin-fps-unlock`，由已有 `version.dll` 代理在游戏进程内扫描 `il2cpp`并写入目标帧率。当前 7.0.0 `YuanShen.exe` 静态扫描有 22 个原始特征、2 个上游过滤命中，最终去重到唯一可写目标。DLL 增加映像边界、页保护和唯一目标校验；更新后不匹配时只写失败状态并保持默认帧率。DXMT/GPTK 的自动安装、环境隔离和 UI 状态提示已完成，但尚未在登录账号上启用进行真实运行/帧时间验收。

开发包现在在复制完全部资源后执行 ad-hoc 深度签名和严格校验。内置 Python 禁止写 `.pyc`，打包时移除 `__pycache__`；实际启动后再次执行 `codesign --verify --deep --strict` 仍通过。Developer ID 签名、公证和全新 Mac Gatekeeper 验收仍是正式分发门槛。

本轮代码验证为：`swift format lint --recursive --strict Sources Tests` 通过；完整 `swift test` 共 379 项通过，其中新增 DXMT 解帧代理安装、原运行时不变、GPTK 环境隔离、状态解析和显示器特定分辨率覆盖。Windows shim 交叉编译为只依赖 `KERNEL32.dll` 的 13,312-byte x86-64 PE DLL，16 个 VERSION 导出完整。`./script/build_and_run.sh --verify` 与包级 `codesign --verify --deep --strict` 均通过，打包资产 SHA-256 复验通过；打包后的原生界面已实际展开并核对 100 个分辨率选项及其排序。

## 下一步

1. DXMT 与 GPTK 4 的首轮游戏内对比已完成，DXMT 明显更稳且更省内存；下一轮只需补充同一路线视频/截图和用户画面正确性反馈，特别检查 GPTK shim 禁用 MSAA 后的边缘质量。
2. 通用游戏 profile r1 已能自动准备独立 Prefix 并直接启动 `.exe`；下一步是按游戏积累专用参数和可修订 profile。
3. 用下一次真实游戏更新记录官方预下载的增量元数据，并验收 APFS 回滚点的创建耗时、增量空间和一键回滚；当前版本不凭空模拟预下载协议。
4. 在一台没有源码目录和开发 Python 的全新 Mac 上验收应用内下载、续传、运行环境准备与启动全链。

具体优先级见 [PRODUCT_TODO.md](PRODUCT_TODO.md)。

## 常用验证

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
env -u PROTOC_PATH swift build --product MacGameBridge
env -u PROTOC_PATH swift test
swift format lint --recursive --strict Sources Tests
```

构建通过、应用窗口打开、游戏窗口打开、登录成功、持续运行和性能验收是不同阶段，必须分别报告。
