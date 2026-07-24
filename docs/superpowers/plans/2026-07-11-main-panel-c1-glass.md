# Pastera Main Panel Visual Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 Pastera 主界面从多层卡片式工具面板升级为精致、克制、系统原生的 macOS 高频操作面板，同时保留现有信息架构和业务行为。

**Architecture:** 保留 `MainMenuPanelController` 作为主界面状态与交互协调器，不改历史、片段、密码库、同步和安全链路。视觉层以 `MainMenuPanelLayout`、`MainMenuVisualColors`、现有 AppKit 子视图和 `PasteraDesignTokens` 为边界，将当前三个独立圆角表面收敛为一个连续面板，通过排版、留白、轻分隔和状态反馈建立层级。

**Tech Stack:** Swift, AppKit, SF Symbols, Swift Testing, macOS Accessibility APIs

## Design Read

Reading this as: 面向键盘优先和高频剪贴操作用户的原生 macOS 紧凑工具面板，采用冷静、精确、轻量的系统语言，靠 AppKit 语义材质和 SF Symbols 建立质感。

- `DESIGN_VARIANCE: 5`：保留系统秩序，但避免机械的三块等宽卡片。
- `MOTION_INTENSITY: 4`：只为模式切换、搜索展开、hover、编辑态和拖拽提供反馈。
- `VISUAL_DENSITY: 6`：保持 282pt 高频工具密度，通过层级优化减少拥挤感，不盲目放大面板。
- Redesign mode: targeted evolution。保留品牌、信息架构、快捷键和功能路径，只重构视觉层级与反馈。

## Global Constraints

- 保留主界面固定宽度、现有历史、片段、密码库和 OneDrive 入口，不新增产品功能。
- 默认浏览模式不暴露编辑控件；编辑模式和拖拽能力保持现有业务契约。
- 不引入 SwiftUI、第三方 UI 库、自绘图标、营销式渐变、霓虹外发光或装饰性动画。
- 只使用 SF Symbols 与 AppKit 语义颜色；单一强调色跟随系统 `controlAccentColor`。
- 采用统一形状规则：面板 16pt，浮层控件 8pt，分段选择器使用胶囊形；列表默认不套卡片。
- 主界面保持深色主题，但必须支持降低透明度、提高对比度和降低动态效果。
- 所有动画只改变 `transform` 或 `opacity`，持续时间为 100ms 到 160ms，并尊重系统降低动态效果设置。
- 保留当前本地化 key、辅助功能标签、快捷键、焦点顺序和右键菜单语义。
- 不覆盖工作区中正在进行的密码库、文件夹新建、上下文操作和拖拽排序改动。

## Business Scope / Out of Scope

### In Scope

- 主面板外壳、顶部模式上下文、内容列表、底部命令区和搜索抽屉的视觉层级。
- 历史、片段、密码库普通态，以及空态、加载态、错误态、编辑态和拖拽态的一致呈现。
- hover、pressed、selected、focused、disabled 和 destructive 状态。
- 键盘、VoiceOver、降低透明度、提高对比度和降低动态效果验收。
- 安装版真实截图对比和人工交互体感验收。

### Out of Scope

- 数据模型、数据库、同步协议、KDBX、安全认证和剪贴板业务逻辑。
- 主面板宽度扩展、独立窗口、侧栏、模态向导或完整品牌重做。
- 设置中心、状态栏右键菜单和旧独立历史面板的视觉改造。
- 新的编辑能力、多选、嵌套文件夹、撤销历史或跨模块拖拽。

## Visual Direction

### 1. 从三块卡片改为一体化工具面板

- 移除 header、content、footer 三块同权重圆角底板和重复描边。
- 面板使用单一深色基底和一层极轻内边缘，内容区依靠 8pt 节奏与必要的单条 hairline 分组。
- 列表行默认透明，只在 hover、键盘焦点、选中和拖拽目标时出现背景。
- 阴影只用于面板与桌面的空间关系，不用于每个内部模块。

### 2. 重建信息层级

- 顶部左侧显示当前内容类型或文件夹上下文，右侧保留紧凑分页或上下文操作。
- 当前模式选择器是底部唯一高权重组合控件；搜索、同步、设置降为次级图标操作。
- 同一时刻只允许一个主强调状态：当前模式、当前选中行或主保存按钮按场景互斥出现。
- 行标题使用 13pt Medium，辅助信息使用 11pt Regular；数字快捷键使用等宽数字并降低对比度。

### 3. 强化交互体感

- hover 在 100ms 内淡入；pressed 使用轻微 0.98 缩放或 1pt 位移；选中态避免大面积饱和蓝。
- 模式切换用 140ms 内容淡出与淡入，焦点和滚动位置按当前业务规则恢复。
- 搜索抽屉保持向下展开，但让面板外形连续变化，避免出现第四块独立卡片。
- 拖拽插入线、目标文件夹高亮和 450ms 悬停展开使用同一强调色与统一反馈强度。
- 降低动态效果时全部切为即时状态变化。

### 4. 补齐完整状态

- 空态保持紧凑，只说明当前为什么为空，并提供一个上下文明确的主操作。
- 加载态使用与真实行尺寸一致的静态占位，不使用旋转进度指示器。
- 错误态在内容区内显示原因和重试操作，不用瞬时 toast 承担持久错误。
- 编辑态继续内嵌在当前文件夹上下文中，输入、错误和保存状态与浏览列表共享基线。

## File Structure

- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`，调整主面板布局常量、内部表面、行状态、搜索抽屉、模式切换和完整状态呈现。
- Modify: `pastera/Sources/Managers/MainMenuHeaderItemView.swift`，统一顶部上下文、hover、焦点和拖动区域的视觉行为。
- Modify: `pastera/Sources/Utility/PasteraDesignSystem.swift`，仅补充可复用的主面板语义 token，不复制第二套颜色系统。
- Modify: `pastera/Resources/Localizable.xcstrings`，只在空态、错误态或辅助功能需要新文案时增加本地化。
- Modify: `pasteraTests/MainMenuVisualPolishTests.swift`，用语义层级与状态规则替换当前三块表面坐标断言。
- Modify: `pasteraTests/MainMenuEmbeddedContentTests.swift`，覆盖普通态、空态、加载态、错误态和编辑态结构。
- Modify: `pasteraTests/MainMenuModeIconTests.swift`，验证 SF Symbols、选中态和辅助功能标签。
- Reference only: `pasteraTests/MainMenuChildNavigationTests.swift`、`pasteraTests/MainMenuPinFooterTests.swift`、`docs/verification/VERIFICATION.md`。

## Tasks

### Task 1: 建立真实视觉基线与语义验收

**Produces:** 当前安装版在历史、片段、密码库、搜索、空态、编辑态和拖拽态的同尺寸截图集，以及对应问题清单。

- [ ] 使用当前安装版逐一捕获默认历史、片段、密码库、搜索展开、空态、hover、键盘选中、编辑和拖拽状态。
- [ ] 对照 282pt 面板测量边距、行高、控件命中区、文字基线、表面层数、强调色面积和焦点顺序。
- [ ] 将问题分为结构问题和润色问题，先解决卡片套卡片、层级竞争、密集描边和状态不一致。
- [ ] 固定同一屏幕位置、外观模式和数据样本，作为改造前后截图基线。

### Task 2: 收敛 token 与一体化面板骨架

**Produces:** 单一面板基底、统一间距与形状规则，以及不依赖三块卡片坐标的布局测试。

- [ ] 先在 `MainMenuVisualPolishTests` 写失败断言，验证内部不存在三个同权重圆角表面、列表行为透明默认态、内部只保留必要分隔。
- [ ] 将主面板颜色映射回 `PasteraDesignTokens` 的语义角色，删除 `MainMenuVisualColors` 中职责重复的 surface token。
- [ ] 保留 282pt 宽度和现有可用高度，重排顶部、内容与底部命令区的视觉层级。
- [ ] 验证普通、置顶、附着状态栏、搜索展开和屏幕边缘定位不发生尺寸跳变。

### Task 3: 优化顶部、列表和底部命令区

**Produces:** 清晰的上下文标题、安静的列表默认态、唯一主模式选择器和统一图标命中区。

- [ ] 为 header 的标题、辅助信息、返回、分页和类型筛选建立固定基线与最小 28pt 命中区。
- [ ] 让列表行只在 hover、focus、selected、drag target 时显示表面，删除常态卡片感。
- [ ] 统一图标为 SF Symbols，同类图标使用一致 point size、weight 和 optical alignment。
- [ ] 将底部历史、片段、密码库归为一个分段模式控件，搜索、同步和设置保持次级操作。
- [ ] 保留所有现有 tooltip、辅助功能标签、快捷键与键盘导航路径。

### Task 4: 统一搜索、编辑、空载错和拖拽反馈

**Produces:** 不跳出当前上下文的完整状态循环，以及一致的微交互反馈。

- [ ] 为搜索抽屉、模式切换、内嵌编辑、空态、加载态和错误态分别补充失败测试。
- [ ] 搜索展开时让面板外壳连续延伸，保持内容和 footer 的屏幕位置规则。
- [ ] 编辑态保留文件夹上下文，输入控件与列表文字基线对齐，错误信息在字段附近呈现。
- [ ] 统一 hover、pressed、focus、selected、disabled、destructive、drag insertion 和 drag target 状态。
- [ ] 验证降低动态效果、降低透明度和提高对比度环境下的静态替代与可读性。

### Task 5: 回归、安装版视觉验收与体感验收

**Produces:** 自动化证据、安装版截图对比和人工交互验收记录。

- [ ] 运行主菜单相关 suite，确认视觉规则、模式导航、编辑、排序、密码库和搜索行为通过。
- [ ] 运行仓库默认 `xcodebuild` 回归与 `git diff --check`，记录与本需求无关的既有失败。
- [ ] 执行 `./script/install_local.sh`，验证 `/Applications/Pastera.app` 进程与签名。
- [ ] 用 Task 1 相同条件重拍所有状态，并逐项比较边距、基线、层级、状态和可读性。
- [ ] 人工验证鼠标 hover、点击按压、键盘切换、搜索展开、编辑保存、右键菜单和真实拖拽手感。

## Acceptance Mapping

| Acceptance | Implementation | Evidence |
| --- | --- | --- |
| 主界面不再有卡片套卡片感 | Task 2 一体化面板骨架 | 前后同尺寸截图 + 结构测试 |
| 当前内容、选中项和主操作层级清晰 | Task 3 顶部、列表和底部重排 | 普通态、选中态、模式态截图 + 焦点测试 |
| 浏览态不暴露编辑控件 | Task 3 和 Task 4 状态规则 | 片段与密码库浏览态测试 + 截图 |
| 搜索和编辑不造成尺寸或上下文跳变 | Task 4 连续外壳与内嵌状态 | 搜索、编辑布局测试 + 人工操作 |
| 空态、加载态、错误态可理解且可恢复 | Task 4 完整状态循环 | 状态测试 + 安装版截图 |
| 鼠标、键盘、拖拽反馈一致 | Task 3 和 Task 4 交互状态 | 聚焦测试 + 人工体感验收 |
| 辅助功能设置下仍可使用 | Task 4 系统偏好降级 | Reduce Motion、Reduce Transparency、Increase Contrast 人工验收 |
| 业务行为无回归 | 全部任务保持 controller 数据源契约 | 主菜单相关 suite + 默认全量回归 |

## Risks, Rollback and Observation

- 最大风险是 `MainMenuPanelController.swift` 当前同时承载布局、状态和交互，视觉改造容易触碰正在进行的编辑与密码库代码。实施时必须小步提交，并基于当前脏工作区逐段合并。
- 移除内部表面后，透明度和不同桌面背景可能降低可读性。主面板保持近不透明深色基底，并为降低透明度模式提供实色结果。
- 过度动画会降低高频工具效率。任何无法解释为层级、反馈或状态变化的动画都不实现。
- 回滚以视觉层提交为单位，不回滚数据源、Repository、KDBX 或同步改动。
- 上线观察聚焦打开速度、模式切换延迟、搜索展开尺寸、键盘焦点、拖拽插入反馈和不同辅助功能设置下的可读性。

## 2026-07-22 Focused Repair Slice

### Confirmed Root Causes

- 常用主菜单入口以 `pinned: false` 打开，而 `MainMenuPanelBehavior.isMovableByWindowBackground` 只在 pinned 状态返回 `true`，导致真实使用态无法拖动。
- 主面板同时使用系统窗口阴影、1pt 外描边和深色不透明底板，浅色桌面上会形成明显的黑色外圈。
- 搜索展开时，`searchDrawerHeight` 与原主内容的 `bottomInset` 重复计入间隔，搜索框与 footer 实际相隔 14pt。
- 主菜单搜索在每次文本变化时重建整个内容树；中文输入法 marked text 尚未提交时，搜索框被移除、重挂和重新聚焦。`Control+Space` 还可能被面板级空格确认逻辑拦截。

### Focused Tasks

- [ ] 先补失败测试，覆盖 unpinned 拖动、外壳描边与阴影、8pt 搜索间距、marked text 和 `Control+Space` 放行。
- [ ] 让 pinned 与 unpinned 主面板均保留背景拖动，不改变 level、失焦关闭和 collection behavior。
- [ ] 关闭系统黑色窗口阴影，将外壳描边减为 0.5pt 的低对比语义边缘，保留 16pt 圆角与实色深色基底。
- [ ] 将搜索框与 footer 的间距从 14pt 收敛为 8pt，并保持面板顶部、内容与 footer 的屏幕坐标稳定。
- [ ] 复用现有历史搜索的 IME 规则：marked text 期间不刷新结果，组合完成后再更新；搜索字段编辑时不吞输入法切换组合键。
- [ ] 运行定向测试、主菜单相关测试、默认全量回归、Release 构建、`git diff --check` 和本地安装验证。

### Focused Acceptance Mapping

| Acceptance | Automated Evidence | Manual Evidence |
| --- | --- | --- |
| 常用临时主面板可拖动 | unpinned behavior 与真实 panel 属性测试 | 从空白标题区域拖动并确认窗口位置变化 |
| 浅色桌面上无明显黑圈 | `hasShadow == false`、0.5pt 低对比边缘断言 | 同尺寸浅色背景截图 |
| 搜索框与 footer 间距约减半 | 展开布局精确断言为 8pt | 对照用户截图检查底部节奏 |
| 中文输入法可连续组合输入 | marked text 不刷新、提交后刷新、`Control+Space` 不拦截测试 | 切换中文输入法并输入候选词 |

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-11-main-panel-c1-glass.md`
- Plan Status: in progress, focused repair slice requested with direct implementation on 2026-07-22
- Evidence Profile: standard
- Story ID: not-synced
- Task IDs: not-synced
- ZenTao Sync Status: not-synced, user did not request external synchronization
- ZenTao Readback Evidence / Time: none
- Last Updated: 2026-07-22

## Delivery Record

- Actual Implementation: completed the focused repair slice by enabling background drag for pinned and transient panels, removing the system window shadow, reducing the outer edge to a 0.5pt 6%-white hairline, setting the search-to-toolbar gap to 8pt, deferring search refresh while AppKit has marked text, and returning active search-field keyboard handling to the field editor
- Plan Deviations: the 2026-07-22 request narrowed execution to drag behavior, outer chrome, search spacing, and Chinese IME stability; the broader visual redesign, state catalogue, and screenshot matrix remain outside this repair
- Impact: limited to main-panel window behavior, legacy header drag permission, outer chrome, search drawer geometry, search input handling, and focused AppKit tests; no data model, repository, KDBX, sync, or password-vault business logic was changed by this slice
- Verification: TDD red run produced 6 expected failures across 81 focused tests; green focused run passed 81/81; the default clean full run hit 8 unrelated concurrent failures plus an Xcode result-bundle writer error, while all 6 implicated suites passed 135/135 when rerun together; `git diff --check` passed; unsigned universal Release archive succeeded and produced Pastera 3.0.1 (301); `./script/install_local.sh` succeeded, `/Applications/Pastera.app` passed strict deep code-sign verification, and PID 54019 was read back from the installed executable
- Remaining Risks: real Chinese IME candidate selection and pointer drag feel still require a short human check because Computer Use cannot enumerate or operate this LSUIElement menu-bar panel; the repository full suite remains susceptible to parallel test interference even though the implicated suites pass in grouped rerun
- Follow-ups: manually open the installed menu-bar panel once, drag from an empty header/background region, switch to a Chinese input source with `Control+Space`, and enter a candidate phrase; no broader visual redesign is included in this focused delivery
- ZenTao Closeout: not requested and not started
