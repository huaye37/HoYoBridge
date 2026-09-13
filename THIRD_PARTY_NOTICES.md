# 第三方来源、许可与分发状态

更新日期：2026-09-13。记录星桥 HoYoBridge（内部名 MacGameBridge）的依赖、复用和历史参考；本文件不是整体再分发授权证明。自有代码 MIT 许可不覆盖第三方代码、预编译包、游戏和美术资源。`LICENSES/` 的许可原文保持原语言，不改写。

**允许未公证的 Pre-release 测试版，但必须明确标注状态。** 公证不是版权授权；下述未核对项也须处理。保留许可文本不等于完成提供对应源代码、修改说明等全部义务。

## YAAGL 与清单来源

- 仓库：[yaagl/yet-another-anime-game-launcher](https://github.com/yaagl/yet-another-anime-game-launcher)。
- 固定提交：`ca78abc29c2fc236261d088c6907d28cab6e9476`。
- YAAGL 自有代码采用 MIT，[原文](LICENSES/YAAGL-MIT.txt)。
- 直接复用：`sophon_server/manifest.proto`、`manifest_ldiff.proto` → `Sources/BridgeCore/Protobuf/` 同名文件；保留归属注释。
- 本地新增 `ChunkInfo` 字段 7 有独立 observed-CN-v2 注释，其命名和校验策略不归于 YAAGL。
- 差分清单原注释指向 Lightczx 在 [Snap.Hutao/issues/2446](https://github.com/DGP-Studio/Snap.Hutao/issues/2446) 的贡献。上游注释中的 MIT 推定不等于本项目独立确认该贡献授权；公开前需核对。不将整个 Snap.Hutao 项目标为直接依赖。
- 兼容启动思路和固定 sidecar 中的 7zz、Steam 兼容资产也来自该上游；附带组件不能统一套用 YAAGL MIT 许可。

2026-09-08 起打包不再含旧 `GameDownloader`，四游戏统一使用后台官方引擎。历史开发包曾含 CPython 3.11.15、YAAGL、Python Protobuf 6.31.1、python-zstandard 0.23.0、psutil 7.0.0、PycURL 7.45.6 和传递库。这些历史包没有完成公开分发核对，不应重新上传。移除下载器不等于移除所有 YAAGL 参考及兼容资产。

## Wine / CrossOver 构建及 Steam 兼容资产

- 兼容构建参考来源：[yaagl/anime-game-wine](https://github.com/yaagl/anime-game-wine)，基础项目 [Wine](https://gitlab.winehq.org/wine/wine)；CodeWeavers / CrossOver 名称和产品属于相应权利人。
- 固定本地资产：`wine-crossover-11.0-1-osx64-signed.tar.xz`，SHA-256 `89fa7e90fb626523a90d5867a03c6be785d017176739c6320a3b86c7838c3a35`。
- 固定 YAAGL sidecar 中的 `steam64.exe`、`steam32.exe`、`lsteamclient64.dll`、`lsteamclient32.dll` 用于兼容，不是完整 Steam 客户端；哈希见 `script/build_and_run.sh`。
- **待完成：** 实际预编译包的获取出处、构建对应源码、修改、传递库许可及适用的源码提供义务。不能把 Wine 的开源身份视为整个预编译包或商业 CrossOver 产品的分发授权。

## DXMT

- [3Shain/dxmt](https://github.com/3Shain/dxmt)，固定 0.80，用于图形转换。
- 资产 `dxmt-v0.80-builtin.tar.gz`，SHA-256 `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d`。
- 完整预编译包、对应修改源码及附带依赖许可清单仍待归档，不因致谢而标记为分发核对完成。

## Jadeite 4.1.0

- [mkrsym1/jadeite](https://github.com/mkrsym1/jadeite)，MIT，Copyright 2023-2024 mkrsym1。
- [许可原文](LICENSES/Jadeite-MIT.txt)；应用内也保留 `RuntimeAssets/Jadeite/LICENSE.txt`。
- 部分游戏的兼容启动链使用 `jadeite.exe`、`game_payload.dll`、`launcher_payload.dll`；具体分支见 `MiHoYoGameLaunchService`，哈希见打包脚本。
- 不表示官方批准，也不证明未来游戏版本仍兼容。

## genshin-fps-unlock

- [34736384/genshin-fps-unlock](https://github.com/34736384/genshin-fps-unlock)，参考 `netcore` 分支，MIT，[原文](LICENSES/genshin-fps-unlock-MIT.txt)。
- 借鉴帧率目标定位方法，本地衍生实现增加边界、页面保护及唯一目标检查，不捆绑上游可执行文件。
- 历史实现位置 `RuntimeAssets/GPTKCompatibility/gptk4_msaa_version.c` 不表示当前产品提供 GPTK；GPTK/D3DMetal 已退出产品打包与启动入口。

## Sparkle 2.9.6

- [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)，MIT，[原文](LICENSES/Sparkle-MIT.txt)。
- revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`，用途为启动器自更新。
- SwiftPM 校验二进制 artifact checksum，版本与 revision 见 `Package.resolved`。应用内另存 `Resources/LICENSES/Sparkle.txt`。
- 已接入组件不等于已开放正式更新源。

## SwiftProtobuf 1.38.1 与构建依赖

- [apple/swift-protobuf](https://github.com/apple/swift-protobuf)，revision `55d7a1cc5666b85c13464aea1c4b4a90feccb4c8`。
- Apache-2.0 加 SwiftProtobuf Runtime Library Exception，[完整原文](LICENSES/SwiftProtobuf-1.38.1.txt)。例外不扩展到其他组件。
- 插件用于构建 protoc 的 Google Protocol Buffers：BSD-3-Clause，[原文](LICENSES/Google-Protobuf-BSD-3-Clause.txt)。
- Abseil：Apache-2.0，[原文](LICENSES/Abseil-Apache-2.0.txt)。
- utf8_range：MIT，[原文](LICENSES/utf8-range-MIT.txt)。
- 以上原文来自解析得到的 SwiftProtobuf 1.38.1 源码。构建依赖不代表独立捆绑的玩家程序。

## Zstandard 1.5.7

- [facebook/zstd](https://github.com/facebook/zstd)，revision `f8745da6ff1ad1e7bab384bd1f9d742439278e99`。
- 采用仓库 BSD 许可，[原文](LICENSES/Zstd-BSD.txt)。
- 从源码构建 libzstd；生产桥接提供解压，压缩辅助函数仅在测试目标使用。

## 官方引擎与 7-Zip

- 官方安装器按需从厂商 CDN 获取，不嵌入应用；引导版本 1.18.0.380，SHA-256 `674ff7201b42058cd569889ccbdc15cdd97709b1442876757a0f81785d716517`。
- 后台适配使用未公开承诺稳定的本地接口，不是官方集成授权。客户端、服务和账号条款仍由其权利人提供。
- [7-Zip](https://www.7-zip.org/) 的 7zz 21.07（Igor Pavlov）取自固定 YAAGL sidecar，用于解包；SHA-256 `10bba361f87be5882e362df8f283646fb5fff1a7f63246149a5809be286897f5`。
- LGPL / unRAR 限制 / BSD 的完整声明：[7-Zip.txt](LICENSES/7-Zip.txt)，应用内保留同名文件。对应源码及适用分发义务仍需核对。

## 美术、商标和游戏资源

官方封面及静态回退图来源见 [背景记录](docs/LAUNCHER_ARTWORK.md)；游戏角色参考生成图标见 [图标记录](docs/APP_ICON.md)。AI 生成不赋予角色和商标的额外权利，公开访问也不自动允许重新打包。

游戏、角色、美术、音频、标识和商标归相应权利人，不适用本项目 MIT。公开分发前须确认适用授权，或替换／移除未确认素材。本项目不暗示米哈游、HoYoverse、Apple、CodeWeavers 或上游作者背书。

如有归属错误，可通过仓库 Issues 提供具体文件及依据联系维护者；私有阶段仅协作者可访问，公开前需确认外部联系渠道。声明和致谢不代替许可，也不免除应履行的义务。
