# 国服只读 ManifestAdapter 契约

## 目的与证据边界

本契约定义首期《原神》官方国服 ManifestAdapter。它只读取版本和资源清单元数据，
为后续下载器提供稳定领域模型，不执行下载、安装、更新或修复。

协议线索只来自 [UPSTREAM_STRATEGY.md](UPSTREAM_STRATEGY.md) 固定的 YAAGL
`0.3.18` / `ca78abc29c2fc236261d088c6907d28cab6e9476` 快照。该证据确认了
`getGameBranches -> getBuild/getPatchBuild -> zstd protobuf -> chunk/ldiff`
分层，但同时确认：YAAGL 警告 CN/BB 未测试，国服更新分支在请求 build 前直接
`assert TODO`。因此这些线索不是当前国服接口规范或可用性证明。

在取得并审核当前官方国服请求/响应样本前：

- 不在代码、fixture 或本文中猜测 CN host、URL、方法、参数名、game/launcher ID、
  header、鉴权方式或错误码。
- live transport 必须返回 `missingEndpointEvidence`；只允许离线 fixture 回放。
- 后续采样形成版本化 `ObservedEndpointProfile` 后，才能启用对应 live 请求。
- profile 只表示“与样本一致”，不表示接口由厂商公开、签名或承诺稳定。

## 本阶段范围

当前实现包含公开 domain、semantic validators、纯内存 replay、canonical descriptor schema v3、
manifest reference digest 和 Data-only byte-integrity bundle。descriptor 声明外部 bytes/hash/reference，
bundle 核对 actual bytes，internal materializer 再通过显式 decoder 重建 response semantics 并签发
Registry capability。当前 concrete decoder 仅存在于 Tests，不访问文件系统；live evidence gate 仍
失败关闭。

另有独立 A0 `ManifestSamplingCore`/`bridge-manifest-sample`，只用于 branch response 的结构发现。它不
属于 `BridgeCore`、不构造 `ManifestInspection`、不解码 branch semantic credential，也不改变
`EvidenceGatedManifestAdapter` 的失败关闭行为。A0 实现批当时仅运行 mock `URLProtocol`；随后两次受控
A1 分别在旧 metadata gate、在新 policy 安全 receipt 后停止，仍未生成 semantic/profile capability。

允许：

- 查询官方国服当前正式版本与预下载是否存在。
- 获取 `getBuild` / `getPatchBuild` 元数据和其指向的压缩 manifest。
- zstd 解压并解析 chunk / ldiff protobuf，计算清单派生大小和本地证据摘要。
- 使用私有缓存或脱敏 fixture 回放相同结果。

禁止：

- production adapter 或批量请求 chunk、ldiff 补丁或游戏文件 payload。唯一例外是独立双门的最小单 chunk 验证交易，它不进 Registry、不解包安装且在第一个 payload 后硬停止。
- 读取、创建或修改游戏目录、`config.ini`、Wine prefix、运行时或系统设置。
- 执行安装、更新、预下载、修复、删除、补丁应用、启动或登录。
- 把版本查询成功写成游戏可安装、可更新或可运行。
- 支持 Bilibili 服、国际服、其他游戏，或接受调用方传入任意 base URL。

## 公开领域契约

建议首个 Swift 实现只暴露一个入口：

```swift
public protocol ManifestAdapter: Sendable {
  func inspect(_ request: ManifestInspectionRequest) async throws -> ManifestInspection
}
```

输入模型：

```swift
public struct ManifestInspectionRequest: Equatable, Sendable {
  public let release: GameRelease        // 首期只能是 .genshinOfficialCN
  public let intent: ManifestIntent
  public let categories: Set<ResourceCategory>
  public let cachePolicy: ManifestCachePolicy
}

public enum ManifestIntent: Equatable, Sendable {
  case full
  case update(from: GameVersion)
  case preDownload(from: GameVersion?)
}
```

实际首批 cache policy 为 `.fixtureOnly(id)`、`.freshCache(maxAgeSeconds)` 和
`.reloadIgnoringCache`；fixture ID 只允许长度不超过 128 的 ASCII 字母数字、点、下划线和连字符，
fresh cache age 必须大于零。categories 目前必须精确等于 `[.game]`。

- `GameVersion` 是有长度上限的非空 opaque string，不是 SemVer。
- `categories` 首期至少含 `.game`；语音类别只有样本确认准确 ID 后才能开放。
- request 不含 URL、密码、package ID、任意 header 或本地游戏路径。
- `.update` 必须提供来源版本；`.preDownload(nil)` 只查询预下载完整清单，提供来源版本
  时才查询其直接增量信息。

安全的公开输出：

```swift
public struct ManifestInspection: Equatable, Sendable {
  public let release: GameRelease
  public let intent: ManifestIntent
  public let availability: ManifestAvailability
  public let branches: BranchSummary
  public let target: BuildManifest?
  public let selectedLdiff: LdiffSelection?
  public let origin: ManifestDataOrigin
  public let evidence: ManifestEvidence
  public let observations: [ManifestObservation]
}
```

- `BranchSummary` 只含正式版和预下载版的 opaque tag，不暴露 branch、package、password。
- `BuildManifest` 含目标 tag、按类别解析的 `ChunkManifest` 和大小统计。
- `LdiffSelection` 含来源/目标 tag，以及按类别从 wire ldiff 中筛出的选择摘要。
- `ManifestAvailability` 区分 `available`、`upToDate`、
  `preDownloadNotPublished`、`directLdiffUnavailable`；不静默改成另一种操作。
- `ManifestDataOrigin` 明确是 `live`、`freshCache` 或 `fixture(id)`，缓存结果不得伪装成 live。
- `ManifestEvidence` 记录 endpoint profile revision、观测时间、响应/manifest SHA-256 和
  schema baseline ID；这些是本地证据，不是官方签名。

public `ChunkManifest` / `LdiffSelectionSummary` 只有 count/byte summary，不暴露文件、chunk、patch object、
MD5、URL 或路径等 leaf 数据。所有 output 的 memberwise initializer 保持 internal，由
`ManifestInspectionFactory` 统一构造；公开调用方只能创建 `GameVersion`、fixture ID 和 inspection
request。`GameVersion` 是 1–128 UTF-8 bytes、NFC、无首尾空白/控制字符的 opaque 值，不实现
SemVer 排序。

## 首批 coherence factory

`ManifestInspectionFactory` 对 summary 和完整 inspection 执行以下不变量：

- chunk summary 要求 referenced bytes 不小于 unique bytes；普通文件数和 target installed bytes
  非零，reference/unique count 与对象字节是否为零保持一致。
- ldiff summary 精确包含 `manifestFileRecordCount`、`selectedPatchFileCount`、
  `fileRecordsWithoutSelectedPatchCount`、`selectedDeletionCount`、`uniquePatchObjectCount`、
  `selectedPatchObjectBytes` 六字段；前两类 file count 相加必须等于 manifest record count，selected
  object count/bytes 与 selected file count 必须一致，总 records + deletions 不超过 100,000。
- build/ldiff categories 必须精确为 `.game`；ldiff source 与 target 不得相同。empty selection 六字段
  全零是合法值，不等于 up-to-date，也不等于整体更新下载 0 bytes。
- observation code 必须是有界安全 ASCII，按 code 排序且唯一；公开 observation 不含 message/value。
- evidence profile revision 非零、artifact kind 唯一、每项 byte size 非零、SHA-256 规范化为小写；
  schema baseline 是有界安全 ASCII，若有 expiresAt 则必须晚于 observedAt。

四种 availability 不会自动互换：

- `available` 必须有正确 slot 的 target；full 和 `preDownload(nil)` 不得有 selected ldiff，带来源
  版本的 update/pre-download 必须有精确 source/target `selectedLdiff`，即使 selection 为空。
- `upToDate` 必须有 target、无 selected ldiff，且请求 source 与 target 完全相等。
- `preDownloadNotPublished` 只能用于 pre-download，pre-download branch、target、selected ldiff 为空。
- `directLdiffUnavailable` 必须有 source 和 target、两者不等、selected ldiff 为空；其唯一当前语义是
  patch response 没有 ldiff descriptor，因此 evidence 只含 patch-response，不含 diff-manifest。

cache policy、origin 与 evidence 也精确绑定：fixture-only 只能返回相同 fixture ID 且必须包含
fixture descriptor；fresh-cache age 不能超过 max age，`observedAt + age` 必须有限且严格早于
expiresAt，并且不能带 fixture evidence；reload-ignoring-cache 只能对应 live origin。artifact kind
集合必须与 availability/target/selectedLdiff 精确一致，不能少报或混入额外来源。任何非 nil
selection 都必须同时有 patch-response 与 diff-manifest；direct-unavailable 只有 patch-response。

公开 output 字段已测试不含 URL、password、package、header、path、token、cookie、message、MD5、
object ID 或 branch ID 等敏感命名。

## Evidence gate 当前行为

`EvidenceGatedManifestAdapter` 没有 transport、cache 或 fixture dependency，也不会尝试网络请求：

- `.fixtureOnly(id)` 仍返回 `fixtureUnavailable(id)`：safe loader 已实现，但本 adapter 没有自动注入
  loader 或 trusted descriptor pin，也不存在 unpinned fallback。
- `.freshCache` 与 `.reloadIgnoringCache` 返回 `missingEndpointEvidence`，因为尚无已审核 endpoint
  profile；不会把空结果伪装成 cache/live inspection。

当前已实现 bounded zstd byte decompressor、allocation-before protobuf wire budget scanner 和固定
YAAGL baseline 的 structural mapper，但仍未实现 production endpoint JSON/branch-build-patch full
decoder、磁盘 cache、ObservedEndpointProfile 或 live endpoint。safe fixture file loader 已实现但不由
Evidence gate 自动注入。测试用
`SyntheticManifestReplayDecoder` 只证明 materializer orchestration/capability gate 和 fixture response
自洽，不能作为 production default。

## A0 branch-only discovery sampler

`bridge-manifest-sample plan` 是完全离线命令，只输出固定 profile 的 safe origin/path、request identity、
1 MiB cap、timeouts 和完整安全 policy SHA；不输出 query names/values、body 或 credential。真正的
`sample-branches-cn` 同时要求当次 policy SHA 与 exact
`MGB_MANIFEST_SAMPLE_NETWORK=ALLOW_BRANCH_CN_V1`，两道门均在 production URLSession configuration/
session 构造前检查。没有 arbitrary URL/profile/path/body/output/retry 参数。

transport 使用 ephemeral、无 HTTP cache/cookie/credential/additional headers、最低 TLS 1.2 与系统
server trust；只对 exact HTTPS host/443/首次 server-trust challenge 使用默认处理，其他 auth 全部取消。
它创建单个 GET data task，不做应用层 retry，拒绝 redirect、final URL 漂移、非 200、非 allowlisted
JSON Content-Type、非 identity encoding、畸形/不一致 Content-Length，以及超过 1 MiB 的 stream。
request 显式关闭 cookie handling，session 不发送/存储 cookie；response `Set-Cookie` 只忽略且不输出，
不作为拒绝项。content type/encoding/length 可组合报告无关联值诊断；`oversized` 只表示大小 cap。这里的
“单 task”不声称 CFNetwork/DNS/TLS 只有一个网络包。

raw body 只在 delegate 内存中分块累计并同步 SHA-256，所有失败都会清空；工具不提供显式文件写入。
严格 scanner 在 1 MiB 内验证 RFC 8259、UTF-8/escape/number、decoded duplicate key、depth/node/string/
128-byte number token limits，并要求 `retcode == 0`、`data` object 与 `game_branches` array。递归 value-free
shape digest 保留 object 内字段相关性；array 只绑定 sorted unique element shapes，不绑定顺序或重复同形
数量，实际 branch entry count 单独写入 receipt。unknown key 只以 key digest 进入 shape，scalar value/
length 不输出。receipt 还显式携带当前 plan policy SHA 与 shape policy version，不能把该 SHA 直接当作已授权
`ObservedEndpointProfile` baseline。

所有成功/失败/cancel/canary 测试均通过 mock/tripwire `URLProtocol`。第一次真实采样必须先在离线门完成
build/test，再直接运行已构建 binary；不能以 `swift run` 作为“只有 vendor GET”的网络证据，因为
SwiftPM 可能先解析依赖或写 `.build`。A0 实现批完成时尚未 live；旧 policy 的第一次受控 A1 通过
HTTP 200/exact final URL 后，以 `response-type-rejected` 在 metadata gate 取消；response delegate 在
允许 body 交付前取消，工具未解析/保存 body。新 policy 的第二次 A1 成功返回 receipt 后立即硬停止：
body SHA-256 `1f5d2f9a0feaa0890ec7db02bbc6f426376d5d228be4ae7c872df1eeedf54dbd`、906 bytes、
branch count 1、observedAt `1787126649`、request
`dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d`、policy
`4b78e4fb1fb711010a90799c145bc08d607f4ad53f4cb70d32438f5ee062cec3`、shape policy 1 / SHA-256
`a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633`。两次均未发起后续请求；未保存
raw body/query/branch/package ID/password/fixture。成功 receipt 只证明该次本地字节与 value-free shape，
不认证官方真实性，也没有形成 `ObservedEndpointProfile`。

A1b 的 safe shape report core 继续使用同一 strict parser，不创建通用 scalar AST。policy v1 只将
`retcode/data/game_branches/message/game/id/biz/main/pre_download/tag/branch/package_id/password`
作为可输出的 known schema key；其他 decoded key 立即替换为小写 SHA-256。scalar 只输出
`string/number/boolean/null` kind；object fields 按既有 key identity/child shape 排序，array 只输出
sorted unique element shapes。默认 report cap 为 4,096 nodes、256 unique array shapes、1,024 unknown
keys 和 256 KiB canonical bytes，任一超限均整体返回 `shape-report-limit`，不会输出部分树。
`plan-branches-shape-cn` / `sample-branches-shape-cn` 使用独立 `ALLOW_BRANCH_CN_SHAPE_V1` gate；plan
绑定 known-key allowlist、prior A1 shape/count、report/receipt caps 与 receipt-only 硬停止。一次受控
A1b live 返回 `matchesPriorShape=true` 后立即结束：body SHA/size 仍为 `1f5d…54dbd` / 906 bytes，
report SHA `bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25`、canonical report 2,178 bytes、
observedAt `1787129607`。安全树确认 root 为 `retcode:number/message:string/data:object`，唯一 branch 为
`game{id:string,biz:string}`、`main{tag,branch,password,package_id:string}`、`pre_download:null`，另有
8 个分布在 branch/main/nested array object 中、只以 key SHA-256 表示的附加字段。receipt 不含任何 scalar value；工具未产生 semantic
branch/getBuild capability，也未发后续请求。

本次 safe tree 对附加 key 的完整 shape 证据为：branch-level boolean
`f8e41a2808921ab7d62f7bfaeac050ace4692c3d9acb070de12d57ebf397d858`；main-level string
`4b5fca649bee6407593ea89121c7ce1dbe747fd6880630d12b38f48c229ce882`、string-array
`d11ab92d9dc587371e23399aeccf990dea2fa5125ec4229abca9914afb246000`、object-array
`a6216ea03e578f212dd604ec5d675c5274a86891bac4e87f80bea10ef511f533`；该 object-array 的 element 内含
三个 string keys `1303c06b0b014d0ce7b988ab173a13f31227d417058ff4bbe6f8c222b4ad913c`、
`4f0d62547aaf2c61a51170253e29edfd54b207b55fc2173bf72819e039ec9a24`、
`8570d988c20fcdbaaae3ea7c529915ea055688a7a588a807d99f5ccfb9fab1f6`，以及一个 string-array key
`d1a1c362651af80e00f3edf924ede8060c24213db5ca58086ae20b9beb820496`。这些 hash 只允许用于冻结/比对
schema，不可反向猜 key 名或据此读取 scalar value。

internal `StrictCNBranchSemanticDecoder` 以 observed semantic policy v1 固定 request identity、A1 shape
policy/SHA/count 与 A1b report policy/SHA/size。输入 `Data` 先 detached-copy，并再次通过 strict scanner
与 exact pins；只有之后 private `Decodable` DTO 才读取 `game.id/biz` 与 main
`tag/branch/package_id/password`。`game.id` 必须等于固定 request game ID；opaque values 必须非空、
无首尾空白/control，按 UTF-8 bytes 分别限制为 128/256 并受 2,048-byte 总 cap。unknown scalar
values 不映射，但其完整 key-hash/shape 已由 report pin 约束。成功 capability 的 domain-separated binding
覆盖 semantic policy、request/transport policy、body/shape/report SHA 与全部 slot raw values；capability/
slot/secret wrappers 均不可编码且全 surface 脱敏。production observed policy 只接受本次 A1b
pins；capability 不向 CLI 暴露，只由受门控的 getBuild 事务在内存中消费，也不保证 Swift
内存中的 secret 可可靠 zeroize。

getBuild response 的首层结构发现使用新增 root-data scanner mode：仍严格要求 root `retcode == 0` 和
`data` object，并复用 duplicate-aware RFC 8259、shape digest 与 bounded safe report，但不要求
`data.game_branches`。branches mode 的既有 SHA/receipt 不变。scanner 本身不持有 getBuild transport 或
URL；受门控的 getBuild 事务在 mock 和一次受控 live 中均消费该模式。

guarded main getBuild transaction 由独立 `plan-build-main-cn` / `sample-build-main-cn` 与
`ALLOW_BRANCH_BUILD_MAIN_CN_V1` gate 控制。plan policy `dd0ab612…4277d` 绑定 fresh branches semantic
pins、exact `api-takumi` origin/path、ordered query names、build request template SHA
`a44a5523…e306d`、1/8/9 MiB branch/build/total caps、root-data report policy 与
`buildReceiptOnlyNoManifestNoPayload`。事务先重新获取 branches 并在内存中签发 capability，再以 capability
内的 branch/package/password 构造一次 getBuild GET。receipt 刻意不输出 actual build URL、actual request
digest 或 capability binding，只记录 safe branch/build body/shape/report evidence 与 requestCount=2。任一
branch semantic 失败都在首请求后停止；build 成功也不继续 manifest/payload。一次受控 live 已按该门
恰好执行 branches+getBuild 两个 GET：build status 200、4,518 bytes、observedAt `1787132716`、body SHA
`c8bae16dc79ed3430b151972dd6c091cbc00df3441a175adcb92a707b16190a0`、shape SHA
`21e89e02cc735be6296f7ab41763875a8b7ff86db2e3fcefec32453e131db851`、report SHA
`ab0d7df71bfd1be62d73d9414184afb58a6495c78a6470a2300283ebb9ee778f`、canonical report 4,521 bytes。
receipt requestCount=2；未输出 actual build URL/request digest/credential，也未访问 manifest/payload。

该 safe tree 已确认 `data.tag:string`、`data.build_id:string` 与 `data.manifests:array`。manifest element 至少
含 `category_id`、`category_name`、`matching_field`、`manifest`、`manifest_download`、`chunk_download`
及其他 hashed-key objects。当前受控字典比对只将以下 key hash 还原为 schema 名：`manifests`
`c7af7c7a…0a59`、`build_id` `dd68ba69…4134`、`manifest` `05b3abf2…57f`、`manifest_download`
`1c6f404e…758c`、`chunk_download` `2975726d…e44a`、`url_prefix` `581a608e…b3e6`、
`compressed_size` `e64d741c…0681`、`uncompressed_size` `9e29f656…852a`、`checksum`
`96fa8f22…b40b`、`category_id` `4f0d6254…9a24`、`matching_field` `8570d988…b1f6`、
`category_name` `be6f7c55…d391`、`compression` `d18f849b…c16b`。其余 hash 继续保持 opaque；不得猜
URL 组合或直接请求 manifest。

internal `StrictMainBuildSemanticDecoder` 固定本次 build shape policy/SHA、report policy/SHA/size 与
`matching_field=game`。输入先 detached-copy，再通过 8 MiB root-data scanner exact pins，之后 private DTO
才读取 `data.tag/build_id/manifests`；build tag 必须等于 fresh branch capability，game category 必须唯一。
manifest id/checksum/compressed/uncompressed size 与 manifest_download password/url_prefix 分别经过非空、
首尾空白/control、UTF-8 byte/total caps 后进入 non-Encodable/redacted capability。binding 覆盖 branch
capability、transport/body/shape/report 与全部选中 raw values。该 decoder 目前仅由 synthetic policy/mock
tests 验证；production pins 不依赖保存的 raw build body。

`plan-manifest-origin-cn` / `sample-manifest-origin-cn` 与独立
`ALLOW_BRANCH_BUILD_ORIGIN_CN_V1` gate 把下一步限制为“安全披露 manifest origin”：事务只重新
执行 fresh branches + getBuild 两个 GET，然后在内存中从 actual build capability 读取
`manifest_download.url_prefix`。它仅接受 HTTPS、lowercase ASCII DNS、非 IP、无 port/userinfo/
query/fragment，以及最多 32 个 component、每个最多 128 UTF-8 bytes、percent-encoded path 最多
2,048 bytes 的 no-dot-segment 绝对路径。v1 policy `fc596584…79e8` 的首次受控 live 在两个
GET 后以无值 `semantic-value-rejected` 停止，没有 receipt 或第三个请求。v2 不放宽
验证规则，只把 build semantic 失败分为 header/selection/manifest-reference/download-reference/
value-budget 五个无值 safe code；第二次受控 live 以 `build-download-reference-rejected` 停止，
同样没有 receipt/第三请求。v3 采用单独 `StrictMainBuildOriginDecoder`：它仍要求 observed
shape/report exact、build tag 绑定 fresh branch 且唯一 `matching_field=game`，但只解码 bounded
url_prefix，不消费无关的 password/checksum/size。返回值只是 non-Encodable/redacted
origin reference，不是完整 build capability；v3 policy SHA 为
`626daa27d87bc10a41afce9e833249d7d662157675b4cf3a7772233704e62dde`。

origin receipt 只保留 branch/build body/shape/report SHA、safe `https://host`、path component count、
percent-encoded path SHA-256、time 和 `requestCount=2`；不输出 path、manifest ID/checksum/password、
actual build URL/request digest 或 capability binding。一次受控 v3 live 以 policy
`626daa27…dde` 完成两个 GET，返回 safe origin `https://autopatchcn.yuanshen.com`、path
component count `5`、path SHA-256
`ea1f952ad03a4218f39f3c89567aac56d03b1bd88252f116f1781249cd7b0485`、observedAt
`1787135597` 和 `requestCount=2`。branch/build body/shape/report SHA 均与上一次成功 getBuild
receipt 相同；输出后立即停止，没有 manifest 或 payload 请求。safe origin
也不是官方真实性或该 host 已获下载授权的证明。

manifest response metadata 另由 `plan-manifest-metadata-cn` / `sample-manifest-metadata-cn` 与
`ALLOW_BRANCH_BUILD_MANIFEST_METADATA_CN_V1` gate 控制。plan policy
`32809f02f6843c6f8f9ea931f18c25d1bb68f3f410b286b46b79405eb64aff8b` 绑定上述 exact
origin/path pin、manifest ID 为 1...256 bytes ASCII unreserved single component、request template SHA
`65f8d3ea14e740776deed2a458bf83b1a172e3d5b5cf11bf5879cb7261d362f5`、
`Accept: application/octet-stream`、identity encoding、64 MiB declared-length 分类线与
`metadataReceiptOnlyNoBodyNoPayload` 停止语义。

`StrictMainManifestRequestDecoder` 继续要求 observed build shape/report、fresh branch tag 和唯一
game selection，并将 manifest ID/url_prefix 与 exact origin pin 绑定为 non-Encodable/redacted
request reference。metadata transport 只在第三个 GET 的 exact final URL/200 后分类
Content-Type、Content-Encoding 与 Content-Length；unknown type/encoding 只输出 normalized SHA，然后在
body 交付前取消。receipt 不含 manifest ID、完整 request path/header/body，也不产生 zstd/protobuf
capability。5 项 mock/tripwire 测试通过后，一次受控 live 执行三个 GET；第三响应
status `200`、Content-Type `application/octet-stream`、Content-Encoding absent、Content-Length
`8,521,303`、request path SHA-256
`ce154736f9d4cd8d3355c17101f99526ccd3a67772cf04defdd362afbf6cfea8`、observedAt
`1787136897`、`requestCount=3` 且 `responseBodyAccepted=false`。branch/build evidence 仍与前次一致；
未接受、保存、hash 或解压 manifest body。

bounded manifest body 读取不放宽上述 metadata gate，而是新的
`plan-manifest-body-cn` / `sample-manifest-body-cn` 和
`ALLOW_BRANCH_BUILD_MANIFEST_BODY_CN_V1`。policy
`e253f675047143eb73dd4a09de22fae280a451872b3e5ed875f9ef4881677dc3` 要求 fresh build
canonical decimal `compressed_size` 精确为 `8,521,303`、request path SHA 仍为 `ce154736…fea8`、
response 为 exact `application/octet-stream`、absent/identity encoding 且 Content-Length 与 build 声明完全相等。
Data 按 transport chunks 做 checked byte count + 同步 SHA-256，short/extra 与头部不符都失败关闭；
receipt 只输出 body SHA/size、media/encoding 分类和 zstd standard magic/其他 prefix SHA 分类。
成功后 Data 不保留、不落盘、不解压，也不请求 chunk/payload。5 项 mock 通过后，
一次受控 live 返回 status `200`、Content-Type `application/octet-stream`、encoding absent、
declared/actual size `8,521,303`、body SHA-256
`ca70fab422a2324aaece888534b9f013d4daf6e2c4430c6edf4da30a3e204c82`、
`frameKind=zstdStandardFrame`、observedAt `1787137904` 和 `requestCount=3`。branch/build/origin/request path
evidence 与前次一致；receipt 后 Data 已丢弃，未解压或请求 payload。

live structural inspection 不将 `ManifestSamplingCore` 与 `BridgeCore` 直接耦合。新的
`plan-manifest-structure-cn` / `sample-manifest-structure-cn` 只在 `bridge-manifest-sample`
executable 层注入 `ManifestBodyStructurallyInspecting`；采样核心仍无 `BridgeCore` 依赖。v1 policy
`1782e2bb3924c6360c0515603cee6fb7d9067b65b6ce4e486aace2fd914a6af3` 绑定 compressed
body SHA `ca70fab4…04c82`、profile revision `1`、`genshinOfficialCN/game`、manifest ID 组合规则与
`yaagl-ca78abc-sophon-protobuf-structural-v1` baseline。

只在 compressed SHA/size/path/fresh build 全部再次匹配后，delegate 才为该调用保留一份 detached
owned Data。CLI 内的 `ManifestLiveChunkInspector` 先再 hash 一次，再经现有 bounded
`ManifestZstdDecompressor`、`ManifestProtobufWireBudgetScanner`、generated decode/recursive unknown reject、
`ManifestProtobufStructuralMapper` 和 `ChunkManifestValidator`。receipt 只保留 compressed/decompressed SHA/size、
wire counts 和 public chunk summary 聚合值；不输出 manifest ID、path、object、hash leaf 或 raw Data，也不签发
`ManifestInspection`/Registry capability。首次 v1 live 在解压前以无值 `content-type-rejected`
停止，v2 确认三个 transport stage 通过，但以 `manifest-decompression-rejected` 停止；
两次都没有 structural receipt 或 payload 请求。v3 仅将 zstd 拒绝细分为 frame/dictionary/
window/output/ratio/truncated/trailing/decoder 无值 safe code，不改变 window/output/ratio 等任何
limit；policy 为 `820ad945c5ce247c99f39d03169d275509aac49a5b8199446624c667997914d5`。
structure-specific sampling 4 项与 BridgeCore façade 2 项测试通过。一次受控 v3 live 返回
`manifest-zstd-window-rejected`；它只证明当前 frame 需要大于 8 MiB 的 window，尚未证明
16 MiB 足够，也未进入 wire/semantic 验证。v4 仅为 live inspector 增加
`ManifestZstdDecompressionLimits.observedCNChunkManifest` (`windowLog=24`)；通用 initializer/default
仍不允许超过 log 23，C bridge 只接受到 log 24，测试锁定 window-24 成功、window-25 拒绝。
v4 policy 为 `0fd87d77b4e30bcb6b9157fd02f5cc95084eb316f8a10deea627e5cfb23aea2e`。
v4 live 在 manifest response 门以 `structure-manifest-response-rejected` 停止。v5 只将该 stage
细分为 identity/status/content-type/encoding/length/oversized 无值 safe code，并保持 exact
`application/octet-stream`、absent/identity encoding 和 exact Content-Length；policy 为
`0bfe69619d500fa6078a1372b98bf645726f75cf93269b9d731c1a8aae1791c4`。
v5 live 返回 `structure-manifest-content-type-rejected`，但 metadata-only gate 紧随观测到的
media type 仍为 `applicationOctetStream`，证明 CDN 当次响应含 `;` parameter。v6 仅对
structure gate 允许 0...4 个 bounded printable-ASCII parameter；不读取或解释 parameter value，不改变
status/final URL/encoding/length/body SHA，也不改变旧 body gate。policy 为
`b0a99e73e2cbc49f211f7eb23a3068edccf04b5586a1008c3a47f9e5c8a04fc9`。
v6 live 已通过 response 与 bounded zstd/log24，但 wire scanner 返回无值
`manifest-wire-rejected`，因此 generated SwiftProtobuf/mapper 仍未执行。v7 仅将该失败分为
`manifest-wire-schema-drift` / `manifest-wire-invalid` / `manifest-wire-resource-limit`，不改变
schema 或 budgets；policy 为
`28ef671cdbaa67bb91242d8d7699e5158c031ce0326f04d6e2498355307d8332`。
v7 live 返回 `manifest-wire-schema-drift`。v8 仅为该失败路径增加
`messageKind/fieldNumber/wireType` 定位；scanner 正常 API 仍对该字段抛 `schemaDrift`，
diagnostic 不保留或输出 field value/length/body offset。policy 为
`70f8ab8689c1af6c2a1ba6319c9f16632c81149637c27f9ce57101d322db134b`。
v8 live 返回 `manifest-wire-schema-drift-chunkInfo-f7-w2`。YAAGL current main 与当前审核的
Hi3Helper Sophon proto 都没有 field 7，因此 v9 不将它加入 generated schema。diagnostic-only scanner
只容忍该一个 field 以统计 occurrence count、min/max length 和 byte class，任何其他 drift 仍失败；
不输出 field value/hash/offset。policy 为
`9acae25d3980ee16e67ae6cf2bbbe773c7706a7129da641b80ba34d87b5ee701`。
v9 live 返回 field 7 occurrence `107,480`、min/max length `32/32`、class `lowerHex`，且 diagnostic
容忍后没有其他 drift。v10 将该观测锁为独立
`mgb-observed-cn-sophon-protobuf-structural-v2` baseline：本地 proto 增加 `string opaque_hash = 7`，
v2 mapper 要求每个 chunk 的值精确为 32-byte lowercase hex，v1 mapper 则要求缺失。
`SemanticChunkObject.wireField7OpaqueHash` 参与相同 object ID 的 metadata conflict 检查，但不把它命名
为 MD5/XXHash、不验证 chunk bytes。profile revision 升为 `2`，v10 policy 为
`7ede9ed410cda836ac9ec2a43e2a5c33e7cf82e3d071bb8885dbf3ccccc5d382`。
v10 live 以 requestCount `3` 通过全部边界：compressed SHA/size
`ca70fab422a2324aaece888534b9f013d4daf6e2c4430c6edf4da30a3e204c82` / `8,521,303`，
decompressed SHA/size
`e5b3a018cf7db0901bdf4d85c3aabfec10612e0d5d9da77c9a9505c05eb96fea` / `15,913,977`；
wire policy `1`、2,673 files、107,480 chunks、110,154 nodes、12,410,255 string bytes。validated chunk
summary 为 0 directories、107,325 unique objects、124,827,264,431 target installed bytes、
121,314,849,412 referenced compressed bytes、121,185,381,917 unique object bytes。observedAt
`1787211698`。receipt 不含任何 path/chunk ID/MD5/xxhash/field7 value，两份 Data 在返回后释放；
未构造 `ManifestInspection`、未进 Registry、未请求 chunk payload。

## Canonical descriptor-only decoder

internal `ManifestReplayDescriptorDecoder` 读取 fixture descriptor 的 summary、evidence metadata 和
external artifact binding 声明，输出 `ValidatedReplayDescriptor`；该类型明确不是 registry fixture，
也不能直接 replay。

输入边界：

- 非空且最多 64 KiB。
- 在 JSON decode 前扫描结构，最大深度 16；字符串内括号不计深度。
- 只用 private `Codable` DTO 接触不可信 JSON。
- 重新以 `JSONEncoder(sortedKeys, withoutEscapingSlashes)` 编码后必须与原 bytes 完全相等。
- 因此拒绝 leading/trailing whitespace、unknown/duplicate key、显式 null 与字段省略差异、key
  重排和 escaped slash；binding migration 后 schema version 固定为 3，v2/v1 直接拒绝。

decoder 只接受 release `genshinOfficialCN` 和 categories `["game"]`，fixture ID/request/version/
summary/evidence metadata/observations 都重新走现有 validated initializer/factory。observations 最多
256 个；profile revision 非零；Unix 时间在 0…9999-12-31 范围，expiresAt 若存在必须晚于
observedAt。

target 与 selected ldiff 的版本身份不从 descriptor summary 自由输入：full/update target 由 official
slot 派生，pre-download target 由 pre-download slot 派生；ldiff source 由 intent source 派生，
target 仍来自 slot。v3 保留 `selectedLdiff` 六字段 DTO；v2/v1 或旧 `patch` 字段不做兼容转换。

`expectedEvidenceArtifactKinds` 由 availability/target/selectedLdiff 形状确定性派生，顺序固定为
branch、build、patch、chunk、diff，且不含 fixture descriptor。非 nil selection 派生 patch + diff；
`directLdiffUnavailable` 只派生 patch response，表示 response 无 descriptor。

schema v3 的 `externalArtifactBindings` 必须与该顺序和数量完全相同。每项都声明 exact kind、64 位
小写 SHA-256 和非零 byte size；size 必须满足 branch/build/patch/chunk/diff `1/8/8/64/64 MiB`
per-kind cap，descriptor 加全部 external artifact 还必须满足 128 MiB total cap。response binding
必须省略 `manifestReferenceSHA256`，chunk/diff binding 则必须提供规范小写摘要；显式 null 不能替代
字段省略。

`ManifestReferenceDigest` v1 使用独立 `MGBMANIFESTREF` domain，按长度 framing 绑定 release、category、
受限 opaque manifest ID、profile revision、chunk/ldiff kind 和 `zstdProtobuf` compression。descriptor
只保存摘要，不保存 manifest ID。它是调用方字段的确定性本地 commitment，不是官方签名或 endpoint
来源证明。

decoder 对包含全部 binding 声明的 canonical descriptor bytes 计算
`fixtureDescriptorSHA256`/`fixtureDescriptorByteSize`，因此任一 claimed hash、size 或 reference 变化
都会改变 descriptor self-hash；独立 known vector 当前为 471 bytes。validated descriptor 仍不含
external artifact Data，不能进入 `ManifestReplayRegistry`。下一层 bundle 只能核对 actual Data 与
这些声明，仍未把 endpoint bytes 解析成与 summary/reference 一致的 semantic 候选。

## Data-only artifact byte-integrity bundle

internal `ManifestReplayArtifactBundleValidator` 接收 validated descriptor 与调用方提供的
`ManifestReplayArtifactData`。它只证明 actual owned bytes 与 descriptor 声明一致，不证明 semantic
derivation，也不授权 registry/replay。

默认上限按 kind 固定：

- branch response：1 MiB。
- build response：8 MiB。
- patch response：8 MiB。
- chunk manifest：64 MiB。
- diff manifest：64 MiB。
- descriptor + 全部 external artifacts 总和：128 MiB。

调用方可收紧但不能放宽默认值。validator 在复制或哈希前做完整 preflight：descriptor size 有效；
binding kind 顺序必须重新等于 factory 派生结果且唯一、不含 fixture descriptor；输入数量和 kind
集合必须 exact；拒绝 missing/extra/duplicate/fixture-descriptor/empty。actual byte size 必须等于
binding claim，每项和总量使用 checked arithmetic 并同时满足声明时默认 cap 与调用方收紧后的 cap；
失败后不会返回部分 bundle。

preflight 通过后，每项按 descriptor binding 顺序处理。validator 每次取最多 64 KiB `ownedChunk`，
同一 chunk 同时 append 到独立 snapshot 并送入 SHA-256，避免“复制一份、哈希另一份”的竞态；最终
actual SHA-256 必须与 binding claim 相同。返回后修改原 mutable backing storage 不会改变 snapshot
或 digest；跨 64 KiB 边界摘要已与 CryptoKit one-shot 结果验证一致。

每个 validated external artifact 保存 actual owned Data/SHA-256/byte size，并携带其 binding 中的
可选 manifest reference；response 为 nil，chunk/diff 为必填。factory evidence 仍只公开
`{kind, sha256, byteSize}`，顺序严格等于 descriptor bindings。descriptor 自身 evidence 使用 decoder
对 canonical raw bytes 计算的 SHA-256/size，并且始终最后追加。完整 `ManifestEvidence` 由 factory
构造，profile revision、时间、expiry 和 schema baseline 来自 descriptor metadata；total byte size
包含 descriptor 与 external artifacts。

输入、validated snapshot 和 bundle 都不是 `Decodable`，其 `description`、`debugDescription` 与
Mirror 仅显示 `<redacted>`，不会泄漏 canary bytes。same-size 内容变化若不匹配 claimed SHA-256 会
失败关闭，不能只生成另一份 bundle；修改 claim 又会改变 descriptor self-hash。

这里有三个明确的非认证边界：`ManifestReferenceDigest` 只承诺调用方提供的 reference 字段，canonical
descriptor 只承诺自身声明，byte bundle 只证明 actual Data 与声明相同。三者都不认证数据来自官方
endpoint。相同 manifest bytes 仍可伴随不同的 reference claim；semantic materializer 因此要求显式
decoder 从 actual build/patch response 产出 reference digest，并与 chunk/diff binding 精确比较。该
decoder 是受信 internal dependency；当前 production 尚无实现。materialized capability 仍只承诺
fixture response 的 semantic/version/reference 自洽，且尚未绑定 branch response 选出的 credential
到随后 build request/response 的 request 链。

重要分配边界：此 API 接收的是已经预分配的 Foundation `Data`。per-kind/total cap 只能阻止后续
snapshot/hash 工作，不能挽回调用方此前的大内存分配。下一节的 safe file loader 已在 artifact Data
分配前用 fd/stat 完成 exact-kind、per-kind 与 total preflight；直接调用本 validator 仍不具备该边界。

byte-only bundle 本身仍不能构造 `MaterializedManifestReplayFixture`、注册 Registry 或执行 replay。
chunk/diff artifact 可继续经过 bounded zstd、wire scanner、fixed-baseline structural mapper 和
validators；production endpoint/full decoder 与 `ObservedEndpointProfile` 尚未实现。

## Safe flat fixture file loader

internal `ManifestReplayFixtureFileLoader` 没有 unpinned API。`load(id:expectedDescriptorSHA256:)` 强制要求
调用方同时提供 validated fixture ID 与预先信任的 descriptor SHA-256；如果 pin 从同一个不可信目录
临时读取，就没有增加信任。pin 只绑定精确 descriptor bytes，不是官方签名或服务端来源证明。

flat layout v1 不读取任意文件名，只允许：

- `fixture.json`。
- `branch-response.redacted.json`。
- `build-response.redacted.json`。
- `patch-response.redacted.json`。
- `chunk-manifest.pb.zst`。
- `ldiff-manifest.pb.zst`。

descriptor 的 external binding shape 决定其中哪些文件必须存在；inventory 必须精确且最多 6 项，
missing/extra/duplicate/其他名称均拒绝。descriptor 先限长 64 KiB 读取并匹配 trusted pin，再走 canonical
schema v3 decoder；decoded self SHA/size 与 requested fixture ID 仍须精确相等。

root URL 必须是无 `.`/`..`/空 component 的绝对 file path，最多 64 components。loader 从 `/` 开始以
`fstatat(..., AT_SYMLINK_NOFOLLOW)` 和 `openat(..., O_DIRECTORY|O_NOFOLLOW)` 逐级取得 dirfd，拒绝 symlink
ancestor。最终 root、fixture 与所有文件必须由 euid 拥有；fixture/files 与 root 同 device。directory
要求 owner rwx、无 group/world write、setuid/setgid/sticky；file 要求 regular、`nlink == 1`、owner
readable、无 execute/group-world write/special bits。已验证 canonical `0755/0644` 和 private
`0700/0600` 两组模式。

读取 descriptor 后先验证 exact inventory，并为全部 expected artifact 打开 FD、核对 declared size、
per-kind cap 与 descriptor+artifacts 128 MiB total，全部通过后才为任何 artifact 分配 `Data`。每个文件
以 64 KiB `pread` 填入 owned buffer，同一 chunk 同步送入 SHA-256；拒绝 short read 和 expected size
后的 extra byte。读完后同时复验 opened FD 与 path 的 device/inode、mode/size、ctime/mtime，再匹配
descriptor SHA claim。

全部 raw bytes 随后仍进入 `ManifestReplayArtifactBundleValidator`，确保 descriptor bindings、actual
owned snapshots 和 evidence 一致；返回前再次验证 flat inventory、fixture dir identity 和通过原路径
重新打开的 root identity。loader 全程 read-only，不创建、修改、删除或联网；取消会关闭 preflight/
active FDs，loader/hooks/errors 默认打印脱敏，并已验证并发 snapshot 不受调用后文件修改影响。

成功只返回 `ValidatedReplayArtifactBundle`。它不做 zstd decompress、wire scan/map、materialize、Registry
或 network/live request。POSIX mode 规则未审计 macOS ACL，同 uid 对手仍可竞争；当前 loader Data 与
BundleValidator 二次 owned snapshot 还会形成 peak memory，这些都属于后续加固边界。

## Bounded zstd decompression capability

SwiftPM 精确固定官方 `facebook/zstd` `1.5.7`，resolved revision 为
`f8745da6ff1ad1e7bab384bd1f9d742439278e99`。`BridgeCore` 不直接依赖或 import upstream module，
只经过窄 `CZstdBridge`，该 bridge 再依赖 upstream `libzstd` product；production 自有 header 与调用点
只有 frame probe、streaming decode 和 destroy。MacGameBridge 自有 compression、dictionary training
与高级 frame 构造 helper 只编入 `CZstdTestSupport` 测试 target；单一 upstream product 仍可能包含完整
compression symbols。BSD license 与第三方 notice 已离线保存。

`ManifestZstdDecompressor` 只接受已经通过 bundle validator 的 `.chunkManifest` 或 `.diffManifest`，
要求调用方提供的 `ManifestReferenceDigest` 与 artifact identity 中的 reference 精确相等。输入必须是
标准 zstd magic 开头的单一 frame；skippable/wrong magic、非零 dictionary ID、trailing bytes 和
concatenated frame 均失败。即使 frame 不声明 dictionary ID，实际需要 raw dictionary 也会在 decode
阶段失败，不能绕过 no-dictionary policy。

默认 limits 为：

- `maximumWindowLog = 23`，即最大 8 MiB window；调用方只能收紧到 10...23。
- chunk/diff decompressed output 各最多 256 MiB。
- 动态 ratio 上限为 `1 MiB + 128 × actual compressed bytes consumed`，按每个 streaming step 的真实
  consumed count 计算，而不是用完整输入声明值预支额度。

known frame content size 在 decode 前先与 kind output cap 比较，完成后还必须精确等于 actual output；
unknown content size 不预分配整个结果，仍在 64 KiB input/128 KiB output chunks 中流式计数。每次输出
chunk 同时 append 到 owned `Data` 并更新 SHA-256，最终 capability 绑定 compressed artifact identity、
owned decompressed bytes、output SHA-256 和 byte size。checksum corruption、truncation、无进展、window/
output/ratio 越界都失败关闭。

入口、每个 streaming step 和返回前检查 cancellation；capability 不实现 `Decodable`，其 description、
debug 和 Mirror 固定脱敏，并已验证并发确定性。默认 limit 只是没有真实国服样本时的 provisional
保守基线；未来只能在审核样本并版本化 endpoint profile 后校准，不能因某个 frame 失败而静默放宽。

该 capability 只证明 bounded decompressed bytes 与已验证 compressed artifact 的关联，不解析 generated
protobuf、不产生 semantic candidate，也不能进入 `ManifestReplayRegistry`。后续 wire scanner、generated
decode、recursive unknown check 与 fixed-baseline structural mapper 已实现；尚未完成的是
profile-authorized endpoint/full decoder、国服实际字段语义确认、文件系统 loader、cache/live endpoint。

## Protobuf wire budget scanner

internal `ManifestProtobufWireBudgetScanner` 只接受 `ManifestZstdDecompressedCapability`。它先核对 owned
`Data.count == byteSize`，再由 compressed artifact kind 选择 chunk `Manifest` 或 ldiff `DiffManifest`
root。scanner 通过 `withUnsafeBytes` 借用现有 decompressed storage，发生在 SwiftProtobuf 分配 generated
message、repeated array 或 String 之前；“zero-copy”仅指本次 raw wire scan 不复制 payload。

scanner 内置 fixed proto 的 10-message schema：`Manifest`、`FileInfo`、`ChunkInfo`、`DiffManifest`、
`DiffFileInfo`、`Patch`、`PatchInfo`、`DeleteFile`、`DeleteFiles`、`DeleteFileInfo`。每层只接受 known
field number 与精确 wire type；repeated message 可重复，所有 scalar/string/singular message 重复均
拒绝。root 与 nested unknown field、wrong wire type 和 singular duplicate 统一为 `schemaDrift`。

所有 tag、length 和 numeric value 都必须是 minimal varint；field zero、越界 field number、超过 10-byte
varint、非法第十字节、截断 length/message 都是 `invalidWire`。int32 仅接受 `Int32.max` 内正值或规范
10-byte sign-extended negative，拒绝 uint32 alias；uint32 不得超过 `UInt32.max`。int64/uint64 保留完整
64-bit wire 范围。显式 numeric zero 在结构层合法；scanner 不要求 singular field 必须出现，也不检查
field ordering。

默认 provisional limits 为：

- file records 100,000。
- chunks 总数 1,000,000、每文件 100,000。
- patches 总数 500,000、每文件 256。
- delete groups 256、delete entries 100,000。
- message depth 3、总 nodes 1,250,000。
- 单个 string field 全局最多 1,024 bytes；schema-specific cap 再收紧到 32/128/256/1,024 bytes；
  所有 string field payload 合计最多 128 MiB。

调用方只能收紧 limits，任一 count/node/depth/string 超限为 `resourceLimit`。scanner 不 decode UTF-8，
不判断 required/default、path、MD5/xxhash、flags、size 正负、source filtering、tag/name 关系或任何业务
语义。以上 limits 仍须由真实国服样本校准，不能把 budget pass 写成 schema/profile/semantic pass。

policy version 1 的 `ManifestProtobufWireBudgetSummary` 绑定 compressed artifact identity、decompressed
SHA-256/byte size、file/chunk/patch/delete group/delete entry/node count 与 total string bytes。它不实现
`Decodable`，description/debug/Mirror 固定脱敏；入口、约每 1,024 fields 或 64 KiB 和返回前检查
cancellation，并已验证并发确定性。receipt 只是瞬时 structural budget 证明，不能进入 Registry。

receipt 本身仍不解码字段。下一节在它之后执行 generated SwiftProtobuf decode、递归 unknown 检查、
fixed-baseline structural mapping 和现有 validators；国服 profile 与完整 endpoint decoder 仍属后续。

## Structural protobuf mapper

internal `ManifestProtobufStructuralMapper` 的输入是 decompressed capability、expected manifest reference、
`ManifestSchemaBaseline`，ldiff 另需 opaque source/target version。baseline 必须精确等于
`yaagl-ca78abc-sophon-protobuf-structural-v1`；kind、manifest reference、owned `Data.count` 与 capability
byte size 也必须匹配。baseline mismatch 为 `schemaDrift`，但这只是固定 YAAGL 快照能力，不是
`ObservedEndpointProfile` 或国服验证。

mapper 先重跑 wire scanner，再以 SwiftProtobuf `messageDepthLimit = 4`、不丢 unknown fields 解码。
随后递归检查 chunk/ldiff 十种 root 与 nested message 的 `unknownFields` 全空；scanner schema drift 继续
保持 `schemaDrift`，malformed/resource/decode/semantic failure 失败关闭。mapper 在遍历中重新计算
file/chunk/patch/delete group/delete entry/node/string counts，并要求与 policy v1 receipt、compressed
artifact identity、decompressed SHA-256/size 全部相等。

chunk mapper 映射每个 raw file/chunk，拒绝负 file size 和 flags 非 0/64，再交
`ChunkManifestValidator`。`SemanticChunkObject.compressedXXHash` 已由 opaque String 迁移为 wire
`UInt64` numeric claim，0 与 `UInt64.max` 都能无损保留。单 chunk 实测已证明它不等于真实压缩字节的 seed-0 XXH64；活跃实现则从 chunk ID 前缀读取 XXH64 并在解压流上校验。因此 mapper 继续保留 field6 claim 但不用它作 integrity verdict；observed-CN-v2 单 chunk 门改用压缩大小 + field7 压缩 MD5 + zstd 精确大小 + field2 解压后 MD5。

ldiff mapper 会先完整验证所有 source 的 raw patch records，而不只检查 requested source：每个 patch
必须有 info，source key 必须是合法 opaque `GameVersion`、不得等于 target、同 file source 唯一，且
`info.tag == key`；signed sizes/ranges、MD5、build ID、patch object metadata 全部验证。之后仅精确选择
`Patch.key == requested sourceVersion`，无 records 与有 records 但无 exact source 分别映射两个既有
unselected reason。

`patch_id` 仍是 opaque object ID；`patch_name` 被安全保留为 patch object `remoteName`，两者都走受限
identifier validator，但 mapper 不猜二者的格式或相互关系。`original_name` 被规范化为安全相对路径并
保留在 selected patch slice/validated leaf，但不要求它等于 outer `DiffFileInfo.filename`。这些关系仍
需真实国服样本与 profile 决定。

所有 raw delete groups 同样先验证：必须有 info，source key 合法、非 target 且全局唯一；每组内 entry
path 必须安全、无 case-fold collision/file ancestor，size 非负。delete hash 空字符串映射为 nil claim，
非空必须是规范 MD5；只有 exact requested-source group 的 entries 进入 deletion selection。empty ldiff
仍产生合法 non-nil empty selection，不发明 `directLdiffUnavailable`。

返回的 `ManifestProtobufStructuralChunkCapability`/`ManifestProtobufStructuralLdiffCapability` 同时携带
receipt、semantic candidate 和 validator result，构造受限、不可 `Decodable`，description/debug/Mirror
固定脱敏，并检查取消与并发确定性。它们不能直接进入 Registry，也不证明当前国服 endpoint/profile；
production endpoint JSON、branch/build/patch response 解码与整条 `ManifestReplaySemanticDecoding` 接线
仍未完成。

## Semantic materializer 与纯内存 replay

internal replay 的唯一可注册链为：

1. canonical schema v3 descriptor。
2. 与 descriptor claims 精确匹配的 owned byte bundle。
3. 调用方显式传入的 internal `ManifestReplaySemanticDecoding`。
4. 依实际 artifact 顺序解码 branch、build、chunk、patch、ldiff。
5. chunk/ldiff semantic candidate 分别经过 `ChunkManifestValidator` 和
   `LdiffSelectionValidator`。
6. `ManifestInspectionFactory` 与 `ManifestReplayCandidate.make` 完整重建并 exact equality。
7. materializer 签发构造器为 `fileprivate` 的 `MaterializedManifestReplayFixture`，再交给 Registry。

`ManifestReplayDecodingScope` 由 descriptor 派生 release、intent、categories、profile revision 和
schema baseline；production decoder 必须把同一 baseline 传给 structural mapper，不能在 decode
调用链中换成另一个 schema 能力。

每个 decoder 结果必须回传完整 `ManifestReplayArtifactIdentity`，materializer 将 kind、actual SHA-256、
byte size 和可选 reference 与对应 owned artifact 精确比较。actual branch 决定 official/pre-download
target；build target 必须相同，其 response reference 必须等于 chunk artifact reference。带来源版本时，
patch source/target 必须精确，ldiff response reference 必须等于 diff artifact reference；chunk/ldiff
内容再由现有 semantic validators 产生公开 summary。

每一层 decoder 返回的 observations 都重新经过 factory，duplicate code 立即拒绝；最终按 code 排序，
并与 descriptor observations 精确相等。materializer 还要求 bundle 中每个 artifact 恰好消费一次，
并要求 actual-driven branches、availability、target、selected ldiff 与 descriptor 全部相同。

`directLdiffUnavailable` 只能来自 actual patch response 的显式 outcome，且不会读取 diff manifest。
descriptor 存在 ldiff 时则必须读取并验证 diff artifact；即使 validator 产出六字段全零，仍是非 nil
empty selection，不能降格成 unavailable 或 up-to-date。

`ManifestReplayCandidate.make` 会再次重建 branch、target/selected summary、evidence、observations 和
最终 inspection。raw candidate 仍不是 capability；`ManifestReplayRegistry` 的唯一 initializer 只接受
`[MaterializedManifestReplayFixture]`，没有 raw candidate、descriptor 或 bundle overload。Registry 按
fixture ID 建立不可变索引，重复 ID 失败；查询的 release、intent、categories、cache policy 必须与
expected request 完全相同。

materializer 在入口、每次取 artifact、decode 前后、validator 前后和签发 capability 前检查取消；
decode/identity/reference/summary mismatch 立即失败且不返回部分 capability。`schemaDrift` 与
`CancellationError` 保留，其他 decoder error 统一失败为 `invalidManifest`。decoded semantic values、
candidate 和 capability 的 description/debug/Mirror 均固定脱敏；不可解码 value 与 immutable
`Sendable` 结果已覆盖并发一致性。

`SyntheticManifestReplayDecoder` 只存在于 `Tests/BridgeCoreTests`，以 artifact SHA-256 绑定合成 payload，
只证明上述 orchestration、fail-fast 和 capability gate。bounded zstd、wire scanner 与 fixed-baseline
structural mapper 已实现，但 production endpoint JSON/branch-build-patch full decoder、
`ObservedEndpointProfile`、磁盘 cache 和 live endpoint 仍无实现。因此这条链
只承诺 fixture response 的 semantic/version/reference 自洽，不认证官方来源；
branch→build request/credential chain 仍未绑定。`EvidenceGatedManifestAdapter` 未自动连接 Registry，
fixture-only 仍返回 `fixtureUnavailable`，其他策略仍返回 `missingEndpointEvidence`。

## Sophon 操作边界

Sophon transport 是 adapter 内部依赖，不向业务层暴露 URL：

1. `getGameBranches(BranchLookup)` 返回所有候选及其 `main` / `pre_download` slot。
   每个 slot 可暂存 tag、branch、package ID、password，但后三者只能存在于敏感内部类型。
2. 不采用 YAAGL 的无条件 `[0]`。首期必须按已采样的国服身份规则得到唯一候选；零个或
   多个匹配均失败关闭。
3. `getBuild(BuildLookup)` 只接收上一步选中的同一 slot 凭据，返回目标 tag 和
   `data.manifests` 描述符；用于 full，以及所有操作的目标 chunk 清单。
4. `getPatchBuild(PatchBuildLookup)` 只用于带来源版本的 update/pre-download，返回 ldiff
   描述符。来源版本用于本地精确选择 `Patch.key`，不得擅自编码成未采样的网络参数。
5. manifest fetch 只允许请求描述符指向的 manifest object；随后立即停止，绝不继续请求
   `chunk_download` 或 `diff_download` payload。

完整调用序列：

| 意图 | slot | 必需调用 | 结果 |
|---|---|---|---|
| `full` | `main` | branches -> getBuild -> chunk manifest | 正式版完整清单 |
| `update(from)` | `main` | branches -> getBuild -> chunk manifest -> getPatchBuild -> ldiff manifest | 指定来源到正式版的直接增量信息 |
| `preDownload(nil)` | `pre_download` | branches -> getBuild -> chunk manifest | 预下载完整清单 |
| `preDownload(from)` | `pre_download` | 与 update 相同 | 指定来源到预下载版的直接增量信息 |

`pre_download` 不存在是正常的 `preDownloadNotPublished`。来源 tag 与目标 tag 相同是
`upToDate`。当前 `directLdiffUnavailable` 只表示 patch response 没有 ldiff descriptor；不得猜测
多跳升级链，也不得自动承诺回退完整下载。若 descriptor 存在，则必须获取并解析 wire
`DiffManifest`，产出一个非 nil `selectedLdiff`；即使没有 selected patch，该 selection 也可为空。

## JSON 与 manifest 描述符

JSON decoder 只把已采样并列入 profile 的字段映射到领域模型。至少验证：

- HTTP 状态、content type、响应大小上限和 API envelope 与样本一致。
- branch slot 的 tag 和内部凭据非空，目标 slot 唯一。
- build 返回的 tag 与 slot tag 完全相等。
- 每个请求类别精确匹配且恰好一个；禁止 YAAGL 式模糊类别匹配。
- manifest ID、压缩方式和 URL 组合方式与 profile 一致，最终 HTTPS host 在 allowlist 内。
- 重定向默认拒绝；若 profile 允许有限重定向，每一跳都重新验证 scheme、host 和上限。

内部 `SensitiveRemoteReference` 可保存请求所需 URL，但不可 `Codable`、不可默认打印，也
不可进入公开输出或持久缓存索引。

## chunk protobuf 模型

`ChunkManifestValidator` 本身仍不解析 protobuf，也不接触 field number、flags 或 URL；它只消费
internal `SemanticChunkManifest`。fixed-baseline structural mapper 现已负责 scanner、generated decode、
recursive unknown check、flags/size/raw field mapping 后调用 validator；未知 flags 为 `schemaDrift`。
这仍不替代未来 `ObservedEndpointProfile`。

semantic validator 当前保证：

- 只接受 `.game`，候选非空，entry 总数不超过 100,000，全部 reference 不超过 1,000,000。
- path 使用与安全归档一致的相对路径边界：拒绝绝对/`~`/反斜杠/冒号/control、空组件、`.`/
  `..`、首尾空白和尾点；深度 32、组件 255 bytes、总长 1,024 bytes。目录可有一个尾 slash，
  文件不可；输出 NFC，并用固定 `en_US_POSIX` case-fold 拒绝碰撞。
- 父目录可以隐式存在，但任何显式普通文件都不能成为另一 entry 的祖先。
- 目录必须 0 bytes、无 whole MD5、无 references；普通文件必须有 32-hex whole MD5（规范为
  小写），非空文件必须有 references，0-byte 文件必须没有范围。
- semantic object ID 使用受限 opaque identifier；compressed 与 uncompressed bytes 都大于零，
  uncompressed MD5 为 32-hex，compressed XXHash 只保留 wire `UInt64` numeric claim。这里不猜实际
  checksum algorithm、seed 或 checked bytes。
- 每个 reference 的 `[fileOffset, fileOffset + uncompressedBytes)` 使用 checked arithmetic，必须
  落在文件内。排序后非空文件必须从 0 开始、到 installedBytes 结束，且相邻范围首尾完全相等，
  因而拒绝 leading/middle/trailing gap、重叠和越界。
- 相同 object ID 的全部 metadata 必须完全相同；否则失败关闭。
- `targetInstalledBytes` 对普通文件 installed bytes checked sum；
  `referencedChunkCompressedBytes` 按每次 reference 累计 compressed bytes；
  `uniqueChunkObjectBytes` 按一致 object ID 去重后 checked sum。
- internal validated files/references/objects 按 UTF-8 稳定排序；公开结果只返回 count/size
  `ChunkManifest` summary，不暴露 path、object ID、MD5 或 checksum leaf。

固定证据中的 `Manifest` 映射为：

- `ChunkFile.path` <- `filename`，必须是唯一、安全的相对游戏路径。
- `ChunkFile.kind` <- `flags`；仅接受已观察的 `0` 文件和 `64` 目录，其他值视为漂移。
- `ChunkFile.installedBytes` <- `size`；负数拒绝，转为 `UInt64` 时检查溢出。
- `ChunkFile.md5` <- 整文件 `md5`。
- `ChunkObject.id` <- `chunk_id`，ID 是 opaque string，不猜测其哈希算法。
- chunk field2 `md5` 已由单样本确认为解压后 MD5；field7 在同一样本等于压缩字节 MD5。field6 仍只保留 numeric claim，不作该 payload 的 integrity verdict。这些 checksum 都不是供应链签名。
- `offset`、`compressed_size`、`uncompressed_size` 均为字节；检查范围溢出、越界、重叠，
  同 ID 的大小/校验字段必须一致。

## ldiff protobuf 模型

internal `LdiffSelectionValidator` 本身不解析 protobuf。fixed-baseline structural mapper 现已先验证
全部 raw patch/delete records，再针对 requested source 把 wire `DiffManifest` 映射为
`SemanticSelectedDiffPlan`：selected files、unselected files 和 deletions。wire message 名仍是
`DiffManifest`，不能机械改名；`LdiffSelection` 是过滤后的领域结果。

unselected file 的 internal reason 只有 `.noPatchRecords` 与 `.noPatchForRequestedSource`，只记录
wire/source-filtering 事实，不公开猜测“新文件”“未修改”或“fallback”。validator 当前保证：

- source 与 target 不同；`manifestFileRecordCount == selected + unselected`，再加 deletions 后总数
  不超过 100,000。empty、unselected-only 和 delete-only selection 都合法。
- selected/unselected/deletion path 取 union 后执行 archive-relative、NFC、固定 case-fold、唯一和
  file-ancestor 检查；隐式目录允许。
- selected file 的 target/original MD5、slice checked range、build ID、patch object ID/bytes 均验证；
  相同 selected object ID 的 metadata 必须一致。
- unselected file 仍验证 target size/MD5 与 reason；deletion 的 original MD5 可选但若存在必须有效。
- `selectedPatchObjectBytes` 只对 selected object ID 去重后 checked sum；它是 ldiff 对象声明量，
  不是实际网络流量或整体 update 下载量。
- public 六字段 summary 为 manifest records、selected files、without-selected files、selected
  deletions、unique selected objects、selected object bytes；不提供整体 update transfer 字段。
- internal leaf 按 UTF-8 稳定排序；public `LdiffSelectionSummary` 不暴露 path、reason、object ID、
  MD5、build ID 或 slice。

缺少 requested-source patch 的 file 只进入 unselected count，不会产生 unavailable。若 patch response
有 descriptor，就必须产生非 nil selection；`directLdiffUnavailable` 在更早的 response 层表示没有
descriptor，不能由本 validator 推导。

固定证据中的 wire `DiffManifest` 经 requested-source filtering 后映射为：

- `DiffFile.targetBytes` / `targetMD5` 是补丁完成后的文件大小与 MD5。
- 只精确选择 `Patch.key == requested sourceVersion` 的项；`Patch.info.tag` 必须与 key 一致。
- `patch_id` 是 opaque 远端对象 ID；`patch_size` 是整个补丁对象的传输字节数。
- `patch_name` 安全保留为独立 `remoteName` claim，不猜它与 `patch_id` 的格式或派生关系。
- `patch_offset` / `patch_length` 是共享补丁对象内的切片，范围必须落在 `patch_size` 内。
- `original_size` / `original_hash` 描述补丁前文件；`original_name` 作为独立安全 path claim 保留，
  不猜它与 outer filename 的关系；`build_id` 保持 opaque，不推断身份语义。
- `files_delete` 对所有 source group 先验证，再只选择 exact requested source；empty hash 映射 nil，
  非空必须是 MD5。它仍只是未来更新计划的描述性数据，本阶段绝不删除对应文件。

复制或生成 protobuf 定义时必须保留 `UPSTREAM_STRATEGY.md` 所述来源、原路径、提交、
版权和 MIT 许可声明。

## 版本、大小与哈希语义

- 版本只做精确相等比较；不排序、不补零、不把 `x.y.z` 当作可证明的 SemVer。
- 展示 tag 不是不可变 build fingerprint。不得仅凭 tag 生成兼容 profile；本阶段只提供
  manifest/响应证据摘要。
- `targetInstalledBytes` 是目标普通文件 `size` 的溢出安全求和，不含目录。
- `referencedChunkCompressedBytes` 是所有 chunk 引用的压缩大小之和。
- `uniqueChunkObjectBytes` 按一致的 chunk ID 去重后求和，更接近空缓存传输量。
- `selectedPatchObjectBytes` 仅对 selected patch object ID 去重；同一对象被多个文件切片复用时
  不能重复累计。它不包含 new/unselected file chunks 或本地 patch fallback，不能显示为总下载量。
- manifest JSON、压缩 protobuf 本身的字节数单列，不混入游戏 payload 大小。
- public ldiff selection 只提供 selected object bytes。未读取本地安装状态时，无法知道
  new/unselected files、缺失/损坏文件或 patch fallback 所需 chunks，整体 update transfer 保持未知。
- MD5/xxHash 只保留协议含义；缓存的每份原始响应、压缩 manifest 和解压 protobuf 另外
  计算 SHA-256。SHA-256 证明本地字节未变，不证明服务端真实性。

## 缓存与回放 fixture

运行时缓存根必须由调用方注入，目录为 `0700`、文件为 `0600`，临时写入后原子提交：

- 含 password、签名 URL 或完整请求的 branch/build JSON 只做内存缓存，不落盘。
- manifest blob 以本地 SHA-256 内容寻址，读取时重新校验。
- 磁盘只保存脱敏 `ManifestInspection`、证据摘要、profile revision、获取/过期时间。
- cache key 包含 release、intent、来源版本、类别和 endpoint profile revision。
- TTL 由明确策略提供；过期或损坏缓存失败关闭，不静默 stale-if-error。

回放 fixture 建议结构：

```text
Fixtures/ManifestAdapter/<id>/
  fixture.json
  getGameBranches.redacted.json
  getBuild.redacted.json
  getPatchBuild.redacted.json       # 仅增量样本
  manifests/<sha256>.pb.zst
  expected-inspection.json
```

`fixture.json` 记录 fixture schema、采样时间、scope、profile revision、请求模板摘要、原始
body SHA-256、脱敏 body SHA-256 和 redaction 清单。真实 password/token/cookie/header/完整
URL 永不进入仓库；以确定性占位符维持字段关系。ReplayTransport 必须硬性禁网，并按逻辑
operation 匹配 fixture，不按含凭据的完整 URL 匹配。

## 接口漂移检测

每个 `ObservedEndpointProfile` 绑定一组已审核 fixture 和 schema baseline。检测分两层：

- 结构漂移：必填 JSON pointer 缺失/改名/类型变化、envelope 变化、未知 protobuf wire type、
  zstd 或 content type 变化，返回 `schemaDrift`。
- 语义漂移：tag 不一致、候选不唯一、类别重复、未知 flags、非法路径/hash/大小、重复对象
  元数据冲突、patch 切片越界，返回具体但脱敏的 `invalidManifest`。

新增 JSON 字段可记录为 additive observation，但不得改变既有解释；未知 protobuf 字段需记录
消息类型和 field number。任何会影响版本、大小、对象定位或哈希语义的变化都必须失败关闭，
保存脱敏样本并发布新的 profile revision 后才能恢复 live 查询。

## 脱敏与日志

视为敏感：password、package ID、cookie、authorization、所有 query value、带签名路径或参数
的 URL、原始响应 body。日志只允许 operation、profile revision、allowlisted host、HTTP 状态、
字节数、耗时、SHA-256 和无值 JSON pointer；错误不得拼接响应 body。

内部 secret wrapper 的 `description` 固定为 `<redacted>`，不可自动编码。单元测试必须覆盖
正常、错误、cache 和 fixture 录制路径，并扫描产物不含已知 canary secret。

## 最小实现与验收顺序

1. 领域模型、semantic validators、evidence gate、A0 mock-only branch discovery、descriptor v3、byte integrity bundle、bounded zstd
   capability、zero-copy wire budget scanner、fixed-baseline structural mapper、safe fixture file loader、
   internal materializer/capability 和 in-memory replay 已完成；下一步实现 production endpoint JSON/
   branch-build-patch full decoder、`ObservedEndpointProfile` 和 cache，并绑定 branch→build request/
   credential chain。
2. synthetic decoder 已覆盖 full、无/有 preload、direct unavailable、empty selection、版本/reference/
   summary/observation mismatch、阶段失败、取消和 secret canary；后续真实 decoder 仍须覆盖 cache
   损坏、schema 漂移和实际 wire 异常。
3. 获得当前官方国服脱敏样本后，评审并新增首个 `ObservedEndpointProfile`；不能直接修改
   默认 URL 常量，因为在此之前不存在可用 live 默认值。
4. live 集成测试必须证明网络请求只到 branches/build/patch-build/manifest 元数据，未触及
   chunk/diff payload；同时证明游戏目录和系统状态零改动。
5. `swift test` 通过只证明 adapter 契约和 fixture；真实版本查询、下载、安装、启动、登录、
   持续运行和性能仍是彼此独立的后续验收门槛。
