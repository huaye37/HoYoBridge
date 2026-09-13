# 归档后端选型

## 结论

先实现与 I/O 解耦、只读且失败关闭的安全计划器；它接收结构化 entry 元数据并生成带策略
版本和原始路径摘要的 `SafeArchivePlan`。调用方负责将计划与已验证 CAS 产物 SHA-256 绑定；
当前不写盘，也不代表已经具备解压能力。

生产 extractor 应采用项目内可固定版本、源码/二进制 SHA-256、许可证和构建参数的
libarchive 窄包装。优先把源码或静态库纳入 SwiftPM 构建；如使用自建 binary framework，必须
把全部传递依赖一同纳入版本、许可、签名和公证流程。不得运行时依赖 Homebrew，也不得把
`tar -t` 的文本列表当作安全计划或生产解压依据。

manifest zstd 不走 libarchive。当前已经固定 upstream `libzstd` 并通过独立窄 bridge 实现 bounded
raw frame decompression；未来 libarchive wrapper 只有在真实 runtime archive 的 allowlisted filter
需要 zstd 时，才可共享同一底层 `libzstd` 构建产物，不能共享 archive parsing surface。

## 本机事实基线（2026-08-19）

- Xcode 26.6 使用 macOS SDK 26.5；在 SDK 内找不到 `archive.h`，直接执行
  `xcrun clang -x c -fsyntax-only - <<< '#include <archive.h>'` 会报 header not found。
  因此当前项目不能只靠系统 SDK 编译 libarchive C 包装。
- 本机另装 Xcode 27 beta 4 / macOS SDK 27.0；同样没有 `archive.h` 或 `zstd.h`。两个 SDK 虽有
  `libarchive.2.tbd` 和 zstd filter symbol，却没有受支持 header，Apple Compression/AppleArchive
  也没有 Zstandard algorithm；不能据此手写 ABI 或改用系统库。
- `/usr/bin/tar` 是指向 `bsdtar` 的符号链接；版本输出为 `bsdtar 3.5.3 - libarchive 3.7.4`。
  文件是 `x86_64/arm64e` 通用 Mach-O，标识为 `com.apple.bsdtar`，由 Apple macOS Software
  Signing 签名。
- Homebrew 前缀为 `/opt/homebrew`；本机 `libarchive` 为 3.8.0、`keg_only: true`，理由是
  macOS 已提供相关组件。formula 元数据声明 `BSD-2-Clause`，源码 URL 和 SHA-256 均已给出；
  安装目录也包含 `COPYING`、`archive.h`、静态库和动态库。
- Homebrew 动态库仅为 arm64，使用 ad-hoc 签名；`otool -L` 显示 install name 和 xz、zstd、
  lz4、libb2 依赖均指向 `/opt/homebrew/opt/...`。这证明它适合本机开发探针，不构成可分发依赖。
- 当前 `Package.swift` 最低平台为 macOS 15，已精确固定 `facebook/zstd` `1.5.7`、revision
  `f8745da6ff1ad1e7bab384bd1f9d742439278e99`。`BridgeCore` 不直接依赖或 import upstream module；
  `CZstdBridge` 自有窄 header/调用点只暴露解压。MacGameBridge 自有 compression/dictionary/frame helper
  仅在 Tests，但 upstream `libzstd` product 仍可能包含完整 compression symbols。尚无 libarchive C
  target、wrapper 或 framework。
- SwiftPM 从 zstd 源码构建并静态进入本项目产物；`otool -L` 不出现外部 `libzstd` 或 Homebrew
  路径。BSD license 和 resolved source notice 已保存在 `LICENSES/` 与 `THIRD_PARTY_NOTICES.md`。

以上事实来自本机 `xcrun`、`file`、`codesign`、`brew info --json=v2`、`otool -L`、安装目录
`COPYING`/headers 和项目文件；未据此声称其他 macOS/Xcode/Homebrew 版本具有相同行为。

## Manifest zstd 与 archive backend 的复用边界

manifest artifact 是 zstd-compressed protobuf blob，不是 archive。`ManifestZstdDecompressor` 直接通过
`CZstdBridge` 做标准单 frame streaming decode，并以 windowLog 23、每类 256 MiB output 与
`1 MiB + 128 × actual consumed bytes` ratio cap 约束资源；它拒绝 trailing/concatenated/skippable/
dictionary，返回 owned bytes/SHA-256 的脱敏 capability。该 capability 不解析 protobuf、不授权
semantic replay，limits 仍待真实国服样本校准。

未来 `CLibArchive` 若确需 zstd filter，可依赖同一 SwiftPM `libzstd` product，避免第二份版本和许可
状态；但它必须保留独立的 entry enumerator/content source wrapper、格式/filter allowlist 和恶意归档
测试。不得让 manifest 调用 libarchive raw format，也不得为了“复用”而给 runtime archive 自动启用
zstd filter。若实际 archive 格式不需要 zstd，wrapper 就不启用该 filter。

## 四条路线比较

### 1. 系统 `tar` 子进程

- **可构建性与 arm64：**无需头文件或链接配置，本机系统工具可原生执行。
- **安全：**子进程直接写盘，调用方无法在每个 entry 落盘前执行同一套强类型策略。
  `tar -t` 是面向终端的文本展示，不是保留路径字节、类型、链接目标和大小语义的稳定协议；
  “先列表、再解压”也无法证明两次解析与最终写入逐 entry 一致。
- **许可、签名与公证：**不重分发系统工具，且本机副本由 Apple 签名；仍需在真实发布包中验证
  子进程启动和权限，这些事实不能替代恶意归档测试。
- **维护结论：**构建代价低，但安全可控性和版本一致性不足；仅保留为诊断或受控开发工具，
  不作为生产 extractor。

### 2. 运行时依赖 Homebrew

- **可构建性与 arm64：**加显式 include/library path 后本机可编译，现装库为 arm64；keg-only
  意味着默认搜索路径不会提供它，其他用户也未必安装相同 Cellar。
- **安全：**能使用完整 entry API，能力优于 CLI 文本，但安全性仍取决于包装策略和固定版本。
- **许可、签名与公证：**本机元数据和 `COPYING` 可审计，但 dylib 为 ad-hoc 签名并引用多项
  Homebrew 绝对路径依赖，不能作为独立、可公证产品的运行时前提。
- **维护结论：**只允许用于开发验证；禁止把 `/opt/homebrew` 路径写入发布构建或要求用户先
  安装 Homebrew。

### 3. 纳入构建的 libarchive 包装

- **可构建性与 arm64：**新增窄 C target/module map，固定上游源码构建静态库；或由项目自己
  生成含 macOS arm64 slice 的 xcframework。若 allowlist 需要 zstd，可共享当前 pinned upstream
  `libzstd` product；不得直接复制当前 Cellar 产物冒充可复现构建。
- **安全：**`archive_read_next_header` 与 `archive_entry_*` 可在写盘前取得 pathname、file type、
  symlink、hardlink 和 size；本机 3.8.0 header 还提供 `SECURE_SYMLINKS`、`SECURE_NODOTDOT`、
  `SECURE_NOABSOLUTEPATHS` 和 `SAFE_WRITES` flags。它们只能做纵深防御，不能代替项目策略。
- **许可：**记录上游 URL、版本、源码/二进制 SHA-256、补丁、构建 flags、启用的格式/filters、
  全部传递依赖及许可证；随发行物保留 libarchive `COPYING` 和实际源文件要求的 notices。
- **签名与公证：**源码/静态链接由最终 Mach-O 统一签名，边界最小；动态 framework 必须使用
  app 内 `@rpath`、嵌入全部非系统依赖并逐层签名，最后对真实 archive 执行公证验证。
- **维护结论：**实现成本中等，但版本、格式面和写盘行为可控，是生产 extractor 的推荐路线。

### 4. 自研纯 Swift parser

- **可构建性与 arm64：**SwiftPM 集成和原生 arm64 最直接，无 C ABI 或嵌套动态库问题。
- **安全：**需要自行正确处理每种格式、压缩 filter、编码、稀疏文件、链接、重复 entry、整数
  溢出和畸形输入；自研 parser 会把成熟解析器的攻击面转移到本项目。
- **许可、签名与公证：**自研代码签名简单；若使用第三方 Swift 包，仍须固定 revision/hash、
  审核许可证与传递依赖，不能因语言是 Swift 就降低供应链要求。
- **维护结论：**若未来只支持一种严格受控格式可重新评估；当前多格式运行时产物不值得承担
  最高实现与 fuzz/兼容维护成本，不推荐。

## 推荐落地顺序与安全边界

1. 先完成纯策略 `SafeArchivePlanner`：只允许普通文件和目录；拒绝绝对路径、`.`/`..`、
   空组件、无效编码、符号链接、硬链接、设备、FIFO/socket、重复路径及 macOS
   case/Unicode 归一化冲突。
2. 计划器以 checked arithmetic 限制 entry 数、单文件大小、声明总展开大小和实际写出总量；
   到达任一上限立即失败，不能只相信 header size。
3. 固定 libarchive 后实现只读 enumerator，让 planner 消费强类型 entry，而非解析 `tar` 文本；
   只启用目录明确需要的格式和 filters。
4. extractor 仅接受已验证 CAS 产物及其匹配 plan，在全新私有 staging 中逐 entry 复核并写入；
   不恢复 owner、setuid/setgid、ACL、xattr、file flags 或设备节点。
5. 完成后复核树结构、数量与实际字节数，再同步并原子发布版本目录；失败只清理本次 staging，
   不改变当前运行时。后续若确需链接，另增版本化策略和恶意 fixture，不能放宽默认策略。

## 进入生产实现前的验收

- 固定依赖清单、hash、许可 notices、arm64 构建产物和最小格式/filter 集合。
- 对最终 products 执行 `otool -L`，不得出现外部 `libzstd`、Cellar 或 `/opt/homebrew` 路径。
- 单测和 corpus 覆盖 traversal、绝对路径、链接逃逸、特殊文件、重复/归一化冲突、截断、畸形
  header、超大声明与实际超限；另运行 libarchive 上游/项目 fuzz corpus。
- `swift build`、`swift test` 通过，并用签名后的真实 app archive 完成 `codesign --verify`、
  Gatekeeper 与 notarization 验证。单元测试通过不等于已经完成真实解压或发布验收。
