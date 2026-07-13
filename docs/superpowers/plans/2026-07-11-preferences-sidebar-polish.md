# Preferences Sidebar Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 精修 Pastera 设置侧栏的字体、图标、间距、选中态和中文命名。

**Architecture:** 保持现有 AppKit 设置窗口结构，只在目录模型提供新名称与 SF Symbol，并由现有侧栏按钮统一视觉参数。测试通过 DEBUG 入口验证菜单结构和布局常量，真实应用截图负责主观视觉验收。

**Tech Stack:** Swift 5、AppKit、Swift Testing、Xcode、SF Symbols

## Global Constraints

- 保持 macOS 13+ 兼容性与现有键盘/辅助功能行为。
- 不修改右侧页面业务逻辑或设置持久化。
- 不引入图片 Logo、第三方依赖或新设计系统。
- 保留当前工作区所有无关改动。

---

### Task 1: 设置侧栏视觉与命名

**Files:**
- Modify: `pasteraTests/PreferenceWindowShellTests.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PasteraPreferenceCatalog.default` 和 `PasteraPreferenceSidebarButton`
- Produces: 六项新菜单名称、两项新分组名、统一侧栏指标和 SF Symbol

- [ ] **Step 1: 写入失败测试**

  更新 shell 测试，断言 188pt 宽度、16pt 内边距、40pt 行高、17pt 图标与 26pt 图标槽、新菜单名称、六个新图标、单一分割线和 14pt 页面顶部间距。

- [ ] **Step 2: 验证测试按预期失败**

  Run: `xcodebuild test -scheme pastera -project pastera.xcodeproj -only-testing:pasteraTests/PreferenceWindowShellTests`

  Expected: 旧宽度、旧文案或旧图标导致断言失败。

- [ ] **Step 3: 最小实现**

  更新目录文案键和图标名；将侧栏宽度设为 188、内边距设为 16、行高设为 40，并让按钮使用 17pt SF Symbol、26pt 固定图标槽、14pt Medium 文本以及浅强调色选中态。删除分组标题，以 1pt 分割线分组，并将页面顶部间距收紧到 14pt。快捷键页使用 38pt 行高、24pt 记录框、4pt 标题后间距和自然高度卡片，为底部保留至少 56pt 空白。

- [ ] **Step 4: 运行定向回归与构建**

  Run: `xcodebuild test -scheme pastera -project pastera.xcodeproj -only-testing:pasteraTests/PreferenceWindowShellTests`

  Expected: PASS。

- [ ] **Step 5: 安装与视觉验收**

  Run: `./script/install_local.sh`

  Expected: `/Applications/Pastera.app` 启动成功；打开设置窗口保存截图，确认图标、文字、间距、选中态和“云同步”均符合设计。
