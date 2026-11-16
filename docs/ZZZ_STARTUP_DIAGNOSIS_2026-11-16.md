# 绝区零国际服启动闪退调查（2026-11-16）

> 2026-11-17 更正：以下 40 秒结果只证明启动包装进程存活；新实验确认游戏崩溃后包装进程仍可能存活，因此不能称为游戏启动成功。用户已复现 timeout 开启仍失败，后续启动顺序对照见 [2026-11-17 调查](ZZZ_STARTUP_DIAGNOSIS_2026-11-17.md)。

## 已确认的证据

- 本机绝区零国际服 3.3.0，多次启动崩溃转储一致：`0xc0000005`，`MHYPBase.dll + 0x1856a61`，向低地址 `0x1000` 写入失败。同期 `driverError.log` 报 `initDriver Failed [4,1114,0]`。
- 官方安装清单 `pkg_version` 中的 `ZenlessZoneZero.exe`、`mhypbase.dll`、`HoYoKProtect.sys` MD5 与实际文件一致。这里只校验启动关键文件，不代表重新校验整个游戏。
- macOS hosts 未发现绝区零相关的遗留屏蔽项。
- 游戏文件位于 SMB 网络盘。同一份文件、同一固定 Wine/DXMT、复制到本机的隔离 prefix，原配置两次均越过崩溃点并运行 40 秒。因此不能把“存放在 NAS”作为必然导致启动失败的结论。

## 找到并修正的配置漏项

启动器的绝区零路径未设置 `WINE_ENABLE_TIMEOUT_FIX`，正在运行的正式启动器也未继承该变量。固定 Wine 11.0-1 的 `ws2_32.dll` 已包含对应实现，YAAGL 对同类绝区零闪退推荐 Steam 兼容入口配合 timeout fix。

0.1.15 为绝区零国服／国际服显式启用此项，并在启动日志记录 `MGB_COMPAT timeout_fix=1`。不升级 Wine，不替换游戏 DLL，不修改 hosts，不切代理，不更改原神或星铁的成功配置。

## 本机对照与边界

| 试验 | 结果 |
| --- | --- |
| 原配置，模块诊断日志 | 运行 40 秒，越过崩溃点 |
| 原配置，正常日志及窗口辅助程序 | 运行 40 秒，越过崩溃点 |
| 启用 timeout fix，第 1 次 | 运行 40 秒，越过崩溃点 |
| 启用 timeout fix，第 2 次 | 运行 40 秒，越过崩溃点 |
| 启用 timeout fix，过滤的网络兼容诊断 | 运行 40 秒；记录 `WSACreateEvent adjusted curl timeout`，确认运行时真正执行而非仅设置变量 |

只在私有实验目录保存隔离 prefix，实验进程使用独立 wineserver，观察结束仅停止实验环境；未替用户登录、接受协议或进行游戏操作。网络诊断仅保留 timeout 修正及异常标记，不记录网络报文／账号凭证。

**这轮原配置也成功了，不能从上述对照推导“所有历史崩溃必由请求超时引起”或“偶发闪退已经彻底消除”。** 已完成的是补齐上游推荐兼容配置并验证其生效。正式 prefix、持续游玩、不同网络条件与国服仍需分别验证。不能把 40 秒启动观察称为可玩验收。

## 一手来源

- [YAAGL #739：绝区零国际服 Unity 启动崩溃，维护者推荐 timeout fix](https://github.com/yaagl/yet-another-anime-game-launcher/issues/739)
- [YAAGL #697：hosts 残留会造成相似保护初始化错误](https://github.com/yaagl/yet-another-anime-game-launcher/issues/697)
- [YAAGL #787：3.3.0 下仍有同类启动失败报告](https://github.com/yaagl/yet-another-anime-game-launcher/issues/787)
- [Spritz-Wine timeout 修正实现](https://github.com/NelloKudo/spritz-wine/blob/master/patches/0001-spritz/0009-HACK-ws2_32-Allow-changing-request-timeout-with-WINE.patch)
