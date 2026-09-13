# 托管产物网络下载

## 当前切片

`ManagedArtifactDownloader` 实现托管运行时产物的全量下载和显式 HTTP Range 续传。它不使用
`URLSession` 的 opaque `resumeData`，也不负责游戏资源协议、限速、解压或安装。

流程为：

```text
签名 RuntimeDefinition
  -> artifact SHA-256 对应的非阻塞 flock lease
  -> 同卷/跨卷容量预检
  -> fresh GET，或 Range + If-Range
  -> 0600 partial + 脱敏 resume metadata
  -> 实际大小与 SHA-256
  -> ContentAddressedArtifactStore 原子发布
```

## 网络边界

- 初始 URL 和每个重定向都必须是 HTTPS、无 userinfo、默认 443 端口，并命中调用方显式
  提供的 host allowlist。
- 单标签主机、`localhost`、`.localhost`、`.local` 和 IP literal 被拒绝。生产 allowlist
  仍必须只包含项目内置的公开下载域名；本层不把签名目录中的任意 host 自动视为可信。
- 重定向数量有限；被拒绝的 URL 错误只记录 scheme/host/port，不记录可能含令牌的路径或查询。
- 使用 ephemeral `URLSession`，关闭 cookie、URL cache 和 credential storage。请求声明
  `Accept-Encoding: identity`，响应若仍带其他 `Content-Encoding` 则拒绝。
- 续传请求使用 `Range: bytes=<partial-size>-` 和强 ETag，或相对响应 `Date` 至少早 60 秒的
  严格 HTTP-date `Last-Modified` 作为 `If-Range`；重定向后会重新附加这三个请求头。
- 续传只接受精确覆盖剩余字节的 206：final URL 摘要、validator、`Content-Range`、
  `Content-Length` 和总大小必须全部一致。服务器返回 200 时，在写入响应 body 前先将 partial
  截断并 seek 到 0，再按 fresh 完整响应处理，绝不会把 200 body 追加到旧前缀。
- 单次请求无进展超时为 60 秒，整个全量传输最多 24 小时；本层不会无限等待网络恢复。
- 不实现 TLS challenge 放行逻辑，证书与主机名继续使用系统默认信任验证。

## 文件与提交边界

- 下载根、`.partial` 和 `.leases` 必须由当前用户拥有且严格为 `0700`。partial、metadata 和
  lease 都只由预期 artifact SHA-256 定位，远端文件名不进入路径。
- 同一 artifact 的 `.leases/<sha>.lock` 使用内核 `flock(LOCK_EX | LOCK_NB)`；lease 文件保持
  存在，避免 unlock/unlink 造成新旧 inode 并发锁竞态。
- 已有 partial 和 metadata 均用 `O_NOFOLLOW` 打开，并通过 `fstat` 验证普通文件、当前用户、
  `0600` 和单链接。metadata 有大小上限，只保存 source/final URL 的 SHA-256 摘要、预期
  size/hash、durable byteCount 及 strong ETag 或 Last-Modified，不保存完整 URL、路径或 token。
- checkpoint 先 `fsync` partial，再以相同目录的 0600 临时文件写入 metadata、`fsync`、原子
  rename 并同步父目录；load 要求 metadata byteCount 与 partial 实际长度完全一致。
- 读取过程中始终执行硬字节上限，结束时再次要求精确大小，并由 `ArtifactVerifier` 做完整
  SHA-256 校验。
- 取消或明确列出的瞬时 `URLError`，只有在已取得有效 validator 且 partial 是非空未完成前缀时
  才 checkpoint 保留。TLS、重定向、响应头、range、validator、哈希、写盘及 HTTP 状态失败
  会删除 partial 和 metadata；416 同样失败关闭。
- 完整 size 与 SHA-256 验证通过后，仍由 `ContentAddressedArtifactStore` 再次复制、校验并以
  `RENAME_EXCL` 原子发布，随后清除 resume state。本层不会把下载文件直接当成已安装运行时。

## 容量与维护

- 网络请求前读取 download root 与 artifact store root 的真实文件系统设备和可用块。同卷要求
  `剩余 partial + 完整 store staging + 1 GiB 默认余量`；跨卷分别检查下载增量和完整 staging，
  两侧各保留余量。所有块乘法和字节加法都检查溢出。
- 有效 resume 在容量或 store 根准备失败时保持不变，不会为了预检失败删除已经验证的前缀。
- `DownloadPartialGarbageCollector` 只由调用方显式运行。它仅识别规范 SHA-256 对应的 part、
  metadata 和原子 metadata 临时文件；每个候选必须先取得持久 lease，再验证 uid、`0600`、
  普通文件、单链接和过期时间。busy、符号链接、目录、FIFO 或硬链接均不删除。
- 每个发生删除的候选立即同步 `.partial` 目录；lease 文件永久保留，避免 unlink 后新旧 inode
  同时被不同进程锁住。

## 后续切片

后续仍需加入速率限制和真实 HTTPS 集成测试。当前网络验证全部使用离线 `URLProtocol`，
不代表真实 CDN 已通过。
