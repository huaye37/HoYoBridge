# 启动器自更新

> 2026-09-13 澄清：允许在 GitHub Releases 发布未公证测试版并提供自更新。Apple 公证与 Sparkle 更新签名不同，前者未完成不禁止后者。测试版须明确未公证状态，组件和素材分发核对、实际安装与两版本升级仍需完成；不能把当前本地包视为已经发布。

采用固定版本 Sparkle 2.9.6；入口为应用菜单「检查启动器更新…」及设置「应用更新」。首次默认关闭自动检查；开启后由 Sparkle 定期检查，下载和安装由用户确认。更新只替换应用包，不移动游戏、prefix 或用户数据。游戏运行或安装维护期间拒绝开始更新检查；准备重启时再次检查，忙碌时暂缓；退出阶段还有任务保护。

## 当前状态（2026-11-12）

新构建默认使用 `https://raw.githubusercontent.com/huaye37/HoYoBridge/main/updates/appcast.xml` 测试源和固定 Ed25519 公钥，要求更新源签名及解压前验签。初始更新源为空；真实两版本安装升级仍未验收。`v0.1.0` 等旧应用没有源和公钥，必须先手动安装一次启用更新的新版本。自动检查默认关闭。

签名私钥保存在维护者 Mac 的登录钥匙串 `hoyobridge-updates` 中；不可提交或公开，需由维护者安全备份。丢失后 ad-hoc 签名应用的密钥更换可能无法平滑完成。

## 发布接线

1. 检查 `generate_keys --account hoyobridge-updates -p` 显示的公钥与构建脚本一致。私钥保留在钥匙串，不要为每次发布重新生成。
2. 设置递增的 `MGB_APP_VERSION` 并执行 `MGB_BUILD_CONFIGURATION=release bash script/build_and_run.sh --package`。默认使用固定测试源与公钥；`MGB_DISABLE_UPDATES=1` 可用于不带更新配置的隔离构建。这一步仍是开发签名，不代表公证发行包。
3. 未公证测试版保留可验证的应用完整性签名，在发布说明标记 ad-hoc／未公证及验证范围；未来公证版用 Developer ID 签名嵌套组件与应用、完成公证并 staple，再重新 ZIP 和计算 SHA256。两种情况下均不要在签名 appcast 后重新改 ZIP。
4. 将最终 ZIP 放进专门的 release 目录，执行 `bash script/prepare_appcast.sh RELEASE_DIRECTORY https://github.com/huaye37/HoYoBridge/releases/download/vVERSION/`。工具从钥匙串读取私钥，生成带 EdDSA 签名的 appcast；脚本只生成，不发布。版本目录必须替换为真实、不可变的下载地址。
5. 发布 ZIP 后确认匿名 HTTPS 下载及哈希，将生成并验签的 XML 原样同步至 `updates/appcast.xml` 并推送；不可手动修改签名后的 XML。固定测试源不依赖 `/releases/latest`。完成客户端发现、下载、验签、替换与重启实测后才能称为自更新验收通过。

## 验收边界

配置校验、构建和 UI 验证不等于完整自更新验收。正式上线前必须用两个递增版本验证：旧版发现新版 → 下载 → 验签 → 替换 → 重启 → 游戏目录及设置保留；另测断网、损坏签名、忙碌任务暂缓与恢复。缺真实签名密钥/公开源时不能声称该端到端流程已通过。

参考：[Sparkle 官方文档](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)。
