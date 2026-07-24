# Pastera 设置中心视觉统一与脚本界面重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变既有设置与持久化语义的前提下，统一 Pastera 设置中心视觉语言，重点改善脚本管理体验，并让用户可以从历史记录对指定文本条目执行指定脚本后复制或粘贴结果。

**Architecture:** 继续使用现有 AppKit 设置中心、页面控制器和 `PasteraDesignTokens`。先把页面、分组、操作区、空状态及二级窗口的视觉规格收敛到共享组件，再迁移普通设置页和脚本四个界面；历史记录通过行级上下文菜单调用新增的“单脚本转换”协调接口，复用现有 `ScriptExecuting`、`PasteService`、目标应用恢复和剪贴板抑制机制，不改变脚本模型或数据库结构。

**Tech Stack:** Swift、AppKit、Auto Layout、SF Symbols、KeyHolder、Swift Testing、Xcode 26.5、macOS 13+

## Global Constraints

- 保留设置中心现有七页、搜索、Anchor 高亮、窗口 frame autosave、键盘导航和辅助功能行为。
- 保留所有偏好键、即时写入、OneDrive 同步、Sparkle、脚本 CRUD、模板草稿、JavaScript 校验、独立测试及快捷键语义；历史脚本入口是新增的显式操作，不改变自动复制/粘贴触发。
- 不引入 SwiftUI、第三方 UI 依赖、全局主题、营销页式 Hero、渐变背景或多层卡片嵌套。
- 视觉语言采用原生 macOS 设置风格：稳定主轴、弱边界、紧凑行高、系统字体、SF Symbols、清晰主次操作。
- 页面默认宽度、最小 `680×480` 窗口、深浅色和“减少动态效果”均不得出现裁切、溢出或不可点击控件。
- 脚本编辑器、模板市场和测试窗口必须允许随父窗口可用区域缩小；代码和长文本区域通过滚动吸收空间，不使用会挤出按钮的刚性内容宽度。
- 保留工作区现有未提交改动；实现时只修改本计划列出的设置与测试文件，发生重叠先对照真实 diff 合并。
- 历史脚本 v1 只支持纯文本历史；图片、文件和混合类型不显示脚本操作，不把标题预览当作真实内容执行。
- “复制为”只把转换结果写入系统剪贴板；“粘贴为”写入结果后复用现有目标应用恢复与自动粘贴链；两者都不修改原历史记录，也不生成重复历史。

---

## Business Scope / Out of Scope

### In Scope

- 设置中心共享页面标题、内容边距、分组容器、设置行、状态、空状态、按钮层级和底部操作区。
- 通用、历史记录、快捷键、脚本、忽略应用、云同步和关于页的统一视觉迁移。
- 脚本首页的信息层级、脚本行、空状态、创建/模板/测试入口和全局快捷键区。
- `ScriptEditorViewController`、`ScriptTemplateMarketViewController`、`ScriptTestViewController` 的统一二级窗口框架和响应式约束。
- 中文与英文设置文案中因视觉层级调整而需要的短文案，以及 VoiceOver 标签。
- 历史文本行右键菜单中的“复制为”和“粘贴为”脚本子菜单、单脚本执行、成功/失败反馈与键盘可达性。

### Out of Scope

- 不新增、删除或移动设置项，不改变侧栏信息架构和搜索结果模型。
- 不改变脚本模型、SQLite 格式、模板内容、执行沙箱、剪贴板写回或快捷键冲突规则。
- 不重做主菜单、历史浏览器、密码库、OneDrive 协议或应用安装流程；只在现有历史行菜单增加脚本动作。
- 不把转换结果回写原历史条目，不提供批量脚本、脚本链编排、图片/文件脚本或每个脚本独立全局快捷键。
- 不为“高级感”增加插画、品牌大图、动效系统或新的设计 Token 体系。

## OneClip 实际用法与 Pastera 取舍

### 已核实的 OneClip 工作流

- 设置 → 脚本首页负责脚本启停、排序、编辑、删除、新建、模板、导入和导出；AI 提示词与学习资源属于辅助内容。
- 编辑器把基本信息、启用状态、复制时应用、粘贴时应用、脚本代码、四类快捷键和测试集中在一个纵向滚动页面。
- 历史记录右键菜单提供“复制为”和“粘贴为”，可用脚本作为子菜单选项；成功后明确提示“脚本转换完成”或“已复制到剪贴板”。
- 这说明脚本有三条真实使用路径：复制/粘贴自动触发、快捷键处理当前剪贴板、对指定历史条目显式执行。

### Pastera 的采用与舍弃

- 采用“管理页只管理、编辑器解释执行时机、历史行提供显式脚本动作”的信息架构。
- 采用成功/失败必须有文字与图标反馈、异步执行期间禁止重复触发、删除必须确认等 `$ui-ux-pro-max` 可用原则。
- 不采用其营销卡、AI 提示词、学习资源、订阅提示、橙色高亮和多层深色卡片；这些不符合 Pastera 当前原生 macOS 设置语言。
- 不照搬每脚本四套快捷键。Pastera v1 保留既有统一手动快捷键，把“指定历史条目 + 指定脚本”作为更清晰的补充入口。
- `$ui-ux-pro-max` 输出中的移动端字体、CTA、Teal/Orange 配色与触控尺寸不适用于 AppKit 桌面设置页，仅保留信息层级、可访问反馈、稳定状态和一致间距建议。

---

### Task 1: 收敛设置中心共享视觉基础

**Files:**
- Modify: `pastera/Sources/Preferences/PasteraPreferenceComponents.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Modify: `pasteraTests/PreferenceWindowShellTests.swift`
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift`

**Interfaces:**
- Consumes: `PasteraDesignTokens.colors(for:opacity:)`、`PasteraPreferencePageViewController`、`PasteraPreferenceGroupView`、`PasteraPreferenceSettingRowView`。
- Produces: `PasteraPreferenceSectionHeaderView`、`PasteraPreferenceEmptyStateView`、`PasteraPreferenceActionBarView` 和统一的页面/分组/行布局常量，供七个页面及脚本二级窗口复用。

- [ ] **Step 1: 写共享视觉契约的失败测试**

  在 `PreferencePaneAlignmentTests` 增加断言：所有原生页面使用同一标题字号、16pt 水平内容边距、12pt 页面模块间距；共享设置行的默认最小高度一致；分组头和正文沿同一左边线。测试通过 DEBUG 只读属性取值，不做截图替代。

- [ ] **Step 2: 运行定向测试并确认 RED**

  ```bash
  xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData-preferences-visual \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:pasteraTests/PreferencePaneAlignmentTests \
    -only-testing:pasteraTests/PreferenceWindowShellTests
  ```

  Expected: 新增视觉契约属性或共享组件尚不存在，测试编译失败或断言失败。

- [ ] **Step 3: 实现共享组件与稳定布局常量**

  在 `PasteraPreferenceComponents.swift` 内集中定义并复用：页面标题 22pt semibold、页面水平边距 16pt、页面模块间距 12pt、分组圆角/边框、设置行标签/说明层级、标准 48pt 行高。新增三个小型组件：

  ```swift
  final class PasteraPreferenceSectionHeaderView: NSStackView {
      init(title: String, subtitle: String?, symbolName: String?)
  }

  final class PasteraPreferenceEmptyStateView: NSStackView {
      init(symbolName: String, title: String, message: String)
  }

  final class PasteraPreferenceActionBarView: NSStackView {
      init(primaryAction: NSButton?, secondaryActions: [NSButton])
  }
  ```

  `CPYPreferencesWindowController` 只调整背景、内容区和滚动区与共享规格的衔接，不修改侧栏目录、搜索或窗口生命周期。

- [ ] **Step 4: 运行共享设置测试并确认 GREEN**

  复用 Step 2 命令；Expected: 两个 suite 全部通过，现有 Anchor、滚动和窗口尺寸测试无回归。

---

### Task 2: 将普通设置页迁移到统一视觉节奏

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYGeneralPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYHistoryPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYExcludeAppPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYAboutPreferenceViewController.swift`
- Modify: `pasteraTests/GeneralPreferenceHelpButtonLayoutTests.swift`
- Modify: `pasteraTests/HistoryPreferenceTests.swift`
- Modify: `pasteraTests/ShortcutPreferenceLayoutDensityTests.swift`
- Modify: `pasteraTests/ExcludeAppPreferenceTests.swift`
- Modify: `pasteraTests/SyncPreferenceTopSectionTests.swift`
- Modify: `pasteraTests/AboutPreferenceTests.swift`

**Interfaces:**
- Consumes: Task 1 的共享分组、设置行、空状态和操作区组件。
- Produces: 六个普通设置页一致的主轴、密度、标题层级、控件中心线和危险操作表达；所有原业务 action 与 Anchor ID 保持不变。

- [ ] **Step 1: 为页面级一致性补失败断言**

  每个既有测试 suite 增加本页可验证 claim：同类设置行共享高度；控件中心线与文字区域中心线一致；危险操作与常规操作不混排；空状态不使用固定大空白；窄内容宽度下按钮完整位于分组内。

- [ ] **Step 2: 运行六个页面的定向测试并确认 RED**

  ```bash
  xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData-preferences-visual \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:pasteraTests/GeneralPreferenceHelpButtonLayoutTests \
    -only-testing:pasteraTests/HistoryPreferenceTests \
    -only-testing:pasteraTests/ShortcutPreferenceLayoutDensityTests \
    -only-testing:pasteraTests/ExcludeAppPreferenceTests \
    -only-testing:pasteraTests/SyncPreferenceTopSectionTests \
    -only-testing:pasteraTests/AboutPreferenceTests
  ```

  Expected: 至少一项新布局 claim 在旧实现上失败。

- [ ] **Step 3: 按页面职责统一构图**

  通用、历史和快捷键页保持紧凑设置行；忽略应用页统一列表空状态和底部添加/移除操作；同步页把账户状态、同步范围、执行动作按阅读顺序排列，避免状态徽章和按钮竞争主视觉；关于页保留应用身份区但降低装饰重量。只复用 Task 1 组件，不改偏好读写、服务调用、Anchor ID 或本地化 key。

- [ ] **Step 4: 运行定向测试并确认 GREEN**

  复用 Step 2 命令；Expected: 六个 suite 全部通过。

---

### Task 3: 重构脚本设置首页的工作流层级

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/ScriptPreferenceTests.swift`
- Modify: `pasteraTests/PreferenceSearchTests.swift`

**Interfaces:**
- Consumes: `ScriptRepositoryProtocol`、`ScriptExecuting`、`HotKeyService`、Task 1 的共享组件。
- Produces: `makeScriptManagementGroup()`、`makeScriptRow(_:)`、`makeManualShortcutGroup()`；首页继续从现有 action 打开编辑器、模板市场和测试 Sheet。

- [ ] **Step 1: 写脚本首页信息层级的失败测试**

  扩展 `scriptsPreferencePageSeparatesManagementShortcutAndTesting`，断言首页只有两个一级视觉组：脚本管理和手动运行；空状态高度为 96–120pt；主操作仅为“新建脚本”；模板与测试为次操作；脚本行不再有独立卡片边框；测试按钮在无脚本时禁用、有脚本时启用。

- [ ] **Step 2: 运行脚本设置测试并确认 RED**

  ```bash
  xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData-preferences-visual \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:pasteraTests/ScriptPreferenceTests \
    -only-testing:pasteraTests/PreferenceSearchTests
  ```

  Expected: 旧首页仍使用自建卡片、136pt 空状态和独立脚本行背景，新断言失败。

- [ ] **Step 3: 使用共享设置组件重组首页**

  用一个全宽脚本管理分组承载标题、说明、列表/空状态和底部操作栏；脚本行改为弱分割列表，名称和触发条件为主信息，启用开关与编辑/删除为尾部操作。手动运行快捷键保持独立轻量设置组，不嵌入测试控件。删除 `replacePageBottomConstraintForCompactContent()` 这类页面特例，恢复共享页面自然内容高度。

- [ ] **Step 4: 收紧文案和辅助功能标签**

  在 `Localizable.xcstrings` 中只调整脚本页必要短文案；图标按钮的 accessibility label 必须包含目标脚本名称。搜索标题、关键词和 Anchor 继续指向脚本页，不增加新页面。

- [ ] **Step 5: 运行定向测试并确认 GREEN**

  复用 Step 2 命令；Expected: 脚本首页、真实 JavaScript、独立测试和设置搜索测试全部通过。

---

### Task 4: 统一脚本编辑、模板市场和测试二级窗口

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/ScriptEditorViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/ScriptTemplateMarketViewController.swift`
- Modify: `pastera/Sources/Preferences/Panels/ScriptTestViewController.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceComponents.swift`
- Modify: `pasteraTests/ScriptPreferenceTests.swift`

**Interfaces:**
- Consumes: 现有 `ScriptExecuting`、`ScriptTemplateCatalog`、`ScriptTransform` 和 Task 1 共享视觉组件。
- Produces: `PasteraPreferenceSheetScaffold`，统一 title/subtitle、滚动内容、底部操作与窗口最小/理想尺寸；三个 controller 的业务回调签名保持不变。

- [ ] **Step 1: 写二级窗口一致性与缩放失败测试**

  在 `ScriptPreferenceTests` 增加断言：三个 controller 使用同一 Sheet scaffold；标题、说明、关闭/保存操作位于一致区域；宽度缩至 560pt 时内容没有水平溢出；编辑器代码区、模板列表和测试输入区各自滚动；结果出现/消失不推动主要操作出窗口。

- [ ] **Step 2: 运行脚本测试并确认 RED**

  复用 Task 3 Step 2 命令。Expected: 三个窗口当前分别固定为 `760×680`、`760×650`、`620×500`，且模板卡有 590pt 最小标签宽度，新断言失败。

- [ ] **Step 3: 新增共享 Sheet 框架**

  在 `PasteraPreferenceComponents.swift` 新增：

  ```swift
  final class PasteraPreferenceSheetScaffold: NSView {
      init(
          title: String,
          subtitle: String,
          contentView: NSView,
          leadingActions: [NSButton],
          trailingActions: [NSButton]
      )
  }
  ```

  框架提供 560pt 最小宽度、760pt 理想宽度、统一 20–22pt 内容边距、弱分割头/底栏和自然高度约束；窗口高度不足时只滚动正文。

- [ ] **Step 4: 迁移编辑器**

  保持基础信息、执行配置、脚本代码和测试四段顺序；去掉每段独立厚卡片感，改为共享正文中的弱分区。代码编辑器保留等宽字体和独立滚动；保存仍要求名称、触发条件、`transform(clip)` 和成功校验，字段变化继续使旧校验失效。

- [ ] **Step 5: 迁移模板市场和测试窗口**

  模板市场移除 590pt 标签最小宽度和刚性 760pt 列表宽度，模板项改为可压缩的标题/说明/代码摘要 + 固定尾部添加按钮；搜索与分类在空间不足时整体换为两行。测试窗口保持选择器、输入、运行、结果的单列顺序，运行状态和成功/失败同时使用图标与文字。

- [ ] **Step 6: 运行脚本定向测试并确认 GREEN**

  复用 Task 3 Step 2 命令；Expected: 脚本首页、编辑器、模板市场、测试窗口及真实 JavaScript 测试全部通过。

---

### Task 5: 在历史记录中提供指定脚本的“复制为 / 粘贴为”

**Files:**
- Modify: `pastera/Sources/Services/ClipboardScriptCoordinator.swift`
- Modify: `pastera/Sources/Services/PasteService.swift`
- Modify: `pastera/Sources/Managers/HistoryMenuRowView.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/ClipboardScriptCoordinatorTests.swift`
- Modify: `pasteraTests/MainMenuEmbeddedContentTests.swift`
- Modify: `pasteraTests/HistoryMenuKeyEquivalentTests.swift`

**Interfaces:**
- Consumes: `ScriptRepositoryProtocol.fetchAll()`、`ScriptExecuting.execute(scripts:input:)`、`PasteboardHistoryRepository.fetchContent(id:)`、`PasteService.pasteText(_:restoring:)` 和 `PasteTargetContext`。
- Produces: `availableHistoryScripts() -> [ScriptTransform]`、`transformHistoryText(_:using:sourceAppBundleIdentifier:) async -> ScriptTransformOutcome`、历史行 `onCopyUsingScript` / `onPasteUsingScript` 菜单动作。

- [x] **Step 1: 写单脚本历史转换的失败测试**

  在 `ClipboardScriptCoordinatorTests` 增加：只返回启用且支持手动运行的脚本并保持 `sortIndex` 顺序；指定脚本执行时只传入该脚本；禁用、缺失、失败和输出不变分别映射为明确 outcome；转换结果写入剪贴板后抑制监听器重复采集一次。

- [x] **Step 2: 写历史行菜单的失败测试**

  在 `MainMenuEmbeddedContentTests` 与 `HistoryMenuKeyEquivalentTests` 增加：纯文本行在有可用脚本时显示“复制为”和“粘贴为”两个子菜单；每个子菜单按脚本顺序列项；图片/文件行或无脚本时不显示；菜单项具有脚本名称和完整 accessibility label；键盘可以打开菜单并选择动作。

- [x] **Step 3: 运行历史脚本定向测试并确认 RED**

  ```bash
  xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData-preferences-visual \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:pasteraTests/ClipboardScriptCoordinatorTests \
    -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
    -only-testing:pasteraTests/HistoryMenuKeyEquivalentTests
  ```

  Expected: 单脚本 API 和历史行脚本菜单尚不存在，测试编译失败或断言失败。

- [x] **Step 4: 实现可用脚本查询与指定脚本转换**

  在 `ClipboardScriptCoordinating` 增加：

  ```swift
  func availableHistoryScripts() -> [ScriptTransform]
  func transformHistoryText(
      _ text: String,
      using scriptID: UUID,
      sourceAppBundleIdentifier: String?
  ) async -> ScriptTransformOutcome
  ```

  `availableHistoryScripts()` 只返回 `isEnabled && runManually` 的脚本；`transformHistoryText` 必须重新从 repository 解析脚本 ID，避免菜单打开后脚本已删除仍执行陈旧对象。执行只传一个脚本，不串联其他自动触发脚本。

- [x] **Step 5: 扩展历史行上下文菜单**

  `HistoryMenuRowView` 接收结构化脚本动作而不是持有 repository：

  ```swift
  struct HistoryScriptAction {
      let id: UUID
      let title: String
      let copy: () -> Void
      let paste: () -> Void
  }
  ```

  在现有“编辑 / 删除”菜单前增加“复制为”和“粘贴为”子菜单；主菜单嵌入模式和独立历史面板复用同一构造路径。菜单为空时完全省略，不显示不可用占位。

- [x] **Step 6: 连接真实历史内容、剪贴板与粘贴链**

  `MenuManager` 只为 `.string` / `.deprecatedString` 历史读取 `PasteboardContent.stringValue`。复制动作异步执行指定脚本，成功后通过协调器写入剪贴板并登记 suppression；粘贴动作成功后调用 `PasteService.pasteText(output, restoring: targetContext)`。动作开始后关闭历史浮层，禁止重复提交，原历史 ID 和内容不变。

- [ ] **Step 7: 增加非静默反馈与错误边界**

  成功反馈包含脚本名和“已复制”或“已粘贴”；失败区分脚本已删除、脚本禁用、执行超时、JavaScript 错误和结果类型错误。使用系统通知/HUD 的现有最轻量反馈入口；不得只用红绿颜色，也不得弹阻塞式错误对话框。

- [ ] **Step 8: 运行定向测试并确认 GREEN**

  复用 Step 3 命令；Expected: 三个 suite 全部通过，历史原内容不变且剪贴板抑制只消费一次。

  > 2026-07-17 实施记录：Swift 解析与 `git diff --check` 已通过。Xcode 定向测试和构建均停在 SwiftPM 对 GRDB.swift、realm-core 执行递归 submodule update；因本机磁盘仅余约 475 MiB，已主动终止，未将其标记为 GREEN。Step 7 的可见成功/失败反馈仍待实现。

---

### Task 6: 构建、真实窗口与视觉验收

**Files:**
- Modify only if evidence exposes a P1/P2 issue: files listed in Tasks 1–4
- Update: this plan's `Delivery Record`

**Interfaces:**
- Consumes: Tasks 1–5 完成后的设置中心、脚本历史工作流和现有本地安装脚本。
- Produces: 可复核的测试、构建、运行和截图证据；不另建交付文件。

- [ ] **Step 1: 运行设置与脚本相关回归**

  ```bash
  xcodebuild test -project pastera.xcodeproj -scheme pastera -destination 'platform=macOS' \
    -derivedDataPath .build/DerivedData-preferences-visual \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:pasteraTests/PreferenceWindowShellTests \
    -only-testing:pasteraTests/PreferencePaneAlignmentTests \
    -only-testing:pasteraTests/PreferenceWindowInteractionRegressionTests \
    -only-testing:pasteraTests/PreferenceSearchTests \
    -only-testing:pasteraTests/ScriptPreferenceTests \
    -only-testing:pasteraTests/ScriptTemplateCatalogTests \
    -only-testing:pasteraTests/ClipboardScriptCoordinatorTests \
    -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
    -only-testing:pasteraTests/HistoryMenuKeyEquivalentTests
  ```

  Expected: 所有定向 suite 通过，无 Auto Layout assertion。

- [ ] **Step 2: 运行完整回归与静态检查**

  ```bash
  git diff --check
  jq empty pastera/Resources/Localizable.xcstrings
  xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -scheme pastera -project pastera.xcodeproj \
    -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
    -packageCachePath "$PWD/.spm-cache/PackageCache" \
    -skipPackagePluginValidation -skipMacroValidation clean test
  ```

  Expected: diff 与本地化格式检查退出 0；完整测试通过。

- [ ] **Step 3: 安装并打开真实设置窗口**

  ```bash
  ./script/install_local.sh
  open -a /Applications/Pastera.app --args --open-preferences
  ```

  Expected: `/Applications/Pastera.app` 为当前构建且设置窗口成功显示。

- [ ] **Step 4: 完成页面级截图验收**

  在浅色和深色外观分别检查：七个设置页默认宽度与最小宽度；脚本空态和多脚本态；编辑器初始/校验成功/失败；模板市场默认/搜索结果/空结果；测试窗口初始/成功/失败。逐项确认主轴、模块边界、视觉密度、控件中心线、空白平衡、焦点顺序、横向溢出和操作可见性。

- [ ] **Step 5: 回写唯一计划**

  将真实变更、偏差、测试命令结果、截图路径、安装进程、历史脚本复制/粘贴结果、剩余风险和后续项写入下方 `Delivery Record`。P1/P2 视觉问题或历史脚本 P1 行为问题未修复并重新验证前，不得标记计划完成。

---

## Acceptance Mapping

| 验收项 | 自动化/静态证据 | 真实 UI 证据 |
| --- | --- | --- |
| 七页共享标题、边距、分组和设置行节奏 | `PreferencePaneAlignmentTests`、各页面定向测试 | 默认/最小宽度七页截图 |
| 设置项行为、搜索、Anchor 与键盘导航不变 | `PreferenceWindowShellTests`、`PreferenceSearchTests`、`PreferenceWindowInteractionRegressionTests` | 搜索定位、滚动和焦点人工操作 |
| 脚本首页层级清晰且无卡片拼贴 | `ScriptPreferenceTests` 首页结构断言 | 空态与多脚本态截图 |
| 编辑器、模板市场、测试窗口统一且可缩放 | `ScriptPreferenceTests` scaffold/布局断言 | 560pt 窄宽和理想宽度截图 |
| JavaScript、模板、快捷键和剪贴板边界不变 | `ScriptPreferenceTests`、`ScriptTemplateCatalogTests`、现有 execution/coordinator tests | 编辑、模板创建、独立测试完整路径 |
| 历史文本可按指定脚本“复制为 / 粘贴为” | `ClipboardScriptCoordinatorTests`、`MainMenuEmbeddedContentTests`、`HistoryMenuKeyEquivalentTests` | 右键选择脚本、复制结果、粘贴到前台应用 |
| 历史脚本不会修改原条目或重复采集 | coordinator suppression 与 repository 回读断言 | 操作前后历史内容/数量人工核对 |
| 深浅色、文本、状态和辅助功能可读 | 本地化 JSON 检查、accessibility label 断言 | 浅色/深色、成功/失败/空状态截图 |
| 可安装并供用户复验 | 完整 `xcodebuild clean test`、安装脚本 | `/Applications/Pastera.app` 运行进程与真实设置窗口 |

## Risks, Rollback and Observation

- 最大风险是共享组件调整导致七个页面同时出现高度或约束回归；按 Task 1→2→3→4 分层实施，每层保持可独立回退。
- `CPYPreferencesWindowController.swift` 当前存在用户未提交改动，实施前必须重新读取 diff，只合并与设置视觉直接相关的部分。
- 模板市场和编辑器取消刚性宽度后，长中文、英文和代码摘要可能暴露压缩优先级问题；必须在 560pt 与 760pt 两档真实窗口检查。
- 历史脚本动作是异步的，菜单关闭、目标应用恢复和脚本完成存在时序风险；必须捕获打开历史面板前的 `PasteTargetContext`，不得在脚本结束后重新猜测前台应用。
- “粘贴为”会写入系统剪贴板并发送粘贴事件；失败时必须保留原剪贴板或明确提示，且只有成功写入后才能触发粘贴。
- 视觉回滚以恢复本计划涉及的共享组件和页面布局提交为单位，不回滚业务 model、repository、同步或脚本执行文件。
- 观察重点：Auto Layout 控制台告警、页面切换后的内容高度、搜索 Anchor 滚动位置、Sheet 关闭后的焦点恢复、长脚本名和长错误文本。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-17-preferences-visual-unification.md`
- Plan Status: `confirmed-not-started`
- Evidence Profile: `standard`
- Story ID: `not-applicable`
- Task IDs: `not-applicable`; Superpowers Tasks 1–6 组成一个本地 UI 与历史脚本交付闭环
- ZenTao Sync Status: `not-synced`（本需求未要求 ZenTao 归档）
- ZenTao Readback Evidence / Time: `not-applicable`
- Last Updated: `2026-07-23 Asia/Shanghai`

## Delivery Record

### Actual Implementation

- 2026-07-23 完成了本轮用户明确要求的脚本设置范围，即 Task 3、Task 4 及对应的 Task 6 验收；整份计划的普通设置页和历史脚本剩余工作未在本轮扩展。
- 脚本首页改为单一全高“我的脚本”工作区。脚本列表占满剩余高度，操作栏与全局快捷键固定在底部；脚本行使用弱分割列表，尾部直接提供启用、上移、下移、编辑和删除；“新建脚本”为唯一主操作，模板和测试为次操作。
- `PasteraPreferenceComponents.swift` 增加共享空状态、操作栏和 `PasteraPreferenceSheetScaffold`。三个脚本 Sheet 统一为固定标题区、可滚动正文和固定底部操作区，最小宽度均为 560pt。
- 编辑器按基本信息、执行配置、代码和保存前验证连续排布；保存继续要求必填项和一次成功验证。模板市场改为弱分割行与固定尾部“添加”按钮；独立测试使用单列布局和稳定的图标加文字结果区。
- 保留原脚本模型、repository、JavaScript 执行、模板内容、快捷键语义和 Sheet 回调签名；模板选择进入编辑器、编辑器取消、独立测试均沿用真实父窗口 Sheet 生命周期。

### Plan Deviations

- 本轮没有实施 Task 1、Task 2，也没有继续 Task 5 Step 7–8；因此整份计划仍未完成，不能据此宣称七个设置页已统一。
- `Localizable.xcstrings` 未发生变化；新增短文案继续使用现有 `pasteraScriptString` 双语入口，避免为本轮脚本局部重构扩大本地化文件 diff。
- Task 4 的编辑器在 760pt 理想宽度下将代码区收紧为 158pt、测试输入区收紧为 64pt，使“保存前验证”在初始视口中可见；正文仍可独立滚动。
- 完整 `clean test` 在全量并行负载下退出 65，最终列出 8 个非脚本 UI 的超时/性能失败；把对应 6 个 suite 隔离重跑后 125 个测试全部通过。该事实记录为全仓回归缺口，不包装成完整 GREEN。

### Impact

- 本轮实际影响脚本设置首页、脚本编辑器、模板市场、独立测试 Sheet 及设置共享组件；没有修改脚本数据模型、SQLite、执行沙箱、剪贴板写回或快捷键持久化。
- 实施期间工作区原有主菜单、密码箱和其他未提交改动均被保留；脚本设置范围最终由提交 `178af2c` 独立推送，没有混入其他任务。

### Verification

- TDD RED：新增首页共享组/操作层级、排序、Sheet scaffold、编辑器弱分区和模板尾部操作断言后，`ScriptPreferenceTests` 按预期失败。
- `ScriptPreferenceTests`：14 个测试通过，包含真实 JavaScript、模板筛选、全高工作区、Sheet 响应式契约、行内排序和独立测试不修改剪贴板。
- `PreferenceWindowInteractionRegressionTests`：3 个测试通过，真实覆盖“设置 → 脚本 → 从模板创建 → 添加 → 编辑器取消”Sheet 链路。
- Task 6 定向回归：`PreferenceWindowShellTests`、`PreferencePaneAlignmentTests`、`PreferenceWindowInteractionRegressionTests`、`PreferenceSearchTests`、`ScriptPreferenceTests`、`ScriptTemplateCatalogTests`、`ClipboardScriptCoordinatorTests`、`MainMenuEmbeddedContentTests`、`HistoryMenuKeyEquivalentTests` 共 132 个测试、9 个 suite 通过。
- 静态检查：`git diff --check` 与 `jq empty pastera/Resources/Localizable.xcstrings` 均退出 0；聚焦测试日志未出现 Auto Layout 冲突。
- 完整回归：全量 `xcodebuild ... clean test` 退出 65，最终失败列表为 8 个 Agent/密码箱/性能测试；对应 6 个 suite 隔离重跑 125 个测试全部通过，说明失败只在全量并行负载中复现。
- 安装：`./script/install_local.sh --verify` 构建、临时签名、磁盘校验和 `/Applications/Pastera.app` 进程路径校验均通过。
- 真实 UI：通过 Computer Use 实操模板创建、编辑器测试成功、取消返回、独立“压缩 JSON”测试输出 `{"a":1}`；深色主页/模板/编辑器截图分别位于 `/var/folders/0_/qwspc2w10vg5kh3qp84jcmb80000gn/T/com.openai.sky.CUAService/Pastera Screenshot 2026-07-23 at 4.22.23 PM.jpeg`、`/var/folders/0_/qwspc2w10vg5kh3qp84jcmb80000gn/T/com.openai.sky.CUAService/Pastera Screenshot 2026-07-23 at 4.22.33 PM.jpeg`、`/var/folders/0_/qwspc2w10vg5kh3qp84jcmb80000gn/T/com.openai.sky.CUAService/Pastera Screenshot 2026-07-23 at 4.22.58 PM.jpeg`，浅色主页截图位于 `/var/folders/0_/qwspc2w10vg5kh3qp84jcmb80000gn/T/com.openai.sky.CUAService/Pastera Screenshot 2026-07-23 at 4.26.12 PM.jpeg`。
- 全高布局补充验收：默认 `760×600` 和最小 `680×480` 均保持操作与快捷键可见；真实执行“从模板创建 → 移除空行 → 运行测试 → 取消返回”未再卡住。

### Remaining Risks

- 全量并行 `clean test` 尚未取得退出 0；隔离重跑已排除脚本 UI 回归，但 Agent 命令超时、Broker 时序和 10k 搜索性能在全量负载下仍可能抖动。
- 本轮只对脚本相关页面完成深浅色和理想宽度实机验收；七个普通设置页、脚本空态/多脚本态及所有 560pt 截图仍属于整份计划的后续验收范围。
- Computer Use 截图位于系统临时目录，后续系统清理后路径可能失效。

### Follow-ups

- 后续继续本计划时，先完成 Tasks 1–2 的普通设置页统一、Task 5 Step 7 的非静默反馈，以及 Task 6 的七页/560pt 完整截图矩阵。
- 将全量并行回归中的 8 个负载型失败作为独立稳定性问题处理，不与本轮脚本 UI diff 混改。

### ZenTao Closeout

- 未要求，未执行。
