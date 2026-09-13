# 启动器自更新

> 2026-09-13 澄清：允许在 GitHub Releases 发布未公证 Pre-release 测试版并提供自更新。Apple 公证与 Sparkle 更新签名不同，前者未完成不禁止后者。测试版须明确未公证状态，组件和素材分发核对、实际安装与两版本升级仍需完成；不能把当前本地包视为已经发布。

采用固定版本 Sparkle 2.9.6；入口为应用菜单「检查启动器更新…」及设置「应用更新」。首次默认关闭自动检查；开启后由 Sparkle 定期检查，下载和安装由用户确认。更新只替换应用包，不移动游戏、prefix 或用户数据。游戏运行或安装维护期间拒绝开始更新检查；准备重启时再次检查，忙碌时暂缓；退出阶段还有任务保护。

## 当前状态

已接入客户端及 framework 打包；没有配置正式更新源和真实公钥的开发版明确显示尚未开放，不请求伪造的 feed，也不声称已经是最新版。反馈功能暂缓，没有玩家提交入口。

GitHub 仓库在 2026-09-09 检查时仍为私有。面向普通玩家的更新 XML 和 ZIP 必须无需登录即可读取；不得把维护者 GitHub token 嵌入客户端。公开仓库或部署独立公开更新站需由维护者决定。

## 发布接线

1. 首次在维护者 Mac 执行 `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account hoyobridge-updates`。私钥保留在登录钥匙串并安全备份，不进仓库。将输出的公钥用于以下构建变量。
2. 设置 `MGB_UPDATE_FEED_URL`（稳定 HTTPS appcast 地址）、`MGB_SPARKLE_PUBLIC_KEY`（32 字节 Ed25519 公钥的 base64）及递增的 `MGB_APP_VERSION`，运行 `bash script/build_and_run.sh --package`。这一步仍是开发签名，不代表公证发行包。
3. 未公证测试版保留可验证的应用完整性签名，在发布说明标记 ad-hoc／未公证及验证范围；未来公证版用 Developer ID 签名嵌套组件与应用、完成公证并 staple，再重新 ZIP 和计算 SHA256。两种情况下均不要在签名 appcast 后重新改 ZIP。
4. 将最终 ZIP 放进专门的 release 目录，执行 `bash script/prepare_appcast.sh RELEASE_DIRECTORY https://github.com/huaye37/HoYoBridge/releases/download/vVERSION/`。工具从钥匙串读取私钥，生成带 EdDSA 签名的 appcast；脚本只生成，不发布。版本目录必须替换为真实、不可变的下载地址。
5. 发布 ZIP 及 appcast；测试版必须使用独立、稳定的测试 feed 地址或明确版本地址，不依赖 `/releases/latest/download/appcast.xml` 自动发现 Pre-release。未来正式版才可考虑该 latest 地址。先确认匿名 HTTPS 下载及 feed 指向正常，再发布首个启用更新的客户端；私有仓库链接不能充当普通玩家可访问的更新源。

## 验收边界

配置校验、构建和 UI 验证不等于完整自更新验收。正式上线前必须用两个递增版本验证：旧版发现新版 → 下载 → 验签 → 替换 → 重启 → 游戏目录及设置保留；另测断网、损坏签名、忙碌任务暂缓与恢复。缺真实签名密钥/公开源时不能声称该端到端流程已通过。

参考：[Sparkle 官方文档](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)。
