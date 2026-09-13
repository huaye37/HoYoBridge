# GPTK 4 与 DXMT 首轮启动界面对比

日期：2026-08-22

## 结论

本轮不是游戏内性能基准。它只覆盖当前机器的自动启动/登录界面落点、
`1600 × 900`、相同平衡画质配置和约 30 秒采样窗口。这组数据只能作为
后端初步筛查，不能证明 DXMT 在实际跑图、战斗或复杂场景更快。

- 两者平均帧率都接近 60 FPS，单看平均值没有实际差异。
- DXMT 的 99 百分位帧时间为 `16.67 ms`，GPTK 为 `25.00 ms`；按相同口径换算，
  1% Low 分别约为 `60.0 FPS` 和 `40.0 FPS`。
- GPTK 的总 CPU 占用平均比 DXMT 高约 `29.2%`。
- GPTK 的平均 GPU 时间比 DXMT 高约 `9.7%`，95 百分位 GPU 时间高约 `25.8%`。
- GPTK 的 Metal HUD 进程内存低约 `127.5 MB`，但 `ps` 统计的整套 Wine 进程 RSS
  只低约 `13.8 MB`；不足以抵消帧节奏和 CPU 的劣势。

因此，现阶段仍保留 DXMT 0.80 为默认选项、把 GPTK 4 标为实验选项；
最终后端判断必须等固定游戏场景基准完成后重新作出。

## 游戏内复测

同日随后使用应用内“两阶段基准”完成首轮真实游戏内复测。两轮均为窗口
`1600 × 900`、平衡档；用户分别确认已进入同一场景后，启动器稳定 10 秒并采集
约 60 秒。Wine 游戏窗口没有暴露 macOS Accessibility，因此场景一致性来自用户
确认，画面正确性仍需用户反馈。

| 指标 | GPTK 4.0b2 | DXMT 0.80 | 判断 |
| --- | ---: | ---: | --- |
| 有效帧样本 | 3,164 | 3,567 | DXMT 在相近时间内呈现更多帧 |
| 平均 FPS | 53.45 | 57.40 | DXMT 高约 7.4% |
| P99 帧时间 | 91.67 ms | 16.67 ms | DXMT 明显更稳 |
| P99.5 帧时间 | 125.00 ms | 50.00 ms | GPTK 长尾卡顿更重 |
| P99.9 帧时间 | 291.66 ms | 166.67 ms | 两者都有尖峰，GPTK 更差 |
| 最大帧时间 | 425.00 ms | 516.66 ms | DXMT 有一次更深的孤立尖峰 |
| 大于 33.34 ms 的慢帧 | 103（3.26%） | 27（0.76%） | GPTK 约为 3.8 倍 |
| 大于 100 ms 的帧 | 26 | 8 | GPTK 约为 3.3 倍 |
| 采样窗口平均 RSS | 5.87 GiB | 4.51 GiB | GPTK 多约 1.36 GiB |
| 采样窗口峰值 RSS | 6.16 GiB | 4.64 GiB | GPTK 多约 1.52 GiB |
| 采样窗口平均 CPU | 362% | 379% | GPTK 略低，但帧率和帧节奏更差 |

DXMT 的 P99 仍为 `16.67 ms`，但其 `27` 个慢帧不到总样本的 1%，所以单看
P99/“1% Low”会掩盖少量严重尖峰。DXMT 最大尖峰达到 `516.66 ms`，与用户反馈的
“大多数时候正常、偶尔明显掉帧”一致。最终仍保留 DXMT 0.80 为默认；GPTK 4
继续作为实验后端，不作为当前性能升级方案。

## 测试条件

| 项目 | 值 |
| --- | --- |
| 机器 | MacBook Pro `Mac17,9`，Apple M5 Pro，48 GB |
| 系统 | macOS 27.0 beta，build `26A5416b` |
| Xcode / xctrace | Xcode 26.6 `17F113` / xctrace 16.0 |
| 游戏 | 原神国服 7.0.0 |
| 输出 | 窗口模式，`1600 × 900` |
| 帧率目标 | 60 FPS |
| GPTK | Game Porting Toolkit 4.0 beta 2，D3DMetal SHA-256 `f5b56df1…503e2bad` |
| DXMT | DXMT 0.80，64 位 `d3d11.dll` SHA-256 `7ca382af…f885c47` |
| 采集窗口 | 启动约 75 秒后，约 30 秒启动/登录界面数据 |

两个 Prefix 中的 `GENERAL_DATA_h2389025596` 块 SHA-256 完全一致，均为
`b6a6e0e0…fc625d0`；注册表中的窗口模式和 `1600 × 900` 分辨率也一致。
两轮均通过同一个 Steam compatibility stub 启动同一个 `YuanShen.exe`。

## 结果

| 指标 | GPTK 4.0b2 | DXMT 0.80 | 判断 |
| --- | ---: | ---: | --- |
| 有效帧样本 | 1,770 | 1,768 | 数量相当 |
| 平均 FPS | 60.37 | 59.97 | 都达到 60；差异无实际意义 |
| 平均帧时间 | 16.57 ms | 16.68 ms | 平均值掩盖了 GPTK 的摆动 |
| 帧时间标准差 | 3.05 ms | 0.20 ms | DXMT 帧节奏更一致 |
| 95 百分位帧时间 | 25.00 ms | 16.67 ms | DXMT 更稳 |
| 99 百分位帧时间 | 25.00 ms | 16.67 ms | DXMT 更稳 |
| 1% Low | 40.0 FPS | 60.0 FPS | DXMT 明显更好 |
| 大于 33.34 ms 的帧 | 0 | 0 | 该稳态窗口都无深度卡顿 |
| 平均 GPU 时间 | 4.54 ms | 4.14 ms | DXMT 低约 8.9% |
| 95 百分位 GPU 时间 | 8.20 ms | 6.51 ms | DXMT 低约 20.5% |
| 总 CPU 平均 / 峰值 | 252.8% / 258.5% | 195.6% / 200.0% | GPTK 平均高约 29.2% |
| Wine 进程 RSS 平均 / 峰值 | 2,343 / 2,349 MB | 2,357 / 2,360 MB | 基本相同 |
| Metal HUD 进程内存平均 / 峰值 | 2,907 / 2,912 MB | 3,035 / 3,037 MB | GPTK 低约 4.2% |
| Metal HUD 图形内存平均 | 517 MB | 489 MB | GPTK 高约 28 MB |

GPTK 的帧时间分布为：`1,532` 帧在 `16.67 ms`、`130` 帧在 `8.33 ms`、
`108` 帧在 `25.00 ms`。DXMT 的 `1,768` 帧中，`1,767` 帧为 `16.67 ms`，
仅 `1` 帧为 `25.00 ms`。GPTK 的平均 FPS 看起来略高，实际是 8.33 ms 与
25 ms 帧交替抵消后的结果，不代表体感更顺。

## 采集与计算口径

逐帧数据来自 [Apple Metal Performance HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance/)
的 per-frame 日志。每条记录包含帧号、图形内存、进程内存，以及随后每一帧的
present interval 和 GPU time。

- 平均 FPS：`有效帧数 / present interval 总时长`
- 1% Low：`1000 / 99 百分位帧时间`
- CPU / RSS：同一窗口内每秒汇总 `YuanShen.exe`、Steam stub 和 `wineserver`
- 大卡顿：帧时间严格大于 `33.34 ms`

原始证据保存在被 Git 忽略的
`LocalRuntimes/Diagnostics/performance-2026-08-22/`：

- `gptk4-metal-hud.log`
- `gptk4-process-samples.csv`
- `dxmt-metal-hud.log`
- `dxmt-process-samples.csv`

## 限制与下一轮

1. 本轮是自动启动后的静态/轻负载稳态，不是角色跑图、战斗或城市复杂场景；不能据此
   宣称 GPTK 在所有游戏场景更慢。
2. Wine 游戏窗口没有暴露给 macOS Accessibility，因此本轮没有形成同画面截图对照；
   画面正确性，尤其是 GPTK shim 禁用多重采样后的边缘质量，仍未验收。
3. `Game Performance` 与 `Metal System Trace` 都录到了原始数据，但该 macOS 27 beta /
   Xcode 26.6 组合生成的 trace 缺少可导出的模板元数据，`xctrace export` 返回
   `Document Missing Template Error`。本报告改用 Apple 官方 Metal HUD 逐帧日志，
   没有从残缺 trace 推导数据。
4. 下一轮应在同一账号、同一传送点、同一朝向和同一路线各跑至少 60 秒，并同时保留
   视频或截图。届时再比较平均 FPS、1% Low、卡顿帧、CPU、内存和画面正确性，作为
   是否调整默认后端的最终依据。
