# 上游复用策略

## 证据快照

2026-08-19（Asia/Shanghai）对官方仓库
[`yaagl/yet-another-anime-game-launcher`](https://github.com/yaagl/yet-another-anime-game-launcher)
进行了临时目录浅克隆和静态代码核对：

- `origin/HEAD` 指向 `refs/heads/main`，`origin/main` HEAD 为
  [`ca78abc29c2fc236261d088c6907d28cab6e9476`](https://github.com/yaagl/yet-another-anime-game-launcher/commit/ca78abc29c2fc236261d088c6907d28cab6e9476)。
- 远端最高稳定 SemVer tag 为 `0.3.18`，也指向该提交。
- 下文的 YAAGL 路径和行号均固定到该提交。此次只检查了源码和远端 Git refs；没有构建或运行 YAAGL，没有调用线上 Sophon 接口，也没有验证下载、更新、游戏启动、登录、持续运行或性能。因此这里描述的是可见代码路径，不是已运行能力。

## YAAGL 与 MIT 复用边界

YAAGL 根许可证允许使用、复制、修改、合并、发布、分发和再许可，但复制件或实质性部分必须保留版权与许可声明，且软件不提供担保（YAAGL `LICENSE:1-20`）。Sophon 实现自身还带有 `SPDX-License-Identifier: MIT` 和 Krock 的版权声明（YAAGL `sophon_server/sophon_api.py:1-3`）。因此复用 YAAGL 源码时必须：

- 记录官方仓库、提交、原始路径和本地修改，并在复制的文件或第三方声明中保留相应版权与 MIT License。
- 优先提取边界清晰的协议适配、manifest 模型和任务进度设计，不继承整个 UI、权限模型或发布流程。
- 不把仓库根 MIT License 外推为所有依赖和数据的许可。仓库内 aria2 为 GPLv2（YAAGL `sidecar/aria2/LICENSE.txt:1-7`），7zz 包含 LGPL、unRAR 限制和 BSD 条款（YAAGL `sidecar/7z/License.txt:1-14`），xdelta 为 Apache-2.0（YAAGL `sidecar/xdelta/LICENSE.txt:1-5`）；Wine、DXMT、游戏资源、官方服务条款和 Apple GPTK/D3DMetal 仍需分别审查。

## YAAGL sidecar 消费官方 Sophon 数据的链路

这是一条由 YAAGL 逆向实现的客户端链路，不是官方发布的稳定接口规范：

1. 原神 channel client 在随机高位端口启动本机 `./sidecar/sophon_server/sophon-server`，只把 host 设为 `127.0.0.1`，然后查询线上版本信息（YAAGL `src/clients/mhy/hk4e/index.tsx:82-100`，`createHK4EChannelClient`）。
2. TypeScript `SophonClient` 通过 `POST /api/install|repair|update` 创建任务，通过 `/ws/{task_id}` 接收进度；取消接口在注释中明确只有 Python 侧的部分支持（YAAGL `src/sophon.ts:72-188`，`startGameOperation`、`streamOperationProgress`、`cancelOperation`）。FastAPI sidecar 再把请求分派到 `perform_install`、`perform_repair` 或 `perform_update`（YAAGL `sophon_server/server.py:45-95`，`run_task`、`handle_game_operation`）。
3. Python `SophonClient.retrieve_API_keys` 根据 `os/cn/bb` 和游戏 ID 调用 `getGameBranches`，从 `game_branches[0][main|pre_download]` 取得 `branch`、`package_id`、`password` 和版本 tag（YAAGL `sophon_server/sophon_api.py:621-679`）。源码同时明确警告 `CN/BB is yet not tested`（同文件 `:629-635`）。
4. `make_getBuild_url` 把这些字段组成 `/downloader/sophon_chunk/api/getBuild|getPatchBuild` URL；`get_getBuild_json` 对新文件读取 `getBuild`，对增量补丁以 POST 读取 `getPatchBuild`（YAAGL `sophon_server/sophon_api.py:693-744`）。
5. `_select_category` 从返回 JSON 的 `data.manifests` 选中 `game` 或语音类别，下载 `manifest_download.url_prefix/{manifest.id}`，zstd 解压后分别解析为 chunk `Manifest` 或 ldiff `DiffManifest` protobuf（YAAGL `sophon_server/sophon_api.py:747-830`）。chunk manifest 描述文件路径、整文件 MD5、偏移、压缩/解压大小和 chunk 校验字段（YAAGL `sophon_server/manifest.proto:7-26`）；diff manifest 描述补丁、源/目标 MD5 与待删除文件（YAAGL `sophon_server/manifest_ldiff.proto:8-60`）。
   `DiffManifest` 是上游 wire message 的原名，不能机械重命名为本项目的 `LdiffSelection`。后者是 wire decoder 针对 requested source 完成 selected/unselected/deletion 分类后的领域结果；不能把每个 wire file record 都假设为已选 patch。
   当前 `yaagl-ca78abc-sophon-protobuf-structural-v1` 只把该固定 proto/comment 锁成 structural baseline：scanner 后以 generated types decode、递归拒绝 unknown，完整验证所有 source 的 raw patch/delete records，再按 exact requested source 选择并进入本地 validators。chunk `xxhash` 只保留 `UInt64` numeric claim；`patch_name`/`original_name` 安全保留但不推断其与 patch ID/outer path 的关系；delete empty hash 只映射为 nil claim。这些是本项目对固定快照的失败关闭解释，不是已观察国服协议事实。
   2026-08-20 的受控国服 manifest 观测另确认 `ChunkInfo` field 7 / wire type 2：107,480 次、全部 32-byte lowercase hex。随后单 chunk 实测确认所选样本的 field7 等于压缩字节 MD5，field2 等于 zstd 解压后 MD5；这仍只是一个当前国服样本的 profile 证据，不是全局协议保证。
   真实压缩字节与本地 proto field6 的 seed-0 XXH64 不匹配。当前 Hi3Helper.Sophon commit `2c0868e34d2fd8d11099eb83e88e0476d28bf871` 的 `Protos/SophonManifestProto.proto` 仅定义 field1–5；`Helper/Extension.cs` 从 `ChunkName` 的 16-hex 前缀取 XXH64，并在解压后 stream 上比较。因此 MacGameBridge 保留 field6 numeric claim 用于漂移检测，但不用它授权 payload。
6. 普通更新任务的可见顺序是：删除旧文件、下载并应用 ldiff、用 chunks 补齐新文件，再刷新 manifest、更新 `config.ini` 版本并删除 ldiff（YAAGL `sophon_server/tasks.py:142-179`，`perform_update`）。新文件会先落到 tempdir、做整文件 MD5 后再移动到游戏目录（YAAGL `sophon_server/sophon_api.py:914-1025`，`download_game_file`）。

这些结构可作为协议研究和 structural mapper 输入；正式启用国服 endpoint/profile 仍必须用当前国服响应样本和可回放测试重新确认字段关系、xxhash 算法/seed/checked bytes、请求方法、鉴权参数、错误语义与版本迁移规则。

## 首期国服增量更新不能直接复用

国服 client 明确传入 `releaseType: "cn"`（YAAGL `src/clients/hk4ecn.ts:68-73`）。更新请求进入 `perform_update` 后会设置 `Options.do_update = True`，清空缓存并调用 `load_manifest`（YAAGL `sophon_server/tasks.py:142-162`）；已有 `YuanShen.exe` 且不是 Bilibili SDK 时又会被识别为 `rel_type = "cn"`（YAAGL `sophon_server/sophon_api.py:406-433`，`_initialize_update`）。

此时 `make_getBuild_url` 的 `do_update + rel_type == "cn"` 分支直接执行 `assert False, "TODO"`（YAAGL `sophon_server/sophon_api.py:693-715`）。这发生在 `load_manifest` 获取 `getBuild/getPatchBuild` 数据之前，所以该快照不能作为 MacGameBridge 首期国服增量更新器。非更新分支虽然列出了 CN `getBuild` host（同文件 `:709-713`），但结合上游的“CN/BB 未测试”警告和本次未运行边界，也只能作为研究线索，不能写成可用能力。

## 当前原神运行时边界

该快照的原神路径是 Wine + DXMT，不是可插拔的 GPTK/D3DMetal 运行时：

- 国服默认 Wine tag 为 `11.0-dxmt-signed-with-patches`（YAAGL `src/clients/hk4ecn.ts:23-25`）。`WineDistributionAttributes.renderBackend` 的类型只有字面量 `"dxmt"`，所有内置 Wine 项也都声明 DXMT（YAAGL `src/wine/distro.ts:5-81`）。
- DXMT 版本常量固定为 `0.80.0`，下载资产固定到 `v0.80/dxmt-v0.80-builtin.tar.gz`（YAAGL `src/downloadable-resource.ts:139-203`，`checkAndDownloadDXMT`）。原神 launch 路径只在 backend 为 DXMT 时下载它（YAAGL `src/clients/mhy/hk4e/index.tsx:263-275`），启动前 `patchProgram` 把 DXMT DLL 和 `winemetal` 文件写入 Wine（YAAGL `src/clients/mhy/patch.ts:66-87`），随后以 Wine 执行游戏并设置 DXMT 环境（YAAGL `src/clients/mhy/hk4e/program-launch-game.ts:90-194`）。
- 全仓唯一的 `gptk` 字样是另一个游戏 CBJQ 的旧 Wine release URL/tag（YAAGL `src/clients/cbjq.ts:8-10`）；它没有对应的 `renderBackend` 类型、选择器或 D3DMetal 实现。源码中也没有 `D3DMetal` 符号。因此不能把它描述为 YAAGL 已有 GPTK/D3DMetal backend。

上述只是硬编码配置和调用关系；本次没有证明 Wine、DXMT 0.80 或原神在目标 macOS/芯片/游戏版本上能够实际运行。

## 可借鉴与必须重做

可以借鉴：

- loopback sidecar 与 UI 解耦、HTTP 建任务、WebSocket 汇报长任务进度的边界；但取消、恢复和崩溃重入语义要另行设计。
- `getGameBranches → getBuild/getPatchBuild → zstd protobuf manifest → chunk/ldiff` 的协议分层、category 选择和 protobuf 字段模型。
- 临时文件组装、完成后再移动，以及按 manifest 做文件完整性检查的基本思路。
- install/update/repair 分离与线上版本、可更新源版本、预下载版本的领域模型。

必须重做或加固：

- **国服更新适配器**：用当前官方国服流量和响应重新实现、记录并测试 CN `getBuild/getPatchBuild`，覆盖全量安装、增量更新、预下载、断点续传、旧版本不可直升和接口漂移；不能绕过上游 `assert` 后猜 host。
- **事务与回滚**：YAAGL 会先逐个删除旧文件（YAAGL `sophon_server/sophon_api.py:1341-1375`），再把每个补丁结果直接移动覆盖原文件（同文件 `:1205-1262`），没有整次更新的提交点。MacGameBridge 必须在独立 staging 中完成下载、校验和补丁，生成变更计划与恢复点，再原子提交，并留下可重放审计记录。
- **完整性与供应链**：保留官方 manifest 的 MD5/大小校验以满足协议，同时为本地缓存、运行时和分发物增加 SHA-256、来源、版本、签名/公钥策略与失败隔离；不能把“大小相同”当成正式复用依据。
- **网络与进程边界**：YAAGL sidecar 全局关闭 TLS 校验（YAAGL `sophon_server/server.py:13-14`）；aria2 以 `--rpc-listen-all=true`、允许任意 origin 且未配置 RPC secret 启动（YAAGL `src/app.tsx:54-74`）。本项目必须保留 TLS 校验，仅监听 loopback，使用不可预测端口和进程级认证，并限制请求、路径和日志内容。
- **运行时抽象**：从模型层显式区分 Wine 发行版、图形 backend 和游戏兼容配置；DXMT 与未来经许可接入的 GPTK/D3DMetal 必须有独立能力探测、版本/哈希/许可证和回滚，不能复制只有 `"dxmt"` 的联合类型。
- **自更新与系统修改**：YAAGL 自更新会删除现有 sidecar 后直接解包 GitHub Release asset，代码路径未见签名或哈希验证（YAAGL `src/updater.ts:94-150`）；其启动路径还能以管理员权限临时编辑 `/etc/hosts`（YAAGL `src/clients/mhy/hk4e/program-launch-game.ts:133-163`）。这两种实现均不得直接移植；本项目更新必须先验签、staging、原子切换并可恢复，也不得静默修改 hosts、代理、DNS、Gatekeeper 或 SIP。

## 其他组件与跟随上游

- Wine、DXMT、aria2、7zz、xdelta、hpatchz 等分别维护来源、固定版本、哈希、许可证和源码义务；正式发行不在用户设备上无版本地拉取 `latest`。
- Apple GPTK/D3DMetal 由用户从 Apple Developer 获取 DMG，MacGameBridge 只在本地校验、导入并组装独立运行时；完成 Apple 许可审查前，不代为下载或打进公开发行包。
- 定期获取 YAAGL、DXMT 和 Wine 的上游变化，固定快照后进入测试通道。通用缺陷可向上游提交；MacGameBridge 的国服事务更新、安全边界、签名目录、运行时选择和回滚策略保留在本仓库。
