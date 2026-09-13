# 当前研发状态

更新时间：2026-08-22

## 已完成

1. SwiftPM 项目、MIT 许可证与项目级工作规则。
2. macOS、Apple Silicon、Metal、Rosetta、Xcode、GPTK/D3DMetal、Gatekeeper 和磁盘只读探针。
3. 版本化兼容目录模型、语义校验、Ed25519 签名验证、channel key 权限、有效期、客户端版本和 revision 回退保护。
4. 标准/实验模式选择器，以及绑定目录 revision、原始 payload SHA-256、配置 revision 和声明摘要的实验确认。
5. 托管产物的流式字节数/SHA-256 验证、私有 staging、内容寻址缓存和并发独占原子提交。
6. YAAGL `0.3.18`/`ca78abc` 的更新、运行时、启动补丁和供应链边界审查。
7. 托管运行时产物的严格 HTTPS fresh GET 与显式 Range/If-Range 续传：确定性 SHA 路径、非阻塞内核 lease、脱敏原子 metadata、强 validator、严格 206/Content-Range、200 写前归零、失败分类清理、精确大小、SHA-256 和内容寻址提交。
8. 同卷/跨卷下载与 CAS 双 staging 容量预检，以及持久 lease 保护、失败关闭的显式过期 partial GC。
9. 国服只读 `ManifestAdapter` 领域与证据契约；在取得当前脱敏样本前，live transport 必须失败关闭。
10. 后端无关的安全归档计划：仅普通文件/目录、稳定 NFC/case-fold 路径、祖先冲突检查、权限归一化及 entry/单文件/总量/膨胀比限制。
11. 后端无关的 `SafeStagingExtractor`：对 source 与计划重新绑定身份，在全新私有 tree 中按目录 FD 写入，限制实际字节，复验最终清单与文件 inode，并在失败或取消时进行受限清理。
12. 归档计划与 staging tree 的稳定密封：plan canonical SHA-256、逐文件写入时 SHA-256、最终 FD 重哈希、确定性 tree seal，以及用于下一层接管复验的 root device/inode 交接。
13. `SafeStagingExtractor.reverify` 只读复验：candidate seal 元数据自洽、root device/inode、精确 inventory、逐文件最终 FD 重哈希，以及 root/path 身份前后复核。
14. `RuntimeInstallIdentityBuilder` 纯模型：以 `MGBINSTALL` v1 绑定 runtime definition、artifact、plan、tree、entry/file count 和展开字节，并拒绝 runtime artifact 大小与 planner 膨胀比分母不一致。
15. `VersionedRuntimeStore` 发布与精确复用：安全私有 root、持久非阻塞发布锁、store-owned extraction、receipt 读回、二次 tree 复验、同卷 `RENAME_EXCL`、显式 commit state，以及 `EEXIST` 下 exact receipt/tree/target identity 验证后的 `reusedExisting`。
16. `RuntimeActivationIdentityBuilder` 纯模型：内部运行 `CompatibilitySelector`，以 `MGBCURRENT` v1 绑定 catalog、selection/ack、profile/game、runtime/install/artifact/plan/tree、tier 和 generation。
17. `VersionedRuntimeStore.activateFirst`：generation 1、共用发布锁、确定性 installed full verify、`ENOENT` current 门槛、`0600` exact 临时文件、提交前二次复验、`RENAME_EXCL`、root `fsync` 和显式 current commit state。
18. `activateReplacingCurrent` exact CAS：trusted expected bytes/inode、checked generation `+1`、新 installed/temp 二次验证、无 fallback 的 `RENAME_SWAP`、swap 后新旧双向复验、安全 unlink、二次 root `fsync` 和 committed state。
19. `rollbackCurrent` 显式薄包装：选择目标旧 installed/profile，以最新可信 catalog/request 和 trusted expected 重新 selector/full verify，并通过同一 CAS 生成更高 generation 的新 activation。
20. 内部 `RuntimeRecordDecoder`：untrusted DTO、128 MiB/64 KiB 与 depth 64 预检、install path/limits/case-fold/tree/installID、activation ack/tier/activationID，以及 canonical exact bytes 拒绝。
21. `reopenInstalled`：仅 install ID + `VerifiedCatalog`、安全 dirfd/发布锁、128 MiB bounded canonical receipt、唯一 managed/nonblocked/nonrevoked runtime identity cross-check、payload full rehash 和 target/root 终检。
22. `resolveCurrent`：单一发布锁、64 KiB bounded canonical current、两次 locked installed reopen、最新 catalog/request selector/ack、同 generation builder exact equality，以及 final current/root identity。
23. ManifestAdapter 首批领域模型：public validated request/summary output、internal coherence factory、四种 availability、cache-origin-expiry 与 exact evidence 绑定、无敏感字段，以及 `EvidenceGatedManifestAdapter` 失败关闭入口。
24. internal `ChunkManifestValidator`：纯 semantic candidate、安全 archive path/NFC case-fold/祖先、100,000 entry/1,000,000 reference、连续全覆盖范围、同 object ID 元数据一致和 checked target/referenced/unique 聚合。
25. internal `LdiffSelectionValidator`：接收 source-filtered selected/unselected/deletion plan，验证六字段 summary、empty/unselected-only/delete-only、union path、slice/object 和 selected object checked 去重聚合。
26. internal 纯内存 `ManifestReplayCandidate/Registry/Adapter`：逐层 factory 重建与 candidate equality、evidence 稳定排序、fixture ID + 完整 request 精确匹配、重复/未知拒绝、取消和确定性并发读取；Registry 只接受 materialized capability，无 raw 旁路。
27. Ldiff provenance：非 nil `selectedLdiff` 强制 patch-response + diff-manifest；`directLdiffUnavailable` 仅表示 patch response 无 descriptor，只保留 patch-response evidence。
28. canonical descriptor schema v3：ordered `externalArtifactBindings` 精确声明 kind、小写 SHA-256、非零 byte size/default cap 和 manifest reference shape；v2/v1/旧 `patch` shape 严格拒绝，descriptor self-hash 绑定全部 canonical 声明。
29. domain-separated `ManifestReferenceDigest` v1：本地绑定 release/category、opaque manifest ID、profile revision、chunk/ldiff kind 和 compression；chunk/diff binding 必须携带，branch/build/patch response binding 必须省略。
30. internal Data-only artifact bundle validator：actual owned byte size/SHA-256 与 descriptor 声明精确匹配，携带 chunk/diff reference，保留 1/8/8/64/64 MiB + total 128 MiB cap、64 KiB snapshot/hash、stable factory evidence 和全 surface redaction。
31. 固定 SwiftProtobuf `1.38.1` 与 `SwiftProtobufPlugin` 唯一 codegen gate：从 YAAGL 固定提交生成 internal chunk/ldiff wire 类型，完成 synthetic round-trip、unknown-field 保留和 message-depth 基础验证。
32. internal semantic materializer/capability：descriptor v3 → owned bundle → explicit decoder → actual-driven branch/build/chunk/patch/ldiff → validators → Factory/Candidate → `fileprivate MaterializedManifestReplayFixture`；identity/version/reference/observations exact、direct/empty 分离、fail-fast/cancellation/redaction。
33. bounded manifest zstd byte capability：精确固定 upstream zstd 1.5.7、窄 `CZstdBridge`、标准单 frame/no trailing/skippable/dictionary、windowLog 23、每类 256 MiB output 与 actual-consumed 动态 ratio cap、known/unknown content size、owned output/SHA-256、取消和脱敏。
34. zero-copy protobuf wire budget scanner：zstd capability-only、固定 10-message known-field/wire schema、singular duplicate 与 non-minimal varint 拒绝、int32/uint32 type-aware 编码、depth/count/node/string provisional caps、取消和 policy v1 脱敏回执。
35. fixed-baseline structural protobuf mapper：scope schemaBaseline + reference/kind 绑定、scanner、SwiftProtobuf depth 4、recursive unknown reject、全 raw chunk/patch/delete 映射与 exact receipt recount、source/deletion exact selection、现有 validators，以及脱敏 structural capability。
36. safe flat fixture file loader：mandatory trusted descriptor SHA pin、固定文件名/inventory、从 `/` dirfd + `O_NOFOLLOW` 打开的 euid-owned same-device roots/files、mode/type/nlink policy、all-file size/cap/total preflight、64 KiB pread/hash、post-read/final anchors 和 byte-bundle-only 返回。
37. A0 branch-only discovery sampler：独立非 library-product `ManifestSamplingCore`、`bridge-manifest-sample plan`、policy SHA + exact environment 双门、固定 CN branch GET、ephemeral single-task transport、redirect/auth/content metadata 失败关闭、cookie no-send/no-store、1 MiB streaming cap、duplicate-aware RFC 8259 scanner，以及绑定 request/policy/body/shape identity 与 branch count 的脱敏 receipt。
38. A1b safe shape report：strict parser 可选生成只含 known key name、unknown decoded-key SHA-256 与 scalar kind 的递归树；object 保留字段相关性，array 只保留 sorted unique child shapes，并以 4,096 nodes / 256 array shapes / 1,024 unknown keys / 256 KiB canonical report caps 整体失败关闭。独立 plan/command/gate 经 mock 验证后完成一次 receipt-only live 并硬停止，无 credential capability。
39. strict CN branch semantic decoder：detached body → scanner/A1 shape/A1b report exact pins → private DTO → fixed game ID 与 bounded opaque main slot values；输出 internal non-Encodable/redacted capability，binding 覆盖 request/transport/body/shape/report/slot。capability 不向 CLI 暴露，只由受门控的 getBuild 事务在内存中消费。
40. root-data JSON shape scanner：为 getBuild response 提供 `retcode == 0` + `data` object anchor，不要求 `game_branches`；继续复用 strict JSON、shape/report limits、known vector 与取消边界。scanner 自身不发请求，已由下层 mock transaction 消费。
41. main getBuild shape transaction：独立 plan/command/gate 顺序执行 fresh branches semantic capability → exact `api-takumi` getBuild GET → root-data safe report；query values 只来自 capability，receipt 不含 actual URL/request digest/credential，并以 no-manifest/no-payload 硬停止。mock 验证后已完成一次受控 live 两请求并硬停止。
42. strict main build semantic decoder：8 MiB root-data exact pins → private DTO → branch/build tag binding → unique game category → bounded manifest/download references；输出 internal non-Encodable/redacted capability，binding 覆盖 branch capability 与全部 build evidence/raw values。
43. manifest origin discovery：独立 plan/command/gate 只重跑 fresh branches + getBuild，然后从 origin-only reference 失败关闭验证 HTTPS/lowercase ASCII DNS/no IP/no port/no credential/no query/no fragment/no dot-segment 的 bounded prefix；receipt 只输出 safe origin、path component count/SHA，以 no-manifest/no-payload 硬停止。v1 以 `semantic-value-rejected` 停止，v2 定位为 `build-download-reference-rejected`；两次都只执行两个 GET，没有 receipt/第三请求。v3 只消费 exact shape/report、fresh tag、unique game 与 url_prefix，一次受控 live 成功返回 `https://autopatchcn.yuanshen.com`、5 个 path components 和 path SHA `ea1f952a…0485`，随后停止，未访问 manifest/payload。
44. manifest response metadata discovery：独立 plan/gate 把 observed origin/path pin、manifest ID single-component 规则、request template 和 response-header-only 停止绑定到 policy `32809f02…ff8b`。第三个 GET 只接收 exact final URL/200 和 Content-Type/Encoding/Length metadata，在 body 交付前取消；unknown header 只输出 SHA classification，receipt 不含 manifest ID/path/header value/body。5 项 mock 通过后，一次受控 live 观测到 `application/octet-stream`、encoding absent、length `8,521,303`、request path SHA `ce154736…fea8`且 `responseBodyAccepted=false`。
45. bounded manifest body discovery：独立 plan/gate 再绑定 fresh build compressed_size、request path SHA、exact octet-stream/encoding/Content-Length；body 只在内存中逐 chunk 计数并计算 SHA-256，short/extra/header mismatch 均拒绝。receipt 只含 SHA/size/magic kind，不落盘、不解压、不请求 payload。policy `e253f675…7dc3`；5 项 mock 后的一次受控 live 返回 exact `8,521,303` bytes、SHA `ca70fab4…04c82` 和 `zstdStandardFrame`，随后丢弃 Data。
46. live manifest structural bridge：独立 plan/gate 绑定 compressed SHA/size、profile revision、release/category 和 fixed schema baseline；`ManifestSamplingCore` 仍不依赖 `BridgeCore`，由 CLI executable 注入 package inspector。façade 再 hash 后执行已有 bounded zstd→wire scanner→generated decode/unknown reject→structural mapper/validator，只返回聚合 SHA/count/bytes，不产生 Registry/payload。v8/v9 确认 `chunkInfo f7 w2`共107,480次、全32-byte lowerHex。v10 升为 profile revision2/observed CN structural v2，一次受控 live 完整通过：2,673 files、107,480 refs、107,325 unique objects，decompressed `15,913,977` bytes / SHA `e5b3a018…96fea`，未进 Registry/payload。
47. 原生 macOS 启动器：`MacGameBridge` SwiftUI executable 以游戏库为主导航，内置原神国服、添加其他 `.exe`、一键启动/停止、日志入口、窗口/分辨率/界面语言/语音设置，同时保留 `SystemProbe`、下载预算和路线图工具。`script/build_and_run.sh` 会构建真实 `.app` 并启动，Codex `Run` 操作与之共用。
48. 下载计划与空间预检页：将 observed CN v2 的 `121,185,381,917` unique compressed bytes、`124,827,264,431` target installed bytes 与 20 GB 本地安全余量 checked 求和为保守峰值 `266,012,646,348` bytes。页面对照实时 `SystemProbe.freeDiskBytes` 输出空间充足/不足/未知，不触网、不创建文件，也不替代下载时的真实分卷容量门。
49. 安装位置只读选择：下载计划页通过窄 `NSOpenPanel` 边界选取一个已存在目录，禁止面板创建目录、禁止文件/多选/别名解析。`InstallVolumeProbe` 只接受绝对 file URL，用 `O_DIRECTORY|O_NOFOLLOW` + `fstatfs` 读取所在卷可用容量；所选 URL 只存活于当前进程，不创建/修改文件，也不是安装授权。已在真实 UI 中选择 `/Users/Shared` 并看到该卷容量结论更新。
50. chunk origin 与单 payload 门：`plan-chunk-origin-cn` 以 2 GET 观测到 `https://autopatchcn.yuanshen.com`、5 个 path components 与 path SHA `50e6250f…d2eb`。`plan-one-chunk-payload-cn` 只选最小 unique object，限制 16 MiB compressed/64 MiB uncompressed，并以四 GET 后硬停止。
51. 首个真实 chunk：policy `36e23a25…5f6d0` 的受控 live 下载 21 bytes；压缩大小、field7 compressed MD5、zstd exact output 和 field2 uncompressed MD5 全部通过。计算 SHA-256 `8a1c5ac944823490b4879b551f5862fe3718e96738f7f4e29490c280391b5391`，以 `0444`/单链接存入 `LocalRuntimes/ChunkProbeCache/objects/sha256/8a/...`，独立 `stat/shasum/md5` 复验通过，缓存中只有这 1 个 object。
52. 国服 7.0.0 完整客户端：`script/download_genshin_cn_full.py` 固定 YAAGL `ca78abc`，完成容量预检后以 4 workers 下载、续传并逐文件 MD5 校验 2,673 个清单文件。目标目录为用户管理的 `~/Games/MacGameBridge/Genshin Impact`，实测占用 119 GiB；`config.ini` 为 7.0.0，`YuanShen.exe`、`YuanShen_Data/globalgamemanagers` 和 complete marker 已独立复核。该结果只证明文件下载完整，不代表兼容运行时、启动、登录或可玩。
53. 首次运行时与启动：从 GitHub Release 固定 Wine 11.0 signed `4ebba536…8b4c` 和 DXMT 0.80 `8f260e36…529d`，归档路径/链接检查后安装到 `LocalRuntimes` 私有目录，DXMT 注入文件逐项 SHA 比对。win64 prefix 返回 Windows 10.0.19045，并通过 M5 Pro/Metal 枚举与 `cmd /c ver`。原始启动和 YAAGL cloud 参数对照启动均在窗口前退出，日志一致为 `WDFLDR.SYS` 缺失、HoYoKProtect driver load `c0000142`；未修改游戏文件、hosts、代理、Gatekeeper 或 SIP。
54. 已确认的离线时序实验：同时禁用 USB LAN/Wi-Fi Network Service，在离线状态用同一普通用户 Wine prefix 启动，10 秒后自动恢复网络并再观察 20 秒。游戏仍以 code 5 退出，日志与前两次完全一致为 `WDFLDR.SYS`/HoYoKProtect `c0000142`；两个网络服务和默认路由已复验恢复，未修改游戏文件、hosts、DNS、代理或系统安全设置。该结果否定了在本机重复网络时序 workaround 的价值。
55. Wine 版本对照：另从 GitHub Release 固定 YAAGL Wine 11.8 `42430b7e…7a9c` 和 Dawn Wine 11.4 `b0ff5bb6…13aa`，分别完成归档安全检查、独立 DXMT 激活副本、全新 win64 prefix、Windows 10.0.19045/M5 Pro 烟测及正常联网启动。两者均与 Wine 11.0 一样在窗口前以 `WDFLDR.SYS`/HoYoKProtect `c0000142` 退出。三个独立候选的一致结果将下一步收窄为 Windows Driver Framework/Wine 驱动兼容研究，而非图形 backend、网络时序或游戏下载问题。
56. 完整 YAAGL 默认链对照：从 pinned `secret.b64` 解析并确认 Dawn Winery Root CA 指纹，在全新 Wine 11.0 prefix 中通过 `wine.inf` 导入；复制 YAAGL 自带 32/64 位 Steam/lsteamclient stub；临时追加三条 YAAGL hosts，并临时移走 upload_crash/crashreport/vulkan-1。启动退出后 `/etc/hosts` 与三个游戏文件均按整文件 SHA 恢复。结果仍为 `WDFLDR.SYS`/HoYoKProtect `c0000142`，证明当前差异不是漏装 Docker、DWCA、Steam stub 或 YAAGL 文件/hosts 步骤。
57. 成功启动主路径：CrossOver 11.0-1 + DXMT 0.80 + Steam compatibility stub 已成功打开原版国服 7.0.0，用户确认“打开游戏没啥问题”。此前 Wine/WDF 路线保留为实验研究，不再是产品主路径；登录、持续运行与性能另行验收。
58. 原生一键启动：应用定位固定 runtime/prefix/game，使用 `Foundation.Process` 启动 Wine/Steam，不经 shell。启动前自动停止 prefix、写入窗口/分辨率、`zh-CN` Windows 区域、SDK 语言与游戏文本/语音配置；停止按钮通过该 prefix 的 `wineserver` 退出。
59. 原生安装与更新入口：SwiftUI 页已接入固定国服完整下载 helper，能识别已安装/可续传状态、选择安装卷、启动或继续、展示字节进度/速度/预计时间、取消并将诊断日志写到用户 `Library/Logs/MacGameBridge`；输出解析不展示单文件名。开发 `.app` 已内置可迁移 Python 3.11、YAAGL `ca78abc`、Protobuf/Zstandard/PycURL/psutil 与 hpatchz，优先使用 bundle toolchain，源码 checkout 只保留开发回退。构建时执行解释器 SHA、版本/import 和 YAAGL 核心文件哈希检查；离开源码目录的 resolver 测试已覆盖。正式分发仍待第三方二进制许可审计、签名和全新 Mac 下载验收。
60. 自包含运行环境准备：构建脚本逐项校验并把 456,021,524-byte CrossOver 11.0-1、18,681,669-byte DXMT 0.80 和四个固定 Steam 兼容文件写入 `.app` Resources。安装中心可在用户 Application Support 的 staging 中解包 Wine、覆盖九个 DXMT 文件、运行 `wineboot` 创建 Prefix、安装 32/64 位 Steam stub 并发布带 marker 的 runtime/prefix；启动器优先使用该用户安装，仍兼容已有开发运行时。小型真实 tar/prefix 端到端测试已覆盖该装配链；公开分发前仍需第三方许可清单、签名与全新 Mac 实机验收。
61. 一键首次准备：主游戏页按实际状态显示安装、续传、准备并启动或直接启动；开始安装会同时触发固定运行环境准备，运行时先完成时继续等待游戏下载。游戏已存在但用户运行时缺失时，主按钮在准备完成后自动继续启动。所选游戏根目录以绝对 file path 持久保存，`GameRuntimePaths` 在环境变量之后、默认路径之前读取，确保非默认磁盘安装完成后仍能被启动器定位。
62. 性能诊断与自动平衡档：实机 registry 显示游戏虽然以 1600×900 窗口输出，但自定义配置仍使用最高内部渲染比例、高阴影/特效/环境质量、反射/雾和游戏 VSync；游戏日志同时持续出现 shader load。启动器现默认写入“平衡性能”档，将内部渲染比例调为 1.0、重型效果降至中档或关闭，并由 DXMT 统一 60 FPS pacing；用户也可选“保留游戏设置”。游戏运行期间每 2 秒自动采样该 Prefix 的 Wine/游戏进程 RSS、CPU 和进程数，在页面显示当前/峰值并写入 launcher 日志，下一次正常游玩即可形成可比较的实机数据。
63. 运行报告与更新检查：首轮平衡档已自动记录 525 个采样点、约 17.5 分钟，峰值 RSS 5,900,636,160 bytes，仍有 shader load 与 2 次 DXMT stream-output 警告。原神页现自动汇总最近一轮运行时长、峰值/平均内存、CPU 和兼容事件。安装中心使用隔离临时目录查询国服 main 目标版本；实测仍为 7.0.0，实际 `config.ini` 与 managed marker 前后 SHA 均不变。发现更新或执行校验修复时，已有 MD5 正确文件继续复用，只下载变化内容。
64. GPTK 4 与通用游戏 profile：应用已能选择 Apple 官方 GPTK 4 DMG，只读处理内层 Evaluation image，导入 `redist/lib`，去隔离后复验 D3DMetal 签名并以 SHA-256 绑定管理副本。选择 GPTK 启动时会克隆 CrossOver runtime/Prefix，仅在独立副本中覆盖 D3DMetal 模块并设置 dyld/Wine 后端；DXMT 仍为默认且不被覆盖。该链已通过合成包导入、篡改拒绝、独立克隆和幂等回归，但本机尚无真实 GPTK 4 DMG，因此不声称原神 D3DMetal 已启动或已提帧。新增 Windows `.exe` 仍使用 `generic-crossover11-dxmt-r1`。
65. APFS 更新回滚点：已安装游戏执行更新或校验前会先在同卷用 `cp -cR` 创建 clone-on-write 安全备份，失败时不会启动更新。安装中心显示备份版本和时间，游戏关闭时可用 `RENAME_SWAP` 原子切换当前目录与备份，刚换下来的版本继续保留为反向回滚点。小型真实 APFS 测试覆盖克隆后写隔离、A→B→A 双向回滚和已有回滚点替换；尚未改动或回滚用户正在更新的真实游戏目录。

## 真实状态

- GPTK 4 官方 DMG 导入、独立运行时组装和应用内启动代码已实现；它是未完成实机验收的实验后端，不继承 DXMT 已验证可启动的结论。
- 本机没有检测到 GPTK/D3DMetal。
- 原神仍只把本机已验证成功的国服 7.0.0/CrossOver 11 + DXMT 路径标为可启动。其他游戏可使用通用实验 profile，但不继承“已验证可玩”结论。
- 通用 runtime downloader 仍只有离线 `URLProtocol` 覆盖；国服完整客户端本次由固定 YAAGL 后端的独立 wrapper 下载，不等于该通用 downloader 已接入游戏资源。
- 归档层可以把测试用受控 source 写入安全 staging tree，但尚无真实 ZIP/tar/7z parser 或固定版本 libarchive backend，因此还不能处理真实归档端到端链路。
- sealed tree 现在可在 store 持锁的同一调用链中发布为 fresh version；它仍不构成持久启动授权。
- 安装 identity/record 会写入新版本目录；已有目标只有与本次可信 expected receipt/tree 精确一致时才复用，不 decode、不修改或修复，损坏目标失败关闭。
- installed version 可跨 store 实例以 `reopenedExisting` 恢复，但这不是同 uid 篡改的密码学来源证明；尚无版本 GC，也未通过真实 libarchive 下载/解压运行时。
- activation 可首次创建、CAS、rollback，并可由新 store 实例 resolve current；rollback 已覆盖 A→B→A，更多故障测试与产品流程仍待补充。
- install/current reader 已分别接入 reopen/resolve full verify，但 resolved 结果只是锁内 snapshot，不授权长期启动；启动仍须最新可信 catalog/request 与紧邻复验。
- ManifestAdapter 只有 materialized capability 能进入 Registry；raw candidate、descriptor 和 byte bundle 均不能注册。它能用显式 internal decoder 完成纯内存 semantic materialization/replay，但这不是 fixture 文件 loader。
- canonical descriptor bytes 可以解码成 summary/evidence metadata 和 external artifact hash/size/reference 声明，但不含 artifact Data，不能注册或 replay。
- external artifact `Data` 可生成与声明精确匹配的 owned bundle；materializer 要求显式 decoder 从 actual response 产出的版本/reference/observations 与 artifact identity 和 descriptor exact。它只承诺 fixture response semantic/version/reference 自洽，不认证官方来源，branch→build request/credential chain 仍未绑定。
- zstd decompressor 已能从 verified chunk/diff artifact 生成 bounded decompressed byte capability；scanner + generated decode + fixed-baseline structural mapper 已能继续消费，但 zstd capability 本身仍不证明 protobuf/semantic，也不能进入 Registry。未实现的是 profile-authorized endpoint/full decoder、国服实际语义确认、磁盘 cache 和 live endpoint；Evidence gate 继续失败关闭。
- wire scanner 已能在 SwiftProtobuf 分配前递归拒绝 unknown/wrong-wire/duplicate singular，并限制结构预算；structural mapper 随后完成 depth-4 generated decode、decoded-tree recursive unknown check、全 raw mapping/source selection 和 validators。budget receipt 与 structural capability 都不能进入 Registry。
- mapper 仅绑定固定 YAAGL structural baseline，不是国服 `ObservedEndpointProfile`。production endpoint JSON/branch-build-patch full decoder、磁盘 cache 和 live endpoint 仍未实现；actual XXH64 校验语义与 name/path 关系仍待真实样本。
- fixture file loader 已实现且只允许调用方提供 trusted descriptor SHA-256 后读取 flat v1；它只返回 `ValidatedReplayArtifactBundle`，未自动连接 zstd/mapper/materializer/Registry。production endpoint full decoder、`ObservedEndpointProfile`、cache/live 仍未实现。
- pin 不是官方签名或 same-uid provenance；ACL 未审计，artifact Data 加 BundleValidator owned snapshot 的 peak memory 仍待优化。`EvidenceGatedManifestAdapter` 没有自动注入 loader，继续失败关闭。
- A0 sampler 已能生成无网络 plan，并在 mock transport 中验证固定请求/响应门。A1 已执行两次受控 live data task：旧 policy 首次通过 HTTP 200/exact final URL 后以 `response-type-rejected` 在 metadata gate 停止；response delegate 在允许 body 交付前取消，工具未解析/保存 body。新 policy 第二次成功返回安全 receipt 后硬停止：body SHA-256 `1f5d2f9a0feaa0890ec7db02bbc6f426376d5d228be4ae7c872df1eeedf54dbd`、906 bytes、branch count 1、observedAt `1787126649`、request `dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d`、policy `4b78e4fb1fb711010a90799c145bc08d607f4ad53f4cb70d32438f5ee062cec3`、shape policy 1 / SHA-256 `a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633`。两次均无后续请求；未保存 raw body/query/credential/fixture，未形成 `ObservedEndpointProfile`。工具“无显式文件写”不表示操作系统绝对零痕迹，“单 data task”也不表示 DNS/TLS/CFNetwork 只产生一个网络包。
- A1b 已新增独立 `plan-branches-shape-cn` / `sample-branches-shape-cn`、`ALLOW_BRANCH_CN_SHAPE_V1` gate 与 policy SHA `e7eb…20e4`。一次受控 live 返回 `matchesPriorShape=true` 后硬停止：body SHA/size 仍为 `1f5d…54dbd` / 906 bytes，report SHA `bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25`、canonical report 2,178 bytes、observedAt `1787129607`。安全树确认唯一 branch 含 `game{id,biz}`、`main{tag,branch,package_id,password}`、`pre_download=null` 及 8 个分布在 nested 结构中的 hashed-key fields；未输出 scalar value，未发后续请求，也未构造 getBuild credential capability。
- strict branch capability 已在受门控的 main getBuild live 事务中短暂生成并仅用于构造 exact getBuild request；没有 standalone credential 输出、持久化或缓存。
- main getBuild transaction 的受控 live 恰好执行 branches+getBuild 两个 GET：build 200/4,518 bytes、observedAt `1787132716`、body SHA `c8bae16d…90a0`、shape SHA `21e89e02…b851`、report SHA `ab0d7df7…778f`、canonical report 4,521 bytes。receipt 不含 actual URL/request digest/credential，未访问 manifest/payload。safe tree 已确认 tag/build_id/manifests 与 manifest/download descriptor 层次；剩余 hashed keys 尚未审核，不能据此启用 manifest fetch。
- strict full build decoder 继续保持 production pins 与完整 field/value gate；manifest-origin v3 不放宽或签发该 capability，而是另用最小权限 origin decoder 读取 url_prefix。下层 metadata-only gate 已以受 pin 约束的短暂 manifest request 完成一次 live header 观测，但未接受 body。
- manifest body/live zstd/protobuf、最小单 chunk payload和一次完整客户端文件下载已经证明；仍没有 production `ObservedEndpointProfile`、内建批量调度 UI、兼容 runtime 安装或 Registry 启动授权。
- manifest body sampler 已以 exact build/header/length 约束流式生成一次 live SHA/size/magic receipt；它不把 Data 升级为 zstd/protobuf capability，body 也未保留。
- structure bridge 已在 mock/合成 protobuf 中证明同一 fresh transaction 的 owned Data 可被既有 zstd/scanner/mapper 消费；输出仍只是 discovery receipt，非 endpoint profile/inspection/registry 授权。
- observed CN v2 已产生首份真实 structural summary，但 field7 仍只是 opaque claim，且 branch/build/manifest 证据尚未组合成可签发 `ManifestInspection` 的完整 `ObservedEndpointProfile`。
- zstd 默认 window/output/ratio limits 是未见真实国服样本前的保守 provisional baseline；bundle cap 单独使用时仍发生在 compressed `Data` 已分配后，safe fixture loader 则已在 artifact Data 分配前完成 size/cap/total preflight。
- fixed-baseline mapper 已将 wire `DiffManifest` 全量校验并映射为 source-filtered 领域结果；selection 可以为空或只含 unselected/deletion，其 selected object bytes 只表示 ldiff 对象声明量，不是整体 update 下载量。profile-authorized 国服 full decoder 仍未实现。
- Gatekeeper 仍保持用户现有的 `assessments disabled` 状态；项目没有修改它。

## 本轮验证

- `swift format lint --recursive --strict Sources Tests`：通过。
- `env -u PROTOC_PATH swift build`：通过；`SwiftProtobufPlugin` 从锁定依赖构建 codegen tools，未使用系统 `protoc`。当前包含 `BridgeCore`、`bridge-probe`、`bridge-catalog`、`bridge-manifest-sample` 和 `MacGameBridge`；后者已由项目脚本封装为 `.app` 并成功启动。
- `otool -L`：`bridge-probe`、`bridge-catalog` 和测试 bundle 均无外部 `libzstd`、Homebrew 或 Cellar 路径；这不表示 upstream 静态 product 不含 compression symbols，只证明运行时没有外部 zstd dylib 依赖。
- `env -u PROTOC_PATH swift test`：48 个测试套件、371 项测试全部通过；新增 GPTK 4 合成 redist 导入、管理副本篡改拒绝、安全版本名、独立 runtime/Prefix 覆盖、DXMT 原树不变、幂等准备、GPTK 环境与 framework 版本检测覆盖。测试本身不触网、不启动真实游戏，也不触碰真实游戏目录。
- `./script/build_and_run.sh --verify`：成功构建并打开 `dist/MacGameBridge.app`；已实际检查游戏库、原神详情页、窗口/语言 pickers、自动化准备与产品待办。
- `swift run bridge-catalog validate Catalogs/development-catalog.json`：通过未签名开发目录语义校验；仍为 0 个游戏版本 profile。
- `swift run bridge-probe --json`：本机为 macOS 27、Apple Silicon，Metal、Rosetta 和 Xcode 可用；GPTK/D3DMetal 未检测到；Gatekeeper 报告 `assessments disabled`。

以上已经包含完整游戏下载、用户实际进入游戏和本轮性能根因诊断；平衡档是否改善同场景掉帧与峰值内存仍待下一次正常游玩的自动采样验收，也不代表全新机器分发安装已经验收。

## 下一阶段

1. 为网络字节源加入限速和真实 HTTPS 集成测试。
2. 固定并纳入构建的 libarchive 窄包装，实现真实归档的只读 entry 枚举和内容 source，并接入现有目录 FD 驱动的 staging writer；继续拒绝链接、设备和特殊元数据。
3. 把本机已经验证的 CrossOver/DXMT/Steam 启动链接入受版本控制的 runtime 安装与激活记录，形成全新 Mac 可自动恢复的流程。
4. 将已审核的 branch/build/origin/body/structural/payload pins 收敛为一个 internal `ObservedEndpointProfile` candidate，补 profile expiry/revision 与 branch→build request binding；然后实现经用户确认、可取消/续传的小批量下载，不直接扩展到全量 121 GB。
5. 使用 Apple 官方 GPTK 4 DMG 验收应用内导入、原神 D3DMetal 启动和后端识别，再与 DXMT 做同场景帧时间、1% Low、内存和画面正确性 A/B。
6. 在已接入的通用实验 profile 上，按游戏补充专用启动器、DRM、更新和图形参数。
