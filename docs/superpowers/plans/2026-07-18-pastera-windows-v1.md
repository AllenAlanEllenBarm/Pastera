# Pastera Windows V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 11 x64 上以原生 Windows 技术完整复刻开工前 macOS 基线版本已经可运行、可验收的 Pastera 核心能力，并保持 OneDrive、同步快照、文件资源和 KDBX 密码箱的跨平台兼容。

**Architecture:** 新客户端放在同一仓库的 `windows/` 子树，使用 C#、WinUI 3、Windows App SDK 和 SQLite。Presentation 只依赖 Application/Domain 接口；剪贴板、托盘、快捷键、输入注入、Windows Hello、DPAPI、会话事件和 OneDrive 发现全部隔离在 Windows Platform 层。macOS 源码是行为基线而不是框架模板，跨平台契约由固定 baseline tag、协议文档和双向兼容 fixtures 共同约束。

**Tech Stack:** Windows 11 x64、C#、.NET 10、WinUI 3、Windows App SDK 稳定通道、SQLite、受限进程内 JavaScript 引擎、KDBX、Windows Hello、DPAPI、MSIX/签名安装链。

## Global Constraints

- Windows V1 仅承诺 Windows 11 x64；Windows 10 和 ARM64 不属于 V1 发布门。
- 开工前必须先将当前 macOS 功能整理、验证并生成干净 baseline commit/tag；V1 范围固定引用该 tag。
- V1 对等的是 baseline 中已经可运行、可验收的能力；仅存在于路线图中的截图捕获、截图翻译等未来功能不进入 V1。
- 九个核心功能域全部属于 V1；实施里程碑只表示依赖顺序，不能用于提前宣称 V1 完成。
- UI 使用 Windows 11 原生信息结构和交互，不做 AppKit 像素级复刻。
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
5. JavaScript 转换脚本、模板、编辑、测试以及 copy/paste/manual 触发。
6. KDBX 密码箱、文件夹/条目、合并、冲突、自动锁定、Windows Hello/DPAPI 和安全剪贴板。
7. OneDrive 文件夹发现/选择、历史/片段/文件资源/KDBX 跨平台同步。
8. 设置搜索、启动项、语言/外观、保留/过滤、快捷键、同步范围、日志、诊断和版本化迁移。
9. 安装、卸载、升级、首次运行、签名、完整性校验和真实 Windows 验收。

### Out of Scope

- baseline tag 中尚未实现的未来目标。
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
- `VaultSession`：管理 KDBX 解锁、Hello/DPAPI 便捷层、自动锁定、外部 revision 和冲突处理。
- `SyncCoordinator`：生成/读取独立快照和 manifest；负责 LWW、tombstone、suppression 与域级警告。
- `WindowsPlatformServices`：提供 `IClipboardMonitor`、`IClipboardWriter`、`IHotKeyRegistrar`、`IInputInjector`、`ISessionMonitor`、`IUserPresenceVerifier`、`ISecretProtector` 和 `IOneDriveLocator`。

### Core data flows

1. 捕获：clipboard event → 类型读取/规范化 → 排除/安全标记/自身抑制 → copy 脚本 → 去重/预算 → SQLite + 原子资源 → 缩略图/OCR → UI 通知。
2. 粘贴：选择历史/片段 → paste 脚本 → 构造 Windows formats → 自身抑制 → 写回剪贴板 → 可选 `SendInput Ctrl+V`；注入失败时仍保留剪贴板内容和当前选择。
3. 同步：repository 导出 → 临时快照/manifest → 原子替换设备文件 → OneDrive 客户端上传；导入先校验版本/大小/路径，再在本地事务中合并。
4. 密码箱：主密码解锁 KDBX → 可选 Hello/DPAPI 便捷解锁 → 内存会话 → revision 检测/合并 → 原子写入与备份；秘密复制绕过历史并条件式定时清空。

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

- [ ] 验证 macOS 当前功能和测试，整理未提交改动后生成唯一 baseline commit/tag。
- [ ] 从 baseline 逐页、逐服务、逐测试登记九个功能域的行为和错误语义。
- [ ] 导出文本、URL、HTML/RTF、图片、PDF、文件列表的类型样本和规范化预期。
- [ ] 导出 history schema v4、snippet schema v3、file manifest v1 和 KDBX 的无敏感测试 fixtures。
- [ ] 在 Windows 测试中固定 baseline tag 与 fixture SHA-256，防止基线漂移。
- [ ] 提交 baseline 与兼容契约，Windows 后续任务只引用该 tag。

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
- [ ] 使用 baseline 行为矩阵逐项核对编辑、删除、收藏和焦点恢复。
- [ ] 运行自动化测试和 Windows UI smoke，记录证据并提交。

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
- [ ] 验证键盘路径、空状态、冲突和回滚行为并提交。

### Task 7: M3 实现受限 JavaScript 转换与设置中心

**Files:**
- Create: `windows/src/Pastera.Domain/Scripts/`
- Create: `windows/src/Pastera.Application/Scripts/ScriptPipeline.cs`
- Create: `windows/src/Pastera.Infrastructure/Scripts/`
- Create: `windows/src/Pastera.App/Settings/`
- Create: `windows/tests/Pastera.Application.Tests/Scripts/`

**Interfaces:**
- Produces: `IScriptExecutor.ExecuteAsync(IReadOnlyList<ScriptTransform>, ScriptInput, CancellationToken)`；保持 `transform(clip)`、copy/paste/manual 触发语义。

- [ ] 编写源码过大、输入过大、缺少 transform、异常、非字符串结果、超时和容量耗尽测试。
- [ ] 选择可取消的进程内 JavaScript 引擎，并在依赖审查中证明没有文件、网络、进程或系统对象暴露。
- [ ] 实现有界并发、超时终止和按 sortIndex 串行转换。
- [ ] 接入 ClipboardCoordinator、PasteCoordinator 和手动快捷键。
- [ ] 实现脚本列表、模板市场、编辑、触发选项和独立测试窗口。
- [ ] 实现设置搜索以及 baseline 中所有通用/历史/排除/快捷键/同步/脚本/关于设置。
- [ ] 运行脚本安全测试和设置迁移测试并提交。

### Task 8: M4 实现 KDBX、Windows Hello/DPAPI 与安全剪贴板

**Files:**
- Create: `windows/src/Pastera.Domain/Vault/`
- Create: `windows/src/Pastera.Application/Vault/`
- Create: `windows/src/Pastera.Platform.Windows/Security/`
- Create: `windows/src/Pastera.App/Vault/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Vault/`

**Interfaces:**
- Produces: `IPasswordVaultStore`, `IUserPresenceVerifier`, `ISecretProtector`, `ISecureClipboardWriter`。

- [ ] 以无敏感 KDBX fixtures 编写跨平台读取、写入、历史、tombstone 和冲突合并测试。
- [ ] 实现 KDBX 文件夹/条目 CRUD、完整顺序、revision 检测、原子写入和备份。
- [ ] 实现主密码解锁，以及用户显式启用的 Windows Hello + DPAPI 便捷解锁。
- [ ] 在 Hello/DPAPI 失效或 KDBX 外部变化时强制退回主密码。
- [ ] 实现空闲超时、锁屏、睡眠、退出立即锁定和内存会话清理。
- [ ] 实现安全复制、自身历史抑制和“仅当剪贴板未变化时清空”。
- [ ] 完成密码箱 UI 与键盘路径，运行安全/兼容测试并提交。

### Task 9: M4 实现 OneDrive 全域跨平台同步

**Files:**
- Create: `windows/src/Pastera.Domain/Sync/`
- Create: `windows/src/Pastera.Application/Sync/SyncCoordinator.cs`
- Create: `windows/src/Pastera.Platform.Windows/OneDrive/`
- Create: `windows/src/Pastera.Infrastructure/Sync/`
- Create: `windows/tests/Pastera.Compatibility.Tests/Sync/`

**Interfaces:**
- Produces: `IOneDriveLocator`, `ISyncSnapshotStore`；必须兼容 history v4、snippet v3、file manifest v1 和既有目录树。

- [ ] 用 macOS fixtures 编写 Windows 导入和 Windows 导出再由 macOS 读取的双向测试。
- [ ] 实现个人版/商业版 OneDrive 根发现、多账户选择和手选路径边界校验。
- [ ] 实现 history/snippet/file snapshot 导出、临时写入、哈希比较和原子替换。
- [ ] 实现 LWW、tombstone、remote absence non-delete、local suppression 和损坏快照跳过。
- [ ] 接入 KDBX 文件位置与冲突文件处理，但不把解锁材料写入同步目录。
- [ ] 实现 manual、startup、timer 和 local-change upload-only 编排。
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
- [ ] 实现稳定通道更新检查、签名/哈希验证和失败回退；不依赖 Store/winget。
- [ ] 在干净 Windows 11 x64 机器验证安装、重启、升级、卸载和重装。
- [ ] 运行全量测试、签名/包完整性检查和九域人工验收矩阵。
- [ ] 将真实差异、证据和残余风险回写本 plan 的 Delivery Record 后提交发布候选。

## Acceptance Mapping

| Acceptance | Evidence |
| --- | --- |
| baseline 范围固定且可追溯 | 干净 macOS baseline tag、功能矩阵、fixture SHA-256 |
| 全类型捕获和粘贴 | Clipboard compatibility tests；Notepad/浏览器/Office/资源管理器人工矩阵 |
| 历史、搜索、OCR、收藏、保留 | Domain/Infrastructure tests；不可见历史搜索与资源恢复测试 |
| 托盘、窗口、键盘与快捷键 | WinUI smoke；快捷键冲突、单实例和焦点恢复测试 |
| 片段完整行为 | schema v3 fixtures；CRUD、排序、tombstone 和快捷键测试 |
| JavaScript 功能与隔离 | `transform(clip)` 兼容测试；大小、异常、超时、并发和能力隔离测试 |
| KDBX 与本机便捷解锁 | KDBX fixtures；Hello/DPAPI 失效回退；锁屏/睡眠/定时锁定测试 |
| 安全剪贴板 | 密码不进入历史；内容未变才清空；日志/数据库敏感信息扫描 |
| OneDrive 跨平台同步 | macOS ↔ Windows 双向 fixtures 与真实双设备目录验证 |
| 安装与升级 | 干净 Windows 11 x64 安装、升级保留数据、卸载、签名和哈希检查 |
| Windows V1 完成 | 九域无阻断缺口，全量自动化通过，真实机器人工矩阵通过 |

证据档位采用 `standard`：新工程必须从 Task 1 起建立自动化测试和真实 Windows 平台验收，不能以“macOS 已通过”代替 Windows 证据。

## Risks, Rollback and Observation

- **WinUI/Win32 互操作风险：** 托盘、隐藏消息窗口、焦点和输入注入必须留在 Platform 层；单域失败允许回退到手工复制/粘贴。
- **剪贴板格式差异：** 以 protocol type map 和 fixtures 防止 Windows 常量污染跨平台协议；不支持格式必须显示为可诊断跳过。
- **资源一致性风险：** 资源使用临时文件 + 原子替换，数据库事务失败不留下已引用的半成品；启动恢复只清无引用临时文件。
- **脚本资源风险：** 引擎必须支持真正终止/取消；若不能可靠停止超时执行，则阻断脚本域交付而不是后台继续运行。
- **凭据风险：** Hello/DPAPI 仅缓存本机保护材料；任何异常均可退回主密码。日志和崩溃信息不得包含秘密。
- **同步冲突风险：** remote absence 永不删除本地数据；损坏快照跳过并警告；每次写入保留可恢复的原子边界。
- **范围漂移风险：** baseline tag 后的 macOS 新功能不自动加入 V1；通过变更评审更新本 plan 才能改变范围。
- **回滚：** 每个里程碑独立提交且保持应用可启动；平台新能力可由设置关闭；数据库迁移必须保留升级前备份和向前恢复路径。
- **观察：** 开发版记录脱敏的 clipboard、paste、sync、vault、script、update 域级结果码和耗时，不记录内容正文或凭据。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-18-pastera-windows-v1.md`
- Plan Status: `design-approved; implementation-not-started`
- Evidence Profile: `standard`
- Baseline Status: `pending M0 clean baseline commit/tag`
- Story ID: `not-synced`
- Task IDs: `not-synced`
- ZenTao Sync Status: `not-synced`
- ZenTao Readback Evidence / Time: `not-synced`
- Last Updated: `2026-07-18 Asia/Shanghai`

## Delivery Record

### Actual Implementation

尚未开始；本轮只完成并确认 Windows V1 设计。

### Plan Deviations

无。设计过程明确由最初的“文本最小闭环”调整为九个核心功能域完整对等。

### Impact

计划新增同仓库 `windows/` 客户端，不修改 macOS 运行时行为。跨平台影响集中在 OneDrive 协议、fixtures、KDBX 和类型映射。

### Verification

设计已逐段确认：总体架构、九域功能对等矩阵、数据流/失败语义、M0-M5 实施阶段与发布门。代码、构建和真实 Windows 验证尚未开始。

### Remaining Risks

开工前仍需完成 M0：整理当前 macOS 未提交改动、生成干净 baseline commit/tag，并在真实 Windows 11 x64 环境确定具体 JS/KDBX/MSIX 库版本。

### Follow-ups

用户确认本 plan 后，在 macOS 仓库先执行 M0；M1-M5 必须由 Windows 机器上的 Codex/开发者实施并验收。

### ZenTao Closeout

未请求 ZenTao 同步，未写入或回读任何 Story/Task。
