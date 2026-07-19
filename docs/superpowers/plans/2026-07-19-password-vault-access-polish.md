# Password Vault Access Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复主菜单悬停快捷提示残留和历史数字键无法粘贴的问题，并将密码箱首次设置与解锁表单重构为紧凑、清晰、可完整键盘操作的内嵌凭据卡片。

**Architecture:** 保留现有 `MainMenuPanelController`、嵌入式密码箱和 `PasteTargetContext` 业务边界。悬停提示由工具栏拥有完整的显示/关闭/超时生命周期；历史数字键复用鼠标选择的唯一粘贴出口；主密码表单继续是控制器内的轻量 AppKit 视图，但把验证、可见性和提交状态收敛到同一组件。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode 26.5、macOS 13+

## Global Constraints

- 密码箱必须继续嵌入主菜单，不新增弹窗、向导或独立密码窗口。
- KDBX、Keychain 快速解锁、系统认证和 `PasswordVaultUIController` 的安全边界保持不变。
- 历史数字键必须与鼠标/Return 选择复用同一个 `selectHistory(id, PasteTargetContext?)` 出口。
- 主密码、确认密码和任何凭据不得写入日志、仓库文档、测试快照或聊天记录。
- 使用系统字体、SF Symbols、语义颜色和现有 Pastera 深色面板视觉；不引入第三方 UI 依赖。
- 控件布局遵循 4/8pt 间距节奏，键盘焦点可见，交互目标不小于 28pt；动效遵守 Reduce Motion。
- 只修改本需求行为链，保留当前未跟踪的 `.codex/config.toml` 与 `.superpowers/`。

---

## Business Scope / Out of Scope

### In Scope

- 工具栏悬停提示在离开、模块切换、内容重载、窗口关闭时立即消失，并在持续悬停时最多显示约 1.5 秒后淡出。
- 历史页按可见数字快捷键后，将对应历史内容粘贴到打开 Pastera 前的目标输入框。
- 重构“设置主密码”和“解锁密码箱”两种状态的布局、验证、显示/隐藏密码、加载态与中文文案。
- 为上述行为增加聚焦回归测试和密码表单布局/交互测试。

### Out of Scope

- 修改 KDBX 格式、主密码派生方式、Keychain 数据或 OneDrive 同步协议。
- 重构密码条目编辑器、文件夹操作、搜索、上下文快捷粘贴或 Windows 客户端。
- 改造整个主菜单视觉体系或底部工具栏信息架构。

## Acceptance Mapping

| 验收项 | 自动化证据 | 人工证据 |
| --- | --- | --- |
| 快捷提示不会残留或叠加 | 工具栏测试覆盖重载/关闭/超时清理 | 连续悬停历史、片段、密码箱，确认只出现一个且自动消失 |
| 历史数字键粘贴到原输入框 | 主菜单测试断言数字键命中可见 ID，并把原 `PasteTargetContext` 传给 `selectHistory` | 在 TextEdit 输入框打开历史页，按数字后内容直接出现 |
| 解锁表单紧凑清晰 | 密码箱菜单测试断言单字段、显示切换、主按钮宽度、文案与错误定位 | 锁定密码箱后验证键盘 Tab、Return、错误和加载态 |
| 设置主密码可靠 | 测试覆盖双字段、空值、不同值、显示切换、按钮启用条件 | 首次设置验证两次密码一致前不可提交，成功后直接进入密码箱 |
| 无回归 | 聚焦测试与默认无签名 `xcodebuild test` 通过 | 安装本地 App 后检查主菜单三模块 |

## File Map

- Modify: `pastera/Sources/Managers/MainMenuFooterButtons.swift` — 管理悬停提示的延迟显示、自动隐藏及所有销毁边界。
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift` — 统一历史数字选择链路；重构密码箱访问表单与文案。
- Modify: `pastera/Resources/Localizable.xcstrings` — 新增或更新主密码设置/解锁中文文案。
- Modify: `pasteraTests/MainMenuEmbeddedContentTests.swift` — 覆盖嵌入式历史数字选择与目标上下文。
- Modify: `pasteraTests/CPYWindowAppearanceTests.swift` — 覆盖工具栏悬停提示生命周期。
- Modify: `pasteraTests/PasswordVaultMenuTests.swift` — 覆盖密码表单布局、显示切换、校验和提交状态。

### Task 1: 修复悬停快捷提示生命周期

**Interfaces:**
- Consumes: `MainMenuToolbarButton.onHoverChanged`、`MainMenuHoverTipController.scheduleShow(content:relativeTo:)`。
- Produces: `MainMenuHoverTipController.close()` 的幂等清理，以及显示后的自动隐藏调度。

- [ ] **Step 1: 写失败测试**

在 `CPYWindowAppearanceTests.swift` 增加测试：悬停密码箱按钮后创建提示，模拟工具栏移出窗口或销毁，断言子 `NSPanel` 被 `orderOut` 且从父窗口移除；持续悬停超过自动隐藏时长后也满足相同断言。

- [ ] **Step 2: 运行聚焦测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:PasteraTests/CPYWindowAppearanceTests
```

Expected: FAIL；现有 controller 仅在 `mouseExited` 时关闭，工具栏重载/销毁和持续悬停没有关闭路径。

- [ ] **Step 3: 实现最小生命周期修复**

在 `MainMenuHoverTipController` 中分别持有 `pendingShow` 与 `pendingClose`。`scheduleShow` 先调用 `close()`；显示成功后调度约 1.5 秒关闭。`close()` 同时取消两个 work item、移除 child window、`orderOut` 并清空引用。为 controller 增加 `deinit { close() }`，为 `MainMenuToolbarView` 在 `viewWillMove(toWindow: nil)` 时主动关闭。淡出仅在未启用 Reduce Motion 时使用约 0.18 秒动画。

- [ ] **Step 4: 运行聚焦测试**

运行 Step 2 命令。Expected: PASS，且连续切换三个按钮时父窗口最多只有一个 hover-tip child window。

### Task 2: 让历史数字键复用目标粘贴链路

**Interfaces:**
- Consumes: `HistoryMenuNumberShortcutMapper.rowIndex(for:startsAtZero:rowCount:)`、`visibleHistoryIDs`、`pasteTargetContext`。
- Produces: 数字键调用与行确认相同的 `confirmHistorySelection(_:)`。

- [ ] **Step 1: 写失败测试**

在 `MainMenuEmbeddedContentTests.swift` 构造两个历史条目和固定 `PasteTargetContext`，显示历史模式后发送数字键事件，断言 data source 收到第二条 ID 与同一目标进程标识；同时断言关闭/非历史模式、搜索字段正在输入数字以及关闭数字快捷键偏好时不会误选。

- [ ] **Step 2: 运行聚焦测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:PasteraTests/MainMenuEmbeddedContentTests
```

Expected: FAIL，失败断言应明确当前事件被错误消费或未携带打开面板前保存的目标上下文。

- [ ] **Step 3: 修正事件路由**

让 `confirmNumberShortcut(_:)` 只在数字快捷键偏好开启、历史内容区拥有导航语义且搜索/安全输入字段不拥有焦点时处理事件；命中后仅调用 `confirmHistorySelection(visibleHistoryIDs[rowIndex])`，不复制关闭、激活或粘贴逻辑。必要时调整 `MainMenuPanel.keyDown`/field-editor 转发顺序，使无修饰数字事件先经过面板数字映射，但密码字段和搜索字段保持原生输入。

- [ ] **Step 4: 运行聚焦测试**

运行 Step 2 命令。Expected: PASS；鼠标、Return 与数字键三条入口均到达同一 data source 闭包。

### Task 3: 重构主密码设置与解锁卡片

**Interfaces:**
- Consumes: `PasswordVaultAccessView.Mode`、`onSubmit(String)`、`onQuickUnlock()`、`passwordVaultAccessError`。
- Produces: 内嵌访问卡片、字段级校验、密码显示切换和可测试布局快照。

- [ ] **Step 1: 写失败测试**

在 `PasswordVaultMenuTests.swift` 增加并更新断言：

- 解锁态标题为“解锁密码箱”，说明为“输入主密码以查看和使用已保存的密码”，只有一个安全字段。
- 设置态标题为“设置主密码”，说明包含“忘记后无法恢复”，字段标签为“主密码”“再次输入”。
- 两个模式均可显示/隐藏密码且不改变值；按钮占满内容宽度。
- 设置态空值或两次不一致时不可提交并把错误放在对应字段下；一致时 Return 提交一次。
- busy 状态禁用输入、可见性按钮和提交按钮，按钮文案显示当前动作进度。

- [ ] **Step 2: 运行密码箱菜单测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:PasteraTests/PasswordVaultMenuTests
```

Expected: FAIL；现有表单是右对齐窄按钮、无密码可见性切换，设置态只在提交时校验。

- [ ] **Step 3: 实现访问卡片和文案**

在 `PasswordVaultAccessView` 中保持单列结构：12pt 水平内边距，标题/说明、字段组、字段错误、全宽 32pt 主按钮和次要快速解锁按钮按 8pt 节奏排列。为每个密码字段配置 SF Symbol `eye`/`eye.slash` 的 28pt 可访问按钮，通过安全字段与普通字段切换时同步同一字符串和 first responder。设置态根据两个字段实时更新按钮启用状态；解锁态允许非空时提交。服务错误继续由 `passwordVaultAccessError` 显示在表单内，成功后现有状态刷新直接进入密码箱。

更新 `Localizable.xcstrings`，中文采用：`设置主密码`、`主密码用于加密密码箱，忘记后无法恢复。`、`再次输入`、`创建密码箱`、`解锁密码箱`、`输入主密码以查看和使用已保存的密码。`、`两次输入的主密码不一致。`、`使用快速解锁`。

- [ ] **Step 4: 运行密码箱菜单测试**

运行 Step 2 命令。Expected: PASS，且布局快照中所有控件位于 view bounds 内。

### Task 4: 集成验证与本地安装

**Interfaces:**
- Consumes: Tasks 1-3 的 UI 与事件行为。
- Produces: 可运行的本地 `Pastera.app` 和人工验收证据。

- [ ] **Step 1: 运行三个聚焦测试套件**

依次运行 Tasks 1-3 的命令。Expected: 全部 PASS。

- [ ] **Step 2: 运行仓库默认回归**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation clean test
```

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 3: 检查 diff 与凭据安全**

Run:

```bash
git diff --check
git diff -- pastera/Sources/Managers/MainMenuFooterButtons.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Resources/Localizable.xcstrings \
  pasteraTests/CPYWindowAppearanceTests.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift
```

Expected: 无空白错误、无明文凭据、无范围外改动。

- [ ] **Step 4: 安装并人工验证**

Run: `./script/install_local.sh`

Expected: `/Applications/Pastera.app` 被最新本地构建替换并启动。使用 TextEdit 验证历史数字粘贴；连续悬停三个模式按钮验证提示自动消失；分别验证首次设置与锁定解锁的 Tab、Return、显示/隐藏、错误和加载态。

## Risks, Rollback and Observation

- **风险：** 子 `NSPanel` 的淡出回调可能晚于父工具栏销毁；通过幂等 `close()`、取消 work item 和弱引用避免悬空窗口。
- **风险：** 抢先处理数字键可能破坏搜索和密码输入；只在内容导航上下文处理，并用 first responder 负向测试锁定。
- **风险：** 安全字段/普通字段切换可能丢失内容或光标；共享字符串、同步 selection 并在测试中验证不改变值。
- **回滚：** Tasks 1-3 可按文件和测试独立回退，不涉及存储迁移、KDBX 内容或用户设置格式。
- **观察：** 本地安装后重点观察主菜单反复 reload、鼠标停留在底栏时切换模块，以及从不同目标 App 打开历史后按数字粘贴。

## Delivery Metadata

- Plan: `docs/superpowers/plans/2026-07-19-password-vault-access-polish.md`
- Status: Implemented and verified locally
- Evidence Profile: standard
- ZenTao: 仓库未提供 `docs/zentao/ZENTAO.md`，本计划不创建或臆造 Story/Task ID
- Prior contracts: `2026-07-15-password-vault-inline-unlock`、`2026-07-17-password-vault-contextual-actions`

## Delivery Record

- Actual Implementation: Hover tips now own delayed-show and delayed-close work items, close when their toolbar leaves a window, and fade after 1.5 seconds. Main-menu panels route plain numeric key equivalents and the displayed Preferences shortcut through the existing keyboard path. The password access card now uses full-width actions, improved Chinese copy, live submit eligibility, busy-state disabling, and value-preserving show/hide controls. A live General-settings audit also restored the configured opacity and menu-title-length behavior in the embedded main menu.
- Plan Deviations: Focused test commands use the repository's actual target name `pasteraTests` instead of the planned `PasteraTests`. The numeric event required an AppKit `performKeyEquivalent` route, but the reported failure to paste after selection had a separate machine-state cause: automatic paste was disabled in the installed debug app domain. The user subsequently requested a live audit of General settings; that audit found two adjacent embedded-main-menu regressions outside the original password-vault scope: opacity was hard-coded to 1.0 and title rendering imposed a 60-character minimum.
- Impact: AppKit presentation and keyboard routing only. No KDBX format, Keychain, OneDrive, repository schema, or password derivation changes.
- Verification: Focused password-vault command passed 77 tests across `CPYWindowAppearanceTests`, `MainMenuEmbeddedContentTests`, and `PasswordVaultMenuTests`; the Preferences shortcut regression command also passed. Repository default `clean test` passed after the shortcut fix with `** TEST SUCCEEDED **`. The General-settings audit passed 40 related tests, 20 main-menu visual/history tests, and 11 live-opacity footer tests after updating the superseded opaque-background expectation. `jq empty pastera/Resources/Localizable.xcstrings` and `git diff --check` passed. `./script/install_local.sh` completed with `** BUILD SUCCEEDED **`, installed `/Applications/Pastera.app`, and launched the new build.
- Remaining Risks: Automated tests cannot prove the pointer remains over every real status-item geometry or that every external target app accepts synthetic paste. The final broad test attempt after the General-settings audit stopped on a superseded opacity expectation; that expectation was corrected and its focused 11-test suite passed, but the entire broad suite was not rerun afterward. Automatic paste still depends on macOS Accessibility approval for the currently installed signature.
- Follow-ups: Live diagnosis found Accessibility trusted, numeric shortcuts enabled, and `kCPYPrefInputPasteCommandKey = 0` in `com.pastera-app.Pastera.debug`. The setting was changed to `1`, and all 8 `PasteServiceTargetRestoreTests` passed, including the enabled and disabled preference branches. A later report showed the footer's displayed `⌘,` shortcut was not handled by the embedded panel; a failing regression test reproduced it, then the panel was changed to route command key equivalents through `handleKeyboardNavigation`, where exact `⌘,` now invokes `onOpenPreferences`.
- ZenTao Closeout: Not applicable; no repository ZenTao contract found
