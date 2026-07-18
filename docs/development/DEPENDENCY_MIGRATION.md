# Clipy 依赖迁移记录

本文记录 Pastera 独立化时对 `Clipy/*` 生产依赖的实际调用审计、处置结果与后续维护边界。

## 已移除的直接依赖

| 依赖 | 原调用 | Pastera 处置 |
| --- | --- | --- |
| `LoginServiceKit` | `AppDelegate` 中启用、关闭登录项 | 使用 macOS `SMAppService.mainApp.register()` / `unregister()`，由 `LaunchAtLoginController` 封装并测试 |
| `Screeen` | `ScreenShotObserver` 监听桌面截图元数据 | 使用本地 `PasteraScreenshotObserver` 和 `NSMetadataQuery` 保留截图自动入库 |
| `Sauce`（直接调用） | `PasteService` 查询当前键盘布局下 Command-V 的虚拟键码 | 使用本地 `PasteShortcutKeyCodeResolver` 和 Carbon `UCKeyTranslate`；无法解析时回退 ANSI V 键码 |

`Sauce` 仍是快捷键组件的传递依赖，但已迁移到 Pastera 维护地址，不再从 `Clipy/*` 获取。

## 保留并迁移的快捷键组件

`Magnet` 与 `KeyHolder` 在主菜单、历史面板、片段面板、脚本设置、快捷键设置和快捷键录制控件中共有大量调用，并包含 XIB 归档类名。一次性本地重写会同时改变快捷键注册、冲突处理、录制 UI 和已有归档兼容性，因此本轮保留 API，并迁移为 Pastera 维护 fork：

- `pastera-app/Magnet` 3.5.1：其 Sauce 地址改为 `pastera-app/Sauce`。
- `pastera-app/KeyHolder` 4.3.1：其 Magnet、Sauce 地址改为 `pastera-app`。
- `pastera-app/Sauce` 2.5.1：保留原许可证和实现，供上述组件传递使用。

这些 fork 属于兼容性边界，不代表继续跟踪 Clipy 产品仓库。安全修复、Swift/Xcode 兼容修复和 Pastera 所需行为由 `pastera-app` 自行维护。

## 自动约束

`ReleasePackagingConfigurationTests.productionPackagesDoNotReferenceClipyOrganization` 会同时扫描 Xcode 工程和 `Package.resolved`。任何生产包 URL 再次出现 `github.com/Clipy/`（忽略大小写）都会导致测试失败。

新增或升级依赖时必须：

1. 核对实际 import 与调用路径；
2. 核对许可证及发布包归属要求；
3. 重新解析 Swift Package 图；
4. 运行依赖静态检查、相关聚焦测试和完整 macOS 测试。
