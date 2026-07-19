# History Background Work Resource Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复实时 OCR 排队持有完整图片、历史清理全表解码、未配置 OneDrive 仍常驻全量观察三项资源问题，并以用户可感知但不打断操作的状态带反馈 OCR 延迟。

**Architecture:** SQLite 成为后台工作的事实源。历史表保存可索引的内容特征，OCR 使用持久化工作表而不是捕获 `PasteboardContent` 的内存闭包，清理和同步观察只读取轻量 token；`SyncCoordinator` 根据当前配置按需安装 timer 与局部观察。主菜单在工具栏上方显示由真实 OCR 队列状态驱动的临时任务状态带。

**Tech Stack:** Swift 6、AppKit、Combine、SQLiteData/SQLite、Vision、Swift Testing、XCTest

## Global Constraints

- 保持 macOS 13+、Xcode 26.5、Swift Package Manager 和 SQLiteData 现有技术边界，不引入新依赖。
- 不改变剪贴板历史、OCR 搜索、OneDrive 文件协议、同步冲突语义和历史保留设置的业务契约。
- 后台调度不得在闭包或 publisher 输出中长期持有图片 BLOB、完整 `PasteboardContent` 或完整历史数组。
- OCR 状态必须来自真实持久化队列，不显示估算百分比，不发送系统通知，不改变菜单栏图标。
- OCR 状态带采用已确认的 A 方案，固定约 32pt，位于历史内容和底部工具栏之间，不覆盖内容、不替换高频按钮。
- 所有新增文案进入 `Localizable.xcstrings`，至少保持现有英语、德语、意大利语、日语和简体中文本地化完整性。
- 保存、迁移和删除必须保持外键一致性；历史删除后对应 OCR job 自动删除。
- 保留用户现有未提交改动，特别是本轮已完成的 OCR 启动回填优化，不触碰 `.codex/config.toml` 与 `.superpowers/`。

---

## Business Scope / Out of Scope

### In Scope

- 实时 OCR 从“闭包捕获完整内容”改为“持久化 ID 工作队列 + 单工作泵”。
- OCR 队列提供识别中、完成、部分失败三个真实状态，主菜单展示临时状态带。
- 历史记录增加图片、文件、文本同步候选三项可索引特征，迁移旧数据并在后续写入时维护。
- 媒体保留清理改为索引查询，不再逐条 JSON 解码全表。
- OneDrive 根据有效目录和启用方向按需激活 timer、历史观察和片段观察；配置变化后立即重配置。
- 历史同步观察仅发布 `id/updateAt` token，不构造完整历史对象数组。

### Out of Scope

- 不改变 Vision 识别参数、语言、12 MiB 图片源上限、OCR 文本格式或搜索排序。
- 不把 OCR 做成用户可暂停、取消、手动重试或配置并发数的新功能。
- 不修改 OneDrive 快照、manifest、加密兼容、冲突解决、KDBX 文件格式或 Windows 协议。
- 不新增系统通知、菜单栏徽标、悬浮 toast、独立 OCR 设置页或长期任务中心。
- 不做与这三条调用链无关的数据库、主菜单或设置中心重构。

## Design Decisions

### 1. 持久化 OCR 工作队列

新增 `pasteboardHistoryOCRJobs`：以 `pasteboardHistoryID` 为主键，保存 `priority` 与 `enqueuedAt`。实时任务优先级高于启动回填；相同优先级按最新任务优先。队列表只保存轻量标识，不保存图片或正文，并通过外键级联删除。

`enqueueIndexing(historyID:)` 只 upsert job 并唤醒工作泵。工作泵在串行 OCR queue 上保持一个 `isPumpScheduled` 标志，每轮从数据库取一个 job ID，再按 ID 读取一条内容并在 `autoreleasepool` 中识别。完成、不可识别或失败后删除该 job，再将下一轮放回队尾。应用退出时未完成 job 留在数据库，下次启动继续。

启动回填继续遵守最多 200 条预算，但改为把候选 ID 批量写入 job 表；不会在内存保留候选数组或内容。实时任务可通过较高 priority 在后续回填前执行。

### 2. 共享历史特征

在 `pasteboardHistories` 增加三个严格整数布尔列：`containsImage`、`containsFile`、`isTextSyncCandidate`。迁移时仅一次解码旧 `pasteboardTypes`，之后所有保存和同步导入路径都从类型集合计算特征。

建立按 `updateAt DESC` 排序的 partial index：图片、文件、当前设备文本同步候选各一条。媒体保留直接通过对应 partial index 获取 offset 之后的 ID，两类结果在 Swift `Set` 中去重后一次删除。同步观察只选择 `id/updateAt` token。

### 3. OneDrive 激活状态机

`SyncCoordinator` 拆出 `reloadConfiguration()`。协调器始终只保留一个轻量设置变化通知；满足“根目录存在且可用，并且至少一种同步工作可执行”时才安装 timer。历史 upload/file upload 需要历史 token observer，snippet upload 需要 snippet observer，纯 import 只需要 timer，未配置状态不安装业务数据 observer。

所有 `UserDefaultsSyncSettingsStore` setter 发送同一个 typed notification。协调器在自己的 queue 上读取完整最新设置并对比 activation signature，只增删变化的资源，不重复订阅。手动同步仍可主动执行并返回现有 skipped 状态。

### 4. OCR 延迟状态带

状态模型为 `idle`、`indexing(remaining:)`、`completed(processed:skipped:)`。开始时队列计数从 0 变为非 0，主菜单在内容和 footer dock 之间展开约 32pt：`正在识别图片文字`，尾部显示 `剩余 N 项`。细线只表达后台仍在推进，不显示百分比。

最后一项完成后：无失败显示 `图片文字已更新 / 已识别 N 项`；有失败显示 `部分图片无法识别 / N 项已跳过`。完成态停留约 1.5 秒后收起。普通模式使用约 160ms 淡入与高度变化；Reduce Motion 下直接切换与收起。菜单关闭不影响任务，重新打开时读取当前状态。

## File Map

- Modify `pastera/Sources/Database/SQLiteDataMigrator.swift`: 注册 V6，增加历史特征列、partial index 与 OCR job 表并迁移旧数据。
- Modify `pastera/Sources/Database/SQLiteDataSchema.swift`: 增加历史特征字段与 `PasteboardHistoryOCRJob` 模型。
- Modify `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`: 维护特征，提供 OCR job 操作、索引清理与轻量同步 token publisher。
- Modify `pastera/Sources/Services/PasteboardHistoryOCRIndexer.swift`: 改为持久化单泵调度并发布活动状态。
- Modify `pastera/Sources/Services/ClipService.swift`: 实时 OCR 只传 `historyID`。
- Modify `pastera/Sources/Services/SyncCoordinator.swift`: 设置变化通知与按需 activation state machine。
- Modify `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`: 保持现有 setter 路径，由 store 通知协调器重配置。
- Modify `pastera/Sources/Managers/MainMenuPanelController.swift`: 承载状态带、订阅 OCR 活动并重算内容 frame。
- Create `pastera/Sources/Managers/MainMenuOCRActivityView.swift`: 单一职责的状态带视图和 Reduce Motion 动画策略。
- Modify `pastera/Resources/Localizable.xcstrings`: OCR 活动文案本地化。
- Modify `pasteraTests/Database/SQLiteDataMigratorTests.swift`: V6 schema、旧数据特征回填和级联删除验证。
- Modify `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`: job 顺序、特征维护、索引清理、轻量 token 验证。
- Modify `pasteraTests/SyncCoordinatorTests.swift`: 未配置、纯导入、上传和配置切换资源生命周期验证。
- Modify `pasteraTests/MainMenuVisualPolishTests.swift`: 状态带结构、固定高度、footer 不被替换、Reduce Motion 验证。
- Modify `pasteraTests/Repositories/PasteboardHistorySearchPerformanceTests.swift`: 大历史量下清理查询与 observer 输出的回归基线。

## Acceptance Mapping

| Requirement | Evidence |
| --- | --- |
| 实时 OCR 不捕获完整图片内容 | 可控 scheduler 测试证明排队任务只保存 ID；排入多张大图后释放调用方内容的弱引用/生命周期测试 |
| OCR job 持久、去重、实时优先 | repository 测试覆盖同 ID upsert、实时优先于回填、重建 indexer 后继续、历史删除级联 |
| 单次最多加载一条图片 | controlled pump + recognizer 测试记录并发峰值为 1，失败后继续下一条 |
| OCR 延迟对用户可感知 | AppKit 结构测试 + 同尺寸真实截图，覆盖识别中、完成、部分失败、收起和 Reduce Motion |
| 媒体清理不再全表 JSON 解码 | migration 特征正确性测试；repository 清理混合类型与去重测试；`EXPLAIN QUERY PLAN` 命中 partial index |
| OneDrive 未配置不观察全历史 | coordinator fake repositories 断言未安装 history/snippet observer 与 timer |
| OneDrive 按启用方向最小激活 | 纯导入只有 timer；history upload 只装历史 observer；snippet upload 只装 snippet observer；关闭后释放 |
| 配置变化立即生效且不重复订阅 | typed notification 后 activation signature 测试覆盖 off→on、on→off、换目录、重复相同配置 |
| 业务契约无回归 | focused tests、完整 `xcodebuild ... clean test`、`git diff --check`、本地安装与进程核验 |
| 资源收益可观测 | Instruments 人工矩阵记录 OCR backlog、连续复制大图、2000 条历史清理和未配置 OneDrive 四种场景的内存/CPU趋势 |

证据档位：`standard`。仓库具备完整测试和本地安装入口；性能收益额外保留 Instruments 人工验收，不以单测替代真实资源观察。

## Tasks

### Task 1: 建立历史特征与持久化 OCR job schema

**Files:**
- Modify: `pastera/Sources/Database/SQLiteDataMigrator.swift`
- Modify: `pastera/Sources/Database/SQLiteDataSchema.swift`
- Test: `pasteraTests/Database/SQLiteDataMigratorTests.swift`

**Interfaces:**
- Produces: `PasteboardHistory.containsImage: Bool`、`containsFile: Bool`、`isTextSyncCandidate: Bool`
- Produces: `PasteboardHistoryOCRJob(historyID:priority:enqueuedAt:)`

- [ ] 写 V6 migration 失败测试，覆盖新列默认值、旧 JSON 类型回填、三条 partial index、OCR job 外键级联。
- [ ] 运行 `SQLiteDataMigratorTests`，确认因 V6 尚不存在而失败。
- [ ] 注册 V6，在单个 migration transaction 中新增列、一次性回填特征、创建索引与 job 表。
- [ ] 更新 SQLiteData schema model，使 Bool 与 strict INTEGER 映射一致。
- [ ] 重跑 migration tests，确认新库与 V5 升级库均通过。

### Task 2: 用数据库队列替换实时 OCR 内容闭包

**Files:**
- Modify: `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`
- Modify: `pastera/Sources/Services/PasteboardHistoryOCRIndexer.swift`
- Modify: `pastera/Sources/Services/ClipService.swift`
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`

**Interfaces:**
- Produces: `enqueueOCRJob(historyID:priority:enqueuedAt:)`、`fetchNextOCRJobID()`、`deleteOCRJob(historyID:)`、`countOCRJobs()`
- Changes: `PasteboardHistoryOCRIndexing.enqueueIndexing(historyID:)`
- Produces: `PasteboardHistoryOCRActivity` publisher/state

- [ ] 先改测试 double 契约并写失败测试：实时 enqueue 不接收 content、job 去重、实时优先、单泵峰值 1、失败继续、重建后恢复。
- [ ] 运行 OCR focused tests，确认新契约和持久化行为尚未实现而失败。
- [ ] repository 实现 job CRUD 与启动候选批量入队，所有查询只返回 ID/count。
- [ ] indexer 实现 `isPumpScheduled` 单泵；每轮只 fetch 一个 ID 和一条 content，识别包在 `autoreleasepool` 中，终态删除 job。
- [ ] `ClipService` 保存后仅传 saved ID；删除所有排队闭包对 `PasteboardContent` 的捕获。
- [ ] 发布真实 remaining/processed/skipped 活动状态，并用 generation token 防止旧的 1.5 秒完成收起覆盖新任务。
- [ ] 重跑 OCR focused tests，确认实时优先、崩溃恢复语义和内存边界通过。

### Task 3: 用可索引特征替换媒体清理全表解码

**Files:**
- Modify: `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`
- Test: `pasteraTests/Repositories/PasteboardHistorySearchPerformanceTests.swift`

**Interfaces:**
- Consumes: Task 1 的历史特征与 partial index
- Produces: 基于 `containsImage/containsFile` 的 indexed retention queries

- [ ] 写失败测试覆盖本地保存、远端 upsert、派生文本更新后特征一致性，以及混合 image+file 只删除一次。
- [ ] 增加 `EXPLAIN QUERY PLAN` 测试，要求图片和文件 overflow 查询命中对应 partial index。
- [ ] 在所有历史写入入口统一调用纯函数 `contentFacets(pasteboardTypes:)`，禁止分散重复判断。
- [ ] 用两条 offset ID 查询替换 cursor + `JSONDecoder` 全表循环；用 `Set` 合并后批量删除。
- [ ] 重跑 retention 与 performance focused tests，确认数量契约和索引路径通过。

### Task 4: 让 OneDrive 观察资源随配置激活

**Files:**
- Modify: `pastera/Sources/Services/SyncCoordinator.swift`
- Modify: `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`
- Test: `pasteraTests/SyncCoordinatorTests.swift`
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `isTextSyncCandidate` 与索引
- Produces: `SyncCoordinator.reloadConfiguration()` 和可比较 `ActivationSignature`
- Produces: lightweight history change token publisher

- [ ] 写 coordinator 失败测试覆盖未配置、目录无效、纯 import、history upload、snippet upload、关闭和重复配置。
- [ ] 写 repository 失败测试，证明 publisher 只选择 `id/updateAt` 且忽略远端、非候选内容。
- [ ] settings store 每次实际 setter 变更后发送 typed notification；相同值不重复触发。
- [ ] coordinator 用 activation signature 差量管理 timer、history cancellable、snippet cancellable，`stop()` 完全释放。
- [ ] 将历史观察 SQL 下推到 `deviceID + isTextSyncCandidate`，publisher 只输出 change tokens。
- [ ] 重跑 sync focused tests，确认现有 manual/startup/status 语义不变。

### Task 5: 实现已确认的 OCR 临时状态带

**Files:**
- Create: `pastera/Sources/Managers/MainMenuOCRActivityView.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/MainMenuVisualPolishTests.swift`
- Modify: `pasteraTests/CPYWindowAppearanceTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `PasteboardHistoryOCRActivity`
- Produces: `MainMenuOCRActivityView.render(activity:reduceMotion:)`

- [ ] 写失败的 AppKit 结构测试，锁定约 32pt 高度、footer 按钮仍存在、idle 隐藏、三个状态文案和 accessibility value。
- [ ] 创建单一职责状态带，复用系统 label/secondary label/semantic colors，不引入新视觉 token。
- [ ] 在 panel controller 中把状态带放在 scroll content 与 footer dock 之间；显隐时只重算内容 frame。
- [ ] 普通模式使用约 160ms 淡入/高度动画，完成态 1.5 秒；Reduce Motion 关闭空间动画。
- [ ] 补齐五种语言本地化，重跑主菜单 appearance/visual focused tests。
- [ ] 安装同一 build，在固定主菜单尺寸截取识别中、完成、部分失败三张真实截图，检查无覆盖、无按钮位移、文字不裁切。

### Task 6: 综合回归与资源验收

**Files:**
- Modify: `docs/superpowers/plans/2026-07-19-history-background-work-resource-optimization.md` 的 Delivery Record

- [ ] 运行数据库、repository、OCR、sync、main menu focused tests。
- [ ] 运行仓库默认 `xcodebuild ... clean test` 完整回归。
- [ ] 运行 `git diff --check`，确认无格式错误且 diff 未包含用户无关文件。
- [ ] 运行 `./script/install_local.sh`，核验 `/Applications/Pastera.app` 为当前 build 且进程存活。
- [ ] 用 Instruments 对比四个场景：连续复制大图、启动 200 OCR backlog、2000 条历史 prune、未配置 OneDrive idle；记录峰值与回落趋势。
- [ ] 将真实实现、偏差、测试、截图、Instruments 观察和剩余风险回写本文件，不创建第二份交付记录。

## Risks, Rollback and Observation

- **Migration cost:** V6 首次升级仍需一次性解码旧 `pasteboardTypes`。在单事务中执行并只写三个小整数；测试覆盖 0、典型和大数据集。若迁移失败，SQLiteData 保持 migration 未完成，可回滚应用版本重试，不删除旧 JSON。
- **Queue starvation:** 持续实时复制可能推迟低优先级回填。实时体验优先，回填仅在实时队列间隙继续；观察 job count 是否长期只增不减。
- **Failure retry:** 本轮识别失败被视为该 job 的终态并从队列移除，避免无限循环；历史仍可通过现有按需 OCR 路径再次尝试。
- **Observer activation drift:** 设置、目录或 vault 状态可能变化。activation signature 必须覆盖 root、方向、interval 和 vault 可同步性；重复重配置不得重复 timer/subscription。
- **UI height regression:** 状态带改变历史滚动区高度但不改变 panel 总高度。固定尺寸截图验证 footer、最后一行与空状态布局。
- **Rollback:** 代码可回退到 V6 前调度与查询实现；新增列和 job 表保留不会影响旧查询。不要逆向删除 migration 或用户历史。
- **Observation:** 安装后观察 OCR queue count、OCR queue CPU、主进程内存回落、prune duration、未配置 OneDrive idle CPU；若 queue 长期积压或 idle wakeups 增加，停止扩展并回查 activation/job 终态。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-19-history-background-work-resource-optimization.md`
- Plan Status: `implemented / automated-verification-complete / manual-performance-acceptance-pending`
- Evidence Profile: `standard`
- Story ID: `not-requested`
- Task IDs: `not-requested`; Superpowers Tasks 1-6 属于同一性能与资源优化闭环
- ZenTao Sync Status: `not-synced`，用户未要求禅道归档
- ZenTao Readback Evidence / Time: `not-applicable`
- Last Updated: `2026-07-19`

## Delivery Record

### Actual Implementation

- 新增 V6 migration：历史特征列、三条 partial index、持久化 OCR job 表和旧数据一次性回填。
- 实时 OCR 改为只提交 history ID；SQLite job 按实时/回填优先级调度，单泵每轮只加载一条内容。
- 启动 OCR 候选、媒体保留清理和文本同步观察均使用可索引特征或轻量 `id/updateAt` token。
- `SyncCoordinator` 通过 activation signature 按当前 root、同步方向和 vault 状态安装或释放 timer/history/snippet observation。
- 主菜单增加 32pt OCR 状态带，展示真实剩余数、完成数和跳过数；完成态保留 1.5 秒并支持 Reduce Motion。
- OCR 状态文案已补齐英语、德语、意大利语、日语和简体中文。

### Plan Deviations

- 状态带进入时使用 160ms alpha 动画；为避免主菜单滚动区与键盘焦点在完整 content reload 中抖动，高度重排保持即时，不对整块历史列表做空间插值。
- 未在自动化环境伪造 Instruments 负载；真实 200 张图片 OCR、连续复制大图和 idle CPU 对比保留为人工性能验收。

### Impact

- 实际触达 SQLite schema/migration、历史 repository、OCR 调度、OneDrive 生命周期、主菜单 AppKit 状态展示、本地化资源和 Xcode source membership。
- 不改变 OneDrive 文件协议、OCR 文本格式、Vision 参数、历史保留设置含义或面板总高度。

### Verification

- 设计方向 A 已由用户在视觉对比稿中选择并确认。
- 聚焦验证：repository/migration/sync 50 tests 通过；OCR/UI 28 tests 通过。
- 完整验证：默认 `xcodebuild ... clean test` 通过，682 tests / 75 suites，耗时 76.364 秒。
- `jq empty pastera/Resources/Localizable.xcstrings` 通过；`git diff --check` 通过。
- `./script/install_local.sh` 成功；`/Applications/Pastera.app` 已替换并运行，安装后 PID 84321。

### Remaining Risks

- V6 一次性迁移耗时和真实 Vision 工作负载内存回落仍需在有代表性的用户历史库上用 Instruments 确认。
- 三种 OCR 状态已做 AppKit 结构和本地化验证，但尚未保存真实窗口截图作为视觉证据。

### Follow-ups

- 人工验收连续复制大图、启动 200 OCR backlog、2000 条历史 prune 和未配置 OneDrive idle 四种场景。
- 观察持久化 OCR job 数是否长期只增不减；若出现，检查不可识别 job 的终态删除路径。

### ZenTao Closeout

- 未请求 ZenTao 写入，无外部状态变更。
