# 启动器自更新

> 2026-09-13 澄清：允许在 GitHub Releases 发布未公证 Pre-release 测试版并提供自更新。Apple 公证与 Sparkle 更新签名不同，前者未完成不禁止后者。测试版须明确未公证状态，组件和素材分发核对、实际安装与两版本升级仍需完成；不能把当前本地包视为已经发布。

采用固定版本 Sparkle 2.9.6；入口为应用菜单「检查启动器更新…」及设置「应用更新」。首次默认关闭自动检查；开启后由 Sparkle 定期检查，下载和安装由用户确认。更新只替换应用包，不移动游戏、prefix 或用户数据。游戏运行或安装维护期间拒绝开始更新检查；准备重启时再次检查，忙碌时暂缓；退出阶段还有任务保护。

## 当前状态（2026-11-12）

新构建默认内置测试版更新源 `https://raw.githubusercontent.com/huaye37/HoYoBridge/main/updates/appcast.xml` 和 Sparkle Ed25519 公钥；要求签名更新目录、下载后解压前验签。自动检查默认关闭，用户可在设置开启。0.1.5 起已开放签名测试版发布；隔离的真实 0.1.4 应用副本已完成公开包下载、验签、替换，探针重启后读回新版版本号，独立测试数据保留。没有替用户点击更新或替换正式应用。探针安装验证与用户在真实设置窗口中操作的验收应分别记录。

`v0.1.0` 及此前安装的应用没有更新源和公钥，无法自行发现首个启用更新的版本，必须先手动安装一次启用更新的版本。更新不会修改游戏目录。签名私钥仅保存在维护者 Mac 的登录钥匙串 `hoyobridge-updates` 项中，不能提交、发布或写入日志；应由维护者另行安全备份，丢失后 ad-hoc 签名应用的密钥更换可能无法平滑完成。未公证测试版的信任状态和分发素材边界见各版发行说明与第三方声明。

## 发布接线

1. 维护者确认 `generate_keys --account hoyobridge-updates -p` 返回的公钥与构建脚本内置公钥一致。保管并安全备份钥匙串中的私钥，不进仓库；不可为每次发布重新生成。
2. 设置递增的 `MGB_APP_VERSION`，运行 `MGB_BUILD_CONFIGURATION=release bash script/build_and_run.sh --package`。默认使用上述测试 feed 和固定公钥；可用 `MGB_DISABLE_UPDATES=1` 做不含更新配置的隔离构建。可覆盖 `MGB_UPDATE_FEED_URL` 和 `MGB_SPARKLE_PUBLIC_KEY` 用于独立测试，覆盖时必须同时指向匹配的测试签名身份。这一步仍是开发签名，不代表公证发行包。
3. 未公证测试版保留可验证的应用完整性签名，在发布说明标记 ad-hoc／未公证及验证范围；未来公证版用 Developer ID 签名嵌套组件与应用、完成公证并 staple，再重新 ZIP 和计算 SHA256。两种情况下均不要在签名 appcast 后重新改 ZIP。
4. 将最终 ZIP 放进专门的 release 目录，执行 `bash script/prepare_appcast.sh RELEASE_DIRECTORY https://github.com/huaye37/HoYoBridge/releases/download/vVERSION/`。工具从钥匙串读取私钥，生成带 EdDSA 签名的 appcast；脚本只生成，不发布。版本目录必须替换为真实、不可变的下载地址。
5. 发布版本固定地址的 ZIP，确认附件匿名可下载并与本地哈希一致，然后将生成、验签后的 appcast 原样同步至公开仓库 `updates/appcast.xml` 并推送。不可手动改签名后的 XML；测试版 feed 固定追踪 main，不依赖 `/releases/latest`。验证客户端发现、验签、替换与重启成功后才能称自更新已验收。

## 验收边界

配置校验、构建和 UI 验证不等于完整自更新验收。正式上线前必须用两个递增版本验证：旧版发现新版 → 下载 → 验签 → 替换 → 重启 → 游戏目录及设置保留；另测断网、损坏签名、忙碌任务暂缓与恢复。缺真实签名密钥/公开源时不能声称该端到端流程已通过。

参考：[Sparkle 官方文档](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)。
