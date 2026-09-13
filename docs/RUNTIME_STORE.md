# Versioned runtime store

`VersionedRuntimeStore` 把 managed-download runtime、`SafeArchivePlan` 和受控内容 source 组合成
一个版本目录。正常路径发布全新版本；若相同 install ID 已存在，只在本次可信 expected receipt
和 tree 与目标精确一致时复用。store 可安全 reopen installed、创建/CAS/rollback current，并在新实例中 resolve current；仍无 runtime 启动。

## 目录布局

```text
runtime-root/                         # 调用方预先创建，owner，0700
  .publish.lock                      # 持久普通文件，0600，不删除
  current.json                       # activateFirst 成功后才存在，0600
  .current.<uuid>.tmp                # create/swap 使用的唯一临时文件
  .staging/                          # owner，0700
    <uuid>/
      payload/                       # store-owned SafeStagingExtractor 输出
      install.json                   # sorted-key RuntimeInstallRecord，0600
  versions/                          # owner，0700
    <installID-prefix>/
      <installID>/
        payload/
        install.json
```

`installID-prefix` 是小写 install ID 的前两个字符。路径不使用 URL 文件名、runtime version 或
归档内路径。

## Root 与发布锁

- root 必须已经存在；store 不创建它。
- root 必须是绝对 canonical file URL，每一级祖先都必须是真实目录而非 symlink。
- root 必须由当前用户拥有且权限严格为 `0700`；路径侧身份在事务前、rename 前和提交后复核。
- `.publish.lock` 是同卷、owner、`0600`、单链接普通文件。首次创建后 `fsync` 文件与 root。
- store 使用 `flock(LOCK_EX | LOCK_NB)`。busy 立即返回，不等待，也不会创建本次 staging wrapper。
- lock 文件是持久协调点；释放锁只 `LOCK_UN`/close，不 unlink。

## 输入预检

创建文件系统事务前先拒绝非 managed-download、未确认再分发、空许可证、无效 artifact SHA-256/大小、不支持的 plan policy，以及 runtime 与 plan 大小错配。

`runtime.byteSize` 必须等于 `plan.archiveByteSize`。这是身份与解压膨胀比分母预检，不是新的
磁盘可用空间检查；下载/CAS 容量检查仍属于现有 capacity preflight。

## Store-owned extraction

store 在 `.staging` 下创建唯一 UUID wrapper，再把尚不存在的 `payload` URL 交给
`SafeStagingExtractor.extract`。外部调用方不能把任意已有 tree 直接交给 publish API。

extractor 返回 sealed candidate 后，store 构建 `MGBINSTALL` v1 record，并执行第一次
`SafeStagingExtractor.reverify`。失败或取消仍处于 rename 前，会清理本次唯一 wrapper；若安全
清理也失败，则同时保留 install 与 cleanup 错误。

## Receipt 与 wrapper 复验

- `install.json` 由 store 以 sorted-key `JSONEncoder` 生成，使用 `O_EXCL|O_NOFOLLOW` 和 `0600`。
- receipt 写完后 `fsync`，关闭前后复核 device/inode、类型、owner、link count、mode 和大小。
- store 从只读 FD 精确读回预期字节，并拒绝短读、额外字节或内容变化；不靠 decode 信任 JSON。
- wrapper 的精确 inventory 只能是 `install.json` 和 `payload`。
- payload root 必须匹配 extractor 交接的 device/inode；receipt 也绑定其创建时身份。
- receipt 写入后先复验 wrapper；准备 rename 前，再次完整 reverify payload 并重新读回 receipt。

这里的“canonical receipt”指本实现生成的 sorted-key 确定性字节和逐字节读回，不表示接受任意
外部 JSON 作为可信 record。

## 原子提交

目标为 `versions/<prefix>/<installID>`。`.staging`、wrapper、`versions` 和 prefix 必须位于 root
同一文件系统；跨卷直接失败。

rename 前最后核对 root、wrapper path identity 和任务取消。唯一提交点是：

```text
renameatx_np(staging, wrapper, prefix, installID, RENAME_EXCL)
```

成功后版本立即可见。store 随后 `fsync` 目标 prefix 和源 `.staging`，再从最终版本路径重新
reverify payload、逐字节检查 receipt、核对 wrapper/root 身份。

## EEXIST 与精确复用

如果 `RENAME_EXCL` 返回 `EEXIST`，store 以本次安全输入重新构建出的 receipt 和 sealed candidate
作为唯一 expected，不从已有 JSON 恢复信任：

目标必须是同卷 owner `0700` 真实目录，inventory 精确为 `install.json`/`payload`。`install.json`
必须是 `0600` 单链接普通文件并与 expected bytes 完全一致；payload 用实际 device/inode 和
expected seal 完整重哈希。wrapper、target path inode 与 root 终检全过后，才清理本地 wrapper
并返回 `reusedExisting`；store 不 decode existing receipt。

任一步失败都返回 `corruptExistingVersion`，保留并且不修改、覆盖、删除或修复 existing target；
清理范围只限本次本地 wrapper。receipt 或 payload 即使只是同大小内容变化也会失败关闭。

独立 `reopenInstalled` 不接受裸 runtime/URL：它在同一锁/dirfd 边界内限长 128 MiB 读取 receipt，经 canonical decoder 后与 catalog 中唯一 managed、未 blocked/撤销的 runtime definition/artifact
对账，再 full reverify payload 与 target/root identity，成功返回 `reopenedExisting`。这只证明
self-consistency/catalog identity，不是同 uid 篡改的密码学来源证明。

## 取消与 commit state

- rename 前：取消和普通错误都应清理本次唯一 wrapper；没有版本对外可见。
- rename 成功：版本已提交，不再清理，即使随后收到取消。
- rename 后、目录同步失败：抛出 committed error，状态为 `versionVisible`，durability 未确认。
- 目录同步成功后的非取消错误：抛出 committed error，版本可见且 durability 已确认。
- rename 后的迟到取消：返回 `InstalledRuntimeVersion`，不把成功提交伪装成未安装。

调用方必须按 commit state 决定恢复动作，不能看到 error 就删除版本目录。

## Current create 与 exact CAS

`activateFirst` 与 install 使用同一把持久 `.publish.lock`，固定构建 generation `1` 的
`MGBCURRENT` record，并从 install record 重建 expected receipt/tree，对确定性版本路径执行完整
receipt、inventory 和 payload reverify。

首次激活要求 `current.json` 严格为 `ENOENT`。任何普通文件、symlink、目录或其他已有对象都返回
`currentAlreadyExists` 且保持不变。store 将 sorted-key activation bytes 写入同卷、owner、`0600`
的唯一 `.current.<uuid>.tmp`，`fsync` 后逐字节读回并固定 device/inode。

pre-commit hook 返回后，store 再次检查 current 缺失、installed full verify、temp 精确字节/身份
和 root identity，再检查取消并用同目录 `RENAME_EXCL` 提交。成功后 `fsync(root)`，复验最终
current 字节、继承的 temp inode 和 root identity。

rename 前错误/取消会删除并同步 temp；rename 后迟到取消返回成功。提交后错误用
`currentVisible(activationID:durabilityConfirmed:)` 区分 root 同步前后的状态。

`activateReplacingCurrent` 接受调用方持有的 `Encodable` expected record 作为 capability，验证
其格式并以 checked `generation + 1` 构建新 activation。在同一发布锁内，磁盘 current 必须在
hook 前后都与 expected bytes/inode 精确一致；新 installed version 和新 temp 也二次复验。

提交只使用 `RENAME_SWAP`，不支持时直接失败、没有覆盖 fallback。swap 后先 `fsync(root)`，再
逐字节/逐 inode 核对新 current 与落到 temp 名下的旧 current；旧 temp 身份仍正确才 unlink，
随后第二次 `fsync(root)` 并终检新 current/root。stale expected、同大小篡改或异常类型失败关闭。

swap 前取消清理新 temp且旧 current 不变；swap 后不自动回换，错误以 committed state 报告。
`rollbackCurrent` 是同一 CAS 的薄包装：旧 installed/profile 加最新可信 catalog/request 会重新 selector/full verify，并以 trusted expected 生成 checked `generation + 1`。
A→B→A 为 1→2→3 且产生新 activation ID；stale expected 失败。更多故障测试/产品流程仍待补充。

## 尚未完成

- 固定版本 libarchive 和真实 ZIP/tar/7z 内容 source。
- 将 `resolveCurrent` 返回的锁内 snapshot 紧邻接入实际启动，并在 launch 前再复验。
- 版本/失败 staging GC、保留策略和磁盘配额管理。
- Wine prefix 创建、游戏启动、登录、持续运行和性能验收。
