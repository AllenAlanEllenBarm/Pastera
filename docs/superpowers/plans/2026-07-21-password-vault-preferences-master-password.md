# Password Vault Preferences and Master Password Change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS“偏好设置”中增加完整的“密码箱”安全设置页，提供自动锁定、快速解锁和“重置主密码”能力；其中“重置”严格表示验证当前主密码后更换新主密码、保留全部数据，并持续明确提醒主密码忘记后无法通过其他方式找回。

**Architecture:** 偏好页只通过现有 `PasswordVaultUIController` 读取状态和发起操作，不直接访问 KDBX 文件或 Keychain。`PasswordVaultUIController` 继续把所有存储与 Agent 操作串行到现有 `VaultAgentSerialExecutor`；`KDBXPasswordVaultStore` 增加可回滚的多文件换密事务，在提交前合并磁盘最新版本、重新加密主库/备份/受管冲突归档并用新密码逐一回读。偏好页复用原生 AppKit 组件和现有偏好设置外壳，主密码修改使用原生 Sheet。

**Tech Stack:** Swift 6、AppKit、Swift Testing、KDBXKit、Security/Keychain、Xcode 26.5、macOS 13+

## Global Constraints

- “重置主密码”不是找回、绕过或清空密码箱；只允许“当前主密码验证成功 → 设置新主密码 → 保留全部文件夹、条目和历史”。
- 首次设置和修改主密码都必须常驻展示：`主密码用于加密密码箱。忘记后无法通过其他方式找回。`
- 当前主密码即使在密码箱已解锁时也必须重新验证；不能用内存中的已解锁状态替代验证。
- 主密码、确认密码、派生密钥和明文条目不得写入日志、测试快照、仓库文档、崩溃附加信息或聊天记录；Sheet 关闭、取消和成功后清空全部字段。
- 换密必须覆盖 Pastera 管理的全部 KDBX 工件：活动主库、`PasteraVault.kdbx.bak`、同目录冲突副本和 `conflicts/resolved` 下的归档；成功后旧密码不能再打开其中任何一个。
- 换密提交前必须合并 OneDrive/磁盘最新主库与未归档冲突副本；暂存后若源文件修订再次变化，必须中止并保留旧文件。
- 文件换密成功后，快速解锁和 Agent 自动解锁的 Keychain 原始密钥必须刷新；Keychain 刷新失败不回滚已成功的 KDBX 换密，但必须删除失效密钥、关闭对应能力并向用户显示警告。
- 所有换密、快速解锁和 Agent 访问继续使用同一个串行执行器，避免并发读取旧/新密钥或中间状态。
- 使用系统字体、SF Symbols、语义颜色、系统蓝强调色和现有 Pastera 设计 token；不引入渐变、装饰性光效、第三方 UI 依赖或自定义导航体系。
- 布局采用 `DESIGN_VARIANCE 4`、`MOTION_INTENSITY 2`、`VISUAL_DENSITY 4`：宽窗口下两组卡片权重约 `1.18 : 0.82`，窄窗口堆叠；内容不足一屏时仅“密码箱”页垂直居中，内容超高时恢复顶部固定和滚动。
- 键盘顺序、Return/Escape、可见焦点、VoiceOver 标签、Reduce Motion、深色模式和最小窗口尺寸必须可用。
- 只修改本计划列出的密码箱/偏好设置链路；保留当前未跟踪的 `.codex/config.toml`、`.superpowers/` 和任何用户无关改动。

---

## Business Scope / Out of Scope

### In Scope

- 偏好设置侧栏在“快捷键”和“忽略应用”之间增加“密码箱”，使用 SF Symbol `lock.shield`，并支持偏好搜索跳转。
- 新页面展示密码箱状态、自动锁定时间、快速解锁开关和修改主密码入口。
- 自动锁定提供现有受支持选项：1、5、15、30 分钟；修改后持久化并立即重排当前已解锁会话的锁定计时。
- 快速解锁开关控制用户意图和 Keychain 密钥；关闭后，后续主密码解锁不得悄悄重新启用。
- 原生“修改主密码”Sheet：当前主密码、新主密码、确认新主密码、三个显示/隐藏按钮、常驻不可找回警告、字段级错误、busy 状态和成功提示。
- not configured、locked、unlocked、busy、read-only/file failure 五类页面状态和相应操作限制。
- KDBX 多文件换密事务、OneDrive 最新版本合并、Keychain 凭据刷新、Agent 串行一致性和失败回滚。
- 更新首次创建密码箱的不可找回文案，确保创建与修改两条路径一致。

### Out of Scope

- 忘记主密码后的恢复、绕过、管理员重置、安全问题、恢复码或云端托管密钥。
- 删除密码箱后重新创建、清空数据、改变 KDBX 格式或替换 KDBX 密钥派生算法。
- 修改密码条目编辑器、文件夹交互、搜索、复制/粘贴行为或 Windows 客户端。
- 新增“永不锁定”、自定义分钟数、密码强度规则或强制复杂度策略。
- 修改 OneDrive 同步协议、Agent 授权期限模型或新增遥测上传。

## Acceptance Mapping

| 验收项 | 自动化证据 | 人工证据 |
| --- | --- | --- |
| 侧栏和页面信息架构正确 | catalog/search/factory 测试断言 `.passwordVault` 顺序、标题、图标和三个锚点 | 偏好设置中确认“密码箱”位于“快捷键”与“忽略应用”之间 |
| 页面不再集中在顶部 | 布局测试断言空余高度时上下留白近似、窄窗口改为堆叠、超高内容回到顶部滚动 | 默认 760×600、最小 680×480 和加宽窗口观察整体平衡 |
| 首次设置和修改均提示不可找回 | 本地化与主菜单/Sheet 测试断言完整文案 | 两条路径均可在输入前直接看到“无法通过其他方式找回” |
| 自动锁定即时生效 | controller/store 测试断言只接受 60/300/900/1800 秒、写入 defaults 并重排计时 | 修改时间后保持解锁，确认按新时间自动锁定 |
| 快速解锁开关可靠 | 测试覆盖启用、关闭、locked 启用失败，以及关闭后再次主密码解锁不写回 Keychain | 关闭后锁定，确认不再出现/自动尝试快速解锁；重新启用后恢复 |
| 当前密码错误不改文件 | 换密测试断言 `.wrongMasterPassword`、所有字节/修订不变、旧密码仍可用 | Sheet 只清空当前密码、保留新密码与确认并重新聚焦 |
| 换密成功且保留全部数据 | 测试用新密码读取主库、备份、冲突副本/归档和条目历史，旧密码全部失败 | 使用临时测试密码箱修改后检查文件夹与条目无变化 |
| 任一步骤失败可回滚 | 故障注入覆盖暂存、回读、源修订检查、逐文件替换；断言旧文件完整且无残留临时文件 | 模拟只读/同步冲突时显示恢复建议，不关闭 Sheet 冒充成功 |
| OneDrive 与 Agent 边界稳定 | 外部版本合并测试、串行执行测试、自动解锁密钥刷新测试 | 修改后 Agent 集成仍可授权；Keychain 失败时页面显示需重新启用的警告 |
| Sheet 键盘和辅助功能完整 | UI 测试覆盖 Tab、Return、Escape、显示切换、busy、VoiceOver 标签、深色/窄宽度 | 全键盘完成一次失败和一次成功流程，焦点与错误位置清晰 |
| 无回归并可运行 | 聚焦测试、默认 `clean test`、Release build、JSON/whitespace 检查通过 | 本地安装最新 `Pastera.app` 后完成状态矩阵验收 |

## File Map

- Modify: `pastera/Sources/Services/PasswordVaultStore.swift` — 增加安全设置状态、换密结果/警告和 store 协议方法。
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift` — 合并最新内容、生成新密钥材料、刷新会话与 Keychain 能力。
- Create: `pastera/Sources/Services/VaultArtifactRekeyTransaction.swift` — 枚举受管工件、暂存/回读/修订复核、逐文件提交和失败回滚。
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift` — defaults 意图、自动锁定/快速解锁/换密 API、状态观察者和串行调度。
- Modify: `pastera/Sources/Environments/Environment.swift` — 让默认 KDBX store 与 UI controller 使用同一 `UserDefaults` 和自动锁定时间提供器。
- Modify: `pastera/Sources/Constants.swift` — 新增快速解锁意图 key。
- Modify: `pastera/Sources/Utility/CPYUtilities.swift` — 注册快速解锁默认值，保留升级后现有行为。
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift` — 新 pane、侧栏元数据和搜索锚点。
- Modify: `pastera/Sources/Preferences/PasteraPreferenceComponents.swift` — 为自适应网格增加可选列权重，默认行为保持 1:1。
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift` — 注册原生页面，并仅对密码箱页启用空间充足时的垂直居中。
- Create: `pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift` — 安全设置页面、状态映射和 CTA。
- Create: `pastera/Sources/Preferences/Panels/PasswordVaultMasterPasswordSheetController.swift` — 三字段原生 Sheet 和字段级交互。
- Modify: `pastera/Sources/Managers/MainMenuPanelController.swift` — 统一首次设置的不可找回文案，仅做文案/断言所需调整。
- Modify: `pastera/Resources/Localizable.xcstrings` — 页面、Sheet、错误、警告和成功状态的中英文文案。
- Modify: `pastera.xcodeproj/project.pbxproj` — 显式加入三个新 Swift 源文件和两个新测试文件。
- Create: `pasteraTests/PasswordVaultMasterPasswordTests.swift` — 多工件换密、外部合并、Keychain 警告和回滚。
- Create: `pasteraTests/PasswordVaultSecuritySettingsTests.swift` — defaults、自动锁定、快速解锁、观察者和 Agent 串行边界。
- Modify: `pasteraTests/PreferenceSearchTests.swift` — 固定 pane/catalog 顺序和搜索所有权。
- Modify: `pasteraTests/PreferenceWindowShellTests.swift` — 侧栏顺序、图标、factory/cache 和垂直定位。
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift` — 新页面宽窄布局、锚点和 bounds。
- Modify: `pasteraTests/KeyboardAccessibilityTests.swift` — Sheet 键盘、焦点、深色和可访问标签。
- Modify: `pasteraTests/PasswordVaultMenuTests.swift` — 首次设置文案包含不可通过其他方式找回。

### Task 1: 用失败测试锁定多工件换密事务

**Interfaces:**

- Produces in `PasswordVaultStore.swift`:

```swift
enum PasswordVaultMasterPasswordChangeWarning: String, Hashable {
    case quickUnlockDisabled
    case automationUnlockDisabled
    case credentialCleanupFailed
    case conflictArchivePending
}

struct PasswordVaultMasterPasswordChangeResult: Equatable {
    let warnings: [PasswordVaultMasterPasswordChangeWarning]
}

protocol PasswordVaultStore {
    func changeMasterPassword(
        currentPassword: String,
        newPassword: String,
        keepQuickUnlockEnabled: Bool
    ) throws -> PasswordVaultMasterPasswordChangeResult
}
```

同时给 `PasswordVaultError` 增加 `case invalidAutoLockInterval`，避免把不支持的安全设置值误报为密码错误；协议默认实现抛 `.unsupportedFormat`，让不支持主密码的 legacy `KeychainPasswordVaultStore` 和测试 stub 保持源码兼容。

- Consumes: `KDBXReader.parse`、`KDBXWriter.write`、`KDBXVaultMerger`、`VaultFileCoordinator.vaultURL(for:)`。
- Produces: `VaultArtifactRekeyTransaction`，其测试接缝可在 `.stageWrite`、`.stageReadback`、`.revisionCheck`、`.replace` 注入一次失败。

- [ ] **Step 1: 创建失败测试**

在 `PasswordVaultMasterPasswordTests.swift` 建立临时同步根、内存 quick/automation key store 和故障注入 transaction，覆盖：

1. 当前密码错误时主库、`.bak`、同目录 conflict、`conflicts/resolved` 归档字节完全不变。
2. 新密码为空返回 `.invalidPassword`，不创建暂存文件。
3. 成功时主库保留内存内容、磁盘外部新增内容和 conflict 内容；每个工件可用新密码读取、旧密码均失败。
4. `.stageWrite`、`.stageReadback`、`.revisionCheck` 和第 N 个 `.replace` 分别失败时，所有原文件仍由旧密码打开，新密码不能打开，目录无 `.pastera-rekey-*` 残留。
5. 暂存完成后外部改写任一源文件时返回 `.externalConflict`，不覆盖外部版本。
6. 调用前 locked 的 store 成功后仍 locked；调用前 unlocked/read-only 的 store 才保留可读会话。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PasswordVaultMasterPasswordTests
```

Expected: FAIL；协议没有换密方法，且当前 `VaultFileCoordinator.write` 只能单文件写入并会覆盖 `.bak`。

- [ ] **Step 3: 实现文件事务最小骨架**

在 `VaultArtifactRekeyTransaction.swift`：

- 枚举活动主库、`main.appendingPathExtension("bak")`、主库目录下非隐藏 `.kdbx` 冲突副本、`conflicts/resolved` 下递归 `.kdbx` 文件。
- 记录每个源文件的 SHA-256 修订；用同目录隐藏临时文件暂存，写完后从磁盘回读，不把仅在内存中的 `Data` 当作验证证据。
- 接收验证闭包，要求调用方用新 `UnlockData` 解析每个暂存文件。
- 提交前重新计算全部源修订；任一变化则清理暂存并抛 `.externalConflict`。
- 提交时先把原文件移动到唯一 rollback 路径，再把暂存文件移到正式路径；中途失败按逆序恢复，最后清理所有暂存/rollback 文件。
- 不调用普通 `VaultFileCoordinator.write`，避免换密过程自动覆盖受管 `.bak`。

- [ ] **Step 4: 实现 KDBX 换密**

在 `KDBXPasswordVaultStore.changeMasterPassword`：

1. 从正式主库用 `currentPassword` 新建的 `UnlockData` 解析，确保已解锁状态也重新验证当前密码。
2. 将当前内存 content、最新磁盘主库和未归档 conflict 依次交给 `KDBXVaultMerger`；归档和 `.bak` 只重新加密，不重新并入活动库。
3. 为新密码创建 `UnlockData`，编码所有受管工件；让 transaction 从暂存路径逐一用新密钥回读验证后再提交。
4. 先刷新需要保留的 quick/automation raw key，再恢复调用前的逻辑状态：调用前是 locked 则清空临时 `content`/`unlockData` 并继续 locked；调用前 readable 才保留新 content/new unlock data 并 `sessionController.touch()`。失败时保持调用前的内存状态和旧密钥。
5. 成功提交后归档已合并 conflict；归档移动失败不回滚安全上已完成的换密，返回 `.conflictArchivePending` 并保留可恢复文件。

- [ ] **Step 5: 运行聚焦测试**

运行 Step 2 命令。Expected: PASS；同时运行：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PasswordVaultStoreTests
```

Expected: 现有 KDBX 生命周期、并发 merge、quick unlock 和 automation unlock 测试继续 PASS。

- [ ] **Step 6: 提交本任务**

```bash
git add pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Services/VaultArtifactRekeyTransaction.swift \
  pasteraTests/PasswordVaultMasterPasswordTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add transactional master password change"
```

### Task 2: 统一安全设置状态、快速解锁意图和串行控制器 API

**Interfaces:**

- Produces in `PasswordVaultStore.swift`:

```swift
struct PasswordVaultSecuritySettingsState: Equatable {
    let vaultState: PasswordVaultState
    let isBusy: Bool
    let autoLockInterval: TimeInterval
    let quickUnlockEnabled: Bool
    let quickUnlockAvailable: Bool
}

protocol PasswordVaultStore {
    func enableQuickUnlock() throws
    func disableQuickUnlock() throws
    func refreshAutoLockSchedule()
}
```

为三个新增 store 方法提供保守默认实现：enable 抛 `.keychainUnavailable`，disable 与 refresh 为幂等 no-op；真实 KDBX store 覆盖全部行为。

- Produces in `PasswordVaultUIController.swift`:

```swift
func loadSecuritySettings(completion: @escaping (PasswordVaultSecuritySettingsState) -> Void)
func setAutoLockInterval(_ interval: TimeInterval, completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
func setQuickUnlockEnabled(_ enabled: Bool, completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
func changeMasterPassword(
    currentPassword: String,
    newPassword: String,
    completion: @escaping (Result<PasswordVaultMasterPasswordChangeResult, PasswordVaultError>) -> Void
)
@discardableResult func addStateChangeObserver(_ observer: @escaping () -> Void) -> UUID
func removeStateChangeObserver(_ identifier: UUID)
```

- Consumes: `Constants.UserDefaults.passwordVaultAutoLockInterval`、新 `passwordVaultQuickUnlockEnabled`、`VaultSessionController.allowedTimeouts`、现有 `vaultAgentExecutor`。

- [ ] **Step 1: 写安全设置失败测试**

在 `PasswordVaultSecuritySettingsTests.swift` 覆盖：

- 快速解锁默认 intent 为 `true`；关闭时删除 key、写 `false`，随后 `unlock(masterPassword:)` 不再保存 key。
- 已解锁时重新开启会保存 32-byte KDBX raw key；locked 时开启返回 `.vaultLocked` 且 UI intent 保持关闭。
- 自动锁定仅接受 `[60, 300, 900, 1_800]`，持久化后对已解锁 store 调用 `refreshAutoLockSchedule()`。
- `onChange` 的现有 MenuManager 单一回调和新增 observer 可以同时收到通知，移除 observer 后不再回调。
- `changeMasterPassword` 与一个阻塞的 Agent operation 不能并发进入 store；顺序完全由同一个 `VaultAgentSerialExecutor` 决定。
- 换密后 quick/automation Keychain save 失败时删除旧 key、结果返回对应 warning；controller 把 quick intent 改为 `false`。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests
```

Expected: FAIL；当前 create/unlock 固定 `rememberQuickUnlock: true`，且没有安全设置快照、observer 或刷新 timer 的 API。

- [ ] **Step 3: 实现 defaults 与 store 行为**

- 在 `Constants.swift` 添加 `passwordVaultQuickUnlockEnabled`，在 `CPYUtilities.registerDefaultValues()` 注册 `true`，兼容现有用户升级行为。
- `PasswordVaultUIController` 注入 `UserDefaults`；当 key 尚无显式对象时也按 `true` 处理，避免测试/启动顺序造成行为漂移。
- `createDatabase` 与 `unlock` 从 intent 读取 `rememberQuickUnlock`，不再硬编码 `true`。
- `KDBXPasswordVaultStore.enableQuickUnlock()` 只允许 readable 状态且必须有当前 `unlockData`；`disableQuickUnlock()` 幂等删除交互 key。
- `VaultSessionController` 暴露 `resolvedTimeout(defaults:)` 并接收可注入 timeout provider；`refreshAutoLockSchedule()` 仅在 readable 状态重新 `touch()`；不受支持的值返回新增 `.invalidAutoLockInterval`。
- 把 `Environment.init` 的 `passwordVaultStore` 参数改为可选；函数体使用 `passwordVaultStore ?? KDBXPasswordVaultStore(autoLockTimeoutProvider: { VaultSessionController.resolvedTimeout(defaults: defaults) })`，再用同一 defaults 构造 UI controller，避免自定义 suite 与 `.standard` 分裂。

- [ ] **Step 4: 实现 controller API 和状态观察**

- 所有读取 `store.canQuickUnlock`、写 key、换密和 timer 刷新均进入 `vaultAgentExecutor`/`storeQueue`。
- defaults 只在 store 操作成功后提交；失败时控件回滚到先前值。
- 换密结果含 `.quickUnlockDisabled` 时把 intent 写为 `false`；automation warning 不改变 Agent 偏好，只要求重新授权。
- 保留现有 `onChange`，新增锁保护的 observer 字典；统一通过主线程 `notifyStateChange()` 同时通知二者，页面销毁时移除 token。

- [ ] **Step 5: 运行聚焦与相邻回归**

运行 Step 2 命令，再运行：

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests \
       -only-testing:pasteraTests/PasswordVaultMenuTests
```

Expected: PASS；Agent 自动解锁、主菜单首次创建和现有 session 自动锁定无回归。

- [ ] **Step 6: 提交本任务**

```bash
git add pastera/Sources/Constants.swift \
  pastera/Sources/Utility/CPYUtilities.swift \
  pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Managers/PasswordVaultUIController.swift \
  pastera/Sources/Environments/Environment.swift \
  pasteraTests/PasswordVaultSecuritySettingsTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): expose password vault security settings"
```

### Task 3: 增加垂直平衡的密码箱偏好页

**Interfaces:**

- Consumes: `PasteraPreferencePageViewController`、`PasteraPreferenceGroupView`、`PasteraPreferenceSettingRowView`、`PasswordVaultSecuritySettingsState`。
- Produces: `.passwordVault` pane、`vault.autoLock`、`vault.quickUnlock`、`vault.masterPassword` 三个搜索锚点。

- [ ] **Step 1: 更新 catalog/shell 失败断言**

先修改 `PreferenceSearchTests.swift`、`PreferenceWindowShellTests.swift` 和 `PreferencePaneAlignmentTests.swift`：

- 固定顺序变为 `.general, .history, .scripts, .shortcuts, .passwordVault, .excludedApps, ...`。
- 侧栏标题为“密码箱”，图标为 `lock.shield`，位于“快捷键”和“忽略应用”之间。
- factory 缓存 `CPYPasswordVaultPreferenceViewController`，三个搜索项均能激活并 reveal 对应锚点。
- 默认宽度下卡片堆叠且内容整体垂直居中；pane 内容宽度达到 760pt 后同一行权重近似 `1.18 : 0.82`；最小窗口和内容溢出时顶部 inset 不小于 16pt 且可滚动。

- [ ] **Step 2: 运行偏好设置测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/PreferenceSearchTests \
       -only-testing:pasteraTests/PreferenceWindowShellTests \
       -only-testing:pasteraTests/PreferencePaneAlignmentTests
```

Expected: FAIL；catalog 与 factory 尚无密码箱 pane，现有自适应网格只支持等宽，所有 pane 统一顶部固定。

- [ ] **Step 3: 实现 catalog、加权网格和专属垂直定位**

- 在 catalog 的 Usage Preferences 分组添加 `.passwordVault`；搜索关键词覆盖“密码箱/vault/自动锁定/快速解锁/主密码/重置密码”。
- `PasteraPreferenceAdaptiveGridView` 的 item 保存可选 weight，单列忽略 weight，双列使用宽度比例约束；旧调用默认 `1`，现有页面布局不变。
- `CPYPreferencesWindowController.selectedPaneOriginY` 仅当当前 pane 为 `.passwordVault` 且 `contentHeight + 32 < visibleHeight` 时返回 `(visibleHeight - contentHeight) / 2`；其他 pane 和溢出状态仍返回现有 inset。
- factory 返回 `CPYPasswordVaultPreferenceViewController()`，并把新文件加入 app target。

- [ ] **Step 4: 实现页面状态与布局**

`CPYPasswordVaultPreferenceViewController`：

- 标题下方展示说明“管理密码箱的锁定、解锁和主密码”以及中性状态 badge，不使用大面积彩色 banner。
- “锁定与解锁”组权重 `1.18`：自动锁定 pop-up、快速解锁 switch、按状态变化的次级说明。
- “主密码”组权重 `0.82`：常驻不可找回警告和“修改主密码”按钮。
- not configured：两组设置禁用，展示“前往密码箱设置”按钮，调用 `AppEnvironment.current.menuManager.popUpMenu(.passwordVault)`。
- locked：自动锁定和修改主密码可用；关闭快速解锁可用，关闭状态下尝试启用则回滚并提示先在主菜单解锁。
- unlocked：全部可用；busy：控件禁用并用可访问状态说明；read-only/failed：禁止换密并给出同步/文件恢复建议。
- 通过 `addStateChangeObserver` 刷新页面，不覆盖 MenuManager 的 `onChange`；deinit/视图退出时移除 observer。

- [ ] **Step 5: 运行聚焦测试**

运行 Step 2 命令。Expected: PASS；再运行 `KeyboardAccessibilityTests.preferencePanesUseComfortableVerticalRhythm` 和 `preferencePaneSwitchingKeepsWindowSizeStableAndUsesScrollDocuments`，确认其他 pane 仍保持原行为。

- [ ] **Step 6: 提交本任务**

```bash
git add pastera/Sources/Preferences/PasteraPreferenceCatalog.swift \
  pastera/Sources/Preferences/PasteraPreferenceComponents.swift \
  pastera/Sources/Preferences/CPYPreferencesWindowController.swift \
  pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift \
  pasteraTests/PreferenceSearchTests.swift \
  pasteraTests/PreferenceWindowShellTests.swift \
  pasteraTests/PreferencePaneAlignmentTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(preferences): add password vault security page"
```

### Task 4: 实现主密码修改 Sheet 与错误恢复交互

**Interfaces:**

- Consumes: `PasswordVaultUIController.changeMasterPassword(...)`、页面当前 window、`PasswordVaultMasterPasswordChangeResult.warnings`。
- Produces: `PasswordVaultMasterPasswordSheetController` 和页面成功/警告状态。

- [ ] **Step 1: 写 Sheet 失败测试**

在 `KeyboardAccessibilityTests.swift` 增加原生 Sheet 测试：

- 三个标签在字段上方，默认全部是 `NSSecureTextField`，每个 `eye/eye.slash` 按钮不改变值或 first responder。
- `新主密码用于加密密码箱。忘记后无法通过其他方式找回。` 始终可见且可被 VoiceOver 读取。
- 三字段非空且新/确认一致前主按钮禁用；不增加复杂度/强度限制。
- Return 只提交一次；Escape 在非 busy 时取消；busy 时字段、显示按钮、取消和关闭按钮全部禁用。
- 两次不一致时错误显示在确认字段下；错误当前密码时仅清空当前字段、保留新/确认并把焦点放回当前字段。
- 深色模式、360pt Sheet 宽度和默认宽度下控件均不越界，key-view loop 顺序为当前 → 新 → 确认 → 取消 → 修改。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/KeyboardAccessibilityTests
```

Expected: FAIL；目前没有偏好页 Sheet。

- [ ] **Step 3: 实现 Sheet 组件**

- 使用原生 `NSWindow` + `beginSheet`，宽度约 440pt，字段单列，标签在上方，常驻 warning 使用 `exclamationmark.triangle` 和语义 secondary/orange，不做装饰性大卡片。
- 复用主菜单已验证的安全字段/普通字段切换原则：同步字符串、selection 和焦点；普通字段只在用户主动显示时存在可见状态。
- 本地 mismatch 不调用 controller；服务请求开始后进入 busy，阻止重复提交和窗口关闭。
- `.wrongMasterPassword`：退出 busy、当前字段清空、内联错误、重新聚焦，保留新密码与确认。
- `.externalConflict`/`.saveFailed`/`.cloudUnavailable`：保留字段并显示可执行恢复建议；不把换密失败显示为成功。
- 成功：先清空三个字段，再结束 Sheet；页面 announce `主密码已修改。`。warnings 映射为“快速解锁已关闭，请重新启用”“Agent 自动解锁需重新授权”或“冲突归档待处理”，不撤销成功状态。
- `deinit`、取消、窗口被父窗口关闭时都调用统一 `clearSecrets()`。

- [ ] **Step 4: 连接页面和本地化**

- 页面只调用 `PasswordVaultUIController.changeMasterPassword`，不持有 store、URL 或 Keychain 对象。
- 更新 `Localizable.xcstrings` 中创建路径文案为“主密码用于加密密码箱。忘记后无法通过其他方式找回。”；修改 Sheet 使用“新主密码用于加密密码箱。忘记后无法通过其他方式找回。”。
- 为页面标题、锁定选项、状态、错误、Keychain partial-success warning 和 success announcement 增加中英文翻译。
- 在 `PasswordVaultMenuTests.swift` 明确断言首次创建文案包含“无法通过其他方式找回”。

- [ ] **Step 5: 运行 Sheet、页面和创建路径测试**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test -only-testing:pasteraTests/KeyboardAccessibilityTests \
       -only-testing:pasteraTests/PasswordVaultMenuTests \
       -only-testing:pasteraTests/PreferencePaneAlignmentTests
jq empty pastera/Resources/Localizable.xcstrings
```

Expected: 全部 PASS，localization catalog 是有效 JSON。

- [ ] **Step 6: 提交本任务**

```bash
git add pastera/Sources/Preferences/Panels/PasswordVaultMasterPasswordSheetController.swift \
  pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift \
  pastera/Sources/Managers/MainMenuPanelController.swift \
  pastera/Resources/Localizable.xcstrings \
  pasteraTests/KeyboardAccessibilityTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(vault): add master password change sheet"
```

### Task 5: 集成验证、安装与交付记录

**Interfaces:**

- Consumes: Tasks 1-4 的 store、controller、偏好页和 Sheet。
- Produces: 完整自动化证据、本地可运行 `Pastera.app` 和本计划 Delivery Record。

- [ ] **Step 1: 重跑全部聚焦测试**

依次运行 Tasks 1-4 的聚焦命令。Expected: 全部 PASS，无依赖执行顺序的测试。

- [ ] **Step 2: 运行仓库默认回归**

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

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 3: 运行 Release 构建和静态检查**

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -configuration Release \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  build
jq empty pastera/Resources/Localizable.xcstrings
git diff --check
```

Expected: `** BUILD SUCCEEDED **`，JSON 和 whitespace 检查通过。

- [ ] **Step 4: 审查安全范围和实际 diff**

```bash
git status --short
git diff --stat
git diff -- pastera/Sources/Services/PasswordVaultStore.swift \
  pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Services/VaultArtifactRekeyTransaction.swift \
  pastera/Sources/Managers/PasswordVaultUIController.swift \
  pastera/Sources/Preferences \
  pastera/Resources/Localizable.xcstrings \
  pasteraTests
```

Expected: 无明文凭据、无日志打印 secret、无范围外业务改动，`.codex/config.toml` 与 `.superpowers/` 未被暂存。

- [ ] **Step 5: 安装并人工验收**

Run: `./script/install_local.sh`

使用临时/测试同步根，不使用唯一真实密码箱做破坏性试验：

1. 未配置：按钮禁用和“前往密码箱设置”正确。
2. 首次设置：输入前可见“无法通过其他方式找回”。
3. locked/unlocked：状态 badge、自动锁定和快速解锁控制状态正确。
4. 快速解锁关闭 → 主密码解锁 → 再锁定，确认不会自动恢复；重新开启后恢复。
5. Sheet mismatch、错误当前密码、成功、busy、Escape、显示/隐藏和 VoiceOver 路径正确。
6. 成功换密后文件夹/条目不变，新密码解锁成功、旧密码失败；Agent 自动解锁仍可用或明确要求重新授权。
7. 默认、最小和加宽窗口确认页面垂直平衡，深色模式无硬编码白色区域。

- [ ] **Step 6: 更新唯一计划的 Delivery Record**

只更新本文件底部，写入实际实现、偏差、测试数量/命令结果、Release build、本地安装和剩余风险；不要创建第二份完成报告或平行 plan。

- [ ] **Step 7: 提交交付记录**

```bash
git add docs/superpowers/plans/2026-07-21-password-vault-preferences-master-password.md
git commit -m "docs(vault): record password vault preferences delivery"
```

## Risks, Rollback and Observation

- **风险：多文件没有原生跨文件原子提交。** 通过同目录暂存、源修订复核、逐文件 rollback 路径和每个失败点故障注入，把可观察结果约束为“全部旧文件”或“全部新文件”。
- **风险：OneDrive 在暂存期间再次写入。** 提交前逐文件复核 SHA-256；变化立即返回 `.externalConflict`，不覆盖远端新版本。
- **风险：旧密码仍能打开备份或归档。** 工件枚举测试显式覆盖 `.bak`、同目录 conflict 和 `conflicts/resolved`；成功验收必须逐文件断言旧密码失败。
- **风险：Keychain 刷新在 KDBX 成功后失败。** 不回滚已经安全提交的 KDBX；删除无效 key、关闭对应能力、返回 partial-success warning，并要求重新启用/授权。
- **风险：换密与 Agent secret 请求交错。** 两者强制使用现有 `VaultAgentSerialExecutor`，测试用阻塞 operation 证明不会并发进入 store。
- **风险：快速解锁关闭后被旧流程重新打开。** `createDatabase`/`unlock` 必须读取持久化 intent，并有“关闭 → 主密码解锁 → key 仍为空”的回归测试。
- **风险：垂直居中破坏其他偏好页或搜索 reveal。** 定位逻辑只对 `.passwordVault` 生效；溢出时顶部固定，现有所有 pane 的定位测试继续运行。
- **回滚代码：** Tasks 1-4 可按提交逆序回退；不改变 KDBX 文件格式，回退后的旧版本仍可使用用户最后设置的新主密码打开标准 KDBX。
- **回滚运行时数据：** 换密失败自动恢复旧文件；换密成功不自动恢复旧密码，因为这会重新暴露旧凭据。用户如需再次修改，只能用当前新密码重复同一流程。
- **观察：** 本地安装后重点观察 OneDrive 正在同步时的冲突提示、睡眠/切换用户后的自动锁定、Keychain 被拒绝时的 warning、Agent 授权跨换密后的行为和 Sheet 关闭时 secret 清理。

## Delivery Metadata

- Plan: `docs/superpowers/plans/2026-07-21-password-vault-preferences-master-password.md`
- Status: Design confirmed; implementation pending
- Evidence Profile: standard
- Source: user-confirmed design plus current repository inspection on 2026-07-21
- ZenTao Story ID: absent
- ZenTao Task ID: absent
- ZenTao Sync: not-synced；仓库不存在 `docs/zentao/ZENTAO.md`，不得创建或臆造编号
- Prior contracts: `2026-07-15-password-vault-inline-unlock`、`2026-07-17-password-vault-contextual-actions`、`2026-07-19-password-vault-access-polish`
- Design decisions: native Preferences page + native Sheet；known-current-password change；complete security settings；vertical-balanced layout

## Delivery Record

- Actual Implementation: 已交付密码箱安全设置闭环。KDBX store 支持在校验当前主密码后，对主文件、备份、同目录冲突文件和 `conflicts/resolved` 工件执行带冲突复核与失败回滚的统一换密；Preferences 新增垂直平衡的“密码箱”页面，展示未配置/已锁定/已解锁状态，并提供自动锁定、快速解锁和修改主密码入口；原生 Sheet 覆盖当前/新/确认密码、显示隐藏、键盘操作、busy、防重复提交、错误聚焦和 secret 清理；首次设置和换密流程均明确显示“忘记后无法通过其他方式找回”。
- Plan Deviations: 用户界面的“重置主密码”按已确认安全语义实现为“验证当前密码后修改”，未提供绕过、找回或清空密码箱的恢复路径。未对唯一真实密码箱执行破坏性人工换密，数据保留与旧/新密码行为使用临时 KDBX、故障注入和自动化测试验证。默认并行 `clean test` 受仓库既有共享状态/时序竞争及 Xcode result-bundle `writerNotOpen` 影响出现 6 项失败；同产物定向复跑和单 worker 全量复跑通过。Release scheme 的 Build Action 会连带编译使用 `@testable import` 的测试 target，因此 scheme Release 以 65 退出；改为仅构建 `pastera` 应用 target 后通过。
- Impact: 触达密码箱 store/API、KDBX 多工件换密事务、Keychain 快速解锁意图、Agent 串行执行边界、Preferences catalog/搜索/布局、5 种本地化和本机应用安装。未改变 KDBX 文件格式；成功换密后当前数据保留，旧密码失效，新密码生效；Keychain 刷新失败时保留已安全提交的 KDBX，并返回需要重新授权的 partial-success warning。
- Verification: 密码换密与安全设置聚焦套件通过；`KeyboardAccessibilityTests`、`PasswordVaultMenuTests`、`PreferencePaneAlignmentTests`、`PreferenceSearchTests` 组合 70 项通过；默认并行全量失败所在的 `PasteboardHistorySyncRepositoryTests`、`VaultAgentPerformanceTests`、`VaultAgentBrokerTests`、`VaultAgentIntegrationInstallerTests` 定向复跑退出码 0；隔离 DerivedData 下 `test-without-building -parallel-testing-enabled NO -maximum-parallel-testing-workers 1` 全量退出码 0（193.478 秒）；`xcodebuild -target pastera -configuration Release ... build` 退出码 0；`jq empty pastera/Resources/Localizable.xcstrings`、5 语言偏好文案覆盖检查、`git diff --check 532508a..ecefadc` 和新增日志扫描通过；`./script/install_local.sh` 构建、ad-hoc 签名、替换和启动成功，`/Applications/Pastera.app` 回读为 3.0.1 (301)、`com.pastera-app.Pastera.debug`，运行路径为 `/Applications/Pastera.app/Contents/MacOS/Pastera`。
- Remaining Risks: OneDrive 在多工件暂存/提交窗口内并发写入、Keychain 被拒绝后的重新授权、真实用户大体量密码箱换密耗时仍需上线观察；默认并行测试仍可能受全局状态竞争影响；Xcode 26.5 当前报告 CoreSimulator 1051.54 低于 1051.55；Release scheme 的测试 target 配置尚未修正。未在唯一真实密码箱上执行人工换密，也未完成全量 VoiceOver、深色模式和各窗口宽度的人工遍历。
- Follow-ups: 后续可独立修正 Release scheme，避免应用 Release 构建连带编译测试 target；隔离并发测试的全局状态并升级匹配的 CoreSimulator。功能范围内无阻断性待办；人工验收应继续使用临时/测试同步根。
- ZenTao Closeout: 未执行；仓库没有本需求已确认的 ZenTao Story/Task ID，用户也未授权 ZenTao 写操作。
