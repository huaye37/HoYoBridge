# 架构方向

## 总体流程

```text
版本监控
  -> Manifest 与资源协议适配器
  -> 下载、校验、修复和原子更新
  -> 版本化兼容配置
  -> Wine 与图形运行时
  -> 启动、诊断与恢复
  -> 性能和兼容性报告
```

## 运行时策略

图形后端采用可插拔设计：

- DXMT Stable
- DXMT Latest
- GPTK 4 / D3DMetal
- CrossOver D3DMetal
- 用户提供的自定义运行时

“最新”不等于“默认”。自动选择必须依据游戏版本、macOS、芯片和真实基准结果；实验兼容模式允许用户强制切换并恢复。

## 组件分层

1. `BridgeCore`：纯 Swift 核心模型、能力探测、兼容规则和诊断。
2. `bridge-probe`：只读命令行探针，为本机调试和 CI 提供结构化报告。
3. `bridge-catalog`：只校验本地未签名开发目录，并明确标记其不受信任。
4. Catalog 层：验证原始 payload 的 Ed25519 签名、有效期、revision、最低客户端版本、撤销清单和引用完整性；只有 `VerifiedCatalog` 能进入选择器。
5. Manifest 层：目标 replay 链为 trusted descriptor pin → safe flat fixture loader → schema v3 descriptor/owned byte bundle → actual-driven endpoint decoder → factory/candidate → `fileprivate` materialized capability → Registry；其中 chunk/ldiff leaf 子链固定为 bounded zstd capability → zero-copy wire budget receipt → generated decode/recursive unknown check → fixed-baseline structural mapper/source selection → `ChunkManifestValidator`/`LdiffSelectionValidator`。当前 loader 只返回 byte bundle，Registry 不接受 raw candidate、descriptor、bundle、仅解压 capability、budget receipt 或 structural capability。production endpoint JSON/branch-build-patch full decoder、`ObservedEndpointProfile`、cache/live 仍未实现；Evidence gate 继续失败关闭。完整链仍只证明 fixture response 的 semantic/version/reference 本地自洽，不认证官方来源，branch→build request/credential chain 也未绑定。
   A0 discovery 由独立 `ManifestSamplingCore` 承担，不依赖也不被 `BridgeCore` 依赖。它只有无网络的 `plan` 与双门固定 `sample-branches-cn`，receipt 是 value-free shape/body identity 证据而非 endpoint profile、semantic branch 或 adapter capability；两次受控 A1 分别在旧 metadata gate 停止、在新 policy receipt 后硬停止，均未进入后续请求，也未形成 profile。
6. Network 层：只向内置 allowlist 的 HTTPS host 下载固定大小/哈希产物；支持跨卷容量预检、fresh GET、绑定强 validator 的严格续传，以及持久 lease 保护的显式 partial GC；尚未完成限速和真实 CDN 集成。
7. Artifact 层：流式校验字节数和 SHA-256，并以 `objects/sha256/<prefix>/<digest>` 存入不可变内容寻址缓存。
8. Extraction 层：当前已完成带 canonical digest 的后端无关安全计划，以及目录 FD 驱动、逐文件 SHA-256、最终 FD 重哈希、确定性 tree seal、root device/inode 交接、sealed tree 复验和失败清理；仍需固定版本 libarchive 窄包装提供真实归档只读枚举与内容 source，随后才进入 runtime 发布。
9. Runtime 层：当前完成 `MGBINSTALL` v1、sealed tree 发布/复用和 catalog-bound `reopenInstalled`；后续负责 GC 和运行时版本管理。
10. Launcher 层：当前完成 `MGBCURRENT` v1、首次发布、exact CAS、rollback，以及 current resolve/重启恢复；后续负责紧邻启动的复验与实际启动。
11. UI/Launcher 层：`MacGameBridge` SwiftUI executable 使用 `NavigationSplitView` 组织游戏库与工具页。内置原神 profile 通过固定 `GameRuntimePaths`、`GenshinPrefixConfigurator` 和 `GameLaunchService` 自动应用独立 prefix 的语言/窗口设置，并以 `Foundation.Process` 启动或停止已验证的 Wine/Steam 链；不构造任意 shell 命令。自定义 `.exe` 只能加入库，必须建立独立 compatibility profile 后才能启动。`RuntimePreparationService` 校验应用内固定 CrossOver/DXMT/Steam 资产，在 staging 中解包、覆盖 DXMT、创建 Prefix 并发布到用户 Application Support；启动路径优先使用该自包含安装，再兼容开发目录。`GameInstallationService` 优先调用 Resources 内固定 Python/YAAGL toolchain，只解析无文件名的 `SUMMARY`/`PROGRESS`/`COMPLETE` 记录，开发 checkout 仅作回退；下载安装无需用户提供 Python、YAAGL 或终端命令。`GamePrimaryActionResolver` 将首次安装、续传、运行环境准备和启动映射到单一主按钮；非默认游戏目录写入用户偏好并由 launcher 复用。

## 代码生成验证门

- 构建：`env -u PROTOC_PATH swift build`
- 测试：`env -u PROTOC_PATH swift test`
- `SwiftProtobufPlugin` 是唯一 codegen 入口，不配置 `protocPath`且不接受外部
`PROTOC_PATH`。该门只验证生成类型与 wire 基础行为，不替代 semantic validator。

## A0 branch discovery 门

`bridge-manifest-sample` 是单独 executable product；`ManifestSamplingCore` 不作为 library product 发布。
production profile 固定 HTTPS origin/path 与私有 query，外部不能传 URL、profile、请求 body、输出路径或
retry 参数。`plan` 的 policy SHA 绑定 safe origin/path、系统信任+最低 TLS 1.2、exact final URL/200/JSON/
identity、redirect/auth 拒绝、cookie 不发送不存储、HTTP cache 禁用、单 data task 无应用层 retry、
1 MiB cap、timeouts，以及
`responseBodyMemoryOnlyNoExplicitFileWrite` 边界。

cookie 边界具体为 request `httpShouldHandleCookies=false`、session cookie storage=nil，response
`Set-Cookie` 忽略且不输出；它不是 response rejection gate。旧 policy 的第一次受控 A1 已通过 HTTP 200
与 exact final URL，随后以合并错误 `response-type-rejected` 在 metadata gate 取消；response delegate 在
允许 body 交付前取消，工具未解析/保存 body。新 policy 的第二次 A1 成功产生 body/request/policy/
value-free shape receipt 后立即硬停止。两次均未发起后续请求，也未保存 raw body、credential 或 fixture。

真实采样前必须先离线完成 build/test，再直接执行已构建 binary；live 阶段不使用裸 `swift run` 作为
“单请求”证据，因为 SwiftPM 自身可能解析依赖或写 `.build`。工具层的“单请求”只表示创建一个 vendor
HTTP data task；DNS、TLS/证书状态查询和 CFNetwork 底层重连不等于单个网络包。当前所有测试均由
`URLProtocol` mock/tripwire 完成；两次 live 只是受控证据采样，不认证远端官方真实性，也不产生
`ObservedEndpointProfile` 或 adapter capability。

响应 body 最多 1 MiB，只在内存中增量 SHA 后进入 duplicate-aware RFC 8259 scanner。scanner 输出
value-free recursive shape SHA 与独立 branch entry count；shape SHA 不含 scalar value、array 顺序或
重复同形元素数量，也不能直接充当 `ObservedEndpointProfile` schema baseline。receipt 不含 query、
body、branch、package 或 password。第二次 A1 receipt 为 body SHA-256
`1f5d2f9a0feaa0890ec7db02bbc6f426376d5d228be4ae7c872df1eeedf54dbd`、906 bytes、branch count 1、
observedAt `1787126649`、request `dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d`、
policy `4b78e4fb1fb711010a90799c145bc08d607f4ad53f4cb70d32438f5ee062cec3`、shape policy 1 / SHA-256
`a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633`。

A1b 的 safe shape report core 复用同一次 strict parse：known-key policy v1 只输出人工固定的 schema key
名称，其他 decoded UTF-8 key 只输出小写 SHA-256；scalar 只输出 kind，不输出 value 或 length。object
按既有 key identity → child shape 排序，array 按 child shape digest 排序去重，因此不会丢失元素内字段
相关性，也不把重复数量写进 schema。默认 report cap 为 4,096 nodes、256 unique array shapes、1,024
unknown keys 和 256 KiB canonical bytes；超限不返回截断树。独立 `plan-branches-shape-cn` /
`sample-branches-shape-cn` 使用 `ALLOW_BRANCH_CN_SHAPE_V1` gate，plan 绑定 known-key allowlist、prior
A1 shape/count、report/receipt caps 与 `receiptOnlyNoCapabilityNoFollowup`。一次受控 A1b live 产生
`matchesPriorShape=true` 的安全树后立即硬停止：body SHA/size 与 A1 相同，report SHA 为
`bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25`，canonical report 2,178 bytes。
树确认唯一 branch 具有 `game{id,biz}`、`main{tag,branch,package_id,password}` 与
`pre_download=null`，其余字段只保留 key SHA-256/shape。没有 semantic branch capability 或 getBuild
接线，也未发后续请求。

`StrictCNBranchSemanticDecoder` 是下一层 internal mock-only gate。它只在同一 owned body 已通过
duplicate-aware scanner、A1 shape SHA 与 A1b report SHA/size/count exact pin 后，才使用 private
`Decodable` DTO 读取 `game{id,biz}` 与 main slot；unknown values 虽不映射，但其 key/shape 已被 report
pin 绑定。game ID 必须精确等于固定 request，opaque values 只做非空、UTF-8 byte cap、首尾空白/control
拒绝，不 trim/normalize。返回 capability 的 binding 覆盖 request/transport/body/shape/report 与全部原始
slot values；类型不 Encodable/Decodable 且 description/debug/Mirror 脱敏。capability 不在 CLI
暴露，只在受门控的 getBuild 事务内存中消费；Swift `String` 也不承诺内存 zeroize。

getBuild response 不复用 branches anchor：同一 scanner 已新增 root-data 模式，只要求 root
`retcode == 0` 与 `data` object，并继续执行完整 RFC 8259/duplicate/limits/value-free report；它不要求
`data.game_branches`。scanner 本身不发请求；受门控的 getBuild 事务在 mock 和一次受控 live 中
均使用该模式。

下一层 guarded transaction 暴露独立 `plan-build-main-cn` / `sample-build-main-cn` 和
`ALLOW_BRANCH_BUILD_MAIN_CN_V1` gate。它顺序执行 fresh branches → observed semantic pins → internal
capability → exact `https://api-takumi.mihoyo.com/downloader/sophon_chunk/api/getBuild` GET；query names
固定为 `branch/package_id/password`，values 只来自 capability，完整 URL 与 actual request digest 都不进入
receipt。branch/build/total response caps 为 1/8/9 MiB，两个 operation 都复用 TLS/auth/redirect/content/
cookie 失败关闭门。build response 只做 root-data safe shape report，随后以
`buildReceiptOnlyNoManifestNoPayload` 硬停止。独立 mock 验证后，一次受控 live 恰好完成 branches+getBuild
两个 GET 并停止：build 200/4,518 bytes，body/shape/report SHA 分别为
`c8bae16d…90a0` / `21e89e02…b851` / `ab0d7df7…778f`。未访问 manifest URL 或 payload。

`StrictMainBuildSemanticDecoder` 以该 build shape/report/size 作为 production observed pins。它 detached-copy
body 并复跑 8 MiB root-data scanner 后，private DTO 才读取 `data.tag/build_id/manifests`；tag 必须等于
fresh branch capability，且 `matching_field=game` 必须唯一。选中 manifest 的 id/checksum/compressed/
uncompressed size 与 manifest_download password/url_prefix 仅进入 bounded、non-Encodable、全 surface
脱敏 capability；domain-separated binding 覆盖 branch capability、transport/body/shape/report 与全部 raw
values。

下一个 mock-only 边界是 `plan-manifest-origin-cn` / `sample-manifest-origin-cn` 与独立
`ALLOW_BRANCH_BUILD_ORIGIN_CN_V1` gate。它仍只顺序创建 fresh branches + getBuild 两个 data task，
然后在内存中由 actual build capability 验证 manifest prefix：HTTPS、lowercase ASCII DNS、非 IP、
无 port/userinfo/query/fragment，且 path 为无 dot segment 的有界绝对路径。receipt 只保留 safe
origin、path component count 与 percent-encoded path SHA-256，不输出 path、manifest ID、password
或 actual request URL。policy SHA 为
v1 policy `fc596584…79e8` 的首次受控 live 在两个 GET 后以无值
`semantic-value-rejected` 停止，没有返回 receipt 或创建第三个请求。v2 只将 build semantic
失败拆成无值 stage code，第二次受控 live 定位为 `build-download-reference-rejected`，
同样没有 receipt/第三请求。v3 不再要求完整 build capability，而是签发更窄的
origin-only reference：继续精确绑定 shape/report、fresh branch tag 和唯一 `matching_field=game`，
但只读取/验证 url_prefix，不消费 password、checksum 或 size。v3 policy SHA 为
`626daa27d87bc10a41afce9e833249d7d662157675b4cf3a7772233704e62dde`。一次受控 v3 live 在两个 GET 后
返回 `https://autopatchcn.yuanshen.com`、5 个 path components、path SHA
`ea1f952ad03a4218f39f3c89567aac56d03b1bd88252f116f1781249cd7b0485` 与 `requestCount=2`，
随后按 `originReceiptOnlyNoManifestRequest` 硬停止。该 host/path 证据未自动进入下载 allowlist。

manifest response metadata 必须再经过独立 `plan-manifest-metadata-cn` /
`sample-manifest-metadata-cn` 和 `ALLOW_BRANCH_BUILD_MANIFEST_METADATA_CN_V1` gate。plan 将 exact
`autopatchcn.yuanshen.com` origin、prefix path count/SHA、ASCII single-component manifest ID 规则、
`application/octet-stream` request Accept、identity encoding 与 64 MiB declared-length 分类上限绑定为
policy `32809f02f6843c6f8f9ea931f18c25d1bb68f3f410b286b46b79405eb64aff8b`。
`StrictMainManifestRequestDecoder` 重新绑定 fresh branch tag、build shape/report、unique game、manifest ID
和 origin pin，但返回类型不可编码且脱敏。metadata transport 在第三个 GET 收到 exact
final URL/status 与 headers 后立即取消 body 交付；未知 Content-Type/Encoding 只输出规范化值 SHA，
receipt 只留请求 path SHA 与 safe header classifications。一次受控 live 以三个 GET 完成，
第三响应为 `application/octet-stream`、Content-Encoding absent、declared length `8,521,303`、
request path SHA `ce154736f9d4cd8d3355c17101f99526ccd3a67772cf04defdd362afbf6cfea8`，
且 `responseBodyAccepted=false`。本阶段没有读取、保存或解压 manifest body。

manifest body 读取使用第三个独立 `plan-manifest-body-cn` / `sample-manifest-body-cn`
与 `ALLOW_BRANCH_BUILD_MANIFEST_BODY_CN_V1` gate。plan policy
`e253f675047143eb73dd4a09de22fae280a451872b3e5ed875f9ef4881677dc3` 同时要求 fresh build
`compressed_size == 8,521,303`、request path SHA 不变、exact `application/octet-stream`、
absent/identity encoding 和 exact Content-Length。response body 只在内存 Data 中逐 chunk 计数/更新
SHA-256，short/extra/header mismatch 均立即失败；完成后只保留 body SHA/size 和前 4 bytes
magic 分类，不保留 Data、不落盘、不解压、不请求 payload。5 项 mock 通过后，
一次受控 live 精确读取 `8,521,303` bytes，body SHA-256 为
`ca70fab422a2324aaece888534b9f013d4daf6e2c4430c6edf4da30a3e204c82`，frame kind 为
`zstdStandardFrame`，`requestCount=3`。receipt 生成后 Data 已丢弃。

structural inspection 使用 `plan-manifest-structure-cn` / `sample-manifest-structure-cn` 和
`ALLOW_BRANCH_BUILD_MANIFEST_STRUCTURE_CN_V1`。v1 policy
`1782e2bb3924c6360c0515603cee6fb7d9067b65b6ce4e486aace2fd914a6af3` 绑定上述
compressed SHA/size、profile revision `1`、`genshinOfficialCN/game` 和 fixed structural baseline。
`ManifestSamplingCore` 仍不依赖 `BridgeCore`；只有 `bridge-manifest-sample` executable 同时依赖
两个 target，把同一 fresh transaction 内的 detached package bytes capability 交给窄
`ManifestLiveChunkInspector`。façade 重新验证 compressed SHA 后执行现有 bounded zstd、wire
scanner、generated decode/unknown reject 和 structural mapper/validator。receipt 只输出聚合 SHA/count/bytes，
不含 path/object/raw Data，不产生 Registry capability 或 payload 请求。首次 v1 live 在进入解压前以
`content-type-rejected` 停止。v2 确认 transport 通过，但 zstd 以无值
`manifest-decompression-rejected` 停止。v3 只将 zstd 失败分为 frame/dictionary/window/output/
ratio/truncated/trailing/decoder 无值原因，不改变任何 limit；policy 更新为
`820ad945c5ce247c99f39d03169d275509aac49a5b8199446624c667997914d5`。当前 4 项
structure-specific sampling 与 2 项 BridgeCore 定向测试通过。一次受控 v3 live 返回
`manifest-zstd-window-rejected`，因此已确认当前 CN frame 超出 8 MiB window，但尚未进入
wire scanner/mapper。v4 只对 `ManifestLiveChunkInspector` 使用 `windowLog=24` / 16 MiB，
fixture/replay default 仍是 log 23；C bridge maximum 只提到 24，log 25 仍失败关闭。plan policy 为
`0fd87d77b4e30bcb6b9157fd02f5cc95084eb316f8a10deea627e5cfb23aea2e`。
v4 live 在 manifest response 门以 `structure-manifest-response-rejected` 停止，未进入 zstd。v5
只将该 stage 的 final URL/status/content-type/encoding/length/oversized 分为独立无值原因，
不改变接受规则；policy 为
`0bfe69619d500fa6078a1372b98bf645726f75cf93269b9d731c1a8aae1791c4`。
v5 live 返回 `structure-manifest-content-type-rejected`，而紧随的 metadata-only 观测仍将
media type 归类为 `applicationOctetStream`，因此可确定差异是 content-type parameters。v6 只在
structure binary mode 允许最多 4 个、每个最多 128 printable ASCII bytes 的 parameter；body gate 仍
要求无参数 exact type。policy 为
`b0a99e73e2cbc49f211f7eb23a3068edccf04b5586a1008c3a47f9e5c8a04fc9`。
v6 live 通过 response 与 zstd/log24 后在 wire scanner 以 `manifest-wire-rejected` 停止。v7 只将
scanner 拒绝细分为 schema drift、invalid wire 和 resource limit，不改 fixed 10-message schema、
depth/count/string/node budgets 或 generated decode；policy 为
`28ef671cdbaa67bb91242d8d7699e5158c031ce0326f04d6e2498355307d8332`。
v7 live 定位为 `manifest-wire-schema-drift`。v8 在不改变 scanner 接受结果的前提下，仅在
schema-drift 失败路径重跑 zero-copy scanner，输出首个 drift 的 fixed message kind、field number 和
wire type；不读取 field value，不跳过 unknown，不进 generated decoder。policy 为
`70f8ab8689c1af6c2a1ba6319c9f16632c81149637c27f9ce57101d322db134b`。
v8 live 定位为 `chunkInfo` field 7 / wire type 2。v9 的正常 scanner 仍在此处拒绝；只有
diagnostic 重扫描允许该一个 field，并在其他 schema/budget 仍完整通过时输出 occurrence count、
min/max byte length 和无值 byte-class。policy 为
`9acae25d3980ee16e67ae6cf2bbbe773c7706a7129da641b80ba34d87b5ee701`。
v9 live 确认 field 7 在 107,480 个 chunk 中均为 32-byte lowercase hex，且 diagnostic 容忍后
无其他 drift。v10 删除临时 field7 diagnostic 双路径，正式 scanner 读取 singular string field 7；
mapper 由 baseline 决定 v1 必须 absent、observed CN v2 必须 lowercase-hex32。opaque claim 参与 object
metadata equality，但无算法或 checked-bytes 语义。v10 plan 使用 profile revision 2、baseline
`mgb-observed-cn-sophon-protobuf-structural-v2` 与 policy
`7ede9ed410cda836ac9ec2a43e2a5c33e7cf82e3d071bb8885dbf3ccccc5d382`。
v10 live 完整通过该链：compressed/decompressed SHA 分别为 `ca70fab4…04c82` /
`e5b3a018…96fea`，解压后 15,913,977 bytes，wire receipt 为 2,673 files、107,480 chunks、
110,154 nodes 和 12,410,255 string bytes；validated summary 为 107,325 unique objects、
124,827,264,431 target bytes、121,314,849,412 referenced compressed bytes 与 121,185,381,917
unique object bytes。这仍只是 discovery receipt，不是 `ManifestInspection` 或 Registry capability。

payload probe 在另一个 policy/gate 中从 validated objects 按 `compressedBytes`、再按 UTF-8
object ID 确定性选一个最小候选，限制压缩 16 MiB/解压 64 MiB。请求链严格为
branches → getBuild → manifest → one chunk，chunk prefix 须匹配已单独观测的 safe origin/path pin。
下载字节先校验 exact compressed size 和 field7 compressed MD5，再以 windowLog 24 单帧解压，
要求 exact uncompressed size 与 field2 MD5。成功后以 SHA-256 进入
`LocalRuntimes/ChunkProbeCache` 私有 CAS；不解包成游戏文件、不请求第二个 chunk。

## Manifest zstd 字节门

SwiftPM 精确固定 `facebook/zstd` `1.5.7`/`f8745da6ff1ad1e7bab384bd1f9d742439278e99`。
依赖方向仅为 `BridgeCore → CZstdBridge → libzstd`；`BridgeCore` 不直接依赖或 import upstream
module，production 窄 header 与调用点只暴露 frame probe、streaming decode 和 destroy。MacGameBridge
自有压缩/字典/高级 frame 构造 helper 只存在于 Tests；单一 upstream `libzstd` product 仍可能包含完整
compression symbols。

`ManifestZstdDecompressor` 要求标准单 frame、完整消费、无 trailing/concatenated/skippable/dictionary，
以 windowLog 23、chunk/diff 各 256 MiB 和 `1 MiB + 128 × actual consumed bytes` 三重门限制内存与
膨胀。known frame content size 先预检并在结束时精确复核；unknown size 仍按流式实际输出计数。返回
owned bytes、输出 SHA-256/size 和 compressed artifact identity 的脱敏 capability，但不提供 protobuf
或 semantic 授权。限值需待真实国服样本审核后按版本化 profile 校准，不能静默放宽。

## Protobuf wire budget 门

`ManifestProtobufWireBudgetScanner` 在 generated SwiftProtobuf allocation 前，直接借用 zstd capability 的
owned `Data` 字节视图扫描固定 10 个 message schema，不复制 payload 或构造 field string。它只接受
known field number 与对应 wire type，拒绝 singular duplicate，并要求 tag、length 和 numeric value 均
使用 minimal varint；int32/uint32 还执行 protobuf 类型范围与 sign-extension 检查。

默认 provisional budgets 为 depth 3、files 100,000、chunks 1,000,000/每文件 100,000、patches
500,000/每文件 256、delete groups 256、delete entries 100,000、nodes 1,250,000、单 string field
最多 1,024 bytes、全部 string bytes 128 MiB。调用方只能收紧。unknown/wrong-wire/duplicate singular
归为 `schemaDrift`，畸形或 non-minimal wire 归为 `invalidWire`，预算超限归为 `resourceLimit`。

policy v1 脱敏回执绑定 compressed artifact identity、decompressed SHA-256/size 与各计数，并在入口、
约每 1,024 fields 或 64 KiB 和返回前检查取消。它不检查 UTF-8、required/default、path/hash、flags、
source filtering 或任何业务关系，不是 semantic mapper/profile。下一节在该 receipt 后执行 generated
decode、recursive `unknownFields` 与 fixed-baseline structural mapping。

## Structural protobuf mapper

`ManifestProtobufStructuralMapper` 只接受 zstd capability、expected manifest reference 和精确
`yaagl-ca78abc-sophon-protobuf-structural-v1` schema baseline。它先重跑 scanner，再用 SwiftProtobuf
depth 4 decode且保留 unknown fields，随后递归要求 10-message tree 的 `unknownFields` 全空。mapper
重新统计 files/chunks/patches/delete groups/delete entries/nodes/string bytes，并与 policy v1 receipt、
compressed identity 和 decompressed SHA/size 完全相同。

chunk raw records 全量映射后进入 `ChunkManifestValidator`；`xxhash` 作为 wire `UInt64` numeric claim
保留，不声称已验证实际 XXH64 algorithm、seed 或 checked bytes。ldiff 对所有 source 的 patch/delete
records 先完整校验，再按 opaque `GameVersion` exact source 选择；零 patch 与无匹配 source 保持不同
reason，exact deletion group 选择也不合并。`patch_name` 与 `original_name` 分别安全保留为 remote name
和 normalized path，但不猜其与 patch ID 或 outer file path 的关系；delete hash empty 映射 nil，非空
必须是 MD5。

返回的 structural chunk/ldiff capability 含 receipt、candidate 和 validator result，构造受限且
description/debug/Mirror 脱敏，不实现 `Decodable`。它只证明固定 YAAGL baseline 的结构映射，不是
`ObservedEndpointProfile`、国服样本验证或 Registry/launch 授权。

## Safe fixture file loader

`ManifestReplayFixtureFileLoader.load` 强制接收 `ManifestFixtureID` 与 trusted descriptor SHA-256，不提供
unpinned overload。flat layout v1 只允许 `fixture.json`、`branch-response.redacted.json`、
`build-response.redacted.json`、`patch-response.redacted.json`、`chunk-manifest.pb.zst` 和
`ldiff-manifest.pb.zst`；实际 exact inventory 由 canonical descriptor shape 决定。

root 从 `/` 开始按最多 64 个绝对 path components 用 dirfd、`fstatat(..., NOFOLLOW)` 与
`openat(..., O_DIRECTORY|O_NOFOLLOW)` 逐级打开；最终 root、fixture 和文件必须属于 euid，fixture/files
与 root 同 device。root/fixture 要求 owner rwx、无 group/world write 与 setuid/setgid/sticky；文件必须
regular、`nlink == 1`、owner-readable、无 execute/group-world write/special bits。canonical supported
mode pairs 为 `0755/0644` 与 `0700/0600`。

loader 先按 pin 读取/哈希最多 64 KiB descriptor，要求 canonical schema v3、自身 SHA/size 与 requested
fixture ID exact；随后验证 flat inventory，并在任何 artifact Data 分配前打开全部 expected files，完成
declared size、per-kind cap 与 128 MiB total preflight。每个文件再以 64 KiB `pread` 填充 owned Data，
同一 chunk 更新 SHA-256，拒绝 short/extra bytes，并以 fd/path device+inode、mode/size、ctime/mtime
复验。之后仍进入 BundleValidator，结束前再次验证 inventory、fixture directory 与重新打开的 root。

loader 全程 read-only，支持 cancellation、FD cleanup、并发 deterministic snapshot；loader/hooks/errors
默认打印均脱敏。返回值只到 `ValidatedReplayArtifactBundle`，不会 zstd decompress、wire scan/map、
materialize、Registry、network 或游戏文件访问。descriptor pin 若来自同一不可信目录就没有信任意义，
也不等于官方签名；mode checks 不审计 ACL，同 uid 对手和 BundleValidator 二次 owned snapshot 的 peak
memory 仍属后续边界。

## 兼容目录选择规则

- 游戏版本同时匹配展示版本和不可变构建指纹，不使用模糊版本范围。
- 标准配置必须绑定固定运行时，并具有安装、启动、登录、持续运行和画面正确性验证记录。
- 实验模式不会自动降级或自动选中实验项；用户必须明确选择配置。
- 实验确认绑定 catalog revision、原始 payload SHA-256、profile ID/revision 和 disclosure digest。
- 相同最高优先级存在多个标准候选时返回歧义，不随机选择。
- 被撤销、过期、回退、签名错误或供应链字段不完整的条目一律失败关闭。
- stable/testing 签名公钥分别声明允许签署的 channel，不能跨通道提权。

## 安全与更新原则

- 下载写入唯一临时文件，完成校验后原子替换。
- 每个二进制记录来源、SHA-256、许可证和适用范围。
- 托管下载还必须记录固定 HTTPS URL 和预期字节数，禁止 `latest`、`main` 等浮动版本。
- 本地服务只监听回环地址，并使用随机认证密钥。
- 系统改动使用事务模型：预览、确认、应用、验证、回滚。
- 稳定版和测试版分通道发布，兼容配置与应用程序可独立更新。
- 不在许可证未确认时重新分发 GPTK/D3DMetal。

## 产物缓存事务

缓存提交只处理已下载的原始压缩包或二进制，不执行解压：

1. staging 与对象目录都位于同一私有缓存根目录。
2. 通过 `O_NOFOLLOW` 打开文件，要求普通文件，并分块统计实际字节数和 SHA-256。
3. 验证成功后把 staging 权限改为只读并执行 `fsync`。
4. 使用 `renameatx_np(..., RENAME_EXCL)` 作为唯一提交点。
5. 并发提交遇到已有对象时重新验证赢家；正确则复用，损坏则失败关闭。
6. 任意提交前错误都会删除唯一 staging，已存在对象保持不变。

详见 [ARTIFACT_STORE.md](ARTIFACT_STORE.md)。

## 归档 staging 事务

归档 staging 与内容寻址缓存提交是两条独立事务。`SafeStagingExtractor` 只消费已经由
`SafeArchivePlanner` 验证、并绑定同一 CAS 产物 SHA-256 的受控 source：

1. 调用方提供一个当前用户拥有、严格 `0700` 的可信私有 parent，以及其下尚不存在的直接子项。
2. parent 必须是绝对规范路径，且从 `/` 开始的每一级祖先都不能是 symlink；macOS 的 `/var`
   是 `/private/var` 的别名，调用方必须先用 `realpath` 得到真实路径。
3. 计划以带 domain/schema 和长度 framing 的 canonical SHA-256 绑定策略、大小和全部规范条目，
   不依赖 JSON key 顺序或归档输入顺序。
4. root、目录和文件都通过持有的 dirfd 创建；文件按计划精确计数、归一化权限、计算写入时
   SHA-256 并 `fsync`。
5. 返回前重新枚举整个 tree；每个普通文件从最终只读 FD 重哈希，并复验创建时与扫描后的
   device/inode、大小、权限和路径身份。
6. 规范排序的路径、类型、权限、大小和逐文件 SHA-256 形成版本化 tree seal；交接对象还携带
   artifact/plan SHA-256、策略/seal 版本和最终 root device/inode。
7. `SafeStagingExtractor.reverify` 会先验证 candidate 的版本、计数、规范 entry 顺序、祖先结构和
   tree seal 自洽，再匹配 root device/inode、精确 inventory，并从最终 FD 逐文件重哈希。
8. 该调用返回后会关闭 FD，只代表完成瞬间的 snapshot。未来 publisher 必须从复验前开始持有
   对同一 staging 事务的独占锁，在 rename 前再次匹配 root 身份，并在提交后按事务需要从最终
   路径复验；当前仍不执行 runtime rename、current 切换或启动。

详见 [STAGING_EXTRACTION.md](STAGING_EXTRACTION.md)。

## Runtime 安装身份

`RuntimeInstallIdentityBuilder` 把已验证的 managed-download runtime 定义、安全计划和 sealed
staging candidate 收敛为 `RuntimeInstallRecord`。`installID` 使用 `MGBINSTALL` domain 与 schema
version 1，依次绑定 runtime ID、runtime definition SHA-256、规范 artifact SHA-256、plan policy
version 与 SHA-256、tree seal version 与 SHA-256、entry count、regular-file count 和展开总字节。
record 同时保留规范 seal entries，便于后续审计与复验。

builder 还要求 runtime 的 artifact SHA-256 与 candidate 一致，candidate 的 plan/tree 与输入计划
自洽，并强制 `runtime.byteSize == plan.archiveByteSize`。后者把 `SafeArchivePlanner` 膨胀比计算的
分母固定到目录中声明的真实产物大小，拒绝使用虚增 archive size 生成更宽松计划后再绑定较小
产物。

`RuntimeInstallRecord` 只支持 `Encodable`，不能把磁盘 JSON 直接 decode 成可信安装能力；记录
必须从受信 runtime、plan 和 candidate 重新构建。`VersionedRuntimeStore` 当前可在自己拥有的
staging 中执行 extraction，把 receipt 与 payload 作为一个 fresh version 原子发布；它没有把
已有 receipt 解码为可信状态；`EEXIST` 复用依赖本次重新生成的预期 record/tree。独立 reopen
使用下述受限 decoder、catalog cross-check 和 payload full verify；current 事务仍不构成启动授权。

## Runtime 发布与精确复用

runtime root 必须预先存在、路径规范、祖先无 symlink、由当前用户拥有且严格 `0700`。store
取得持久 `.publish.lock` 的非阻塞独占 `flock` 后，才创建 `.staging`/`versions` 和本次 UUID
wrapper。输入大小、plan policy 和 artifact identity 在事务前预检，extractor 只由 store 调用。

wrapper 仅允许 `payload` 与 sorted-key `install.json`。receipt 写入、`fsync` 后按原字节重新读取；
payload 在 receipt 前后复验，并在 rename 前再次完整复验。staging 与目标 prefix 必须同卷，唯一
提交点为 `renameatx_np(..., RENAME_EXCL)`；成功后依次同步目标 prefix 和源 staging，再从新路径
复验 payload、receipt 和 root 身份。

rename 前失败或取消会受限清理本次 wrapper；rename 成功后版本已经可见，不能因迟到取消删除。
提交后失败携带 `versionVisible` 和 durability 状态。

若 `RENAME_EXCL` 遇到已有目标，store 不 decode receipt，而是用本次可信输入生成的 sorted-key
receipt 与 seal 作为 expected：已有目录必须只含 `install.json`/`payload`，receipt 必须逐字节
相同，payload 必须完整 reverify，并在返回前再次匹配 target 与 root inode。全部通过才清理本次
wrapper 并返回 `reusedExisting`；任一异常都保留已有目标并失败关闭，不覆盖、不修复。完整边界
见 [RUNTIME_STORE.md](RUNTIME_STORE.md)。

## Runtime 激活身份

`RuntimeActivationIdentityBuilder` 接受 `InstalledRuntimeVersion`、`VerifiedCatalog`、当前
`CompatibilityRequest` 和非零 generation。它内部调用 `CompatibilitySelector.select`，因此不会
绕过标准/实验模式、显式 profile 选择、撤销或实验确认门槛；随后再核对 selected runtime 与
install record 的 runtime definition、artifact 和 install identity。

`activationID` 使用 `MGBCURRENT` domain 与 schema version 1，绑定 generation、catalog
revision/payload SHA-256/channel、selection mode、acknowledgement 分支、profile ID/revision/
definition/disclosure、game ID/version/build fingerprint、runtime ID/definition、install ID、
artifact、plan policy/SHA-256、tree seal version/SHA-256 和 compatibility tier。

标准 profile 写入 acknowledgement tag `0` 且不带摘要；实验 profile 写入 tag `1`，并携带由
精确 `ProfileAcknowledgement` 生成的 `MGBACK` v1 SHA-256。后者再次绑定 catalog revision、原始
payload SHA-256、profile ID/revision 和 disclosure digest。

`RuntimeActivationRecord` 只支持 `Encodable`。builder 本身不读取版本目录，也不保证 generation
相对旧记录单调；store 的首次事务固定 generation 1，替换事务则以 trusted expected record
checked `+1`。详见 [RUNTIME_ACTIVATION.md](RUNTIME_ACTIVATION.md)。

## 首次 current 事务

`activateFirst` 先构建 generation `1` activation，再要求版本位于确定性的
`versions/<prefix>/<installID>`。它取得与 install 共用的 `.publish.lock`，用 expected install
record 对磁盘版本执行 receipt、inventory 和逐文件重哈希完整复验。

`current.json` 必须严格得到 `ENOENT`；普通文件、symlink、目录或其他已有类型都不读取、不覆盖。
store 创建唯一 `.current.<uuid>.tmp`，以 `0600` 写入 sorted-key bytes，`fsync` 后逐字节读回并
固定 device/inode。pre-commit hook 返回后，再次检查 current 缺失、installed、temp 和 root，
然后检查取消并以同目录 `RENAME_EXCL` 提交。

rename 成功后 current 已可见；store `fsync(root)` 并复验最终字节/inode/root。提交前错误或取消
清理 temp；提交后迟到取消不回滚。同步失败返回 `currentVisible` 且 durability 未确认，同步后的
错误返回 durable 状态。

`activateReplacingCurrent` 接受调用方持有的、仅可编码的 expected record 作为 CAS capability。
在同一锁内，磁盘 current 必须先后两次与 expected bytes/inode 精确一致；新 installed version
和新 `0600` temp 也在 hook 后二次复验。新 record generation 必须是 expected generation 的
checked `+1`。

替换只调用 `renameatx_np(..., RENAME_SWAP)`，系统不支持时直接失败，不退化为覆盖 rename。
swap 后先 `fsync(root)`，再验证新 current 和落到 temp 名下的旧 current 各自 bytes/inode；旧
temp 仅在身份仍匹配时 unlink，之后第二次 `fsync(root)` 并终检新 current/root。stale expected、
同大小篡改或异常 current 类型均失败关闭。

swap 前取消清理新 temp、保留旧 current；swap 后绝不自动回换，后续错误以 `currentVisible` 和
durability 状态报告。`rollbackCurrent` 仅把目标旧 installed/profile、调用方提供的最新可信
catalog/request 和 trusted expected 交给同一 CAS；selector 与 installed full verify 都重新执行，
generation checked `+1`。A→B→A 生成 1→2→3 和新的 activation ID；stale expected 仍拒绝。
更多回滚故障测试与面向用户流程仍属后续。

内部 `RuntimeRecordDecoder` 只通过 untrusted `Decodable` DTO 接触 JSON：install/activation 分别限制
128 MiB/64 KiB，解码前限制 depth 64。install 重验 path/default limits/NFC case-fold、tree seal 和
install ID；activation 重验 ack/tier 与 activation ID。最终 sorted-key 重编码必须逐字节等于输入，
因此 unknown/duplicate/whitespace 均拒绝。结果只证明自洽，不替代 selector、install 或 launch。

`reopenInstalled` 只接收小写 install ID 与 `VerifiedCatalog`，从 store root 确定性派生路径。在
`.publish.lock` 下以 dirfd/O_NOFOLLOW 打开目标，限长 128 MiB 读取 receipt，并用内部 canonical
decoder 重建 record。catalog 必须恰有一个同 ID、managed、未 blocked/撤销且 definition/artifact
一致的 runtime；随后完整重哈希 payload，终检 target/root identity，返回 `reopenedExisting`。
它不是同 uid 篡改的密码学来源证明；启动仍需最新 catalog/request 的 selector。

`resolveCurrent` 在同一 `.publish.lock` 下限长 64 KiB 读取 canonical current，先 locked reopen
installed，再以调用方提供的最新 `VerifiedCatalog`/request 重新运行 selector 和同 generation
activation builder；重建 record 必须与 current 精确相等。随后第二次 locked reopen installed，
终检 current bytes/inode 与 root，返回包含 current/installed/decision 的 snapshot。missing、非法
record 与未授权分别失败。锁在返回时释放，因此启动仍须紧邻使用前再次复验 selected runtime。

## 性能验证

每次运行时变更至少比较：平均帧率、1% Low、帧时间、统一内存峰值、功耗、温度、首次与二次启动、画面正确性和持续运行稳定性。
