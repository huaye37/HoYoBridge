# Runtime activation identity

`RuntimeActivationIdentityBuilder` 把一次经过兼容选择的 runtime/profile 决策和一个安装版本收敛
为 `RuntimeActivationRecord`。store 可首次写入 generation 1，并以调用方持有的 trusted expected
record 做 exact CAS 替换；`rollbackCurrent` 复用同一 CAS 选择旧目标。内部 decoder 可重建自洽
record；`resolveCurrent` 可在新 store 实例中恢复 current，但结果只是锁内 snapshot。

## 输入与选择

builder 接受：

- 已有 `InstalledRuntimeVersion`。
- 已验签的 `VerifiedCatalog`。
- 包含当前游戏、系统能力、mode、preferred profile 和 acknowledgements 的
  `CompatibilityRequest`。
- 调用方提供且必须大于零的 `generation`。

builder 内部首先调用 `CompatibilitySelector.select`，而不是接受任意 profile/runtime ID。因此
目录撤销、标准/实验 tier、硬件和游戏匹配、实验模式、显式 profile 选择及风险确认仍沿用同一
选择门槛。

## 安装版本绑定

selected runtime 必须与 install record 的 runtime ID、runtime definition SHA-256 和 artifact
SHA-256 精确一致。install record 还必须满足当前 schema、plan policy、tree seal version、摘要
格式、entry/file count、总字节，以及 version URL 最后一级等于 install ID。

这些检查只验证传入模型的自洽与选择结果的匹配。builder 不打开 `versionURL`；跨重启调用方可
先用 `reopenInstalled(installID:in:)` 限长解码 receipt、对账 catalog 并 full rehash payload，再把
返回的 capability 交给 activation。启动仍必须用最新 catalog/request 重新 selector。

## `MGBCURRENT` v1

`activationID` 使用独立 `MGBCURRENT` domain、schema version 1、定长整数和长度 framing，绑定：

- 非零 generation。
- catalog revision、原始 payload SHA-256 和 channel。
- request selection mode。
- acknowledgement presence tag 与可选摘要。
- profile ID、revision、definition SHA-256 和 disclosure SHA-256。
- game ID、展示版本和小写 build fingerprint。
- runtime ID 和 runtime definition SHA-256。
- install ID 和 artifact SHA-256。
- plan policy version 和 canonical plan SHA-256。
- tree seal version 和 tree SHA-256。
- selected compatibility tier。

selection mode 与 tier 分别绑定：例如 request 可以处于 experimental mode，但 selector 仍可能
选中标准 profile；身份不能把两者混为一个字段。

## 标准与实验确认

标准 profile 不需要风险确认。record 的 `acknowledgementSHA256` 为 `nil`，canonical activation
digest 写入单字节 tag `0`，避免“无摘要”和其他字段拼接产生歧义。

实验 profile 必须先由 selector 找到 request 中精确的 `ProfileAcknowledgement`。builder 不直接
信任调用方提供的任意摘要，而是重新生成 required acknowledgement，再用 `MGBACK` domain、
version 1 绑定：

- catalog revision。
- catalog payload SHA-256。
- profile ID。
- profile revision。
- disclosure digest。

`MGBCURRENT` 写入 tag `1` 和该 `MGBACK` SHA-256。catalog payload、profile revision 或 disclosure
任一变化都会要求新的精确确认，并形成不同 activation identity。

## Catalog、profile 与 game

record 显式保存 catalog revision/payload/channel，便于未来 current reader 与当次可信目录对账。
profile definition digest 还绑定游戏范围、启动参数、环境和风险声明；record 另存 profile ID/
revision、disclosure digest、game ID/version/build fingerprint，提供可审计的精确身份。

这些字段不能替代目录验签、有效期或撤销检查。持久 current 在每次使用前仍必须重新加载可信
catalog，并按当前机器能力和确认状态重新授权。

## Generation

generation 必须大于零并进入 `activationID`，相同选择在不同 generation 下产生不同身份。但
builder 不读取旧 current；`activateFirst` 固定 generation 1，`activateReplacingCurrent` 则对 trusted
expected generation 做 checked `+1`，溢出失败。磁盘 exact CAS 防止 stale expected 覆盖新状态。

## Current 文件事务

`activateFirst` 与 install 共用 `.publish.lock`，先对确定性版本路径执行 receipt、inventory 和
payload full verify。`current.json` 必须严格为 `ENOENT`；任何已有 file、symlink、directory 或
其他类型都保持不变。

store 将 sorted-key record 写入 `0600` 的 `.current.<uuid>.tmp`，`fsync` 并逐字节读回。pre-commit
hook 后再次复验 installed、temp、root 和 current 缺失，再检查取消并以 `RENAME_EXCL` 提交。
成功后 `fsync(root)` 并复验最终 current 字节与 inode。

rename 前取消会清理 temp；rename 后 current 已可见，迟到取消不回滚。提交后错误通过
`currentVisible` 的 durability 标志区分 root 同步前后状态。

替换 API 接受由先前 builder/store 返回、只能编码的 `expectedCurrent` capability。持锁后先确认
磁盘 current 是安全普通文件，且 bytes/device/inode 与 expected 精确一致；同大小篡改或 stale
generation 都返回 `currentChanged`。pre-commit hook 后再次复验 expected current、新 installed、
新 temp 和 root。

CAS 只使用 `renameatx_np(..., RENAME_SWAP)`，不提供非原子 fallback。swap 后旧 current 位于新
temp 名下；store 先 `fsync(root)`，再分别复验新/旧 bytes 与 inode。旧 temp 仍匹配 expected 才
安全 unlink，随后第二次 `fsync(root)` 并终检新 current/root。

swap 前取消保留旧 current并清理新 temp；swap 后不自动回换，任何后续错误以 committed state
报告。`rollbackCurrent` 是薄包装：调用方提供目标旧 installed/profile、最新可信 catalog/request
和 trusted expected，builder 重新 selector，store 重新 full verify，并执行 checked generation
`+1` CAS。A→B→A 的 generation 为 1/2/3，第三次 activation ID 必须不同于第一次；stale expected
仍返回 `currentChanged`。更多故障测试和面向用户流程仍待补充。

## 编码与信任边界

`RuntimeActivationRecord` 是 `Encodable`、`Equatable`、`Sendable`，不是 `Decodable`。内部
decoder 经 untrusted DTO、ack/tier/activationID 和 canonical exact bytes 检查后才能重建自洽值；
这仍不能把任意磁盘 JSON 提升为可信启动能力。

`resolveCurrent` 已实现 64 KiB canonical current read、两次 installed reopen、latest
selector/ack、同 generation builder exact equality 和 final current/root 复验；返回值仍只是
锁内 snapshot。

当前没有：

- 将 resolved snapshot 紧邻接入实际启动并在 launch 前再复验。
- 更多 rollback 故障测试、面向用户流程与恢复策略。
- 失败后的文件系统、版本目录或内容寻址缓存 rollback。
- Wine prefix 切换、游戏启动、登录、持续运行或性能验收。
