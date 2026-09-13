# 原神国服预下载机制研究

日期：2026-09-04。仅阅读源码、查询公开元数据；未下载游戏资源、未改游戏目录。

## 实时证据

对源码中既有的官方 `getGameBranches` 国服查询进行只读请求，响应 retcode=0：

```json
{"main":{"tag":"7.0.0","branch":"main"},"pre_download":null}
```

仅保留分支／版本，不保存或输出 package password。当前预下载分支为空，不代表下次不会开放；不能据此验证 7.1 内容或下载体积。

接口：`https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGameBranches`，使用本地上游已记录的国服游戏 ID 与 launcher ID。

## 当前实现为什么不等于预下载

本项目 `script/download_genshin_cn_full.py` 以 `do_install=True`、`predownload=False` 运行，按完整目标清单复用相同文件、重下变化文件。不能把这个脚本的 predownload 改成 True 就当作安全预下载：它仍会重写 config.ini、标记文件及目标游戏内容。

预下载应保留当前版本和启动能力，只写独立缓存。上线后必须重新查询正式分支，确认目标清单身份并校验缓存，不能仅凭版本文字相同直接信任旧缓存。

## 两条实现路线

### YAAGL 的 ldiff 补丁路线

- 通过 `pre_download` 或 `main` 分支选择目标版本。
- 根据已安装版本选择对应 PatchInfo；下载 patch_id 指定的补丁到 ldiff 缓存。
- 预下载模式不应用补丁、不删除旧文件、不更新 config.ini；正式更新用 hpatchz 将旧文件与补丁合成为临时新文件，校验后替换。
- 当前固定源码及此次读取的上游默认分支都在国服更新 URL 分支保留 `assert False, "TODO"`。
- 缓存补丁复用目前主要检查大小，源码仍标注 hash TODO；预下载模式还跳过新增文件下载。因此不可照搬并宣称等价于官方完整流程。
- 当前流程依次替换文件，不能直接当作整版本事务。我们仍需补整体失败恢复和切换门禁。

来源：[YAAGL sophon_api.py](https://github.com/yaagl/yet-another-anime-game-launcher/blob/3ade3364151fa8088e54cbb1f049b21f119cc796/sophon_server/sophon_api.py)、[任务编排](https://github.com/yaagl/yet-another-anime-game-launcher/blob/ca78abc29c2fc236261d088c6907d28cab6e9476/sophon_server/tasks.py)。

### Collapse 的内容块差异路线

Hi3Helper.Sophon 的 `SophonUpdatePreload` 示例读取旧／新两份清单，枚举更新资产；Preload 调用 DownloadDiffChunksAsync 将差异缓存到 chunk_collapse，Update 调用 WriteUpdateAsync，传入旧目录、新目录和缓存目录。示例还提供独立的 PreloadPatch／UpdatePatch 路径，说明内容块复用与二进制差分补丁并不是同一件事。

来源：[README](https://github.com/CollapseLauncher/Hi3Helper.Sophon)、[更新／预下载示例](https://github.com/CollapseLauncher/Hi3Helper.Sophon/blob/main/Test/SophonUpdatePreload/Program.cs)。这是开源实现证据，不是 HoYoPlay 私有实现的完整规格。

建议优先验证内容块差异路线：利用已有完整清单下载能力，复用旧文件中可验证的内容，仅下载新内容；国服 ldiff 接口完成验证后再作为更省流量的优化，不能因为接口未通而退回整包预下载。

## 建议的产品行为（尚未实现）

1. 检查正式和预下载分支；未开放则不显示预下载按钮。
2. 缓存目标版本清单及身份，计算网络下载量与磁盘峰值。按版本／渠道／内容标识隔离缓存，支持续传和完整性检查。
3. 用户点击预下载后只写缓存，旧版游戏仍可用。显示“预下载完成，等待版本开放”，不能提前显示新版已安装。
4. 正式版上线后重新核对清单和缓存；仅补下载缺失或变化部分。关闭游戏，在暂存目录合成目标文件并校验。
5. 校验完成后切换版本、写入版本标记；失败保持旧安装或明确要求恢复，不能继续使用无保障的“旧版仍可启动”提示。
6. 登录／持续运行与 120 FPS 实验兼容单独验收。文件更新成功不能证明游戏可玩；文件回退也不能绕过服务端最低版本要求。

## 用户需要提供什么

- 现在不需要账号、密码、抓包、整包游戏或额外安装 Docker／官方启动器。
- 预下载开放时，告知“已开放”即可重新查公开接口；一张官方启动器中包含当前版本、目标版本和预下载大小的截图有助于对比。
- 如恰好有 Windows 官方启动器，预下载完成后保留其缓存并提供所在文件夹路径更有价值。先查看文件名／大小和脱敏日志，再决定是否需要一个小样本；不要求上传几十 GB 文件，不索要登录令牌。
- 核心待验证证据是 7.0 → 7.1 的真实预下载清单、正式开放后的清单变化，以及缓存复用和断电／中断恢复测试，而不是用户凭证。
