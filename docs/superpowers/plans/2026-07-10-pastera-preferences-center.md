# Pastera 设置中心重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Follow TDD and verify each task independently.

**Goal:** 将现有偏好设置重构为可搜索、宽幅、分组清晰的 AppKit 设置中心。

**Architecture:** 保留现有 `UserDefaults`、OneDrive、Sparkle、KeyHolder 与业务服务，只重建窗口壳层和设置页面。通过静态页面目录、搜索元数据和稳定 Anchor ID 完成搜索导航与定位。

**Tech Stack:** macOS 13+、AppKit、KeyHolder、Sparkle、Swift Testing。

## Global Constraints

- 页面固定为：`通用 / 历史与预览 / 快捷键 / 排除应用 / 同步 / 关于 Pastera`。
- 默认窗口 `760×600`，最小 `680×480`，支持 frame autosave。
- 不增加窗口置顶、快捷键独立启用开关、SwiftUI 或第三方依赖。
- 所有设置即时生效；数字字段在 `Return` 或失焦时提交。
- 保留现有偏好键、同步协议和历史数据，不做数据迁移。
- 保留现有德语、意大利语、日语和简体中文翻译。
- 当前工作区已有未提交改动，实施时不得覆盖无关修改。
- 证据档位为 `standard`。

---

### Task 1: 页面目录与搜索引擎

**Files:**
- Create: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Create: `pastera/Sources/Preferences/PasteraPreferenceSearch.swift`
- Create: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `PasteraPreferencePaneID`, `PasteraPreferenceSearchItem`, `PasteraPreferencePage`, `PasteraPreferenceCatalog`, `PasteraPreferenceSearch`.

- [ ] 写失败测试：六个页面顺序、分组、图标及 Anchor ID 唯一。
- [ ] 运行 `-only-testing:pasteraTests/PreferenceSearchTests` 并确认因类型不存在而失败。
- [ ] 实现目录和纯内存搜索，标题优先于说明和关键词，支持大小写、变音符号和中文匹配。
- [ ] 覆盖按页面分组、空查询和无结果。
- [ ] 重跑定向测试并确认通过。

### Task 2: 窗口壳层与共享组件

**Files:**
- Create: `pastera/Sources/Preferences/PasteraPreferenceComponents.swift`
- Create: `pastera/Sources/Preferences/PasteraPreferenceSearchResultsViewController.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Create: `pasteraTests/PreferenceWindowShellTests.swift`
- Modify: `pasteraTests/KeyboardAccessibilityTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 页面目录、搜索结果与 Anchor ID。
- Produces: 184pt 分组侧栏、搜索结果页、页面缓存和稳定键盘导航。

- [ ] 写失败测试：窗口尺寸、六页侧栏、搜索结果、定位回调、frame autosave 与键盘规则。
- [ ] 运行窗口壳层定向测试并确认失败。
- [ ] 实现代码化窗口、共享页面/分组/设置行/状态组件与搜索结果页。
- [ ] 实现 `⌘F`、两阶段 `Esc`、方向键、Tab、Return、120ms 淡入和减少动态效果。
- [ ] 重跑窗口和键盘测试并确认通过。

### Task 3: 通用与历史页面

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYGeneralPreferenceViewController.swift`
- Create: `pastera/Sources/Preferences/Panels/CPYHistoryPreferenceViewController.swift`
- Modify: `pasteraTests/OpacityPreferenceTests.swift`
- Create: `pasteraTests/HistoryPreferenceTests.swift`
- Modify: `pasteraTests/GeneralPreferenceHelpButtonLayoutTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 2 页面组件与 Anchor 注册。
- Produces: 代码化通用页、历史与预览页、即时类型持久化和权限先行自动粘贴。

- [ ] 写失败测试：未授权自动粘贴、即时类型写入、数字草稿、越界规范化、Repository 清理和清空确认。
- [ ] 运行相关测试并确认失败原因对应缺失行为。
- [ ] 实现通用分组与权限引导，不在未授权时写入自动粘贴偏好。
- [ ] 合并数量、重复项、保存类型、预览类型和危险操作到历史页。
- [ ] 重跑通用与历史定向测试并确认通过。

### Task 4: 快捷键与排除应用

**Files:**
- Modify: `pastera/Sources/Services/HotKeyService.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYExcludeAppPreferenceViewController.swift`
- Create: `pasteraTests/ShortcutPreferenceResetTests.swift`
- Create: `pasteraTests/ExcludeAppPreferenceTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `resetMenuShortcutsToDefaults()`、`resetHistoryPanelShortcutsToDefaults()`。

- [ ] 写失败测试：两组重置、RecordView 刷新、录制/清空语义、排除列表空状态与删除。
- [ ] 运行定向测试并确认失败。
- [ ] 实现 HotKeyService 重置 API 和两张快捷键卡片。
- [ ] 将排除应用改为代码列表，保留添加、删除和键盘操作。
- [ ] 重跑快捷键、排除应用和既有 HotKeyService 测试。

### Task 5: 同步与关于页面

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`
- Create: `pastera/Sources/Preferences/Panels/CPYAboutPreferenceViewController.swift`
- Create: `pasteraTests/AboutPreferenceTests.swift`
- Modify: `pasteraTests/SyncPreferenceTopSectionTests.swift`
- Modify: `pasteraTests/SparkleUpdateFeedTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 2 页面组件；现有 `SyncCoordinator`、`PasteraAppIconProvider` 和 Sparkle updater。
- Produces: 重排同步页及包含 GitHub、License 和更新控制的关于页。

- [ ] 写失败测试：关于页信息、固定 URL、更新状态即时同步及 updater 不可用状态。
- [ ] 运行关于和同步定向测试并确认失败。
- [ ] 用共享组件重排同步页，不改变同步行为。
- [ ] 实现关于页和 Sparkle 自动检查、频率、上次检查、立即检查。
- [ ] 重跑关于、同步和 Sparkle 测试。

### Task 6: 本地化与旧资源清理

**Files:**
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Delete: 已替代的偏好 XIB、旧类型/更新控制器、布局归一化与对齐适配器。

- [ ] 迁移现有德语、意大利语、日语和简体中文文案到 string catalog。
- [ ] 删除仅在旧 XIB 中使用的资源和项目引用。
- [ ] 用 `rg` 确认旧类型页、更新页和布局适配器无残留引用。
- [ ] 运行全部偏好设置定向测试和 `git diff --check`。

### Task 7: 完整验证与本地安装

- [ ] 运行仓库 `AGENTS.md` 指定的完整 `xcodebuild ... clean test`。
- [ ] 运行 `./script/install_local.sh`。
- [ ] 验证 `/Applications/Pastera.app/Contents/MacOS/Pastera` 正在运行。
- [ ] 人工检查六页、搜索定位、最小窗口、权限引导、快捷键重置和外部链接。
