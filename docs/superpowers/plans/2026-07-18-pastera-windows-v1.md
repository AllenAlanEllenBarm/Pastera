# Pastera Windows V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 11 x64 上以原生 Windows 技术完整复刻冻结 macOS 基线及已批准 `7b57094` 增量中已经可运行、可验收的 Pastera 核心能力，并保持 OneDrive、同步快照、文件资源、KDBX 密码箱和 Agent 安全契约的跨平台兼容。

**Architecture:** 新客户端放在同一仓库的 `windows/` 子树，使用 C#、WinUI 3、Windows App SDK 和 SQLite。Presentation 只依赖 Application/Domain 接口；剪贴板、托盘、快捷键、输入注入、Windows Hello、DPAPI、会话事件、Agent IPC 和 OneDrive 发现全部隔离在 Windows Platform 层。macOS 源码是行为基线而不是框架模板，跨平台契约由固定 baseline tag、批准的 parity delta、协议文档和双向兼容 fixtures 共同约束；产品内容区以带来源戳的截图为主验收基准。

**Tech Stack:** Windows 11 x64、C#、.NET 10、WinUI 3、Windows App SDK 稳定通道、SQLite、受限进程内 JavaScript 引擎、KDBX、Windows Hello、DPAPI、MSIX/签名安装链。

## Global Constraints

- Windows V1 仅承诺 Windows 11 x64；Windows 10 和 ARM64 不属于 V1 发布门。
- 冻结基线固定为 `windows-v1-baseline-20260718`；后续不得移动或重建该 tag。
- 本轮批准的功能增量上限固定为 `origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`；增量后的计划内容不会自动加入 V1。
- V1 对等的是冻结基线和批准增量中已经可运行、可验收的能力；仅存在于路线图或本地计划中的截图捕获、截图翻译、快捷键数字导航等未来功能不进入 V1。
- 十个核心功能域全部属于 V1；实施里程碑只表示依赖顺序，不能用于提前宣称 V1 完成。
- UI 使用 Windows 11 原生系统 chrome、控件绘制和平台语义，不复制 AppKit 实现；产品内容区必须保持参考图的信息架构、区域位置、尺寸、间距、顺序和信息密度。
- macOS 界面证据与 Windows 原生适配规则固定在 `docs/windows-reference/`；实现 UI 前必须选定状态匹配的参考图，实现后必须提交 macOS 参考图、Windows 实现图和 50% 透明叠加图。
- 在相同状态、主题和归一化内容区尺寸下：主要区域边界容差 `8 epx`，间距和同类控件/列表行高度容差 `4 epx`，内容区宽高比容差 `3%`；超出即为阻断完成的 P1 偏差，除非用户明确批准。
- 入口、导航、页面拆分、状态或主动作缺失/移动属于 P0 偏差；未获批准的 P0/P1 偏差不得标记为完成。“Windows 原生”或 WinUI 默认尺寸不能作为接受明显偏差的理由。
- 使用 Windows App SDK 稳定通道；不依赖 Preview 或 Experimental API。
- JavaScript 保持 `transform(clip)` 契约，禁止访问文件、网络、进程和系统 API。
- KDBX 主密码是密码箱根凭据；Windows Hello 和 DPAPI 仅作为本机便捷解锁层。
- OneDrive 继续使用本地文件夹协议，不接入 Microsoft Graph 或 OAuth；本地文件写入成功不得表述为云端同步完成。
- 原生 Windows clipboard format 与 Pastera 跨平台类型标识分离。
- 密码、解锁材料、Token、DPAPI blob 和同步口令不得写入普通 SQLite、日志、仓库文档或聊天记录。
- Microsoft Store 和 winget 不是 V1 完成条件。

---

## Business Scope / Out of Scope

### Business Scope

1. 剪贴板捕获、类型规范化、应用排除、去重、保留、收藏、资源、缩略图、OCR 和全文搜索。
2. 系统托盘、主面板、历史浏览器、键盘导航、分页、预览、编辑和删除。
3. 写回剪贴板、可选自动粘贴、全局快捷键、冲突检测和失败恢复。
4. 片段文件夹/条目、排序、启用、编辑、删除、快捷键和同步 tombstone。
5. JavaScript 转换脚本、模板、编辑、测试以及 copy/paste/manual 触发；历史提示词本地格式化、OpenAI-compatible 自备服务、显式撤销/保存和独立设置。
6. KDBX 密码箱、文件夹/条目、本地优先工作副本、主密码变更、原子 rekey、合并、冲突、自动锁定、Windows Hello/DPAPI 和安全剪贴板。
7. 密码箱 Agent 授权、一次性票据、限流、脱敏审计、本地 broker、CLI、Codex/Claude MCP 和安装事务。
8. OneDrive 文件夹发现/选择、历史/片段/文件资源以及加密 KDBX 云端副本的跨平台同步和恢复状态。
9. 设置搜索、启动项、语言/外观、保留/过滤、快捷键、同步范围、提示词、密码箱安全、Agent 集成、软件更新、日志、诊断和版本化迁移。
10. 安装、卸载、升级、首次运行、签名、完整性校验和真实 Windows 验收。

### Out of Scope

- 冻结基线和批准增量中尚未实现的未来目标。
- `7b57094` 之后只有设计或实施计划、没有产品实现的快捷键与数字导航。
- Windows 10、ARM64、Linux 和跨平台 UI 框架。
- Microsoft Graph、OneDrive OAuth、Microsoft Store 和 winget 发布。
- AppKit/XIB/Swift 代码迁移或像素级 macOS UI 复刻。
- PowerShell 脚本和允许 JavaScript 调用本机系统能力。

## Project Structure

```text
windows/
  Pastera.Windows.sln
  Directory.Build.props
  src/
    Pastera.App/                    # WinUI 3 入口、托盘、窗口、视图和 ViewModel
    Pastera.Application/            # coordinators、commands、状态与用例编排
    Pastera.Domain/                 # 历史、片段、脚本、KDBX、同步协议领域模型
    Pastera.Infrastructure/         # SQLite、资源文件、设置、日志、更新元数据
    Pastera.Platform.Windows/       # Clipboard/Win32/Hello/DPAPI/HotKey/Input/OneDrive
  tests/
    Pastera.Domain.Tests/
    Pastera.Application.Tests/
    Pastera.Infrastructure.Tests/
    Pastera.Platform.Windows.Tests/
    Pastera.Compatibility.Tests/
  fixtures/
    clipboard/
    sync/
    vault/
  packaging/
    msix/
```

依赖方向固定为 `App -> Application -> Domain`；`Infrastructure` 与 `Platform.Windows` 实现 Application/Domain 定义的接口并由 App 组合，不允许 Domain 引用 WinUI、Win32 或 SQLite。

## Architecture

### Runtime components

- `ClipboardCoordinator`：接收平台剪贴板事件，执行排除/抑制、类型规范化、copy 脚本链、持久化和索引通知。
- `PasteCoordinator`：读取历史/片段，执行 paste 脚本链，写入多格式剪贴板，并按用户设置请求输入注入。
- `HistoryRepository`：事务化维护历史元数据、资源引用、OCR 文本、收藏和保留策略。
- `SnippetRepository`：维护文件夹、条目、顺序、启用状态和删除 tombstone。
- `ScriptPipeline`：按排序执行受限 JavaScript，并强制源码、输入、并发和超时预算。
- `PromptOptimizationService`：执行显式的本地格式化和 OpenAI-compatible 远程优化，保护凭据并保留撤销/保存边界。
- `VaultSession`：管理本地优先 KDBX、主密码变更、Hello/DPAPI 便捷层、自动锁定、外部 revision、原子 rekey 和冲突处理。
- `VaultAgentRuntime`：管理本地 Agent IPC、授权、一次性票据、限流、脱敏审计、CLI/MCP 适配和安装事务。
- `SyncCoordinator`：生成/读取独立快照和 manifest；负责 LWW、tombstone、suppression 与域级警告。
- `WindowsPlatformServices`：提供 `IClipboardMonitor`、`IClipboardWriter`、`IHotKeyRegistrar`、`IInputInjector`、`ISessionMonitor`、`IUserPresenceVerifier`、`ISecretProtector`、`IAgentPeerVerifier`、`IAgentIpcListener` 和 `IOneDriveLocator`。

### Core data flows

1. 捕获：clipboard event → 类型读取/规范化 → 排除/安全标记/自身抑制 → copy 脚本 → 去重/预算 → SQLite + 原子资源 → 缩略图/OCR → UI 通知。
2. 粘贴：选择历史/片段 → paste 脚本 → 构造 Windows formats → 自身抑制 → 写回剪贴板 → 可选 `SendInput Ctrl+V`；注入失败时仍保留剪贴板内容和当前选择。
3. 同步：repository 导出 → 临时快照/manifest → 原子替换设备文件 → OneDrive 客户端上传；导入先校验版本/大小/路径，再在本地事务中合并。
4. 密码箱：主密码解锁本地 KDBX → 可选 Hello/DPAPI 便捷解锁 → 内存会话 → revision 检测/合并 → 原子写入与备份 → 加密 OneDrive replica；秘密复制绕过历史并条件式定时清空。
5. 提示词优化：用户显式触发 → 本地格式化或受控 provider → 预览结果 → 撤销或显式保存；失败不覆盖原历史内容。
6. Agent：已验证本机 peer → 一次授权/持久 grant → 一次性票据 → 有界 broker 请求 → KDBX 操作或安全粘贴 → 脱敏审计；取消、过期、超限和 peer 不匹配全部 fail closed。

## Implementation Tasks

### Task 1: M0 冻结 macOS 基线并生成兼容契约

**Files:**
- Modify: `docs/development/WINDOWS_PORTING_GUIDE.md`
- Create: `windows/fixtures/clipboard/README.md`
- Create: `windows/fixtures/sync/README.md`
- Create: `windows/fixtures/vault/README.md`

**Interfaces:**
- Consumes: 当前 macOS 工作区、`docs/sync/ONEDRIVE_SYNC.md` 和现有 macOS 测试。
- Produces: 干净 baseline tag、功能对等清单、clipboard type map、跨平台 sync/KDBX fixtures 与预期摘要。

- [x] 验证 macOS 当前功能和测试，整理未提交改动后生成唯一 baseline commit/tag。
- [ ] 从 baseline 逐页、逐服务、逐测试登记冻结时九个功能域的行为和错误语义；后续批准增量单独登记。
- [ ] 导出文本、URL、HTML/RTF、图片、PDF、文件列表的类型样本和规范化预期。
- [ ] 导出 history schema v4、snippet schema v3、file manifest v1 和 KDBX 的无敏感测试 fixtures。
- [ ] 在 Windows 测试中固定 baseline tag 与 fixture SHA-256，防止基线漂移。
- [ ] 提交 baseline 与兼容契约；Windows 后续任务同时引用冻结 tag 和经过评审的批准增量。

### Task 1A: M0.1 刷新 Windows 对齐材料与截图门禁

**Files:**
- Create: `windows/AGENTS.md`
- Modify: `docs/development/WINDOWS_PORTING_GUIDE.md`
- Modify: `docs/superpowers/plans/2026-07-18-pastera-windows-v1.md`
- Create: `docs/windows-reference/WINDOWS_PARITY_DELTA_20260726.md`
- Create: `docs/windows-reference/WINDOWS_CODEX_HANDOFF.md`
- Modify: `docs/windows-reference/README.md`
- Create: `docs/windows-reference/REFERENCE_GEOMETRY.md`
- Modify: `docs/windows-reference/WINDOWS_UI_SPEC.md`
- Create: `docs/windows-reference/current-20260726/README.md`

**Interfaces:**
- Consumes: `windows-v1-baseline-20260718`、`origin/develop@7b57094`、已确认设计 `docs/superpowers/specs/2026-07-30-windows-parity-handoff-refresh-design.md`、现有脱敏 macOS UI 基线包和增量源码/测试。
- Produces: Windows Codex 薄入口、带 commit 锚点的功能增量矩阵、来源明确的截图索引与证据缺口、可执行的 UI 差异门禁和可复制交接提示词。

- [x] 核对 `7450839..7b57094` 的产品提交、源码和测试，区分已交付功能、平台替换和仓库维护。
- [x] 更新本 plan 的 Goal、Scope、Architecture、Task 和 Acceptance Mapping，不创建平行 Windows 计划。
- [x] 更新 `WINDOWS_PORTING_GUIDE.md`，保留冻结基线并增加批准增量入口。
- [x] 新增 `WINDOWS_PARITY_DELTA_20260726.md`，为每个产品域登记 behavior、macOS source、Windows parity、platform replacement、UI evidence 和 status。
- [x] 新增 `windows/AGENTS.md`，只保留阅读顺序、范围锚点、源码边界、截图门禁、验证入口和 skill 路由。
- [x] 更新 `WINDOWS_UI_SPEC.md` 和 `REFERENCE_GEOMETRY.md`：截图为内容区主基准，固定 `8 epx` / `4 epx` / `3%` 几何容差，并定义 P0-P3 差异分级。
- [x] 更新截图索引；保留 2026-07-18 的 14 张脱敏基线图，并对无法安全使用合成数据补拍的 `7b57094` 增量页面登记证据缺口。
- [x] 为现有安全参考图记录来源、路径、主题、内容区尺寸和布局不变量；缺少安全合成截图模式的增量状态明确登记开工门。
- [x] 新增 `WINDOWS_CODEX_HANDOFF.md`，要求 UI 开工前选图、完成后提交基线/Windows/50% 叠加三联图，未获批准的 P0/P1 偏差不得完成。
- [x] 运行 `git diff --check`，核对文档链接、tag/commit、截图格式与脱敏边界，并把实际材料和验证结果回写本 Task 与 Delivery Record。
- [x] 仅提交本轮 Windows 对齐材料，不夹带 Windows 产品实现或本机凭据。

### Task 2: M1 建立 Windows 分层工程、单实例与生命周期

**Files:**
- Create: `windows/Pastera.Windows.sln`
- Create: `windows/Directory.Build.props`
- Create: `windows/src/Pastera.App/`
- Create: `windows/src/Pastera.Application/`
- Create: `windows/src/Pastera.Domain/`
- Create: `windows/src/Pastera.Infrastructure/`
- Create: `windows/src/Pastera.Platform.Windows/`
- Create: `windows/tests/`

**Interfaces:**
- Produces: 可启动的单实例 WinUI 3 托盘应用、依赖注入组合根、版本化设置、结构化脱敏日志和测试项目。

- [ ] 先写架构测试，禁止 Domain/Application 引用 WinUI、Win32 和 SQLite 实现程序集。
- [ ] 创建 x64 WinUI 3 工程和五个项目，锁定 Windows 11 与 .NET 10。
- [ ] 实现单实例激活、托盘驻留、显式退出和窗口关闭不退出。
- [ ] 实现 `%LocalAppData%/Pastera` 下的数据库、资源、设置和日志目录解析。
- [ ] 实现版本化设置迁移及日志脱敏测试。
- [ ] 运行 `dotnet test windows/Pastera.Windows.sln -c Release -a x64` 并提交。

### Task 3: M2 实现 SQLite、资源事务和完整剪贴板捕获

**Files:**
- Create: `windows/src/Pastera.Domain/History/`
- Create: `windows/src/Pastera.Application/Clipboard/ClipboardCoordinator.cs`
- Create: `windows/src/Pastera.Infrastructure/History/`
- Create: `windows/src/Pastera.Platform.Windows/Clipboard/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Clipboard/`

**Interfaces:**
- Produces: `IClipboardMonitor`, `IClipboardReader`, `IHistoryRepository` 与跨平台 `ClipboardContent` 类型映射。

- [ ] 以 fixtures 编写文本、URL、HTML/RTF、图片、PDF 和文件列表规范化失败测试。
- [ ] 实现隐藏消息窗口与 clipboard update 监听，并处理剪贴板暂时占用。
- [ ] 实现 Windows 原生 format 到 Pastera protocol type 的独立映射。
- [ ] 实现应用排除、自身写回抑制、安全剪贴板抑制、去重和大小预算。
- [ ] 实现 SQLite schema/migrations，以及数据库与资源文件的原子一致性流程。
- [ ] 实现启动时只清理无引用临时资源的恢复逻辑。
- [ ] 运行 Domain、Infrastructure、Platform 和 Compatibility 测试并提交。

### Task 4: M2 实现历史 UI、搜索、OCR、收藏与预览

**Files:**
- Create: `windows/src/Pastera.App/History/`
- Create: `windows/src/Pastera.Application/History/`
- Create: `windows/src/Pastera.Infrastructure/Ocr/`
- Create: `windows/tests/Pastera.Application.Tests/History/`

**Interfaces:**
- Consumes: `IHistoryRepository`、`ClipboardContent`。
- Produces: 托盘主面板、完整历史窗口、分页/搜索/收藏/预览 commands 和 OCR indexer。

- [ ] 编写“菜单显示限制与数据库保留独立”“搜索覆盖不可见历史”的失败测试。
- [ ] 实现历史查询、全文搜索、类型过滤、收藏、删除和保留策略。
- [ ] 实现图片缩略图与后台 OCR；OCR 失败只产生域级警告，不破坏历史。
- [ ] 实现 Windows 原生主面板与历史浏览窗口、键盘导航、分页和各类型预览。
- [ ] 使用 baseline + `7b57094` parity delta 逐项核对编辑、删除、收藏、OCR 状态、搜索反馈和焦点恢复。
- [ ] 按状态匹配参考图标出主面板/历史窗口的区域边界、对齐线、间距和可见行数。
- [ ] 提交 macOS 参考图、Windows 实现图和 50% 叠加图；修复全部未获批准的 P0/P1 差异。
- [ ] 运行自动化测试和 Windows UI smoke，记录深色、浅色和 125% 缩放证据并提交。

### Task 5: M2 实现多格式写回、自动粘贴和全局快捷键

**Files:**
- Create: `windows/src/Pastera.Application/Paste/PasteCoordinator.cs`
- Create: `windows/src/Pastera.Platform.Windows/Input/`
- Create: `windows/src/Pastera.Platform.Windows/HotKeys/`
- Create: `windows/tests/Pastera.Platform.Windows.Tests/Input/`

**Interfaces:**
- Produces: `IClipboardWriter`, `IInputInjector`, `IHotKeyRegistrar`；自动粘贴结果必须区分 `CopiedOnly`、`Injected`、`InjectionRejected`。

- [ ] 编写多格式写回、快捷键冲突和注入失败仍保留剪贴板内容的失败测试。
- [ ] 实现 Windows clipboard formats 写回与自身事件抑制。
- [ ] 实现 `RegisterHotKey` 注册、变更、注销和冲突提示。
- [ ] 实现默认关闭的 `SendInput Ctrl+V`，并保留手工粘贴回退。
- [ ] 在 Notepad、浏览器、Office 和文件资源管理器执行真实互操作矩阵。
- [ ] 运行相关测试与 smoke，记录不支持组合并提交。

### Task 6: M3 实现片段、排序、编辑和快捷键

**Files:**
- Create: `windows/src/Pastera.Domain/Snippets/`
- Create: `windows/src/Pastera.Infrastructure/Snippets/`
- Create: `windows/src/Pastera.Application/Snippets/`
- Create: `windows/src/Pastera.App/Snippets/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Snippets/`

**Interfaces:**
- Produces: `ISnippetRepository`，字段和同步语义兼容 folder/item order、enabled、updatedAt、deletedAt。

- [ ] 先用 macOS schema v3 fixture 编写文件夹、条目和 tombstone 兼容测试。
- [ ] 实现片段 repository、去重、完整顺序移动和删除 tombstone。
- [ ] 实现文件夹/条目浏览、创建、编辑、删除和拖放排序。
- [ ] 将片段选择接入 PasteCoordinator，将片段快捷键接入 HotKeyRegistrar。
- [ ] 对照 Snippet 浏览/编辑参考图验证区域比例、工具栏顺序、信息密度、键盘路径、空状态、冲突和回滚行为。
- [ ] 提交 macOS/Windows/叠加三联图，修复全部未获批准的 P0/P1 差异后提交。

### Task 7: M3 实现受限 JavaScript、提示词优化与设置中心

**Files:**
- Create: `windows/src/Pastera.Domain/Scripts/`
- Create: `windows/src/Pastera.Application/Scripts/ScriptPipeline.cs`
- Create: `windows/src/Pastera.Application/PromptOptimization/`
- Create: `windows/src/Pastera.Infrastructure/Scripts/`
- Create: `windows/src/Pastera.Infrastructure/PromptOptimization/`
- Create: `windows/src/Pastera.App/Settings/`
- Create: `windows/tests/Pastera.Application.Tests/Scripts/`
- Create: `windows/tests/Pastera.Application.Tests/PromptOptimization/`

**Interfaces:**
- Produces: `IScriptExecutor.ExecuteAsync(IReadOnlyList<ScriptTransform>, ScriptInput, CancellationToken)` 与 `IPromptOptimizationService.OptimizeAsync(PromptOptimizationRequest, CancellationToken)`；保持 `transform(clip)`、copy/paste/manual 触发语义，并让提示词优化只在用户显式触发后返回可撤销预览。

- [ ] 编写源码过大、输入过大、缺少 transform、异常、非字符串结果、超时和容量耗尽测试。
- [ ] 选择可取消的进程内 JavaScript 引擎，并在依赖审查中证明没有文件、网络、进程或系统对象暴露。
- [ ] 实现有界并发、超时终止和按 sortIndex 串行转换。
- [ ] 接入 ClipboardCoordinator、PasteCoordinator 和手动快捷键。
- [ ] 实现脚本列表、模板市场、编辑、触发选项和独立测试窗口。
- [ ] 编写本地格式化、OpenAI-compatible endpoint 校验、凭据保护、取消、失败不覆盖原文、撤销和显式保存测试。
- [ ] 实现本地格式化和用户自备 OpenAI-compatible provider；不把 Apple Foundation Models 当成 Windows 必选机制。
- [ ] 实现历史编辑器中的显式优化、预览、撤销和保存，以及独立提示词设置页。
- [ ] 实现设置搜索以及 baseline + parity delta 中所有通用/历史/排除/快捷键/同步/脚本/提示词/密码箱安全/Agent 集成/软件更新/关于设置。
- [ ] 对照脚本、提示词和设置参考图提交三联图，修复全部未获批准的 P0/P1 差异。
- [ ] 运行脚本安全、提示词优化、设置迁移和 Windows UI smoke 并提交。

### Task 8: M4 实现 KDBX、Windows Hello/DPAPI 与安全剪贴板

**Files:**
- Create: `windows/src/Pastera.Domain/Vault/`
- Create: `windows/src/Pastera.Application/Vault/`
- Create: `windows/src/Pastera.Platform.Windows/Security/`
- Create: `windows/src/Pastera.App/Vault/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Vault/`

**Interfaces:**
- Produces: `IPasswordVaultStore`, `IUserPresenceVerifier`, `ISecretProtector`, `ISecureClipboardWriter`。

- [ ] 以无敏感 KDBX fixtures 编写跨平台读取、写入、历史、tombstone、冲突合并、主密码变更和 rekey rollback 测试。
- [ ] 实现本地优先 KDBX 工作副本、文件夹/条目 CRUD、完整顺序、revision 检测、原子写入和备份。
- [ ] 实现主密码解锁，以及用户显式启用的 Windows Hello + DPAPI 便捷解锁。
- [ ] 实现主密码变更和原子 rekey；提交前失败必须保留旧主密码可用，提交后失败必须可恢复。
- [ ] 在 Hello/DPAPI 失效或 KDBX 外部变化时强制退回主密码。
- [ ] 实现空闲超时、锁屏、睡眠、退出立即锁定和内存会话清理。
- [ ] 实现安全复制、自身历史抑制和“仅当剪贴板未变化时清空”。
- [ ] 完成密码箱创建、锁定、解锁、主密码设置/变更 UI 与键盘路径。
- [ ] 对照密码箱参考图提交三联图，修复全部未获批准的 P0/P1 差异，运行安全/兼容测试并提交。

### Task 8A: M4 实现密码箱 Agent 安全集成

**Files:**
- Create: `windows/src/Pastera.Domain/VaultAgent/`
- Create: `windows/src/Pastera.Application/VaultAgent/`
- Create: `windows/src/Pastera.Platform.Windows/VaultAgent/`
- Create: `windows/src/Pastera.App/Settings/VaultAgent/`
- Create: `windows/src/Pastera.Agent.Cli/`
- Create: `windows/src/Pastera.Agent.Mcp/`
- Create: `windows/tests/Pastera.Application.Tests/VaultAgent/`
- Create: `windows/tests/Pastera.Platform.Windows.Tests/VaultAgent/`

**Interfaces:**
- Consumes: `IPasswordVaultStore`、`IUserPresenceVerifier`、`ISecureClipboardWriter`。
- Produces: `IVaultAgentRuntime`、`IAgentPeerVerifier`、`IAgentTicketStore`、`IAgentAuditLogger`；所有操作通过版本化 wire contract 返回脱敏结果，不向 Agent 返回主密码或明文密码。

- [ ] 以 parity delta 中的 wire、安全和授权语义编写协议、peer、授权、票据、限流、审计和取消失败测试。
- [ ] 使用 Windows 本机 IPC 与 ACL 实现单用户 listener、peer 身份校验、消息大小上限和有界连接队列。
- [ ] 实现一次授权、持久 grant、一次性短期票据、速率限制和脱敏审计；取消、过期、超限和身份不匹配全部 fail closed。
- [ ] 实现 get/copy/paste 等允许操作，安全粘贴复用 `ISecureClipboardWriter`，不扩大到任意命令或秘密回传。
- [ ] 实现 CLI、Codex/Claude MCP 适配器和可回滚安装事务；不覆盖用户不属于 Pastera 的现有配置。
- [ ] 实现 Agent 集成设置页、授权状态、撤销和恢复反馈。
- [ ] 对照 Agent 设置参考图提交三联图，修复全部未获批准的 P0/P1 差异。
- [ ] 运行协议、安全、性能、资源泄漏、CLI/MCP smoke 和 Windows UI smoke 后提交。

### Task 9: M4 实现 OneDrive 全域跨平台同步

**Files:**
- Create: `windows/src/Pastera.Domain/Sync/`
- Create: `windows/src/Pastera.Application/Sync/SyncCoordinator.cs`
- Create: `windows/src/Pastera.Platform.Windows/OneDrive/`
- Create: `windows/src/Pastera.Infrastructure/Sync/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Sync/`

**Interfaces:**
- Produces: `IOneDriveLocator`, `ISyncSnapshotStore`、`IPasswordVaultCloudReplica`；必须兼容 history v4、snippet v3、file manifest v1、加密 KDBX replica 和既有目录树。

- [ ] 用 macOS fixtures 编写 Windows 导入和 Windows 导出再由 macOS 读取的双向测试。
- [ ] 实现个人版/商业版 OneDrive 根发现、多账户选择和手选路径边界校验。
- [ ] 实现 history/snippet/file snapshot 导出、临时写入、哈希比较和原子替换。
- [ ] 实现 LWW、tombstone、remote absence non-delete、local suppression 和损坏快照跳过。
- [ ] 实现加密 KDBX 云端副本、旧数据迁移、远端缺失重建、并发 revision 合并、冲突文件和事务化恢复，但不把解锁材料写入同步目录。
- [ ] 实现 manual、startup、timer 和 local-change upload-only 编排。
- [ ] 实现密码箱就地同步/恢复 UI，区分 OneDrive 客户端已启动、本地副本已写入和云端下载/上传未知状态。
- [ ] 对照同步和密码箱恢复参考图提交三联图，修复全部未获批准的 P0/P1 差异。
- [ ] 确保 UI 仅报告本地文件工作状态，并在真实双设备 OneDrive 目录执行互操作验收。
- [ ] 运行全部兼容测试并提交。

### Task 10: M5 实现安装、升级、首次运行和发布验证

**Files:**
- Create: `windows/packaging/msix/`
- Create: `windows/src/Pastera.Application/Setup/`
- Create: `windows/src/Pastera.App/Setup/`
- Create: `.github/workflows/windows-release.yml`
- Modify: `docs/development/WINDOWS_PORTING_GUIDE.md`

**Interfaces:**
- Produces: 签名 x64 安装包、完整性元数据、幂等升级迁移、首次运行向导和发布证据。

- [ ] 编写 clean install、升级保留数据、卸载、启动项和损坏更新元数据测试。
- [ ] 实现稳定安装目录、开始菜单、卸载入口和用户可控启动项。
- [ ] 实现首次运行的托盘、快捷键、自动粘贴、OneDrive 和密码箱指引。
- [ ] 实现独立软件更新页、稳定通道自动/手动检查、签名/哈希验证、用户确认后的安装和失败回退；不依赖 Store/winget，也不复用 Sparkle 字段。
- [ ] 在干净 Windows 11 x64 机器验证安装、重启、升级、卸载和重装。
- [ ] 对照软件更新和首次运行参考图提交三联图，修复全部未获批准的 P0/P1 差异。
- [ ] 运行全量测试、签名/包完整性检查和十域人工验收矩阵。
- [ ] 将真实差异、证据和残余风险回写本 plan 的 Delivery Record 后提交发布候选。

## Acceptance Mapping

| Acceptance | Evidence |
| --- | --- |
| baseline 与批准增量固定且可追溯 | macOS baseline tag、`7b57094` parity delta、功能矩阵、fixture SHA-256 |
| 全类型捕获和粘贴 | Clipboard compatibility tests；Notepad/浏览器/Office/资源管理器人工矩阵 |
| 历史、搜索、OCR、收藏、保留 | Domain/Infrastructure tests；不可见历史搜索与资源恢复测试 |
| 托盘、窗口、键盘与快捷键 | WinUI smoke；快捷键冲突、单实例和焦点恢复测试；状态匹配三联截图 |
| 片段完整行为 | schema v3 fixtures；CRUD、排序、tombstone 和快捷键测试 |
| JavaScript 功能与隔离 | `transform(clip)` 兼容测试；大小、异常、超时、并发和能力隔离测试 |
| 提示词优化 | 本地格式化与 OpenAI-compatible provider 测试；显式触发、取消、失败不覆盖、撤销和保存验证 |
| KDBX、本地优先存储与便捷解锁 | KDBX fixtures；主密码变更/rekey rollback；Hello/DPAPI 失效回退；锁屏/睡眠/定时锁定测试 |
| 密码箱 Agent 安全集成 | wire/peer/grant/ticket/rate-limit/audit 测试；CLI/MCP smoke；安装回滚与资源泄漏验证 |
| 安全剪贴板 | 密码不进入历史；内容未变才清空；日志/数据库敏感信息扫描 |
| OneDrive 跨平台同步 | macOS ↔ Windows 双向 fixtures；加密 KDBX replica/恢复测试；真实双设备目录验证 |
| UI 内容区视觉对齐 | 每个主要状态的 macOS 参考图、Windows 图、50% 叠加图和 P0-P3 差异记录；未获批准的 P0/P1 为 0 |
| 安装、更新与升级 | 独立更新页；干净 Windows 11 x64 安装、升级保留数据、卸载、签名和哈希检查 |
| Windows V1 完成 | 十域无阻断缺口，全量自动化通过，真实机器人工矩阵和截图门禁通过 |

证据档位采用 `standard`：新工程必须从 Task 1 起建立自动化测试和真实 Windows 平台验收，不能以“macOS 已通过”代替 Windows 证据。

## Risks, Rollback and Observation

- **WinUI/Win32 互操作风险：** 托盘、隐藏消息窗口、焦点和输入注入必须留在 Platform 层；单域失败允许回退到手工复制/粘贴。
- **剪贴板格式差异：** 以 protocol type map 和 fixtures 防止 Windows 常量污染跨平台协议；不支持格式必须显示为可诊断跳过。
- **资源一致性风险：** 资源使用临时文件 + 原子替换，数据库事务失败不留下已引用的半成品；启动恢复只清无引用临时文件。
- **脚本资源风险：** 引擎必须支持真正终止/取消；若不能可靠停止超时执行，则阻断脚本域交付而不是后台继续运行。
- **凭据风险：** Hello/DPAPI 仅缓存本机保护材料；任何异常均可退回主密码。日志和崩溃信息不得包含秘密。
- **同步冲突风险：** remote absence 永不删除本地数据；损坏快照跳过并警告；每次写入保留可恢复的原子边界。
- **范围漂移风险：** baseline tag 和批准的 `7b57094` 增量之后的 macOS 新功能不自动加入 V1；通过变更评审更新本 plan 才能改变范围。
- **视觉漂移风险：** “Windows 原生”只允许替换系统 chrome、控件绘制和平台语义；未获批准的 P0/P1 截图差异阻断任务完成，不能用构建通过或 AutomationId 存在替代。
- **回滚：** 每个里程碑独立提交且保持应用可启动；平台新能力可由设置关闭；数据库迁移必须保留升级前备份和向前恢复路径。
- **观察：** 开发版记录脱敏的 clipboard、paste、sync、vault、vault-agent、script、prompt、update 域级结果码和耗时，不记录内容正文或凭据。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-18-pastera-windows-v1.md`
- Plan Status: `M0 baseline prepared; M0.1 parity handoff refreshed; Windows implementation not started`
- Evidence Profile: `standard`
- Baseline Status: `windows-v1-baseline-20260718`
- Approved Parity Delta: `origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`
- Story ID: `not-synced`
- Task IDs: `not-synced`
- ZenTao Sync Status: `not-synced`
- ZenTao Readback Evidence / Time: `not-synced`
- Last Updated: `2026-07-30 Asia/Shanghai`

## Delivery Record

### Actual Implementation

M0 已完成 macOS 基线审计、全量回归、跨平台契约清单和 `docs/windows-reference/` UI 参考包。M0.1 保留冻结 tag，并把 Windows V1 的唯一批准增量固定到 `origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`；新增 `windows/AGENTS.md`、功能增量矩阵、严格几何清单、P0-P3 截图门禁、证据缺口登记和可直接复制给 Windows Codex 的开工/纠偏提示词。Windows 客户端尚未开始。

### Plan Deviations

仓库没有可直接复用的安全合成 UI 截图模式，因此 M0.1 没有从用户当前运行环境补拍 `7b57094` 新页面；继续使用 14 张已脱敏基线图，并在 `current-20260726/README.md` 登记缺图页面和开工门。缺图被定义为阻断证据，不是自由设计授权。二进制 SQLite/KDBX 双向 fixtures 仍由 Windows 测试从合成数据生成，避免在仓库中保存固定口令或本机保护材料。

### Impact

M0 新增 `windows/fixtures/` 契约清单和 `docs/windows-reference/` UI 参考包。M0.1 只修改 Windows 开发规则、计划和对齐材料，没有修改 macOS 或 Windows 运行时行为。后续影响集中在同仓库 Windows 客户端、OneDrive 协议、KDBX、Agent wire contract、提示词优化、更新链和 WinUI 3 截图验收。

### Verification

M0 设计已逐段确认。macOS 基线曾运行完整 `xcodebuild ... clean test`，673 tests / 75 suites 通过，命令退出码为 0；随后运行 `./script/install_local.sh --clean --verify`，构建成功并从 `/Applications/Pastera.app` 启动。M0.1 核对冻结 tag、`7b57094` commit 和增量矩阵引用的 92 个源码/测试路径；确认 14 个参考图均为有效 JPEG，且 `sips` 尺寸与 `REFERENCE_GEOMETRY.md` 一致；运行 `git diff --check` 和文档引用/敏感占位扫描通过。待交付树首次默认并发 `clean test` 在 1152 tests / 101 suites 中出现 4 个失败；对应三个 Suite 单 worker 聚焦复跑 41 tests 全部通过，随后单 worker 全量复跑 1152 tests / 101 suites 全部通过并输出 `TEST SUCCEEDED`，未为测试抖动修改产品代码。M0.1 是纯文档变更，没有 Windows solution 或真实 Windows 截图，因此 Windows runtime/UI 验证尚未开始。

### Remaining Risks

M1 开始前仍需在真实 Windows 11 x64 环境确定具体 JS、KDBX 和 MSIX 库版本。`7b57094` 增量页面缺少安全合成参考图；对应 UI Task 在补图或获得用户明确批准前不得开工。macOS 测试日志中的既有 UI/颜色空间噪声不阻断 baseline，但应避免 Windows 测试复制这种无界输出模式。

### Follow-ups

Windows 机器上的 Codex/开发者必须先使用 `WINDOWS_CODEX_HANDOFF.md` 完成 task 前置报告，再按 M1-M5 实施。Windows 侧生成的双向 fixtures 需要回到 macOS compatibility tests 复核。每个 UI 里程碑使用合成数据提交 macOS 参考图、Windows 实图和 50% 叠加图，并补充 Windows 11 浅色、深色和 125% 缩放 smoke，不覆盖 macOS 基线图。

### ZenTao Closeout

未请求 ZenTao 同步，未写入或回读任何 Story/Task。
