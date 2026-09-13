# 历史开发说明（归档于 2026-09-08）

本文保留旧 README 的技术研究记录，包含历史状态与已被替代的产品描述，不作为当前安装指南或兼容性承诺。当前项目首页见 [README](../README.md)。历史命令中的路径仍以项目根目录为基准。

米哈游游戏的非官方 Mac 启动器，支持原神、崩坏：星穹铁道、绝区零和崩坏 3。
与米哈游无官方隶属关系。原项目工作名为 MacGameBridge；为兼容已有安装，
内部包标识、命令行产品名和数据目录继续保留 MacGameBridge。
发行文件名为 `HoYoBridge.app` / `HoYoBridge-macOS-arm64.zip`。

MacGameBridge 是面向 Apple Silicon、macOS 26/27 的非官方米哈游国服游戏管理器，范围为原神、崩坏：星穹铁道、绝区零和崩坏3。流程是打开应用 → 选择游戏和安装位置 → 安装游戏与兼容环境 → 启动。四款游戏独立选择安装；原神使用原有下载器，其余三款接入后台官方引擎适配器，自动获取并校验下载组件，不要求用户操作官方安装向导。新适配器已完成崩坏3实机下载及暂停/重启续传，其他游戏的新安装流程和干净Mac仍需分别验收；目前不是已公证的正式发行版。

首次发行缺口与核查证据见 [首次公开发行验收](FIRST_RELEASE_GAPS.md)。源码 CI 与发行包是两个环节；开发者可用 `MGB_BUILD_CONFIGURATION=release bash script/build_and_run.sh --package` 打包 ZIP 与 SHA-256，但仍需本机固定运行资产，不代表 GitHub 干净构建或公证已经完成。

已有国服 7.0.0 在 `CrossOver 11.0-1 + DXMT 0.80 + Steam 兼容入口` 下的用户进场验证记录；这不代表所有系统和后续游戏版本均已验证。首页显示安装、启动和具体错误，开发工具、性能基准和路线图不再面向普通用户展示。

公开发行尚未完成：当前是本地开发包，Developer ID 签名、公证、GitHub Release 和全新 Mac 从零安装验收仍需完成。不要把本机启动记录理解为“从 GitHub 下载后无需任何系统确认即可游玩”。

底层已包含签名兼容目录、严格 HTTPS 下载/续传、内容寻址缓存、安全归档/runtime 事务和受控 manifest 结构解析。固定 YAAGL `ca78abc` 后端已把国服 7.0.0 的 2,673 个清单文件完整下载并逐文件校验到用户管理目录；实际目录占用 119 GiB，清单声明安装体积 124,827,264,431 bytes。

## 当前能力

- 原生原神启动器：首页只有安装、续传、启动、更新入口、进度和错误说明。
- 原神一键启动/停止：自动使用已验证的 CrossOver/DXMT/Steam 路径，诊断输出写入本地忽略目录。
- 运行环境自动准备：开发 `.app` 内置并校验 CrossOver 11.0-1、DXMT 0.80 与 32/64 位 Steam 兼容资产，首次使用可自动解包到用户应用支持目录并创建独立 Prefix。
- 启动设置：窗口/全屏、连接屏幕的分辨率、图形档位、界面语言、语音语言与启动后隐藏。
- 实验功能仅有手动开启的 120 FPS 解锁和 Metal HUD，首次使用默认关闭；旧 144 FPS 设置不再生效。120 是目标上限，不是帧率保证，且存在兼容性与账号风险。
- 运行环境固定为 CrossOver 11.0-1 + DXMT 0.80，显示组件版本。Steam 兼容组件自动提供，不需要 Steam 客户端；Wine / DXMT 目前随固定应用包更新，不支持任意 Wine 替换。
- 安装与更新中心：选择安装卷、计算保守空间预算，并启动/继续固定国服下载，显示进度、速度、预计时间，支持取消、查看日志、更新前 APFS 安全备份和一键原子回滚。
- 检测 macOS、CPU 架构、硬件型号和内存。
- 检测 Metal GPU 能力。
- GPTK 已从产品中移除：不再提供导入、组合选择或启动路径；旧的 GPTK 选择按 DXMT 处理。已有本地 GPTK 文件不自动删除。
- 报告 Gatekeeper 状态和可用磁盘空间。
- 输出适合人工阅读或自动化处理的 JSON 报告。
- 校验版本固定、来源、大小、SHA-256、许可证和再分发边界。
- 验证 Ed25519 签名目录，并拒绝过期、回退和不兼容客户端版本。
- 标准模式只选择有完整验证记录的配置。
- 实验配置必须明确选择，并确认绑定目录版本、原始签名 payload SHA-256、配置版本和风险声明的凭据。
- 流式验证运行时产物的实际字节数和 SHA-256，不把整个大文件读入内存。
- 在私有 staging 中验证后，用独占原子 rename 提交到 SHA-256 内容寻址缓存。
- 缓存目录严格限制为当前用户的 `0700`，复制、校验和提交前阶段支持任务取消与 staging 清理。
- 已有缓存损坏、类型异常或符号链接时失败关闭，不覆盖现场。
- 只向显式允许的公开 HTTPS host 发起托管产物 fresh GET 或严格校验的 Range/If-Range 续传，限制重定向并拒绝压缩响应、大小漂移和本地目标。
- 下载支持在途取消和唯一 partial 清理，完整大小与 SHA-256 通过后才进入内容寻址缓存。
- 下载前按同卷或跨卷分别检查 partial 增量、完整 CAS staging 和安全余量，容量不足时不会启动网络请求。
- 过期 partial 只能通过显式 GC 清理；GC 必须先取得对应持久 lease，busy 或异常文件失败关闭，lease 文件不会被删除。
- 解压前先拒绝路径逃逸、链接/设备条目、特殊权限、Unicode/大小写碰撞、文件祖先冲突和超过单项/总量/膨胀比限制的归档计划。
- 安全计划生成与 JSON encoder 和输入顺序无关的 canonical SHA-256，绑定策略版本、归档大小和全部规范条目字段。
- 按安全计划把受控 source 写入全新私有 staging tree；逐文件计算写入时 SHA-256，并在最终目录 FD 扫描中重新打开、重哈希和复验类型、权限、大小、device/inode 及完整目录清单。
- 返回确定性的 tree seal，以及 artifact/plan 摘要、seal 版本和最终 root device/inode；`SafeStagingExtractor.reverify` 可重新检查 candidate 自洽性、root 身份、精确清单和逐文件内容。
- `reverify` 只是调用期间的瞬时快照，不是持久启动授权。`VersionedRuntimeStore` 在持久非阻塞发布锁下把 store-owned extraction、二次复验、receipt 校验和独占 rename 保持在同一调用链。
- `RuntimeInstallIdentityBuilder` 生成 domain-separated 的 `MGBINSTALL` v1 安装身份，绑定 runtime definition、artifact、plan、tree、条目/文件数量和展开字节；store 会把其 sorted-key receipt 与 payload 一起发布。
- 安装身份要求 `runtime.byteSize == plan.archiveByteSize`，确保解压膨胀比使用的压缩包大小分母就是目录中绑定并验证的产物大小，拒绝通过放大计划分母绕过限制。
- store 使用同卷 `RENAME_EXCL` 发布到 `versions/<prefix>/<installID>`。目标已存在时，只有预期 sorted-key receipt 逐字节一致、existing payload 完整重哈希复验且 target/root inode 终检通过才返回 `reusedExisting`；不 decode、不修复也不修改已有版本。
- 损坏或异常的已有版本失败关闭并保留现场，只清理本次本地 wrapper。rename 前取消会清理唯一 staging，rename 后取消不会删除已可见版本。
- `RuntimeActivationIdentityBuilder` 内部重新运行 `CompatibilitySelector`，再以 `MGBCURRENT` v1 绑定 catalog revision/payload/channel、选择模式、标准/实验确认、profile/game、runtime/install/artifact/plan/tree、tier 和 generation。
- 标准 profile 在 activation digest 中写入 acknowledgement tag `0`；实验 profile 必须提交与 catalog payload、profile revision 和 disclosure 精确匹配的确认，并绑定其 `MGBACK` 摘要。
- `activateFirst` 固定 generation `1`，与 install 共用 `.publish.lock`；它完整复验已安装版本，把 sorted-key activation 精确写入 `0600` 临时文件，并仅在 `current.json` 严格不存在时以 `RENAME_EXCL` 首次发布。
- 任意类型的已有 `current.json` 都保留且不覆盖。后续激活必须持有 trusted expected `RuntimeActivationRecord`；store 在锁内逐字节匹配 current，并以 checked `generation + 1` 构建新记录。
- CAS 替换只使用 `RENAME_SWAP`，不做非原子 fallback。交换后同时复验新/旧 bytes 与 inode，安全删除旧 temp并再次同步 root；stale expected、同大小篡改或异常类型均失败关闭。
- `rollbackCurrent` 是同一 CAS 的薄包装：调用方选择旧 installed/profile，提供当前最新可信 catalog/request 和 trusted expected，store 重新 selector/full verify 并发布 `generation + 1`。A→B→A 对应 1→2→3，第三个 activation ID 是新身份而非恢复旧记录。
- 内部 `RuntimeRecordDecoder` 先以 untrusted DTO 解析，限制 install 128 MiB、activation 64 KiB 和 JSON depth 64；它重算 tree/install/activation identity，并要求 sorted-key canonical bytes 与输入逐字节一致，从而拒绝 unknown、duplicate 和额外 whitespace。
- decoder 只证明 record 自洽，不执行 selector、不验证磁盘安装或赋予启动权限；公开 trusted record 类型仍保持 `Encodable` 而非 `Decodable`。
- `reopenInstalled(installID:in:)` 只接受小写 install ID 和 `VerifiedCatalog`，不接受裸 runtime/URL；它在发布锁和安全 dirfd 下限长读取 canonical receipt，要求 catalog 中唯一 managed、未 blocked/撤销的 runtime definition/artifact 精确匹配，再完整重哈希 payload 并终检 target/root，成功返回 `reopenedExisting`。
- reopen 不是对同 uid 篡改的密码学来源证明，也不授权启动；启动仍须使用最新可信 catalog/request 重新运行 selector。
- `resolveCurrent` 在单一发布锁内限长 64 KiB 读取并 canonical decode current，两次 locked reopen installed，使用最新 `VerifiedCatalog`/request 重新 selector 与同 generation builder，并要求重建 record 精确相等；结束前再次核对 current bytes/inode 和 root。
- resolve 支持新 store 实例的 current 重启恢复，并区分 missing/invalid/notAuthorized；其 capabilities 已验证可驱动 generation 2 CAS 后再次 resolve。返回值仍只是锁内瞬时快照，启动前须紧邻复验 selected runtime。
- ManifestAdapter 首批公开 opaque `GameVersion`、仅 `.game` 的 validated request、四种显式 availability、build/selected-ldiff summary、cache origin、过期时间和逐项 SHA-256 evidence；输出只能由 internal coherence factory 构造且不含敏感字段。
- internal `ChunkManifestValidator` 已能校验纯 semantic candidate：安全归档路径/NFC case-fold、文件祖先、10 万 entry/100 万 reference、连续无洞且完整覆盖的文件范围、同 object ID 元数据一致，以及 checked target/referenced/unique 聚合；public `ChunkManifest` 仍只有 summary，不暴露 path/object/hash leaf。
- public `ManifestInspection.selectedLdiff` / `LdiffSelectionSummary` 只描述 source-filtered ldiff 选择：manifest records、selected files、without-selected files、deletions、unique objects 和 selected object bytes；empty selection 合法，不包含整体 update transfer 字段。
- internal `LdiffSelectionValidator` 接收已分成 selected/unselected/deletion 的 semantic plan；unselected reason 仅为 `.noPatchRecords` / `.noPatchForRequestedSource`，不会推导“新文件/未修改”。`directLdiffUnavailable` 仅表示 patch response 无 ldiff descriptor，只保留 patch-response evidence；任何非 nil selection 必须同时有 patch-response + diff-manifest evidence。
- internal `ManifestReplayMaterializer` 的唯一链路是 schema v3 descriptor → owned byte bundle → 显式 internal decoder → actual-driven branch/build/chunk/patch/ldiff → semantic validators → `ManifestInspectionFactory`/`ManifestReplayCandidate` → `fileprivate` materialized capability。它要求 artifact identity、版本、build→chunk/patch→ldiff reference 和 actual-derived observations 与 descriptor 精确一致，并严格区分 direct unavailable 与合法 empty selection。
- `ManifestReplayRegistry` 只接受 `MaterializedManifestReplayFixture`，没有 raw candidate/descriptor/bundle 旁路；materializer/adapter 在阶段边界检查取消，decoder 或 identity/summary mismatch 立即失败，相关 semantic/capability surface 固定脱敏。内存 replay 覆盖 full/update/pre-download、empty selection 和 direct unavailable，并支持确定性并发读取。
- internal `ManifestReplayDescriptorDecoder` 已升级 schema v3；v2/v1 和旧 `patch` shape 均拒绝。它要求 `externalArtifactBindings` 按派生顺序精确声明 kind、小写 SHA-256、非零 byte size 和默认 cap，并以 descriptor 自身 SHA-256 绑定全部 canonical 声明。
- chunk/diff binding 必须携带 domain-separated `ManifestReferenceDigest`，response binding 则必须省略该字段。materializer 要求显式 decoder 从 actual build/patch response 产出的 reference 与对应 owned manifest artifact 精确一致；byte-only bundle 本身仍不能注册或 replay。
- internal Data-only artifact bundle 要求 actual owned snapshot 的 byte size/SHA-256 与 descriptor 声明完全相同，并继续携带 chunk/diff reference；默认 cap 为 branch/build/patch/chunk/diff `1/8/8/64/64 MiB`、总量 128 MiB。descriptor/reference/bundle/materializer 只承诺 fixture response 的 semantic/version/reference 本地自洽，不认证官方来源，也尚未绑定 branch→build request/credential 链。
- official `facebook/zstd` `1.5.7`（revision `f8745da6ff1ad1e7bab384bd1f9d742439278e99`）由 SwiftPM 从源码构建；`BridgeCore` 不直接依赖或 import upstream module，只经过窄 `CZstdBridge` header 与解压调用点。MacGameBridge 自有 compression/dictionary helper 仅存在于 Tests；单一 upstream `libzstd` product 仍可能包含完整 compression symbols。许可与来源记录已离线保存。
- internal `ManifestZstdDecompressor` 只接受 identity/reference 已验证的 chunk/diff artifact，拒绝非标准 magic、skippable、dictionary、trailing/concatenated frame；默认限制 windowLog `23`、每类输出 256 MiB，以及 `1 MiB + 128 × actual consumed compressed bytes` 的动态膨胀上限。known/unknown frame content size 均流式处理，输出以 owned chunks 同步计算 SHA-256，支持取消且 capability 全 surface 脱敏。
- internal `ManifestProtobufWireBudgetScanner` 只接受 zstd capability，在 SwiftProtobuf 分配 message/string 前零拷贝扫描固定 10-message schema；它要求 known field/wire、singular 不重复、tag/length/value 最短 varint 和 int32/uint32 合法编码，并以 depth 3、file/chunk/patch/delete/node/string provisional caps 失败关闭。unknown field 或 wrong wire type 为 `schemaDrift`，回执绑定 compressed identity、decompressed SHA/size 与计数且全 surface 脱敏。
- internal `ManifestProtobufStructuralMapper` 要求 scope 精确绑定 `yaagl-ca78abc-sophon-protobuf-structural-v1`，在 scanner 后以 SwiftProtobuf depth 4 decode、递归拒绝全部 unknown fields、映射所有 raw chunk/patch/delete records、按 requested source 精确选择 patch/deletion，并再次要求 mapper counts 与 receipt 完全一致后进入现有 validators。返回的 chunk/ldiff structural capability 脱敏且不可解码。
- chunk field 6 只保留为 `UInt64` numeric claim；真实压缩字节与标准 seed-0 XXH64 不匹配，不再称其为已验证 compressed XXHash。单 chunk 交易改为校验压缩大小、field7 压缩 MD5、受限 zstd 解压大小和 field2 解压后 MD5。ldiff `patch_name`/`original_name` 仍只保留不猜关系。
- internal `ManifestReplayFixtureFileLoader` 没有 unpinned load API：调用方必须提供 trusted descriptor SHA-256。flat layout v1 只允许 `fixture.json` 和按 descriptor shape 派生的五个固定 artifact 名；root/fixture 从 `/` 逐级 `O_NOFOLLOW` 打开并要求 euid owner、同卷、无 group/world write 或 special bits，文件还必须 regular、单链接、不可执行。已覆盖 `0755/0644` 与 `0700/0600`。
- loader 在任何 artifact `Data` 分配前用 dirfd 打开全部文件并完成 size/per-kind/total cap 预检；随后 64 KiB `pread` 到 owned Data，并用同一 chunk 计算 SHA-256，终检 fd/path identity 与 mode/size/timestamps，再经过 `ManifestReplayArtifactBundleValidator` 和 final inventory/fixture/root anchors。它只返回 byte bundle，支持取消且 loader/error 全 surface 脱敏。
- 独立、非 library product 的 `ManifestSamplingCore` 与 `bridge-manifest-sample` 已实现 A0 branch-only discovery：`plan` 只输出无 query 的固定安全策略，`sample-branches-cn` 必须同时匹配当次 policy SHA 与 exact 环境门。production 只创建一个固定 GET data task，无任意 URL/profile/path、无应用层 retry，并拒绝 redirect、非 server-trust auth、非 200/JSON/identity/final-URL 与超过 1 MiB 的响应；cookie 不发送、不存储，response `Set-Cookie` 忽略且不输出。
- A0 的 raw response body 只在内存中用于 SHA-256 与严格 RFC 8259 value-free shape 扫描；receipt 仅含 request/policy/body identity、status/time/size、shape policy+SHA 和 branch entry count。全部自动测试使用 mock `URLProtocol`；A0 实现批完成时尚未 live，也没有产生 `ObservedEndpointProfile`、branch semantic decoder 或 adapter live capability。
- A1 共执行两次受控 live data task：旧 policy 首次通过 HTTP 200/exact final URL 后，以合并错误 `response-type-rejected` 在 metadata gate 停止；response delegate 在允许 body 交付前取消，工具未解析/保存 body。新 policy 第二次成功返回安全 receipt 后立即硬停止，未创建后续请求：body SHA-256 `1f5d2f9a0feaa0890ec7db02bbc6f426376d5d228be4ae7c872df1eeedf54dbd`、906 bytes、1 个 branch entry、observedAt `1787126649`、request `dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d`、policy `4b78e4fb1fb711010a90799c145bc08d607f4ad53f4cb70d32438f5ee062cec3`、shape policy 1 / SHA-256 `a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633`。未保存 raw body、query、credential 或 fixture；该 receipt 不是官方真实性证明、semantic branch 或 `ObservedEndpointProfile`。
- A1b safe shape report 已接入独立 `plan-branches-shape-cn` / `sample-branches-shape-cn` 与 `ALLOW_BRANCH_CN_SHAPE_V1` gate；policy SHA `e7ebc929ac6a6d25dc16c0d58bbaa67cfd15d7dda394b30bd150fd819cf220e4` 绑定 known-key allowlist、prior A1 shape、报告 caps 与 receipt-only 硬停止。一次受控 A1b live 返回 `matchesPriorShape=true` 后立即结束：body SHA/size 仍为 `1f5d…54dbd` / 906 bytes，report SHA `bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25`、canonical report 2,178 bytes、observedAt `1787129607`。安全树确认唯一 branch 含 `game{id,biz}`、`main{tag,branch,package_id,password}`、`pre_download=null` 及只以 SHA-256 表示的附加字段；未输出任何 scalar value，也未签发 credential/getBuild capability 或发后续请求。
- internal `StrictCNBranchSemanticDecoder` 已以 A1b shape/report pin 实现 semantic gate：先 detached-copy body，再复跑 strict scanner/report exact match，之后才由 private `Decodable` DTO 读取 `game{id,biz}` 与 main slot。game ID 必须等于固定 request，所有 opaque value 非空、无首尾空白/control、逐字段/总量受限；成功只返回全 surface 脱敏、不可编码且 binding 覆盖 request/transport/body/shape/report/全部 slot value 的 `ValidatedCNBranchCapability`。它不在 CLI 暴露，仅由受门控的 getBuild 事务在内存中消费。
- strict JSON scanner 新增 root-data 模式：继续要求 root `retcode == 0` 与 `data` object，但不要求 `data.game_branches`，用于 getBuild response 的 value-free shape/report 发现；branches 模式及其既有 known vectors 保持不变。该 scanner 已由下层 mock transaction 消费，但自身不发请求。
- `plan-build-main-cn` / `sample-build-main-cn` 两请求事务使用独立 gate `ALLOW_BRANCH_BUILD_MAIN_CN_V1` 与 policy SHA `dd0ab612aee8d025894e7f43269a287434844ecc29c2dbe03e70ea887844277d`，绑定 fresh branches semantic pins、exact `api-takumi` getBuild template、1/8/9 MiB branch/build/total caps、root-data report 与 `buildReceiptOnlyNoManifestNoPayload`。一次受控 live 恰好执行 branches+getBuild 两个 GET 后硬停止：build HTTP 200、4,518 bytes、body SHA `c8bae16dc79ed3430b151972dd6c091cbc00df3441a175adcb92a707b16190a0`、shape SHA `21e89e02cc735be6296f7ab41763875a8b7ff86db2e3fcefec32453e131db851`、report SHA `ab0d7df71bfd1be62d73d9414184afb58a6495c78a6470a2300283ebb9ee778f`。receipt 不含实际 build URL/request digest/credential；未访问 manifest/payload。
- internal `StrictMainBuildSemanticDecoder` 已以 live build shape/report pins 实现 semantic gate：build `data.tag` 必须等于 fresh branch tag，`manifests` 中必须唯一命中 `matching_field=game`；manifest ID/checksum/compressed/uncompressed size 与 manifest_download password/url_prefix 只进入 bounded、non-Encodable、全 surface 脱敏 capability。binding 覆盖 branch capability、transport/body/shape/report 与全部选中 raw values。
- `plan-manifest-origin-cn` / `sample-manifest-origin-cn` 使用独立 `ALLOW_BRANCH_BUILD_ORIGIN_CN_V1` gate；它仅执行 fresh branches + getBuild 两个 GET，由 origin-only capability 检查 manifest prefix 为 HTTPS/lowercase ASCII DNS/no IP/no port/no credential/no query/no fragment/no dot segment 的有界绝对路径。receipt 只输出 safe origin、path component count 和 path SHA-256，不输出 path/manifest ID/password。v1 在两个 GET 后以 `semantic-value-rejected` 停止，v2 进一步定位为 `build-download-reference-rejected`；两次都没有 receipt 或第三个请求。v3 改用最小权限 decoder，只消费 exact shape/report、fresh branch tag、唯一 game selection 和 url_prefix，不因本阶段无关的 password/checksum/size 拒绝；policy SHA `626daa27d87bc10a41afce9e833249d7d662157675b4cf3a7772233704e62dde`。一次受控 v3 live 成功返回 safe origin `https://autopatchcn.yuanshen.com`、path components `5`、path SHA `ea1f952ad03a4218f39f3c89567aac56d03b1bd88252f116f1781249cd7b0485`、observedAt `1787135597` 和 `requestCount=2`，然后硬停止，未访问 manifest/payload。
- `plan-manifest-metadata-cn` / `sample-manifest-metadata-cn` 将上述 exact origin/path pin 与最小 manifest ID 组合规则绑定到独立 policy `32809f02f6843c6f8f9ea931f18c25d1bb68f3f410b286b46b79405eb64aff8b` 和 `ALLOW_BRANCH_BUILD_MANIFEST_METADATA_CN_V1` gate。事务顺序执行 fresh branches + getBuild + manifest 三个 GET，但第三个只在 200/exact final URL 后分类 Content-Type/Encoding/Length 并在 body 交付前取消。一次受控 live 观测到 `application/octet-stream`、Content-Encoding absent、Content-Length `8,521,303`、request path SHA `ce154736f9d4cd8d3355c17101f99526ccd3a67772cf04defdd362afbf6cfea8`、observedAt `1787136897`、`requestCount=3` 且 `responseBodyAccepted=false`；未读取、保存或解压 manifest body。
- `plan-manifest-body-cn` / `sample-manifest-body-cn` 再以独立 policy `e253f675047143eb73dd4a09de22fae280a451872b3e5ed875f9ef4881677dc3` 和 `ALLOW_BRANCH_BUILD_MANIFEST_BODY_CN_V1` gate 绑定 fresh build 声明 size `8,521,303`、上述 request path SHA、exact `application/octet-stream`、absent/identity encoding 与 exact Content-Length。实现以有界 Data 流式计数/计算 SHA-256，成功只输出 body SHA/size 与 4-byte zstd magic 分类。一次受控 live 返回 body SHA `ca70fab422a2324aaece888534b9f013d4daf6e2c4430c6edf4da30a3e204c82`、size `8,521,303`、`zstdStandardFrame`、observedAt `1787137904` 与 `requestCount=3`；Data 已丢弃，不落盘、不解压、不请求 payload。
- `plan-manifest-structure-cn` / `sample-manifest-structure-cn` 把 exact body SHA、profile revision `1`、`genshinOfficialCN/game` 与 fixed structural baseline 绑在同一 fresh transaction。`ManifestSamplingCore` 仍不依赖 `BridgeCore`；只有 CLI executable 同时依赖两者，将短暂 package 级 owned bytes capability 交给 `ManifestLiveChunkInspector`。façade 再验 SHA 后调用已有 bounded zstd → wire scanner → generated decode/unknown reject → structural mapper/validator；receipt 只含聚合 count/bytes/SHA，不含 path/object/raw Data，也不能进入 Registry。v1 live 在解压前以 `content-type-rejected` 停止，v2 确认 transport 通过但以 `manifest-decompression-rejected` 停止；两次均无 structure/payload。v3 仅将 zstd 失败细分为 frame/dictionary/window/output/ratio/truncated/trailing/decoder 无值 safe code，不改变 limits，policy `820ad945c5ce247c99f39d03169d275509aac49a5b8199446624c667997914d5`。一次受控 v3 live 返回 `manifest-zstd-window-rejected`，证明当前 CN frame 需要超过 8 MiB 的解压窗口；未进入 wire/mapper 或 payload。v4 仅将 live inspector maximum window 提高到 16 MiB (`windowLog=24`)，fixture/replay default 仍为 8 MiB，C bridge 仍拒绝 log 25；policy `0fd87d77b4e30bcb6b9157fd02f5cc95084eb316f8a10deea627e5cfb23aea2e`。
- v4 live 在 manifest response 门以 `structure-manifest-response-rejected` 停止，未到 zstd。v5 进一步定位为 `structure-manifest-content-type-rejected`；同时 metadata-only gate 仍将 media type 分类为 `applicationOctetStream`，因此差异只能来自 `;` parameters。v6 只在 structure gate 允许最多 4 个、每个最多 128 bytes 的 printable ASCII parameter，旧 body gate 仍要求无参数 exact type；policy `b0a99e73e2cbc49f211f7eb23a3068edccf04b5586a1008c3a47f9e5c8a04fc9`。
- v6 live 已通过 response 与 zstd/log24，随后以 `manifest-wire-rejected` 停止，未进入 generated decode/mapper。v7 仅将 wire 原因细分为 `schema-drift / invalid-wire / resource-limit`，不改 fixed schema 或任何 budget；policy `28ef671cdbaa67bb91242d8d7699e5158c031ce0326f04d6e2498355307d8332`。
- v7 live 确认为 `manifest-wire-schema-drift`。v8 只增加首个 drift 的 fixed message kind + field number + wire type 无值诊断，不跳过未知字段、不运行 generated decoder；policy `70f8ab8689c1af6c2a1ba6319c9f16632c81149637c27f9ce57101d322db134b`。
- v8 live 定位到 `chunkInfo` field `7` / wire type `2`。pinned YAAGL main 与另一个活跃 MIT Sophon 实现均未定义该字段，因此 v9 仍不接受它；仅在失败路径统计该 field 的 occurrence count、min/max byte length 和 `lowerHex/upperHex/printableASCII/binary/mixed` 分类，不输出值或哈希；policy `9acae25d3980ee16e67ae6cf2bbbe773c7706a7129da641b80ba34d87b5ee701`。
- v9 live 观测到 field 7 共 `107,480` 次、全部为 32-byte lowercase hex，且容忍该字段后无其他 schema drift。v10 将 profile revision 升为 `2`、baseline 升为 `mgb-observed-cn-sophon-protobuf-structural-v2`，在本地 proto 中以 `opaque_hash` field 7 保留该 claim；v1 要求字段缺失，v2 要求每个 chunk 有严格 32 位小写 hex。该值参与 object metadata conflict 检查，但不命名为 MD5/XXHash、不执行 integrity verdict；policy `7ede9ed410cda836ac9ec2a43e2a5c33e7cf82e3d071bb8885dbf3ccccc5d382`。
- 一次受控 v10 live 完整通过 zstd → wire scanner → generated decode/unknown reject → structural mapper/validator：compressed `8,521,303` bytes / SHA `ca70fab4…04c82`，decompressed `15,913,977` bytes / SHA `e5b3a018cf7db0901bdf4d85c3aabfec10612e0d5d9da77c9a9505c05eb96fea`；2,673 files、0 directories、107,480 references、107,325 unique objects。target installed bytes `124,827,264,431`，referenced compressed bytes `121,314,849,412`，unique object bytes `121,185,381,917`。receipt 不含 path/object/field7 value，Data 已释放，未进 Registry、未请求 payload。
- `plan-chunk-origin-cn` 先以 policy `56b6b2f1…73ca` 确认 chunk CDN safe origin 为 `https://autopatchcn.yuanshen.com`、5 层路径与 path SHA `50e6250f…d2eb`。随后 `sample-one-chunk-payload-cn` 以 policy `36e23a25…5f6d0` 只选压缩体积最小的唯一 object，严格执行 branches→getBuild→manifest→one chunk 四个 GET。成功对 21-byte chunk 验证压缩 MD5、zstd 大小和解压后 MD5，再以 SHA-256 `8a1c5ac944823490b4879b551f5862fe3718e96738f7f4e29490c280391b5391` 提交到私有 CAS。未解包成游戏文件、未请求第二个 chunk。
- descriptor pin 只证明调用方预先信任的精确 bytes，不是官方签名；same-uid mutation、ACL 与当前二次 snapshot 的峰值内存仍是后续加固项。zstd、wire receipt、structural mapper 和 file loader 都不是已验证国服 profile，也不能单独进入 Registry。production endpoint JSON/branch-build-patch full decoder、`ObservedEndpointProfile`、cache/live 接线尚未实现；`EvidenceGatedManifestAdapter` 继续失败关闭且不会触网。
- SwiftProtobuf `1.38.1` 通过唯一的 `SwiftProtobufPlugin` 构建门生成 internal chunk/ldiff wire 类型；目前只验证 synthetic binary round-trip、unknown field 保留和 depth limit，不声称已实现 production semantic mapper 或 endpoint materialization。
- staging 调用方必须提供当前用户拥有、严格 `0700`、绝对规范且所有祖先均非 symlink 的可信私有 parent；macOS 的 `/var` 别名需先经 `realpath` 解析为 `/private/var`。

## 运行

```bash
./script/build_and_run.sh
env -u PROTOC_PATH swift build
env -u PROTOC_PATH swift test
env -u PROTOC_PATH swift build --product bridge-manifest-sample
.build/debug/bridge-manifest-sample plan
swift run bridge-probe
swift run bridge-probe --json
swift run bridge-catalog validate Catalogs/development-catalog.json
```

Codex 桌面端的 `Run` 操作也已绑定同一脚本；脚本会构建并启动
`dist/HoYoBridge.app`。当前已安装的国服客户端可从应用内启动；兼容运行时资产已随开发 `.app` 打包并可自动准备。游戏安装任务也已接入界面，并从 `.app` Resources 内调用固定 Python 3.11、YAAGL `ca78abc`、Protobuf/Zstandard/PycURL/psutil 组件，执行容量预检、续传和逐文件校验；离开源码目录后不再要求用户安装 Python 或 YAAGL。正式签名分发、这些运行时二进制的完整第三方许可审计和全新 Mac 实机验收尚未完成，因此开发构建仍不能直接当成公开发行成品。

主游戏页会根据当前状态把同一个主按钮切换为“安装游戏”“继续安装”“准备并启动”或“启动游戏”。开始安装时会同时准备 CrossOver/DXMT Prefix；用户选择的游戏目录会持久保存并由启动器继续使用，不再要求安装完后手工重新定位。已安装游戏执行更新或校验前会先在同一 APFS 卷创建 clone-on-write 备份；界面可以把当前目录与备份原子交换，回滚后仍保留刚替换下来的版本。

产品待办见 [docs/PRODUCT_TODO.md](PRODUCT_TODO.md)，项目需求边界见 [docs/PRODUCT_BOUNDARIES.md](PRODUCT_BOUNDARIES.md)，架构方向见 [docs/ARCHITECTURE.md](ARCHITECTURE.md)，当前进度见 [docs/STATUS.md](STATUS.md)。网络下载边界见 [docs/NETWORK_DOWNLOADS.md](NETWORK_DOWNLOADS.md)，安全解压策略见 [docs/SAFE_EXTRACTION.md](SAFE_EXTRACTION.md)，staging 写入事务见 [docs/STAGING_EXTRACTION.md](STAGING_EXTRACTION.md)，版本化 runtime store 见 [docs/RUNTIME_STORE.md](RUNTIME_STORE.md)，激活身份见 [docs/RUNTIME_ACTIVATION.md](RUNTIME_ACTIVATION.md)，归档后端决策见 [docs/ARCHIVE_BACKEND.md](ARCHIVE_BACKEND.md)，国服只读资源协议契约见 [docs/MANIFEST_ADAPTER.md](MANIFEST_ADAPTER.md)。

`Catalogs/development-catalog.json` 是未签名开发样例，故意不包含任何游戏版本配置。它通过结构校验不代表受信任，也不会让启动器宣称当前版本可运行。
