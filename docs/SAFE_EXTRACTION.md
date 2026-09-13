# 安全解压计划

## 当前范围

`SafeArchivePlanner` 只把归档后端枚举出的条目转换为稳定、受限的解压计划。它不打开归档或
解压数据。`SafeStagingExtractor` 已能使用目录 FD、`openat`、`O_NOFOLLOW` 和实际写出上限把
受控 source 写入一个全新 staging tree，但真实归档 parser 和最终 runtime 原子切换仍未完成。
调用方必须提供当前用户拥有、严格 `0700`、绝对规范且所有祖先均非 symlink 的可信私有
parent。macOS 的 `/var` 是指向 `/private/var` 的别名，因此使用系统临时目录前必须先以
`realpath` 解析真实路径；仅做字符串标准化不足以满足这个边界。

首个切片只接受普通文件和目录。符号链接、硬链接、FIFO、socket、块/字符设备以及未知类型
全部失败关闭；未来即使支持安全相对链接，也必须作为独立配置和测试切片引入。

## 路径规则

- 拒绝绝对路径、`~`、Windows drive/冒号、反斜杠、控制字符和 NUL。
- 拒绝空、`.`、`..`、重复 slash、组件首尾空白，以及以点结尾的组件。
- 普通文件不能以 slash 结尾；目录可以有一个尾 slash，计划中会移除。
- 每个组件、完整路径和目录深度都有显式 UTF-8 字节或数量上限。
- 输出路径规范化为 NFC，并用固定 `en_US_POSIX` 大小写折叠键检测默认 APFS 上可能发生的
  Unicode/大小写碰撞。任何碰撞都拒绝，不依赖当前开发卷的实际行为。
- 同一路径不得重复；普通文件不能成为另一条目的祖先。检查与归档条目顺序无关。

## 类型、权限与大小

- `ArchiveEntryDescriptor.permissions` 只接受权限位，不接受完整 `st_mode`；setuid、setgid、
  sticky 或更高位均拒绝。
- 目录必须声明 0 字节并规范为 `0700`。
- 普通文件若原权限含任一执行位则规范为 `0700`，否则为 `0600`；不继承归档的其他权限。
- 默认限制为 100,000 个条目、单文件 32 GiB、总展开 256 GiB、路径 1,024 字节、组件
  255 字节、深度 32 和 200 倍展开比。调用方可以收紧；零值表示不允许对应资源，不表示无限。
- 单文件、累计总量和 `archiveByteSize × maximumExpansionRatio` 全部使用溢出检查；归档大小
  为 0 或任何算术溢出都会拒绝。

计划包含 `policyVersion = 1`；每个条目包含规范相对路径、原始路径 SHA-256、声明类型/大小/
权限及规范权限。后端重读归档时必须重新核对这些绑定；调用方还必须把计划与已验证 CAS
产物的 SHA-256 绑定，错误不回显原始路径。计划类型只支持编码输出，不支持直接解码构造；
任何持久化计划都必须重新运行 planner，不能把 JSON 反序列化结果当成已验证能力。

`SafeArchivePlan.canonicalSHA256` 使用独立 domain、digest schema 版本、定长大端整数和长度
framing，按规范 UTF-8 路径顺序覆盖策略版本、归档/展开大小、条目数量，以及每项的类型、
规范路径、原始路径摘要、声明大小、源权限和规范权限。它不对 JSON 编码结果求哈希，因此
JSON encoder、key 顺序或原始条目枚举顺序变化不会改变同一计划的摘要；任一受绑定字段变化
都会产生不同摘要。

计划摘要只描述允许写出的结构，不包含文件内容。文件内容由 staging writer 在写入时逐文件
计算 SHA-256，并在最终 FD 扫描中重新读取核对；最终 tree seal 再把规范路径、类型、权限、
大小和普通文件内容摘要确定性聚合。tree seal 与交接对象仍不等于 runtime 已发布；未来
publisher 必须在重新打开并匹配 root 身份后再次扫描、重算并比较 seal。
当前 `SafeStagingExtractor.reverify` 提供这项只读检查，但它关闭 FD 后即结束，只是瞬时
snapshot；publisher 仍必须以独占锁把复验、rename 和必要的提交后复验包在同一事务边界内。

## 尚未完成

- ZIP/tar/7z 等真实 parser 与固定版本解压后端。
- staging tree 到版本化 runtime 目录的最终原子提交和 current 切换。
- 从真实归档输入到 runtime 发布、选择和启动的端到端集成。
- 可选的安全相对 symlink、硬链接语义、稀疏文件和扩展属性策略。
- 恶意真实归档 fixture、模糊测试以及签名/公证后的依赖分发。

后端选择与分发约束见 [ARCHIVE_BACKEND.md](ARCHIVE_BACKEND.md)。
