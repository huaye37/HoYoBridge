# 发行交接

## 当前决定（2026-09-13）

- 用户已澄清允许 GitHub 未公证 Pre-release 测试版及自更新；此前禁止所有发布的解释已撤销。显著注明未公证和验证范围，不标记为公证稳定版。
- 仓库 `huaye37/HoYoBridge` 已公开，main 已推送；[v0.1.0](https://github.com/huaye37/HoYoBridge/releases/tag/v0.1.0) 已发布为未公证 Pre-release，包含安装 ZIP 与 SHA256 校验文件。源码采用干净初始历史，不公开本机旧调试历史。
- 本机 441 项测试通过，release 优化构建和解压签名／架构／标识／SHA256 验证通过；这不等于干净 Mac 或所有游戏端到端验收。CI 配置暂存 `.github/ci-reference.yml`，当前凭证缺工作流写入权限，尚未启用。
- 自更新客户端已接入 Sparkle，尚无正式源和密钥，不等于端到端验收完成。
- 仅支持四款国服官服；国际服和渠道服不在支持范围。
- 第三方组件和角色／官方素材的公开分发义务仍需处理。声明不替代授权，详见 `THIRD_PARTY_NOTICES.md`。
- 当前说明见 `README.md`、`LAUNCHER_SELF_UPDATE.md` 与 `CURRENT_WORKING_CONTEXT.md`。

## 历史记录（2026-09-07，以下不是当前状态）

用户选定的四人合影图标已固定，后续不再重绘。

本机全量测试：426 tests / 55 suites 通过，日志
`/tmp/mgb-final-full-tests.log`。本轮不下载、重装、更新或删除游戏。

发行构建使用 `MGB_BUILD_CONFIGURATION=release bash script/build_and_run.sh --package`，
与之前默认 debug 构建区分。产物仍是本机 ad-hoc 签名包，不是公证发行包。

## 发布阻塞

- `git remote -v` 为空。需用户指定 GitHub owner/repo 及发布授权，不能凭空配置自身更新源或发布源码。
- 本机只有 Apple Development 证书，没有 Developer ID Application；公证与另一台干净 Mac 的验收尚未完成。
- 打包用到未入库的 LocalRuntimes 固定资产，干净 CI 的发行打包及组件/角色素材分发许可仍未闭环。

## 不能当成已验收的内容

- 三款维护接口与中断状态已接入；真实新版本更新、修复、引擎断连恢复未运行。
- 三款通用迁移、卸载与缓存清理尚未完成；现有原神存储能力不代表四款一致。
- GitHub 自身更新、正式发布、预下载未完成。

该包供本机测试，不能标记为四游戏正式下载即用发行版。
