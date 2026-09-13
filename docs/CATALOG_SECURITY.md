# 兼容目录安全模型

## 可信入口

远程目录采用整体签名 envelope。签名对象是下载到的原始 payload 字节，避免 JSON 字段顺序或重新编码造成歧义。公钥由应用内置信任库按 `keyID` 选择，并绑定允许签署的 stable/testing channel。

`SignedCatalogLoader` 依次验证：

1. envelope 格式和可信 key ID。
2. Ed25519 签名。
3. JSON schema、引用、供应链字段和验证记录。
4. 有效期、最低客户端版本和显式 revision policy。

生产调用没有默认 revision policy：远程更新必须显式使用
`newerThan(lastAcceptedRevision)`，其中 `lastAcceptedRevision` 必须来自持久化的上次验签结果，
不得在首次成功后继续传常量 `0`。加载本地缓存必须使用
`cached(revision:payloadSHA256:)`，同时匹配精确 revision 和上次验签的原始 payload
SHA-256。远程路径拒绝相等 revision，缓存路径拒绝相等 revision 但不同摘要的
payload。只有完成全部验证后，才能将 revision 与 payload SHA-256 作为一个状态原子持久化。
目录和 envelope 有严格大小上限。

验证成功后才生成 `VerifiedCatalog`。运行时选择器不接受裸 `CompatibilityCatalog`。

## 标准模式

标准配置需要：

- 精确游戏展示版本和 SHA-256 构建指纹。
- 固定、未撤销且已验证的运行时。
- 有限 macOS 主版本范围。
- 对每个声明支持的 macOS 主版本，存在绑定同一游戏指纹和运行时定义摘要的验证记录。
- 验证记录完成安装、启动、登录、持续运行和画面正确性门槛。

## 实验模式

实验配置可以使用候选运行时和未完成全部验收的配置，但必须提供逐项影响与恢复说明。打开总开关后仍需显式选择 profile，并提交精确的确认凭据：

```text
catalogRevision + catalogPayloadSHA256 + profileID + profileRevision + disclosureDigest
```

目录 revision、原始签名 payload、配置 revision 或风险声明变化都会使旧确认失效。
若发布端错误地在相同 revision 下替换内容，持久化 revision/digest policy 必须先在
`SignedCatalogLoader` 层拒绝它；确认凭据中的 payload SHA-256 也提供第二层约束。
实验模式不放宽签名、HTTPS、哈希、大小、许可证或撤销规则。

## 开发目录

`Catalogs/development-catalog.json` 只用于模型与工具调试。`bridge-catalog validate` 只证明语义正确，并会明确输出“unsigned development catalog”。远程更新器不得调用此入口。
