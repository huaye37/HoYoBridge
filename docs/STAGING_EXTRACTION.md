# Staging 写入事务

`SafeStagingExtractor` 消费已经由 `SafeArchivePlanner` 生成的计划，以及绑定同一已验证 CAS
产物的内容 source。它不解析 ZIP/tar/7z，也不发布 runtime current 指针。

## 身份边界

- source 必须声明与调用方一致的 artifact SHA-256 和 entry 总数。
- 每个计划条目按原始路径 SHA-256 重新取得 descriptor，并复核 raw path digest、类型、声明
  大小、原权限和 linkTarget；目录不会请求内容 reader，普通文件恰好请求一次。
- source 在全部条目后必须通过 `finish()`，未来 libarchive adapter 用它拒绝额外或遗漏 entry。
- extraction 开始时固定 `SafeArchivePlan.canonicalSHA256`；成功结果同时携带 artifact SHA-256、
  plan SHA-256 和 plan policy version，避免后续只凭可变路径判断来源。

## 文件系统边界

- staging root 必须是已存在、当前用户拥有且严格 `0700` 的父目录下一个尚不存在的直接子项；
  调用方必须传入已规范化且祖先不含 symlink 的绝对路径，返回值使用同一规范路径。
- “规范化”包含真实文件系统路径：macOS 的 `/var` 是 `/private/var` 的 symlink 别名，调用方
  使用系统临时目录时必须先经 `realpath` 得到 `/private/var/...`；只用 URL/string
  standardization 仍会被拒绝。
- root、隐式目录和显式目录全部通过持有的 dirfd 使用 `mkdirat/openat(O_NOFOLLOW)` 创建并复验；
  文件使用 `O_CREAT|O_EXCL|O_NOFOLLOW` 和 `0600`，不覆盖任何已有对象。
- reader 固定分块读取；每次写盘前同时检查条目剩余字节和计划总字节，EOF 必须精确等于声明。
- 写盘时同步计算每个普通文件的 SHA-256；文件完成顺序为实际大小复核、`fchmod` 到
  `0600/0700`、`fsync`、关闭，并保存创建时 device/inode、大小、权限和内容摘要。
- `source.finish()` 后，从最终目录 FD 重新枚举完整 tree。普通文件以 `O_NOFOLLOW` 重新打开，
  在该最终 FD 上完整重哈希，并在哈希前后及路径侧复核 device/inode、大小和权限；同 inode、
  同大小的原地内容替换也会被拒绝。
- 随后自底向上同步目录树和 staging 父目录，并再次复核 root 的初始与最终身份。

## Tree seal 与交接

- 每个 seal entry 包含 NFC 相对路径、类型、权限、大小；普通文件还包含最终 FD 重哈希得到的
  SHA-256，目录没有伪造的内容摘要。隐式父目录同样进入 seal。
- 条目按 UTF-8 字节顺序排列，并使用独立 domain、seal version、定长整数和长度 framing 形成
  deterministic tree SHA-256；相同 tree 不受 reader chunk 划分影响，任一文件内容变化都会改变
  seal。
- `ExtractedStagingTree` 返回 artifact SHA-256、canonical plan SHA-256、plan policy version、tree
  seal version、完整 seal entries、tree SHA-256，以及最终 root FD 的 device/inode。
- root device/inode 是交给下一层 publisher 的身份凭据。publisher 必须从可信 parent 重新以
  `O_NOFOLLOW` 打开 root 并精确匹配，不能只相信 `rootURL`。身份匹配只固定 root，不证明
  descendants 未变化；publisher 还必须在该 FD 下重新枚举、重哈希并比较完整 tree seal。
- 当前批次只返回 sealed staging tree，不执行最终 runtime rename、current 切换或启动。

## 重新复验与竞态边界

`SafeStagingExtractor.reverify(_:)` 对已有 `ExtractedStagingTree` 执行只读复验：

1. 先验证 candidate 自身是否自洽：artifact/plan/tree SHA-256 格式、当前 policy/seal version、
   NFC 安全路径、严格 UTF-8 排序、唯一 entry、允许的类型/权限/内容摘要、完整目录祖先、普通
   文件数量与总字节，以及从 entries 重算的 tree SHA-256 必须全部匹配。
2. 从可信 parent 以 `O_NOFOLLOW` 打开 root，要求当前用户拥有、严格 `0700`，并精确匹配
   candidate 记录的 root device/inode 和 parent 路径身份。
3. 递归枚举实际 tree；每个实际路径必须恰好对应一个 seal entry，拒绝多余、缺失、重复、
   symlink、跨设备或类型/权限/大小异常的对象。
4. 每个普通文件从重新打开的只读 FD 完整重哈希，并在哈希前后同时复核 FD 与路径侧的
   device/inode、大小和权限；内容 SHA-256 必须等于 seal entry。
5. 完成后再次匹配 root FD 与 parent 路径身份。失败只报告复验错误，不把 candidate 当成已清理。

`reverify` 返回 `Void` 并关闭它打开的 FD，因此通过结果只是该调用完成瞬间的 snapshot，不是
可持久化复用的安装或启动授权，也没有重新证明 candidate 中的 artifact/plan 摘要来自外部
可信源。未来 publisher 必须在同一调用链中先取得覆盖该 staging 身份的持久独占锁，在持锁
状态下调用 `reverify`，并一直持有到 rename 和目标父目录 `fsync` 完成；rename 前还要再次从
source parent 核对 root device/inode。若提交后还会释放锁、跨调用链写 install/current record，
或最终目标经历任何可能改变 tree 的步骤，则应从目标 parent 重新打开并复验后再继续。

## Runtime install identity（纯模型）

`RuntimeInstallIdentityBuilder.build(runtime:plan:candidate:)` 只构建安装身份，不访问或修改文件
系统。它只接受 managed-download runtime，并重新核对 runtime definition、artifact、plan、tree
和 candidate entries：

- `MGBINSTALL` v1 `installID` 绑定 runtime ID、`runtime.definitionDigest`、小写 artifact SHA-256、
  plan policy version/canonical SHA-256、tree seal version/SHA-256、entry count、regular-file count
  和展开总字节。seal entries 也进入 `RuntimeInstallRecord`；其内容由 tree SHA-256 间接绑定。
- runtime artifact SHA-256 必须等于 candidate artifact SHA-256；candidate 的 plan 摘要、policy、
  total bytes、tree seal、规范 entry 顺序/祖先/类型/权限/大小必须与输入 plan 精确一致。
- `runtime.byteSize` 必须严格等于 `plan.archiveByteSize`。planner 的膨胀比上限以
  `archiveByteSize` 为分母，这项检查防止调用方用虚增分母通过 planner，再把结果绑定到更小的
  已验证 artifact。
- root URL/device/inode 是发布事务的瞬时文件系统 handoff，不进入稳定 install identity；builder
  也不会代替紧邻发布前、持锁执行的 `SafeStagingExtractor.reverify`。

`RuntimeInstallRecord` 和 entry record 都是 `Encodable` 而非 `Decodable`。编码结果只用于未来
审计/落盘格式，不能从 JSON 直接恢复可信能力；必须重新运行 builder。当前尚无 record 写盘、
版本目录原子 rename、current record、回滚或启动流程。

## 失败与取消

取消、source 错误、短/长内容、身份不符、路径冲突或写盘错误都会进入同一清理路径。清理只从
已持有的 parent/root dirfd 递归，目录使用 `O_NOFOLLOW`，symlink 只删除链接本身，跨设备目录、
未知文件类型或硬链接异常会使清理失败并保留现场。若提取和清理同时失败，错误同时保留两者，
不能宣称 staging 已清理。

真实固定版本 libarchive 后端、恶意归档 corpus、最终 runtime 原子发布、失败回滚和游戏启动
仍是独立后续门槛；当前测试 source 通过不代表真实 ZIP/tar/7z 已可用。
