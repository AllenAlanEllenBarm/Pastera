# 密码箱本地优先与 OneDrive 可选同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将密码箱从“直接读写 OneDrive KDBX”改为“本地加密 KDBX 是唯一工作副本，OneDrive 是用户主动开启的可选同步副本”，保证无 OneDrive、OneDrive 断联和云端错误时仍可完整使用本地密码箱；主界面 OneDrive 图标只显示状态并打开或激活客户端，账户与单向启用留在设置页，密码箱内只保留必要恢复与冲突处理。

**Architecture:** `KDBXPasswordVaultStore` 只访问 Application Support 下的本地 KDBX；一次性迁移服务负责把旧版云端工作文件安全复制到本地；独立的 `PasswordVaultSyncService` 维护同步模式、基线、待同步计数和 OneDrive 副本，通过现有 `SyncCoordinator` 的串行调度执行摘要比较、单向复制或条目级合并。密码箱状态与同步状态独立，云端错误只进入同步状态，不得进入主密码字段错误。

**Tech Stack:** Swift 6、AppKit、Foundation、CryptoKit、KDBXKit、Swift Testing、NSFileCoordinator、macOS OneDrive File Provider、Xcode 26.5。

## Global Constraints

- 实施必须以已确认规格 `docs/superpowers/specs/2026-07-22-password-vault-local-first-onedrive-sync-design.md` 为唯一产品契约。
- 当前 `/Users/feeyo/workspace/github.com/pastera-app/Pastera` 工作区已有未提交改动；不得重置、覆盖或混入这些改动。实施时从包含本计划的 `develop` 新建隔离 worktree，并在合并前逐项核对当前工作区中已完成的云端解锁响应性测试是否需要保留或被新架构替代。
- 本地 Application Support KDBX 是唯一工作副本；解锁、快速解锁、自动化解锁、增删改、改主密码均不得访问 OneDrive 路径。
- “仅保存在本机”是首次创建默认值；检测到 OneDrive 不得自动开启密码箱同步。
- 不更改 KDBX 格式、主密码派生、Keychain、自动锁定、Agent 授权和安全剪贴板策略。
- 本地与 OneDrive 只持久化加密 KDBX。同步元数据、通知、日志、UserDefaults 和 accessibility value 均不得包含标题、账号、密码、网址、备注或解密内容。
- OneDrive 未运行、目录不可用、文件仍是占位符、空间不足、无权限或云端损坏时，本地写入必须成功或只报告本地写入错误；不得报告主密码错误。
- 恢复连接时禁止整库“最后写入覆盖”。两端变化必须在密码箱解锁后按 UUID、修改时间、历史记录和 tombstone 规则合并；无法判定时生成冲突副本。
- 云端临时写入、原子替换和重新读取摘要全部成功后，才允许清除待同步状态。
- 2026-08-04 交互修订覆盖 Task 9/10 的旧入口：点击底部 OneDrive 图标只调用 `openOneDrive()` 以启动或激活客户端，不切换密码箱页面，不打开 popover、sheet 或向导。
- 产品界面删除停止同步、删除云端副本及其确认页；设置页只允许 localOnly 单向启用密码箱同步。
- 只有精确名为 `OneDrive` 的个人根目录可自动选择；任何 `OneDrive-*` 候选都要求用户明确选择，已知共享资料库与 `CloudTemp` 不得作为候选。
- 新增 Swift 源文件与测试文件必须加入 `pastera.xcodeproj/project.pbxproj` 的正确 group、target membership 和 Sources phase。
- 所有功能和修复遵循 TDD：先运行新增测试观察预期 RED，再写最小生产代码，最后运行聚焦测试观察 GREEN。
- 每个任务提交前运行 `git diff --check`，提交只包含该任务文件，不得提交 `.codex/`、`.superpowers/`、`.spm-cache/` 或用户的无关改动。

---

## 交付结构与状态边界

### 本地路径

本地工作文件固定为：

```text
~/Library/Application Support/<bundle-id>/PasswordVault/PasteraVault.kdbx
~/Library/Application Support/<bundle-id>/PasswordVault/PasteraVault.kdbx.bak
~/Library/Application Support/<bundle-id>/PasswordVault/PasswordVaultSyncMetadata.json
```

测试必须通过依赖注入使用临时目录，不能读写真实用户目录。

### 云端路径

为兼容现有数据，继续使用：

```text
<configured-sync-root>/PasteraSync/vault/PasteraVault.kdbx
```

密码箱是否启用 OneDrive 使用独立配置键；历史、片段或文件同步已配置 OneDrive 根目录，不代表密码箱同步已启用。

### 核心接口

实施时以以下类型边界为准；允许因 Swift 编译要求调整访问级别，不得合并密码箱状态与同步状态：

```swift
enum PasswordVaultCommitOrigin: Equatable {
    case userMutation
    case syncMerge
    case migration
}

struct PasswordVaultCommit: Equatable {
    let origin: PasswordVaultCommitOrigin
    let encryptedDigest: String
}

struct PasswordVaultEncryptedSnapshot: Equatable {
    let data: Data
    let digest: String
}

protocol PasswordVaultSyncAccess: AnyObject {
    var state: PasswordVaultState { get }
    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot
    func mergeRemoteSnapshot(
        _ remoteData: Data,
        remoteMasterPassword: String?
    ) throws -> PasswordVaultMergeApplication
    func setCommitObserver(_ observer: @escaping (PasswordVaultCommit) -> Void)
}

struct PasswordVaultMergeApplication: Equatable {
    let encryptedSnapshot: PasswordVaultEncryptedSnapshot
    let conflictCopyCount: Int
}
```

```swift
enum PasswordVaultSyncMode: String, Codable, Equatable {
    case localOnly
    case oneDrive
}

enum PasswordVaultSyncFailure: String, Codable, Equatable, Error {
    case oneDriveNotInstalled
    case oneDriveNotRunning
    case folderUnavailable
    case folderNotWritable
    case remoteUnavailable
    case remoteCorrupted
    case remoteCredentialsRequired
    case remoteWriteFailed
    case remoteVerificationFailed
}

enum PasswordVaultSyncPhase: Equatable {
    case disabled
    case synced
    case syncing(PasswordVaultSyncStep)
    case disconnected(PasswordVaultSyncFailure)
    case waitingForUnlock
    case conflicts(Int)
    case failed(PasswordVaultSyncFailure)
}

enum PasswordVaultSyncStep: String, Codable, Equatable {
    case checking
    case downloading
    case merging
    case savingLocal
    case uploading
    case verifying
}

struct PasswordVaultSyncSnapshot: Equatable {
    let mode: PasswordVaultSyncMode
    let phase: PasswordVaultSyncPhase
    let localVaultAvailable: Bool
    let remoteVaultAvailable: Bool?
    let pendingChangeCount: Int
    let conflictCopyCount: Int
    let lastSyncAt: Date?
}
```

```swift
struct PasswordVaultSyncMetadata: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: PasswordVaultSyncMode
    var localRevision: UInt64
    var lastSyncedLocalRevision: UInt64
    var lastSyncedLocalDigest: String?
    var lastObservedRemoteDigest: String?
    var lastSyncAt: Date?
    var pendingChangeCount: Int
    var conflictCopyCount: Int
    var lastFailure: PasswordVaultSyncFailure?
    var migrationVersion: Int
}

protocol PasswordVaultSyncMetadataStoring {
    func load() throws -> PasswordVaultSyncMetadata
    func save(_ metadata: PasswordVaultSyncMetadata) throws
}
```

### 同步决策表

| 本地相对基线 | 云端相对基线 | 处理 |
| --- | --- | --- |
| 未变化 | 未变化 | 无操作，保持已同步 |
| 已变化 | 未变化 | 上传本地加密 KDBX，回读摘要后更新基线 |
| 未变化 | 已变化 | 解锁后合并云端到本地；锁定时进入“等待解锁” |
| 已变化 | 已变化 | 解锁后执行条目级双向合并；锁定时不覆盖任一端 |
| 首次启用且云端不存在 | 不适用 | 上传本地加密 KDBX，建立基线 |
| 首次启用且云端存在 | 不适用 | 解锁后合并；不同主密码时在当前页面请求云端主密码 |

本地变化判定同时使用 `localRevision != lastSyncedLocalRevision` 和本地加密摘要，避免“本地文件已写入但同步元数据尚未落盘”的崩溃窗口漏同步。

---

## Tasks

### Task 1: 建立隔离实施基线并锁定回归范围

**Files:**
- Read: `AGENTS.md`
- Read: `docs/superpowers/specs/2026-07-22-password-vault-local-first-onedrive-sync-design.md`
- Read: `docs/superpowers/plans/2026-07-22-password-vault-cloud-unlock-responsiveness.md`
- Test: `pasteraTests/PasswordVaultStoreTests.swift`
- Test: `pasteraTests/PasswordVaultMenuTests.swift`
- Test: `pasteraTests/SyncCoordinatorTests.swift`

- [ ] 在当前工作区记录 `git status --short --branch`、`git rev-parse HEAD` 和 `git diff --name-only`，确认用户未提交改动保持原样。
- [ ] 从含本计划的 `develop` 创建隔离 worktree：

```bash
git worktree add ../Pastera-vault-local-first -b codex/password-vault-local-first develop
```

- [ ] 在新 worktree 中确认分支、HEAD、远端关系和清洁状态：

```bash
git status --short --branch
git rev-list --left-right --count origin/develop...HEAD
```

- [ ] 运行当前密码箱和同步基线，保存通过数量与失败名称；基线失败必须先单独复现并归类，不得直接归因于本功能：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests \
  -only-testing:pasteraTests/SyncCoordinatorTests
```

- [ ] 对照旧“云端解锁响应性”计划，列出必须保留的安全回归：忙碌态即时呈现、短读不映射为 KDBX 损坏、内部错误码不直出。记录“云端预取缓存”被本地优先架构替代，不把旧实现原样搬入新 worktree。
- [ ] 本任务不修改生产代码；若基线可复现为仓库已有失败，在计划 Delivery Record 单独记录。

### Task 2: 建立本地 KDBX 原子存储与独立同步模型

**Files:**
- Create: `pastera/Sources/Services/PasswordVaultLocalStorage.swift`
- Create: `pastera/Sources/Services/PasswordVaultSyncModels.swift`
- Modify: `pastera/Sources/Constants.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/PasswordVaultLocalStorageTests.swift`
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`

- [ ] 先添加测试，覆盖：bundle id 路径隔离、首次写入、覆盖前生成 `.bak`、写入失败保留原文件、空数据和错误 KDBX 签名被拒绝、同步元数据 JSON 不含敏感字段。
- [ ] 运行新增测试并观察 RED，预期失败为类型尚不存在或测试 target 尚未包含新文件：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj -destination 'platform=macOS' \
  test -only-testing:pasteraTests/PasswordVaultLocalStorageTests
```

- [ ] 在 `PasswordVaultLocalStorage.swift` 实现以下边界：

```swift
struct PasswordVaultLocalPaths: Equatable {
    let directoryURL: URL
    let vaultURL: URL
    let backupURL: URL
    let metadataURL: URL

    static func live(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.pastera-app.Pastera"
    ) -> PasswordVaultLocalPaths {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let directory = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("PasswordVault", isDirectory: true)
        return PasswordVaultLocalPaths(
            directoryURL: directory,
            vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
            backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
            metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
        )
    }
}

protocol PasswordVaultLocalStoring {
    var paths: PasswordVaultLocalPaths { get }
    func containsVault() -> Bool
    func read() throws -> Data
    func writeAtomically(_ data: Data) throws
    func readBackup() throws -> Data
}

final class FilePasswordVaultLocalStorage: PasswordVaultLocalStoring {
    let paths: PasswordVaultLocalPaths
    private let fileManager: FileManager

    init(paths: PasswordVaultLocalPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) -> FilePasswordVaultLocalStorage {
        FilePasswordVaultLocalStorage(
            paths: .live(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func containsVault() -> Bool {
        fileManager.fileExists(atPath: paths.vaultURL.path)
    }

    func read() throws -> Data {
        let data = try Data(contentsOf: paths.vaultURL)
        try validate(data)
        return data
    }

    func readBackup() throws -> Data {
        let data = try Data(contentsOf: paths.backupURL)
        try validate(data)
        return data
    }

    func writeAtomically(_ data: Data) throws {
        try validate(data)
        try fileManager.createDirectory(
            at: paths.directoryURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = paths.directoryURL
            .appendingPathComponent("PasteraVault-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try validate(Data(contentsOf: temporaryURL))
        if containsVault() {
            let current = try Data(contentsOf: paths.vaultURL)
            try validate(current)
            try current.write(to: paths.backupURL, options: .atomic)
            _ = try fileManager.replaceItemAt(paths.vaultURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: paths.vaultURL)
        }
    }

    private func validate(_ data: Data) throws {
        let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])
        guard data.count >= signature.count, data.prefix(signature.count) == signature else {
            throw PasswordVaultError.corruptedData
        }
    }
}
```

- [ ] `writeAtomically` 必须按“校验新数据签名 → 写同目录临时文件 → 校验临时文件 → 备份现有主文件 → 原子替换主文件”的顺序执行；任一步失败时主文件保持原值。KDBX 签名校验固定检查前八字节 `03 D9 A2 9A 67 FB 4B B5`。
- [ ] 在 `PasswordVaultSyncModels.swift` 实现本计划“核心接口”中的同步模式、步骤、失败类别、快照、元数据、元数据存储协议、提交来源和加密摘要类型；使用 `CryptoKit.SHA256` 统一生成小写十六进制摘要。Task 4 先通过该协议注入测试存储，Task 5 再提供 JSON 生产实现。
- [ ] 在 `Constants.UserDefaults` 增加独立键：

```swift
static let passwordVaultSyncMode = "kPasteraPasswordVaultSyncMode"
static let passwordVaultLocalFirstMigrationVersion = "kPasteraPasswordVaultLocalFirstMigrationVersion"
```

- [ ] 将两个新源文件和一个新测试文件加入 Xcode project 与对应 target。
- [ ] 运行新增测试观察 GREEN，再运行现有 `PasswordVaultStoreTests`，确认未引入类型冲突。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultLocalStorage.swift \
  pastera/Sources/Services/PasswordVaultSyncModels.swift \
  pastera/Sources/Constants.swift \
  pasteraTests/PasswordVaultLocalStorageTests.swift \
  pasteraTests/PasswordVaultStoreTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add local encrypted storage primitives"
```

### Task 3: 将 KDBXPasswordVaultStore 改为只读写本地工作副本

**Files:**
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/VaultArtifactRekeyTransaction.swift`
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`
- Modify: `pasteraTests/PasswordVaultMasterPasswordTests.swift`
- Modify: `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`

- [ ] 先把所有 `KDBXPasswordVaultStore(syncRootProvider:)` 测试夹具改为注入临时 `PasswordVaultLocalStoring`，新增测试证明：`syncRootPath` 不存在、OneDrive 未运行和云端 URL 抛错时，本地创建、解锁、快速解锁、自动化解锁、CRUD、重排、改主密码仍成功。
- [ ] 新增测试：只有本地 KDBX 已成功读取且 `KDBXReader` 返回 `wrongCredentials` 时才抛 `.wrongMasterPassword`；本地文件缺失返回 `.databaseNotConfigured`；本地签名或解析损坏返回 `.corruptedData`。
- [ ] 运行聚焦测试观察 RED，预期旧实现因 `vaultURL()` 依赖 OneDrive 而返回 `.cloudUnavailable`：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj -destination 'platform=macOS' \
  test \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests
```

- [ ] 将初始化边界改为本地存储，并保留文件协调器仅服务于本地原子读写：

```swift
final class KDBXPasswordVaultStore: PasswordVaultStore, PasswordVaultSyncAccess {
    private let localStorage: PasswordVaultLocalStoring
    private var commitObserver: (PasswordVaultCommit) -> Void = { _ in }

    init(
        localStorage: PasswordVaultLocalStoring = FilePasswordVaultLocalStorage.live(),
        unlockKeyStore: VaultUnlockKeyStoring = VaultUnlockKeyStore(),
        automationUnlockKeyStore: VaultAutomationUnlockKeyStoring = VaultAutomationUnlockKeyStore(),
        rekeyTransaction: VaultArtifactRekeyTransaction = VaultArtifactRekeyTransaction(),
        sessionNotificationCenter: NotificationCenter? = nil,
        autoLockTimeoutProvider: @escaping () -> TimeInterval = {
            VaultSessionController.resolvedTimeout(defaults: .standard)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.localStorage = localStorage
        self.unlockKeyStore = unlockKeyStore
        self.automationUnlockKeyStore = automationUnlockKeyStore
        self.rekeyTransaction = rekeyTransaction
        self.sessionNotificationCenter = sessionNotificationCenter
        self.autoLockTimeoutProvider = autoLockTimeoutProvider
        self.now = now
        state = localStorage.containsVault() ? .locked : .notConfigured
    }
}
```

- [ ] `createDatabase`、`unlock`、`unlockWithQuickKey`、`unlockForAutomation`、`save`、`changeMasterPassword`、`lock` 和 `prepareForUnlock` 全部改为本地路径；删除生产代码中的 `syncRootProvider` 和云端 `vaultURL()` 依赖。`prepareForUnlock` 可在后台预读本地加密数据，但不得访问 File Provider。
- [ ] 本地每次成功持久化后发送匿名提交事件；只有用户创建或编辑触发 `.userMutation`，迁移和同步合并分别使用 `.migration` 与 `.syncMerge`，避免远端合并再次增加待同步计数：

```swift
private func publishCommit(data: Data, origin: PasswordVaultCommitOrigin) {
    commitObserver(PasswordVaultCommit(
        origin: origin,
        encryptedDigest: PasswordVaultDigest.hex(data)
    ))
}
```

- [ ] `encryptedSnapshot()` 只读取本地加密字节并计算摘要，不要求解锁。`mergeRemoteSnapshot` 必须要求本地已解锁，使用现有 `KDBXVaultMerger` 合并后以当前本地主密码重新加密并原子写回本地。
- [ ] 远端 KDBX 与本地主密码不同时，`remoteMasterPassword == nil` 返回同步域的“需要云端主密码”结果；提供云端主密码时只在当前串行操作栈内构造 `UnlockData`，操作结束后不缓存、不记录。
- [ ] 扩充 `KDBXVaultMergeResult`，返回实际冲突副本数量而不只是 Bool；补齐文件夹 UUID、条目 UUID、相同修改时间内容冲突、历史版本和 tombstone 晚删规则测试。
- [ ] `VaultArtifactRekeyTransaction` 只管理本地主文件、本地备份和本地冲突归档，不再枚举 OneDrive 同级文件。
- [ ] 运行聚焦测试观察 GREEN，并用 `rg` 确认核心 store 不再依赖同步根：

```bash
rg -n "syncRootProvider|UserDefaultsSyncSettingsStore|cloudUnavailable" \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift
```

预期：无 `syncRootProvider`、无 `UserDefaultsSyncSettingsStore`；`.cloudUnavailable` 不出现在本地解锁与保存分支。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Services/VaultArtifactRekeyTransaction.swift \
  pasteraTests/PasswordVaultStoreTests.swift \
  pasteraTests/PasswordVaultMasterPasswordTests.swift \
  pasteraTests/VaultAutomationUnlockKeyStoreTests.swift
git commit -m "refactor(vault): make local KDBX the working copy"
```

### Task 4: 实现旧版云端工作文件到本地副本的一次性迁移

**Files:**
- Create: `pastera/Sources/Services/PasswordVaultMigrationService.swift`
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/PasswordVaultMigrationTests.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`

- [ ] 先添加迁移矩阵测试：本地已存在不迁移；旧云端可用时复制、回读摘要一致后才标记完成；云端短读、占位文件、无目录、损坏签名、写本地失败时不写完成标记、不覆盖云端、不创建空本地库；重试成功后进入 `.locked`。
- [ ] 新增 `PasswordVaultState` 恢复态测试，明确它不是密码错误：

```swift
enum PasswordVaultLocalPreparationFailure: Equatable {
    case oneDriveUnavailable
    case remoteCorrupted
    case localWriteFailed
}

enum PasswordVaultState: Equatable {
    case notConfigured
    case preparingLocalCopy
    case localCopyUnavailable(PasswordVaultLocalPreparationFailure)
    case locked
    case unlocking
    case unlocked
    case readOnlyWarning(String)
    case recoveryRequired(String)
    case failed(String)
}
```

- [ ] 运行 `PasswordVaultMigrationTests` 观察 RED，预期迁移服务尚不存在。
- [ ] 实现迁移接口：

```swift
enum PasswordVaultMigrationOutcome: Equatable {
    case notNeeded
    case migrated
    case waitingForOneDrive
    case failed(PasswordVaultLocalPreparationFailure)
}

protocol PasswordVaultMigrating {
    func migrateLegacyVaultIfNeeded() throws -> PasswordVaultMigrationOutcome
}
```

- [ ] 迁移顺序固定为：读取旧 `syncRootPath` → 定位兼容云端 KDBX → 后台协调读取完整加密字节 → 校验八字节 KDBX 签名与 SHA-256 → `localStorage.writeAtomically` → 回读本地并比较摘要 → 写入 `migrationVersion = 1`、`mode = oneDrive`、本地与云端基线。只有最后一步成功才允许环境将 store 暴露为 `.locked`。
- [ ] 云端不可用时保留旧根目录配置和云端文件；环境暴露 `.localCopyUnavailable(.oneDriveUnavailable)`，UI 后续显示“本地密码箱尚未准备好”，不得调用 `unlock`。
- [ ] 如果不存在本地 KDBX、没有旧迁移候选且未显式启用密码箱同步，保持 `.notConfigured`，创建页面默认“仅保存在本机”。
- [ ] 将迁移服务加入 Environment 初始化链，并确保迁移在密码箱串行队列执行，不阻塞 AppKit 主线程。
- [ ] 运行迁移与菜单状态测试观察 GREEN。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultMigrationService.swift \
  pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Environments/Environment.swift \
  pasteraTests/PasswordVaultMigrationTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): migrate legacy cloud vault safely"
```

### Task 5: 实现同步元数据存储与 OneDrive 加密副本适配器

**Files:**
- Create: `pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift`
- Create: `pastera/Sources/Services/PasswordVaultCloudReplica.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/PasswordVaultCloudReplicaTests.swift`
- Create: `pasteraTests/PasswordVaultSyncMetadataTests.swift`

- [ ] 先写元数据原子写入、损坏恢复、schema 版本拒绝、敏感字段扫描测试；写 OneDrive 适配器不存在、完整读取、短读、临时写入失败、替换失败、回读摘要不一致和删除失败测试。
- [ ] 运行两个新测试 suite 观察 RED。
- [ ] 实现元数据存储：

```swift
final class JSONPasswordVaultSyncMetadataStore: PasswordVaultSyncMetadataStoring {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.url = url
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> PasswordVaultSyncMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PasswordVaultSyncMetadata.defaultLocalOnly
        }
        return try decoder.decode(PasswordVaultSyncMetadata.self, from: Data(contentsOf: url))
    }

    func save(_ metadata: PasswordVaultSyncMetadata) throws {
        let data = try encoder.encode(metadata)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] 实现云端副本接口：

```swift
struct PasswordVaultCloudSnapshot: Equatable {
    let data: Data
    let digest: String
}

protocol PasswordVaultCloudReplica {
    func read(rootURL: URL) throws -> PasswordVaultCloudSnapshot?
    func writeAtomically(_ data: Data, rootURL: URL) throws -> String
    func delete(rootURL: URL) throws
}
```

- [ ] `OneDrivePasswordVaultCloudReplica` 继续使用兼容路径；读取使用 `NSFileCoordinator` 并校验文件长度与 KDBX 签名；写入使用同目录唯一临时文件，协调原子替换后重新读取目标文件并比较摘要；无论成功失败都清理自身临时文件，不清理 OneDrive 生成的冲突文件。
- [ ] 将 File Provider、权限、空间、短读和摘要错误映射为 `PasswordVaultSyncFailure`，不得映射为 `.wrongMasterPassword` 或本地 `.corruptedData`。
- [ ] `delete` 只删除云端主 KDBX，不删除本地文件、云端历史/片段数据、同步根目录或其他冲突文件；目录不可用时返回失败且不改变元数据。
- [ ] 运行新测试观察 GREEN，并检查编码后的元数据 JSON 不包含测试夹具中的标题、用户名、密码和备注。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift \
  pastera/Sources/Services/PasswordVaultCloudReplica.swift \
  pasteraTests/PasswordVaultCloudReplicaTests.swift \
  pasteraTests/PasswordVaultSyncMetadataTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add encrypted OneDrive replica storage"
```

### Task 6: 实现单边变化、断联积累和同步基线更新

**Files:**
- Create: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncModels.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Create: `pasteraTests/PasswordVaultSyncServiceTests.swift`

- [ ] 使用 fake 本地 snapshot access、fake metadata store、fake cloud replica 和 fake OneDrive process status 先写状态机测试，至少覆盖：默认 localOnly、localOnly 不访问云端、同步启用且 OneDrive 未运行、本地修改累计、只有本地变化上传、只有云端变化且已解锁合并、只有云端变化且锁定等待解锁、无变化不写、云端验证失败不清 pending。
- [ ] 运行新 suite 观察 RED。
- [ ] 实现控制接口：

```swift
protocol PasswordVaultSyncControlling: AnyObject {
    var snapshot: PasswordVaultSyncSnapshot { get }
    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID
    func removeObserver(_ identifier: UUID)
    func record(_ commit: PasswordVaultCommit)
    func synchronize(reason: SyncCoordinator.Reason)
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    func switchToLocalOnly(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    func deleteRemoteReplica(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
}
```

- [ ] `record(.userMutation)` 必须原子增加 `localRevision`；仅当 mode 为 `.oneDrive` 时增加 `pendingChangeCount` 并进入待同步状态。`.syncMerge` 与 `.migration` 只刷新本地摘要，不重复增加 pending。
- [ ] `synchronize` 在访问云端前先判断模式、OneDrive 进程、根目录存在性与可写性。未运行时设置 `.disconnected(.oneDriveNotRunning)` 并返回，不能触发 File Provider 读取。
- [ ] 单边分支按以下纯函数决策，单元测试直接覆盖全部枚举结果：

```swift
enum PasswordVaultSyncDecision: Equatable {
    case noChange
    case uploadLocal
    case applyRemote
    case mergeBoth
}

func passwordVaultSyncDecision(
    localChanged: Bool,
    remoteChanged: Bool
) -> PasswordVaultSyncDecision {
    switch (localChanged, remoteChanged) {
    case (false, false): return .noChange
    case (true, false): return .uploadLocal
    case (false, true): return .applyRemote
    case (true, true): return .mergeBoth
    }
}
```

- [ ] 上传顺序必须是 `.checking → .uploading → .verifying → .synced`；只有 `writeAtomically` 返回已回读摘要后，更新 `lastSyncedLocalRevision`、`lastSyncedLocalDigest`、`lastObservedRemoteDigest`、`lastSyncAt` 并把 pending 归零。
- [ ] 远端变化在已锁定时设置 `.waitingForUnlock`，不替换本地加密文件；解锁状态变化后由调度层自动重试。
- [ ] 公开快照与 observer 回调切回主线程；文件读写、KDBX 合并和元数据写入全部在专用串行队列。
- [ ] 运行新 suite 观察 GREEN。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultSyncService.swift \
  pastera/Sources/Services/PasswordVaultSyncModels.swift \
  pasteraTests/PasswordVaultSyncServiceTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add local-first sync state machine"
```

### Task 7: 实现双向合并、不同主密码和冲突保护

**Files:**
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTests.swift`
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`

- [ ] 先写两端变化测试：不同条目合并、同条目较新者成为当前且较旧者进入 KDBX history、同时间不同内容生成“冲突副本”、较晚 tombstone 删除、较早 tombstone 不删除较新条目、排序差异不产生冲突、锁定时不写任一端。
- [ ] 写不同主密码测试：未提供云端主密码时进入 `.failed(.remoteCredentialsRequired)`；提供正确密码后合并并以本地主密码重新加密；错误云端密码只停留在同步页面，不改变本地解锁状态、不清 pending、不记录密码。
- [ ] 运行两个 suite 观察 RED。
- [ ] 双边分支严格执行：读取并验证本地当前 snapshot → 读取并验证云端 snapshot → 解密合并 → 生成本地主密码加密结果 → 本地存储创建备份并原子替换 → 云端临时写入并原子替换 → 回读云端摘要 → 更新基线。
- [ ] 如果本地写入已成功但云端写入或验证失败，保留新的本地合并结果与 `.bak`，保持 pending 大于零；下次重试将该本地加密结果上传，不重复制造冲突副本。
- [ ] 将冲突数量累加到 metadata 和 snapshot；自动合并无冲突时保持非阻塞，不显示黄色提示；有冲突时状态为 `.conflicts(count)`，但密码箱继续可读写。
- [ ] 远端主密码必须通过方法参数在单次串行任务中使用，禁止写入对象属性、闭包缓存、UserDefaults、日志和 accessibility。
- [ ] 运行测试观察 GREEN，并使用源码扫描确认无凭据输出：

```bash
rg -n "remoteMasterPassword|masterPassword" \
  pastera/Sources/Services/PasswordVaultSyncService.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift
```

逐行确认匹配只用于参数传递和 `UnlockData` 构造，不用于持久化、日志或错误文案。
- [ ] 提交：

```bash
git add pastera/Sources/Services/PasswordVaultSyncService.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Services/PasswordVaultStore.swift \
  pasteraTests/PasswordVaultSyncServiceTests.swift \
  pasteraTests/PasswordVaultStoreTests.swift
git commit -m "feat(vault): merge concurrent OneDrive changes safely"
```

### Task 8: 接入 Environment、SyncCoordinator 和 OneDrive 生命周期

**Files:**
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pastera/Sources/Environments/AppEnvironment.swift`
- Modify: `pastera/Sources/Services/SyncCoordinator.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pasteraTests/SyncCoordinatorTests.swift`
- Modify: `pasteraTests/PasswordVaultSecuritySettingsTests.swift`

- [ ] 先写集成测试：密码箱 OneDrive mode 即使已锁定也让同步 timer 保持；本地 commit 触发去抖同步；OneDrive 终止变为断联；OneDrive 启动触发重试；两端变化且锁定等待；成功解锁触发继续合并；generic history/snippet sync 开关不改变密码箱 mode。
- [ ] 运行 `SyncCoordinatorTests` 观察 RED。
- [ ] Environment 创建一个共享 `PasswordVaultSyncService`，同时注入 `KDBXPasswordVaultStore`、`PasswordVaultUIController`、`SyncCoordinator` 和主菜单，不允许各层自行创建状态不一致的实例：

```swift
struct Environment {
    let passwordVaultStore: PasswordVaultStore
    let passwordVaultSyncService: PasswordVaultSyncControlling
    let passwordVaultUIController: PasswordVaultUIController
}
```

- [ ] `PasswordVaultUIController` 初始化时绑定 store commit observer；本地生命周期完成后只刷新本地视图，云端错误不进入 `PasswordVaultViewState.error`。
- [ ] 删除 `SyncCoordinator.performSync` 中的 `vaultStore.reloadAndMerge()`；改为独立调用 `passwordVaultSyncService.synchronize(reason:)`。ActivationSignature 使用 `vaultSyncEnabled`，不再使用“vault 已解锁”作为是否启动 timer 的条件。
- [ ] `SyncCoordinator` 观察匿名本地提交通知或直接接收 service 回调，使用现有 2 秒 debounce 触发 `.localChange`；同步 service 必须保证重复触发幂等。
- [ ] `MenuManager` 同时观察本地密码箱视图和同步快照，任一变化只刷新可见主窗口，不抢焦点、不清空正在输入的主密码或云端主密码。
- [ ] OneDrive process observation 只更新同步生命周期；mode 为 localOnly 时 OneDrive 未运行不显示红色断联。
- [ ] 运行集成测试和安全设置测试观察 GREEN。
- [ ] 提交：

```bash
git add pastera/Sources/Environments/Environment.swift \
  pastera/Sources/Environments/AppEnvironment.swift \
  pastera/Sources/Services/SyncCoordinator.swift \
  pastera/Sources/Managers/PasswordVaultUIController.swift \
  pastera/Sources/Managers/MenuManager.swift \
  pasteraTests/SyncCoordinatorTests.swift \
  pasteraTests/PasswordVaultSecuritySettingsTests.swift
git commit -m "refactor(vault): separate vault and sync lifecycles"
```

### Task 9: 实现首次保存选择、底部状态图标和主窗口内同步页面

**Files:**
- Create: `pastera/Sources/Managers/PasswordVaultSyncView.swift`
- Modify: `pastera/Sources/Managers/MainMenuFooterButtons.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`
- Modify: `pasteraTests/MainMenuEmbeddedContentTests.swift`
- Modify: `pasteraTests/MainMenuVisualPolishTests.swift`
- Modify: `pasteraTests/MainMenuPinFooterTests.swift`

- [ ] 先写主窗口交互测试，覆盖：创建默认 localOnly；检测到 OneDrive 不自动选中；未启用时图标中性且无红徽标；断联时红色断联徽标与待同步数量；冲突时黄色数量；点击底部图标进入当前窗口同步页面且 fake `openOneDrive` 调用次数为 0；页面返回后恢复密码箱内容。
- [ ] 运行四个菜单 suite 观察 RED。
- [ ] 增加独立主窗口数据源，不把同步动作塞入 `PasswordVaultStore`：

```swift
struct MainMenuPasswordVaultSyncDataSource {
    let snapshot: () -> PasswordVaultSyncSnapshot
    let candidates: () -> [SyncDefaultFolderCandidate]
    let enableOneDrive: (URL, String?, @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) -> Void
    let switchToLocalOnly: (@escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) -> Void
    let retry: () -> Void
    let startOneDrive: () -> Bool
    let deleteRemoteReplica: (@escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) -> Void
}
```

- [ ] `PasswordVaultAccessView` 在 create mode 的主密码字段前增加两个页面内单选卡片：“仅保存在本机”和“使用 OneDrive 同步”；默认始终 localOnly。创建顺序固定为先创建本地 KDBX，再按用户选择进入同步页启用 OneDrive，云端失败不回滚本地创建。
- [ ] 在 `MainMenuPanelController` 增加密码箱内部页面状态：

```swift
private enum PasswordVaultPage: Equatable {
    case vault
    case sync
    case remoteCredentials
    case conflictSummary
    case confirmRemoteDeletion
    case localCopyRecovery
}
```

- [ ] `openOneDriveFromToolbar()` 只设置 `passwordVaultPage = .sync`、`selectedMode = .passwordVault` 并 `reloadContentKeepingTopLeft()`；删除该方法中的直接 `openOneDrive()` 调用。
- [ ] `PasswordVaultSyncView` 以当前窗口行内容回答四件事：本地副本是否安全、OneDrive 是否连接、待同步数量、当前可执行动作。展示 localOnly/OneDrive 模式、候选 OneDrive 目录、最近同步时间、同步步骤、错误原因和上下文按钮。
- [ ] 首次启用检测到多个 OneDrive 根目录时，使用当前页面内单选列表；不得调用 `NSOpenPanel`。无候选时保留 localOnly，并显示安装/登录说明。
- [ ] 底部状态 presentation 由 `PasswordVaultSyncSnapshot` 与 process status 共同计算：disabled 为中性；synced 为蓝色；syncing 为蓝色进度；disconnected 为红色断联徽标；conflicts 为黄色数量。徽标必须有形状和文字/辅助标签，不能只靠颜色。
- [ ] 使用静态 badge layer 或 badge subview；开启“减少动态效果”时不旋转图标，只用静态进度符号和“同步中”文字。
- [ ] accessibility label 示例必须包含语义而不含秘密：`OneDrive 已断开，3 项更改等待同步`、`OneDrive 同步未开启`、`OneDrive 有 2 个冲突副本`。
- [ ] 运行菜单测试观察 GREEN，手动检查 480pt、默认宽度和窄窗口下文字不截断、按钮不越界、键盘 Tab/Return/Escape 顺序正确。
- [ ] 提交：

```bash
git add pastera/Sources/Managers/PasswordVaultSyncView.swift \
  pastera/Sources/Managers/MainMenuFooterButtons.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Sources/Managers/MenuManager.swift \
  pasteraTests/PasswordVaultMenuTests.swift \
  pasteraTests/MainMenuEmbeddedContentTests.swift \
  pasteraTests/MainMenuVisualPolishTests.swift \
  pasteraTests/MainMenuPinFooterTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add inline OneDrive sync experience"
```

### Task 10: 完成恢复、停止同步、删除副本和冲突结果页面

**Files:**
- Modify: `pastera/Sources/Managers/PasswordVaultSyncView.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`
- Modify: `pasteraTests/PasswordVaultSyncServiceTests.swift`

- [ ] 先写恢复与危险操作测试：本地副本未准备好时不显示密码字段；“启动 OneDrive”才调用 open；“重试”保持当前窗口；“继续仅本机创建”显示数据分支警告；停止同步保留两端；删除云端需页面内二次确认；删除失败模式与数据不变；冲突页面可返回密码箱。
- [ ] 写远端不同主密码页面测试：安全字段只存在于 `.remoteCredentials` 页面，错误后仍在同步页面，离开页面立即清空；不得复用本地主密码字段错误 label。
- [ ] 运行两个 suite 观察 RED。
- [ ] 本地副本未准备好时用 `.localCopyRecovery` 替代 unlock 表单，主操作顺序为“启动 OneDrive / 重试”，次操作为“继续仅本机创建新密码箱”；进入创建前先显示当前窗口内的数据分支警告与返回入口。
- [ ] `switchToLocalOnly` 只把 mode 改为 localOnly、停止观察/写云端并清除当前红色断联展示；保留本地 KDBX、云端 KDBX和最后基线，便于将来重启同步时正确判断两端变化。
- [ ] `.confirmRemoteDeletion` 页面明确写出“本地密码箱会保留，OneDrive 副本将删除”；取消只返回同步页；确认成功后切 localOnly 并清 remote digest，失败保持 mode、云端基线和页面错误。
- [ ] `.remoteCredentials` 只在检测到远端不同主密码时展示；提交到单次合并调用后立即清空 secure field，成功进入冲突结果或同步页，失败显示“云端密码箱主密码不正确”而非“本地主密码不正确”。
- [ ] `.conflictSummary` 展示自动合并数量、冲突副本数量和剩余 pending；冲突不锁定密码箱，不强迫立即处理。“查看冲突副本”返回密码箱并应用冲突筛选，“返回密码箱”清除页面提示但不删除冲突条目。
- [ ] 运行测试观察 GREEN，并以 VoiceOver 或 Accessibility Inspector 检查页面标题、模式选择、返回、主要动作、危险动作、badge 和 secure field 标签。
- [ ] 提交：

```bash
git add pastera/Sources/Managers/PasswordVaultSyncView.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Sources/Managers/MenuManager.swift \
  pastera/Sources/Services/PasswordVaultSyncService.swift \
  pasteraTests/PasswordVaultMenuTests.swift \
  pasteraTests/PasswordVaultSyncServiceTests.swift
git commit -m "feat(vault): add inline sync recovery controls"
```

### Task 11: 对齐同步设置、产品文档和完整验证

**Files:**
- Modify: `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`
- Modify: `pasteraTests/SyncPreferenceTopSectionTests.swift`
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift`
- Modify: `docs/sync/ONEDRIVE_SYNC.md`
- Modify: `docs/verification/VERIFICATION.md`
- Modify: `docs/superpowers/plans/2026-07-22-password-vault-local-first-onedrive-sync.md`

- [x] 先写设置页测试：历史/片段 OneDrive 根目录可复用，但其开关不会自动启用密码箱；设置页只显示密码箱同步摘要与“在主窗口管理”入口，不复制另一套控制逻辑，不用 popover 表示密码箱错误。
- [x] 运行设置页测试观察 RED。
- [x] 在 `CPYSyncPreferenceViewController` 增加密码箱同步摘要行：模式、最近同步/待同步状态、“在主窗口管理”。点击入口关闭设置页并打开主菜单密码箱同步页；具体启停、恢复、云端主密码和删除仍只在主窗口完成。
- [x] 更新 `docs/sync/ONEDRIVE_SYNC.md`，补充密码箱本地工作路径、兼容云端路径、独立 mode、摘要基线、断联语义、条目级合并、停止同步和删除边界。
- [x] 更新 `docs/verification/VERIFICATION.md`，加入无 OneDrive、断联、恢复、冲突、迁移、本地损坏、云端损坏和辅助功能手工矩阵。
- [x] 运行所有聚焦 suite：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test \
  -only-testing:pasteraTests/PasswordVaultLocalStorageTests \
  -only-testing:pasteraTests/PasswordVaultMigrationTests \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaTests \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests \
  -only-testing:pasteraTests/SyncCoordinatorTests \
  -only-testing:pasteraTests/SyncPreferenceTopSectionTests \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
  -only-testing:pasteraTests/MainMenuVisualPolishTests \
  -only-testing:pasteraTests/MainMenuVaultSyncFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveInstallationFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveStatusAssetTests \
  -only-testing:pasteraTests/MainMenuFooterButtonActionTests \
  -only-testing:pasteraTests/OneDriveProcessStatusServiceTests
```

- [x] 运行仓库默认 clean full test：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  clean test
```

- [x] 运行 Release 构建，捕获 Debug 测试未覆盖的条件编译和链接错误：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -project pastera.xcodeproj \
  -target pastera \
  -configuration Release \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  SYMROOT="$PWD/.build/release-validation/Products" \
  OBJROOT="$PWD/.build/release-validation/Intermediates.noindex" \
  build
```

- [x] 使用临时本地目录和独立 OneDrive 测试子目录验证真实生命周期，禁止覆盖用户现有 `PasteraVault.kdbx`：
  - localOnly 创建、锁定、重启、解锁和完整 CRUD。
  - OneDrive 未运行时继续 CRUD，footer 出现红色断联徽标，pending 增加。
  - 启动 OneDrive 后只有本地变化自动上传并回读摘要。
  - 在独立测试副本制造远端修改，验证云端单边更新与双边冲突。
  - 锁定时制造双边变化，确认等待解锁且两端摘要均未变化。
  - 停止同步后两端文件仍存在；删除云端只删除独立测试副本。
- [x] 安装并启动最新 Debug build：

```bash
./script/install_local.sh --verify
pgrep -fl '/Applications/Pastera.app/Contents/MacOS/Pastera'
codesign --verify --deep --strict /Applications/Pastera.app
```

- [x] 执行源码与产物安全扫描：

```bash
git diff --check
rg -n "The configured OneDrive folder is unavailable|File Provider|error -17" \
  pastera/Sources pasteraTests
rg -n "password|username|note|website" \
  pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift \
  pastera/Sources/Services/PasswordVaultSyncService.swift
```

第一条用户可见英文错误应无生产代码匹配；后一个扫描的每个匹配都必须是明确的凭据边界测试或一次性内存参数，不得出现在元数据字段、日志和 accessibility。
- [x] 在本计划末尾填写 Delivery Record：实际文件、提交、RED/GREEN 证据、完整测试结果、Release 结果、真实断联验证、安装 readback、偏差和残余风险。
- [x] 提交：

```bash
git add pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift \
  pasteraTests/SyncPreferenceTopSectionTests.swift \
  pasteraTests/PreferencePaneAlignmentTests.swift \
  docs/sync/ONEDRIVE_SYNC.md \
  docs/verification/VERIFICATION.md \
  docs/superpowers/plans/2026-07-22-password-vault-local-first-onedrive-sync.md
git commit -m "docs(vault): verify local-first OneDrive lifecycle"
```

### Task 12: 简化 OneDrive 入口并阻止共享资料库误选（2026-08-04 修订）

本任务覆盖 Task 9/10/11 中已经交付、但被本次产品确认取消的通用同步页面、停止同步、删除云端副本和“在主窗口管理”交互；不回退本地优先、自动同步、合并、冲突与迁移能力。

**Files:**
- Modify: `pastera/Sources/Services/SyncCoordinator.swift`
- Modify: `pastera/Sources/Services/PasswordVaultSyncService.swift`
- Modify: `pastera/Sources/Services/LocalOnlyPasswordVaultSyncController.swift`
- Modify: `pastera/Sources/Managers/MainMenuFooterButtons.swift`
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultSyncView.swift`
- Modify: `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: relevant tests and this specification/plan

- [x] 先修改 resolver 测试观察 RED：精确 `OneDrive` 仍可自动选；单个或多个 `OneDrive-*` 返回需选择结果；中文/英文共享资料库与 `CloudTemp` 不进入候选；设置页面对需选择结果不保存排序后的第一个目录。
- [x] 实现账户选择规则。已保存根目录失效或未通过设置页写入、回读、删除探针时不创建同步目录、不执行新云端写入，保留所有数据并提示重新选择。
- [x] 先修改 footer/menu 测试观察 RED：点击图标在 OneDrive 已运行和未运行时均调用 `openOneDrive()`，不切换密码箱内部页面；未安装时只呈现状态且不打开下载页；图标同时表达客户端运行状态与密码箱同步 badge。
- [x] 删除通用 `PasswordVaultSyncView`、`.sync`、`.confirmRemoteDeletion` 和导航链路；保留 local-copy recovery、remote credentials、conflict summary 三类上下文页面。
- [x] 删除 `switchToLocalOnly`、`deleteRemoteReplica` 的用户动作、data source、service API、实现和对应测试；保留 `PasswordVaultSyncMode.localOnly` 作为首次默认模式和单向启用前状态。
- [x] 设置页删除“在主窗口管理”，localOnly 且根目录有效时显示单向启用；保留账户/根目录、状态摘要与“立即同步”。首次创建选择 OneDrive 时先创建本地 KDBX，再尝试使用已经明确选择且可写的设置根目录启用；失败不回滚本地密码箱。
- [x] 清理已无调用方的停止/删除文案与 UI 测试，运行 `git diff --check`、聚焦 suite、单 worker 完整测试与本地安装。

---

## Acceptance Mapping

| 已确认验收项 | 实施任务 | 自动化/手工证据 |
| --- | --- | --- |
| 不使用 OneDrive 仍可完整使用 | Task 2、3、9 | LocalStorage、Store、Menu tests；localOnly 手工流程 |
| 创建默认仅本机且不自动启用 | Task 8、9 | Menu 与 SyncCoordinator tests |
| OneDrive 断联不阻塞本地操作 | Task 3、6、8、9 | Store、SyncService、footer tests；停止进程验证 |
| 红色断联徽标且不能只靠颜色 | Task 9 | Visual、footer、accessibility tests |
| 点击图标启动或激活 OneDrive 且不导航 | Task 12 | process service fake 与 menu/page state tests |
| 断联期间完整新增、修改、删除 | Task 3、6 | Store 与 pending revision tests |
| 单边变化自动同步 | Task 6 | SyncService decision tests |
| 双边变化条目级合并 | Task 7 | KDBX merge 与 service tests |
| 同条目冲突保留历史或副本 | Task 7、10 | conflict count、history、UI tests |
| 锁定时等待解锁且不覆盖 | Task 6、7、8 | digest 不变与 retry tests |
| 云端验证成功前不清 pending | Task 5、6、7 | write/verify failure tests |
| 工作/共享候选不被静默选中 | Task 12 | resolver 与 settings tests |
| UI 不提供停止同步或删除云端副本 | Task 12 | menu、settings 与 service contract tests |
| 旧版云端工作文件安全迁移 | Task 4 | migration matrix tests |
| 新设备本地未准备好不显示密码错误 | Task 4、10 | recovery page tests |
| 云端错误不进入密码字段 | Task 3、8、9、10 | local wrong-password boundary tests |
| 同步元数据不含秘密 | Task 2、5、7、11 | JSON allowlist 与源码扫描 |
| Debug、Release、安装和真实 OneDrive 验证 | Task 11 | 命令输出、签名、进程和独立测试副本 readback |

## Risks and Rollback

- **迁移中断：** 完成标记只在本地回读摘要一致后写入；重启继续迁移，旧云端文件不删除。
- **元数据晚于本地文件落盘：** 启动时同时比较本地加密摘要和 revision；摘要变化会恢复 pending，不依赖单一计数。
- **OneDrive File Provider 阻塞：** OneDrive 未运行时不访问云端路径；所有云端 I/O 在 utility 串行队列；主窗口只观察快照。
- **不同主密码：** 云端主密码只做一次性内存参数；失败不改变本地库、同步基线和 pending。
- **双边写入部分成功：** 本地先生成备份并原子落盘；云端失败保留本地合并结果和 pending，下次按本地变化重试。
- **现有未提交实现冲突：** 隔离 worktree 实施；合并前逐文件比较当前用户工作区，不使用 reset 或 checkout 覆盖。
- **回滚：** 保留本地 KDBX 与 `.bak`。产品 UI 不提供切回 localOnly 或删除云端；需要工程恢复时先保存两端副本并禁止通过回滚删除任何密码箱。

## Delivery Record

- **Plan Status:** implemented-verified
- **Spec:** `docs/superpowers/specs/2026-07-22-password-vault-local-first-onedrive-sync-design.md`
- **Implementation Branch:** `codex/password-vault-local-first`
- **Worktree:** `/Users/feeyo/workspace/github.com/pastera-app/Pastera-vault-local-first`
- **Implementation Commits:** `52b7f61..1a090e3` 完成设计、计划和 Task 1 至 Task 11；本次 follow-up 修复真实 OneDrive File Provider 占位文件恢复时的误导提示。
- **RED Evidence:** 设置页测试首次编译失败，明确缺少 `passwordVaultSyncSnapshotProvider` 与 `managePasswordVaultSync` 注入点；实现后转绿。真实恢复 follow-up 新增 “running OneDrive recovery explains cloud download without offering to start it again” 测试，首次运行准确失败于“仍显示启动 OneDrive”和“仍提示 OneDrive 断联”两项。
- **GREEN Evidence:** 设置/对齐 15 项（2 suites）、本地优先核心 288 项（15 suites）与 footer 27 项（6 suites）通过，共 315 项/21 suites；五语偏好目录 15 项通过；Agent 超时项串行 57 项通过；单 worker `clean test` 在最终兜底文案调整前为 1122 项/101 suites 全通过；调整后直接回归 70 项/4 suites 通过并重新构建安装。真实恢复 follow-up 的密码箱菜单 suite 为 41/41 通过，新增场景验证 OneDrive 已运行时隐藏“启动 OneDrive”，并改为说明云端密码箱仍在下载。
- **Release Evidence:** 直接用 scheme 的 Release build 会错误包含 `pasteraTests` 并触发 `@testable`/testability 基线问题；按仓库安装与打包脚本的真实 target 边界设置独立 `SYMROOT`/`OBJROOT` 后 `** BUILD SUCCEEDED **`，主程序为 `x86_64 arm64`，最低系统版本 `15.0`。该门禁在最终兜底文案调整前执行；调整后 Debug 目标编译、70 项直接回归与安装签名回读通过。
- **Runtime Evidence:** 隔离临时目录测试覆盖 localOnly CRUD、断联 pending、重连、单边更新、冲突、锁定等待、迁移、本地/远端损坏、停止同步与删除副本。真实 follow-up 中 OneDrive 主进程 PID `89274` 与 File Provider 均已运行；远端 `PasteraVault.kdbx` 初始为 `dataless` 占位文件，Pastera 日志在 13:58 记录系统读取错误 60（超时）。文件完成下载后重启 Pastera，Application Support 本地 KDBX 与远端 KDBX 的 SHA-256 均为 `a26f69a3622511e7c581d52c05fbbace12d746cab202f69f757b4616d3002854`，元数据回读为 `migrationVersion=1`、`mode=oneDrive`、`pendingChangeCount=0`。`./script/install_local.sh --verify` 已重新安装 3.0.1 (301)，ad-hoc 深度签名通过，最终进程 PID `99552` 从 `/Applications/Pastera.app` 运行。
- **Plan Deviations:** 默认并行 full test 被既有 AppKit 颜色空间日志放大并导致三个无关超时项；对应 suite 独立通过后，以单 worker full test 作为稳定门禁。菜单栏 `LSUIElement` 对 Computer Use 不暴露标准窗口，无法完成无密码的真实点击回放；UI 视觉与入口顺序由截图测试、AX 文本和按钮行为测试验证。Release 命令改用仓库脚本一致的 app target 与显式输出目录，避免 scheme 编译测试 bundle。真实 File Provider 冒烟发现“已安装”和“已运行”在恢复页被混为一谈；follow-up 只调整恢复文案与动作展示，不改变显式重试和非破坏性迁移语义。
- **Residual Risks:** OneDrive 已运行但云端占位文件尚未下载完成时，恢复仍依赖用户在下载完成后显式重试；当前界面会准确说明该状态且不再重复提供“启动 OneDrive”。未执行删除远端副本等破坏性真实目录验证。VoiceOver 人工听读未完成，但 footer、摘要、动作与安全输入均有可访问性断言。

### 2026-08-04 Task 12 Follow-up

- **Actual Implementation:** 在 `codex/onedrive-status-simplification`、`/Users/feeyo/workspace/github.com/pastera-app/Pastera/.worktrees/onedrive-status-simplification` 完成。主界面 OneDrive 图标现在按客户端进程状态着色，点击只启动或激活 OneDrive，不再进入通用同步页；保留密码箱同步 badge、自动同步、合并、冲突与三类上下文恢复页。设置页改为仅从 localOnly 单向启用，并在保存新根目录前执行写入、回读、删除探针。
- **Root Selection:** 仅精确名称 `OneDrive` 可自动选择；任何 `OneDrive-*` 账户均要求明确选择。英文 `Shared Libraries`、中文 `共享的库`/`共享库` 和 `CloudTemp` 根目录会被候选发现、已保存根目录校验与新写入路径共同拒绝。因此用户诊断中的 `OneDrive-共享的库-oneDrive` 不再能成为密码箱云端写入根目录。
- **Removed Surface:** 删除通用 `PasswordVaultSyncView` 类型、`.sync`/`.confirmRemoteDeletion` 导航、设置页“在主窗口管理”、停止同步、删除云端副本、确认页及 `switchToLocalOnly`、`deleteRemoteReplica`、cloud replica delete 契约和实现；`PasswordVaultSyncMode.localOnly` 仍作为首次默认和单向启用前状态存在。
- **Implementation Commits:** 无；本次未获授权创建提交或推送。
- **RED Evidence:** resolver 测试先证明单个命名工作账户会被静默选中，且本地化共享资料库会进入候选；footer/menu 测试先证明图标动作没有满足“运行和未运行均 open、且不导航”；设置页探针测试先以缺少注入点编译失败。对应生产实现完成后这些断言转绿。
- **GREEN Evidence:** OneDrive/menu/settings/service/cloud replica 聚焦回归 150 项（9 suites）通过；完整门禁首次发现新增设置文案缺少完整语言覆盖，同时 OCR 搜索用例出现一次共享状态波动。补齐五语文案后，PreferenceSearch 与 OCR 两个 suite 串行 29 项通过；最终使用全新 DerivedData、单 worker 的 `clean test` 为 1150 项（101 suites）全通过。`git diff --check` 与 `jq empty pastera/Resources/Localizable.xcstrings` 通过。
- **Installation Evidence:** `./script/install_local.sh` 构建、ad-hoc 签名并替换 `/Applications/Pastera.app`；回读版本为 3.0.1 (301)，`codesign --verify --deep --strict` 通过，进程 PID `60049` 从 `/Applications/Pastera.app/Contents/MacOS/Pastera` 运行。
- **Plan Deviations:** 真实问题机器不可从当前环境远程操作，本次以用户提供的 defaults/path 证据、跨语言 resolver 测试和本机安装回读闭环。shell 输出里的 `\u5171...` 可能只是 defaults 对 Unicode 的转义显示，不能单独证明路径不存在；解码后的目录名明确是共享资料库，旧选择规则仍不应把它当个人或工作账户根目录。
- **Remaining Risks:** 已保存的共享资料库路径会安全失败并阻止新云端写入，但该 Mac 仍需用户在设置页重新明确选择自己的 OneDrive 账户目录。当前环境未对问题 Mac 做真实 File Provider readback，也未执行任何删除云端数据的破坏性验证。
