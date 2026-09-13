# 首页主视觉

## README 界面预览（2026-09-13）

`docs/images/launcher-preview.png` 为用户提供并要求展示的实际启动器截图，原样用于 README，不包含账号或本机目录。截图中的游戏角色与背景仍归对应权利人，不因作为界面预览而变为 MIT 授权素材。

## 天空之门图标预览（2026-09-04）

`Assets/AppIconSkyPreview.png` 使用内置 image_gen，根据用户提供的原神登录截图生成。配色为天空蓝、云白、暖象牙色，图形为单个白石门与云。用户参考只用于视觉方向，不将截图中的 UI／版本号打包。

提示词：Generate a standalone macOS icon using the reference's clear celestial blue sky, cloud white and warm ivory stone palette. One simple tall ivory fantasy doorway centered on a soft blue rounded-square tile, warm light through the door, a small cloud at its base, clean matte sculpted illustration, recognizable at 32px. No dark teal, emerald, heavy metallic gold, ornate jewelry, ribbons, text, logos, UI or rating labels. Transparent exterior.

生成与两次去背景编辑都没有输出真实 alpha，而是画出了棋盘格。预览尚不能作为正式图标；正在等待用户授权本地去背景。当前 `.app` 仍包含先前深青图标，不将它误报为新图标。图标打包脚本已支持 PNG 转多尺寸 ICNS 并配置 CFBundleIconFile。

## 风景背景

文件：`Sources/BridgeStatus/Resources/LauncherLandscape.png`

2026-09-04 使用内置 image_gen 生成，非官方游戏素材。静态图片通过 SwiftPM
资源包随应用分发，不依赖网络、不播放视频、不持续刷新动画。界面文字均为原生控件。

生成提示词：

> Use case: stylized-concept. Asset type: static landscape artwork for a native macOS Genshin launcher hero. Create a beautiful wide 16:9 anime fantasy landscape, painterly polished game environment concept art: a windswept green meadow in foreground, a distant medieval walled city with windmills on a lake, towering pale cliffs, blue sky and luminous ivory clouds, soft warm morning sunlight. Composition supports launcher UI: keep left third quieter and darker with teal foliage for white title overlay; city and glowing sky are on right two thirds. Elegant inviting atmosphere, finely composed, not busy, no characters, no text, no logos, no watermark, no UI. Landscape image only.
# 2026-09-06 官方背景替换

现由 LauncherArtworkStore 自动获取四游戏官方当前封面（包括原神），下方静态资源仅作无缓存时的回退。启动与前台激活触发查询，同进程最多每小时一次；地址未变不重复下载。缓存按游戏保存最近有效图片与来源 URL，网络或解码失败保留旧图。官方活动图可能先于或独立于本机游戏版本改变。

原神保留现有背景。其余三款采用官方 HoYoPlay 国服 getGames 返回的 display.background.url，图片作为静态 WebP 随应用加载，未引入视频或持续刷新。

- 接口：https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGames?launcher_id=jGHBHlcOq1&language=zh-cn
- 星穹铁道：https://launcher-webstatic.mihoyo.com/launcher-public/2026/08/17/b3811afc4a6a4e7e3879c830329f8ae2_4041979032811000021.webp
- 绝区零：https://launcher-webstatic.mihoyo.com/launcher-public/2026/07/23/44c00562adb813afd747d7d3d8b4798b_6314007566574726598.webp
- 崩坏 3：https://launcher-webstatic.mihoyo.com/launcher-public/2026/07/16/ffdd42e098046b7bea134907a2ea04b2_352028468613440724.webp

版权归原权利人所有；公开分发授权尚未核实，当前为本地界面验证素材。
