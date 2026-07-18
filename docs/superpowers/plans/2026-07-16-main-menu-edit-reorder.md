# 主菜单文件夹与条目编辑排序 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让密码箱与片段模块默认以浏览模式打开，并在编辑模式中支持文件夹折叠、新建文件夹、文件夹排序、条目排序和跨文件夹定点移动。

**Architecture:** `MainMenuPanelController` 继续拥有编辑、展开和拖拽会话状态；新增轻量 AppKit 行拖拽协议与位置计算器，只负责把拖拽转换成完整目标顺序。片段仓库与密码箱 store 分别提供原子重排接口，控制器乐观更新后以权威快照确认，失败时恢复旧快照。

**Tech Stack:** Swift 6.1、AppKit、SQLiteData、KDBXKit、Swift Testing、Xcode 26.5、macOS 13+

## Global Constraints

- 保持主菜单内嵌架构，不新增窗口或 SwiftUI 页面。
- 每次进入密码箱或片段模块时默认退出编辑模式。
- 文件夹保持单选可空的手风琴展开规则。
- 新建文件夹入口只在编辑模式显示，并且只在文件夹列表末尾出现一次。
- 文件夹不能嵌套；密码条目和片段可在文件夹内排序及跨文件夹移动。
- 拖拽提交必须原子更新源、目标和相关索引；失败时不得保留部分结果。
- 不改变密码箱解锁、身份验证、复制、粘贴、同步及片段执行语义。
- 保留工作区现有未提交改动，只修改本计划列出的行为链文件。

---

## Business Scope / Out of Scope

**Business Scope**

- 密码箱与片段模块的默认浏览状态、编辑状态和折叠行为。
- 编辑模式底部 `+ 新建文件夹` 入口。
- 文件夹拖拽排序。
- 密码条目与片段的同文件夹排序和跨文件夹定点移动。
- KDBX、密码箱兼容 store 和 SQLiteData 中的顺序持久化。

**Out of Scope**

- 多选拖拽、文件夹嵌套、跨模块拖拽、撤销历史和自动排序。
- 密码箱解锁流程、片段编辑器或主菜单整体视觉重构。
- ZenTao 创建、更新或状态流转；本任务没有用户授权的 ZenTao 归档要求。

## File Map

- Modify: `pastera/Sources/Services/PasswordVaultStore.swift` — 定义密码箱排序契约，并在兼容 store 中持久化数组顺序。
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift` — 用 KDBX group/entry 原生数组顺序实现原子重排。
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift` — 在现有串行 store queue 上暴露异步重排。
- Modify: `pastera/Sources/Repositories/SnippetRepository.swift` — 原子更新源/目标片段索引并返回成功状态。
- Modify: `pastera/Sources/Managers/MenuManager.swift` — 将仓库和密码箱 controller 的重排闭包接入主菜单数据源。
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift` — 默认浏览、折叠、新建入口、拖拽会话、Drop 计算与回滚。
- Modify: `pastera/Resources/Localizable.xcstrings` — 增加“新建文件夹”、拖拽和保存失败的可访问性文案。
- Test: `pasteraTests/PasswordVaultStoreTests.swift` — 两套密码箱 store 的顺序和原子性。
- Test: `pasteraTests/Repositories/SnippetRepositoryTests.swift` — 片段同文件夹与跨文件夹完整索引。
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift` — 片段模块编辑、折叠、新建入口与拖拽提交。
- Test: `pasteraTests/PasswordVaultMenuTests.swift` — 密码箱默认浏览、折叠、排序和失败回滚。

### Task 1: 建立密码箱原子排序契约

**Files:**
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Test: `pasteraTests/PasswordVaultStoreTests.swift`

**Interfaces:**
- Produces: `PasswordVaultStore.reorderFolders(_ folderIDs: [UUID]) throws`
- Produces: `PasswordVaultStore.moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws`
- Contract: `orderedEntryIDsByFolder` 必须包含受影响源/目标文件夹的完整条目 ID 顺序；同文件夹排序时字典只有一个键。

- [ ] **Step 1: 为兼容 store 和 KDBX store 写失败测试**

在 `PasswordVaultStoreTests.swift` 的共享 store 测试中加入以下断言结构，并分别通过现有工厂运行兼容 store 与 KDBX store：

```swift
let work = try store.createFolder(name: "Work")
let archive = try store.createFolder(name: "Archive")
let first = try store.create(.init(
    folderID: work.id, title: "First", website: "", username: "a", note: "", password: "1"
))
let second = try store.create(.init(
    folderID: work.id, title: "Second", website: "", username: "b", note: "", password: "2"
))
let archived = try store.create(.init(
    folderID: archive.id, title: "Archived", website: "", username: "c", note: "", password: "3"
))

try store.reorderFolders([archive.id, work.id])
#expect(try store.listFolders().map(\.id) == [archive.id, work.id])

try store.moveEntry(
    id: second.id,
    to: archive.id,
    orderedEntryIDsByFolder: [
        work.id: [first.id],
        archive.id: [second.id, archived.id]
    ]
)
#expect(try store.listEntries().filter { $0.folderID == work.id }.map(\.id) == [first.id])
#expect(try store.listEntries().filter { $0.folderID == archive.id }.map(\.id) == [second.id, archived.id])
```

另加无效 ID、重复 ID、遗漏现有 ID 的测试，断言抛出 `.folderNotFound` 或 `.entryNotFound`，且重新读取的顺序完全等于操作前快照。

- [ ] **Step 2: 运行密码箱聚焦测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/PasswordVaultStoreTests test
```

Expected: FAIL，提示 `PasswordVaultStore` 尚无两个重排接口。

- [ ] **Step 3: 实现兼容 store 的完整顺序验证与单次保存**

在协议中加入两个接口，并让兼容 store 直接以 `metadata.folders` 和按文件夹组织后的 `metadata.entries` 数组顺序作为展示顺序，不再用 `updatedAt` 二次排序。实现必须先在内存副本上完成以下校验，再调用一次 `saveMetadata`：

```swift
func reorderFolders(_ folderIDs: [UUID]) throws {
    var metadata = try loadMetadata()
    guard Set(folderIDs) == Set(metadata.folders.map(\.id)), folderIDs.count == metadata.folders.count else {
        throw PasswordVaultError.folderNotFound
    }
    let foldersByID = Dictionary(uniqueKeysWithValues: metadata.folders.map { ($0.id, $0) })
    metadata.folders = try folderIDs.map { id in
        guard let folder = foldersByID[id] else { throw PasswordVaultError.folderNotFound }
        return folder
    }
    try saveMetadata(metadata)
}
```

`moveEntry` 先验证目标文件夹和移动条目，再验证字典中每个文件夹的 ID 集合与操作前该文件夹条目集合（加上或移除移动条目后）一致且无重复；验证全部通过后重建 `metadata.entries` 并保存一次。

- [ ] **Step 4: 实现 KDBX group/entry 数组的原子重排**

`reorderFolders` 用完整 ID 序列重建 `content.database.root.group.groups`。`moveEntry` 在 `var content = try requiredContent()` 副本内移除条目、更新 `previousParentGroup`、`locationChanged` 和 `lastModificationTime`，再按字典给出的完整 ID 顺序重建受影响 group 的 `entries`；所有校验完成后只调用一次 `save(content)`。

`listFolders()` 和 `listEntries()` 必须保持 KDBX 文件中的 group/entry 数组顺序，不再按更新时间重排。

- [ ] **Step 5: 运行聚焦测试并提交**

Run: Task 1 Step 2 的命令。

Expected: `PasswordVaultStoreTests` PASS；现有并发合并测试若仍是已知失败，必须确认失败名称与本任务无关并记录在 Delivery Record，不能把整套测试写成通过。

```bash
git add pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pasteraTests/PasswordVaultStoreTests.swift
git commit -m "feat(vault): persist manual folder and entry order"
```

### Task 2: 让片段跨文件夹移动原子更新两侧顺序

**Files:**
- Modify: `pastera/Sources/Repositories/SnippetRepository.swift`
- Test: `pasteraTests/Repositories/SnippetRepositoryTests.swift`

**Interfaces:**
- Produces: `SnippetRepositoryProtocol.reorderFolders(_ folderIDs: [SnippetFolder.ID]) -> Bool`
- Produces: `SnippetRepositoryProtocol.moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, orderedSnippetIDsByFolder: [SnippetFolder.ID: [Snippet.ID]]) -> Bool`
- Replaces UI usage of the current target-only `updateFolderIndexes` / `moveSnippet(...snippetIDs:)` behavior; legacy methods may remain for non-main-menu callers until references are migrated.

- [ ] **Step 1: 写跨文件夹源索引压紧与失败原子性测试**

扩展现有 `moveSnippet()` 测试：从第二个文件夹移动中间条目后，同时传入两个文件夹的完整顺序并断言两侧索引都从 `0` 连续排列。

```swift
let success = repository.moveSnippet(
    snippet4.id,
    to: folder.id,
    orderedSnippetIDsByFolder: [
        folder.id: [snippet.id, snippet4.id, snippet2.id],
        folder2.id: [snippet3.id, snippet5.id]
    ]
)
#expect(success)
#expect(repository.fetchFolderDetail(id: folder.id)?.snippets.map(\.index) == [0, 1, 2])
#expect(repository.fetchFolderDetail(id: folder2.id)?.snippets.map(\.index) == [0, 1])
```

增加重复 ID 或遗漏 ID 的调用，断言返回 `false` 且操作前后 `fetchFolderDetails()` 相等。

- [ ] **Step 2: 运行仓库聚焦测试并确认新测试失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/SnippetRepositoryTests test
```

Expected: FAIL，缺少返回 `Bool` 的完整重排接口，或源文件夹索引仍为 `[0, 2]`。

- [ ] **Step 3: 在单个 SQLiteData write transaction 中校验并更新**

实现 `reorderFolders` 时校验 ID 集合等于当前全部文件夹集合，然后在同一 transaction 更新连续索引。实现 `moveSnippet` 时先读取受影响文件夹的现有条目集合，计算移动后的期望集合，验证完整顺序无重复且无遗漏，再在同一 transaction 更新移动条目的 `folderID` 和所有受影响条目的 `index`、`updatedAt`、`lastModifiedDeviceID`。捕获错误后返回 `false`。

- [ ] **Step 4: 运行聚焦测试并提交**

Run: Task 2 Step 2 的命令。

Expected: `SnippetRepositoryTests` PASS。

```bash
git add pastera/Sources/Repositories/SnippetRepository.swift \
  pasteraTests/Repositories/SnippetRepositoryTests.swift
git commit -m "fix(snippets): update both sides of reordered moves"
```

### Task 3: 将重排能力接入主菜单数据源

**Files:**
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift`

**Interfaces:**
- Adds to `MainMenuSnippetDataSource`: `reorderFolders` 与 `moveSnippet`，两者返回 `Bool`。
- Adds to `MainMenuPasswordVaultDataSource`: `reorderFolders` 与 `moveEntry` 异步闭包。
- Adds to `PasswordVaultUIController`: 对应异步方法，复用 `perform(completion:operation:)`。

- [ ] **Step 1: 写数据源接线失败测试**

在两个主菜单测试文件构造可记录参数的数据源，分别调用 controller 的测试入口：

```swift
controller.reorderSnippetFoldersForTesting([secondFolderID, firstFolderID])
#expect(receivedFolderOrder == [secondFolderID, firstFolderID])

controller.movePasswordEntryForTesting(
    entryID,
    to: archiveID,
    orderedEntryIDsByFolder: [workID: [], archiveID: [entryID]]
)
#expect(receivedPasswordMove?.destination == archiveID)
```

并增加密码箱保存失败回调，断言 controller 保留编辑模式并公开现有错误状态供行内反馈使用。

- [ ] **Step 2: 运行两组主菜单测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests test
```

Expected: FAIL，缺少数据源闭包与 controller 测试入口。

- [ ] **Step 3: 增加数据源闭包并从 MenuManager 接入真实仓库**

使用以下签名，默认闭包返回失败以保持测试构造器兼容：

```swift
let reorderFolders: ([SnippetFolder.ID]) -> Bool
let moveSnippet: (Snippet.ID, SnippetFolder.ID, [SnippetFolder.ID: [Snippet.ID]]) -> Bool

let reorderFolders: ([PasswordVaultFolder.ID], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
let moveEntry: (PasswordVaultEntry.ID, PasswordVaultFolder.ID, [PasswordVaultFolder.ID: [PasswordVaultEntry.ID]], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
```

`MenuManager` 的片段闭包调用 `snippetRepository` 新接口；密码箱闭包调用 `PasswordVaultUIController` 新异步方法。UI controller 必须在现有 `storeQueue` 中调用 Task 1 的 store 接口，并在完成后刷新 snapshot。

- [ ] **Step 4: 运行聚焦测试并提交**

Run: Task 3 Step 2 的命令。

Expected: 两组测试 PASS。

```bash
git add pastera/Sources/Managers/PasswordVaultUIController.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Sources/Managers/MenuManager.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift
git commit -m "feat(menu): wire reorder operations into embedded data sources"
```

### Task 4: 实现默认浏览、可折叠编辑模式和底部新增入口

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: Task 3 数据源闭包。
- Produces: 模块进入时的浏览状态重置、单选可空展开状态、唯一底部新增行。

- [ ] **Step 1: 写状态与行模型失败测试**

两个模块分别覆盖：进入编辑模式后切到其他模式再返回，`isWorkspaceEditingForTesting == false`；编辑模式点击已展开文件夹后全部收起；收起后行标题仍以 `New Folder` 结尾且只出现一次；退出编辑模式后该行消失。

```swift
controller.openSnippetsFromMainMenu()
controller.toggleWorkspaceEditingForTesting()
controller.toggleSnippetFolderForTesting(folderID)
#expect(controller.expandedSnippetFolderIDForTesting == nil)
#expect(controller.mainMenuVisibleRowTitlesForTesting.filter { $0 == "New Folder" }.count == 1)

controller.openHistoryFromMainMenu()
controller.openSnippetsFromMainMenu()
#expect(!controller.isWorkspaceEditingForTesting)
```

密码箱使用相同断言，并验证无文件夹时编辑模式仍显示新增入口。

- [ ] **Step 2: 运行主菜单聚焦测试并确认失败**

Run: Task 3 Step 2 的命令。

Expected: FAIL；当前片段和密码箱在非编辑状态会自动展开首个文件夹，且新增入口依赖展开状态。

- [ ] **Step 3: 统一模块进入与底部新增行规则**

在模式切换入口集中调用 `endWorkspaceEditing(resetExpansion: false)`，清除 inline editor、快捷键 editor 和拖拽状态。调整 `snippetEmbeddedContent()` 与密码箱内容构建：

```swift
if isWorkspaceEditing, inlineEditorState == nil {
    rows.append(makeNewFolderRow(action: beginCreatingSnippetFolder))
}
```

密码箱追加对应 `beginCreatingPasswordVaultFolder` 行。移除“仅在 `expandedFolderID == nil` 时添加创建区”的分支；文件夹确认动作始终执行 `expandedID = expandedID == id ? nil : id`，编辑模式不得短路折叠。

- [ ] **Step 4: 补齐本地化和无障碍标签**

在 string catalog 中加入或复用：`New Folder`、`Drag to reorder folder`、`Drag to reorder item`、`Move failed. Your previous order was restored.`。新增入口使用 `plus` SF Symbol，标题和 accessibility label 都是 `New Folder`，不使用裸 `+` 作为唯一语义。

- [ ] **Step 5: 运行聚焦测试并提交**

Run: Task 3 Step 2 的命令。

Expected: 两组测试 PASS。

```bash
git add pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Resources/Localizable.xcstrings \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift
git commit -m "feat(menu): keep editing folders collapsible with one add entry"
```

### Task 5: 实现 AppKit 拖拽、定点插入和失败回滚

**Files:**
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Test: `pasteraTests/MainMenuEmbeddedContentTests.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces:**
- Consumes: Task 3 的原子重排闭包。
- Produces: `MainMenuDragPayload`、`MainMenuDropTarget`、纯位置计算函数、行级拖拽 source/destination 行为。
- Constraint: 仅编辑模式注册内部 pasteboard type；浏览模式的 `mouseDragged` 仍保留窗口拖动行为。

- [ ] **Step 1: 先写纯拖拽位置计算和提交参数测试**

测试文件夹从索引 0 拖到索引 2、条目同文件夹前移、条目跨文件夹插入中间、无效自拖放、拖拽取消和保存失败。断言生成完整顺序：

```swift
#expect(MainMenuReorder.folderIDs([a, b, c], moving: a, before: nil) == [b, c, a])
#expect(MainMenuReorder.entryIDs([one, two, three], moving: three, before: two) == [one, three, two])
```

跨文件夹测试断言 source 不再包含移动 ID，destination 在目标位置包含一次移动 ID。

- [ ] **Step 2: 运行主菜单聚焦测试并确认失败**

Run: Task 3 Step 2 的命令。

Expected: FAIL，缺少拖拽 payload、位置计算与测试入口。

- [ ] **Step 3: 在现有 AppKit 行视图中增加最小拖拽边界**

为 `MainMenuPanelRowView` 增加可选 `dragPayload`、`onDropEntered`、`onDropExited`、`onPerformDrop`。编辑模式的 `mouseDragged` 写入进程内自定义 pasteboard type 并开始 `NSDraggingSession`；非编辑模式继续调用 `window?.performDrag(with:)`。目标行注册该 type，根据鼠标 Y 位置显示顶部或底部 2pt 插入线；文件夹主体显示可接收高亮。

拖拽 payload 只编码稳定 ID 和类型，不编码标题或密码内容：

```swift
enum MainMenuDragPayload: Codable, Equatable {
    case snippetFolder(UUID)
    case snippet(UUID, sourceFolderID: UUID)
    case passwordFolder(UUID)
    case passwordEntry(UUID, sourceFolderID: UUID)
}
```

- [ ] **Step 4: 实现悬停展开和控制器拖拽会话**

控制器保存拖拽前的文件夹详情/密码箱快照与 `isWorkspaceEditing`。悬停在已收起文件夹时复用 `MainMenuPanelLayout.folderHoverOpenDelay` 调度展开；离开、放下、模块切换或锁定时取消 work item。Drop 后先更新临时顺序并 reload，再调用数据源；失败回调恢复旧快照/重新读取权威数据、保持编辑模式并展示本地化错误。

- [ ] **Step 5: 验证浏览模式不被拖拽注册破坏**

补充测试断言浏览模式行没有内部 drag payload，现有单击、双击、右键、键盘确认和窗口拖动入口仍可用；编辑模式行才暴露对应 payload。密码内容不得写入 `NSPasteboard`。

- [ ] **Step 6: 运行聚焦测试并提交**

Run: Task 3 Step 2 的命令。

Expected: 两组测试 PASS，拖拽顺序、跨文件夹移动、悬停展开、取消和失败回滚均有覆盖。

```bash
git add pastera/Sources/Managers/MainMenuPanelController.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift
git commit -m "feat(menu): add editable folder and item drag reordering"
```

### Task 6: 完整回归、真实安装与交互验收

**Files:**
- Modify: `docs/superpowers/plans/2026-07-16-main-menu-edit-reorder.md`（仅回写 Delivery Record）

**Interfaces:**
- Consumes: Task 1–5 的完整实现。
- Produces: 可复核的测试、安装和人工验收证据。

- [ ] **Step 1: 运行所有相关聚焦测试**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/SnippetRepositoryTests test
```

Expected: 新增及相关既有测试 PASS；若已知并发 store 测试仍失败，记录准确名称与日志证据。

- [ ] **Step 2: 运行仓库默认回归与静态 diff 检查**

```bash
git diff --check
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation clean test
```

Expected: `git diff --check` 无输出；全量测试 PASS，或只保留已核实且与本变更无关的既有失败。

- [ ] **Step 3: 安装本地构建并人工验收**

```bash
./script/install_local.sh
ps -axo pid,command | rg '/Applications/Pastera\.app/Contents/MacOS/Pastera$'
```

人工在密码箱与片段模块分别验证：默认浏览；进入编辑；展开后再收起至全部折叠；底部仅一个新增文件夹入口；文件夹首尾排序；条目同文件夹前后排序；条目拖入收起文件夹并在悬停展开后放到中间；退出重进后顺序保持；浏览模式复制/粘贴或执行片段正常。

- [ ] **Step 4: 回写 Delivery Record 并提交实现收尾**

填写实际改动、偏差、测试结果、安装进程证据和残余风险，不创建第二份交付文档。

```bash
git add docs/superpowers/plans/2026-07-16-main-menu-edit-reorder.md
git commit -m "docs: record main menu reorder verification"
```

## Acceptance Mapping

| Acceptance | Implementation | Verification |
|---|---|---|
| 默认浏览模式 | Task 4 模式进入重置 | 两个主菜单测试 + 人工重进 |
| 编辑模式允许全部收起 | Task 4 单选可空状态 | controller 状态测试 + 人工折叠 |
| 底部唯一新建文件夹入口 | Task 4 行模型 | 行标题/identifier 数量断言 |
| 文件夹持久排序 | Task 1、2、3、5 | store/repository 重载测试 + 人工重进 |
| 条目内部排序 | Task 1、2、5 | 完整 ID 顺序测试 |
| 条目跨文件夹定点移动 | Task 1、2、5 | 两侧连续索引与 KDBX 顺序测试 |
| 收起目标悬停展开 | Task 5 hover work item | controller 测试 + 人工拖拽 |
| 失败不部分保存 | Task 1、2、5 原子校验和回滚 | 无效顺序测试 + UI 失败回调测试 |
| 原有行为无回归 | 全局约束 | 聚焦/全量测试 + 人工复制、粘贴、执行 |

## Risks, Rollback and Observation

- **风险：** `MainMenuPanelRowView.mouseDragged` 当前用于拖动窗口。编辑模式内部拖拽必须显式分流，避免破坏浏览模式窗口拖动。
- **风险：** 改为持久顺序会替代密码箱现有“按更新时间降序”的隐式行为；这是实现用户排序的必要契约变化，需通过重载测试锁定。
- **风险：** KDBX 外部程序可能改变 group/entry 顺序；下次 `reloadAndMerge()` 后以文件中的权威顺序为准。
- **风险：** 当前工作区已有密码箱大范围未提交改动；实施时逐文件核对 diff，不覆盖这些改动。
- **回滚：** 每个任务独立提交，可按 Task 5 → Task 1 顺序逐层回滚；数据格式不新增字段，回滚不会要求迁移。
- **观察：** 人工关注快速连续拖拽、悬停自动展开、锁定时取消拖拽、窗口拖动以及外部 KDBX 重载后的顺序。

## Delivery Metadata

- Plan status: implemented; awaiting manual visual acceptance
- Evidence profile: standard
- Design source: `docs/superpowers/specs/2026-07-16-main-menu-edit-reorder-design.md`
- ZenTao: not requested; no external write authorized
- Implementation authorization: granted by user on 2026-07-16

## Delivery Record

- Actual Implementation: 密码箱兼容 store、KDBX store 与片段仓库均新增完整顺序的原子重排；主菜单接入文件夹/条目拖拽、跨文件夹移动、收起目标悬停展开、默认浏览态和编辑态底部唯一“+ 新建文件夹”入口。
- Plan Deviations: 为避免持久化失败后的可见闪动，控制器采用“持久化成功后刷新权威快照”，没有先做乐观 UI 更新；当前脏工作区包含用户既有改动，因此未创建会混入既有改动的实现提交。
- Impact: 密码箱与片段模块改为显式持久顺序；浏览模式仍保留窗口拖动、复制/粘贴和片段执行路径。
- Verification: 相关 5 个 suite 共 73 个测试通过；`git diff --check` 通过；默认全量回归执行 635 个测试，其中 22 个失败，失败集中于工作区既有偏好页/视觉尺寸改动、旧默认展开断言及一个同步测试超时；本计划相关旧断言已更新后聚焦回归通过。`./script/install_local.sh` 构建成功并安装到 `/Applications/Pastera.app`，进程已启动。
- Remaining Risks: 真实鼠标拖拽的插入线视觉和不同速度下的悬停手感仍需用户人工验收；CoreSimulator 版本告警与 macOS 服务日志属于环境噪声。
- Follow-ups: 人工验证文件夹首尾排序、条目跨文件夹中间插入及重启后顺序保持；验收后再决定是否拆分提交。
- ZenTao Closeout: not applicable
