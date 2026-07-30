# Windows V1 已批准功能增量

## 范围

- 冻结基线：`windows-v1-baseline-20260718`
- 基线 peeled commit：`745083902114999d98724792ad0d57fd93402377`
- 批准增量上限：`7b57094ce32cf19ac737d24d10e91ebf121aaed5`
- 增量区间：`7450839..7b57094`

本文件只登记上述区间内已经交付、会改变 Windows 产品行为、跨平台契约或验收
的内容。`7b57094` 之后的快捷键/数字导航即使已在其他本地提交实现，也不属于
本轮批准增量；后续要纳入必须再次更新唯一 Windows V1 计划。

每个产品域都使用以下字段：

- `Product behavior`：用户可观察行为和错误语义。
- `macOS source`：`7b57094` 中的源码入口。
- `Tests`：`7b57094` 中的可执行行为证据。
- `Windows parity`：Windows 必须交付的等价结果。
- `Platform replacement`：允许替换的平台机制。
- `UI evidence`：开工前和验收时需要的截图。
- `Status`：Windows 当前状态。

## 增量总览

| 产品域 | 主要提交 | Windows 处理 |
| --- | --- | --- |
| 主面板与后台资源 | `b9f5706`、`dfc2fcb`、`2ac452a` | 纳入历史/主面板任务 |
| 密码箱 Agent | `2997ab3..baa195f`、`d60a02b` | 新增独立 Agent 安全集成任务 |
| 密码箱安全设置 | `56fe756`、`d2243ec`、`ecefadc` | 纳入 KDBX/设置任务 |
| 提示词优化 | `c1b3455`、`d468918`、`3203921`、`5051769`、`d3f42c8` | 纳入历史编辑与设置任务 |
| 本地优先密码箱同步 | `1154891..ad5a97e` | 纳入 KDBX 与 OneDrive 任务 |
| 软件更新 | `94e7389` 及 `7b57094` 中 appcast 修正 | Windows 原生更新通道 |
| 脚本模板与设置 | `178af2c` | 纳入脚本和设置任务 |
| 仓库工具 | `7dbca52`、`7b57094` 的 CodeGraph 部分 | 不属于 Windows 产品功能 |

## 1. 主面板交互与有界后台资源

### Product behavior

- 主面板提示会自动收敛，不遮挡后续操作。
- 搜索、密码箱入口、设置跳转和失败反馈保持当前上下文，不用无提示重建页面。
- OCR 使用持久化 job 和单泵执行，启动/实时处理不无界占用图片内存。
- 历史清理和未配置同步避免无意义地读取完整内容或保持常驻观察。

### macOS source

- `pastera/Sources/Managers/MainMenuPanelController.swift`
- `pastera/Sources/Managers/MainMenuFooterButtons.swift`
- `pastera/Sources/Managers/MainMenuOCRActivityView.swift`
- `pastera/Sources/Managers/MenuManager.swift`
- `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`
- `pastera/Sources/Services/PasteboardHistoryOCRIndexer.swift`
- `pastera/Sources/Services/SyncCoordinator.swift`

### Tests

- `pasteraTests/MainMenuEmbeddedContentTests.swift`
- `pasteraTests/MainMenuVisualPolishTests.swift`
- `pasteraTests/MainMenuPinFooterTests.swift`
- `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`
- `pasteraTests/SyncCoordinatorTests.swift`
- `pasteraTests/Database/SQLiteDataMigratorTests.swift`

### Windows parity

Windows 主面板必须保留相同的信息层级、模式入口、搜索上下文和反馈语义。OCR、
清理和同步观察必须有界；后台优化不得改变用户可见的历史结果或错误边界。

### Platform replacement

WinUI Dispatcher、Windows OCR 组件和 SQLite 实现可以替换 AppKit/Vision/
SQLiteData 机制，但不能删除 OCR 状态、取消、恢复或错误反馈。

### UI evidence

- 继续使用 `main-panel/01-history-synthetic-dark.jpg`、
  `main-panel/02-search-open-dark.jpg` 和
  `history-browser/01-search-empty-dark.jpg` 约束不变区域。
- OCR 活动态和 `7b57094` 新搜索反馈缺少安全参考图；实现前按
  `current-20260726/README.md` 补图。
- Windows 完成证据必须包含同状态三联图和 P0-P3 差异记录。

### Status

`Windows pending`。当前仓库尚无 Windows solution。

## 2. 密码箱 Agent 安全集成

### Product behavior

- 外部 Codex/Claude 通过版本化 wire contract 访问允许的密码箱操作。
- 本机 peer 必须验证；授权、持久 grant、一次性票据、限流和脱敏审计分层。
- broker 连接和消息大小有界；取消、过期、超限、身份不匹配和资源关闭全部
  fail closed。
- CLI/MCP 适配器复用相同安全边界；安装事务不覆盖用户不属于 Pastera 的配置。
- 密码、主密码和解锁材料不通过 Agent 返回；安全粘贴由 Pastera 执行。

### macOS source

- `pastera-agent/Sources/PasteraAgentProtocol/`
- `pastera-agent/Sources/PasteraAgentAdapter/`
- `pastera/Sources/Services/VaultAgentAuthorizationCoordinator.swift`
- `pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift`
- `pastera/Sources/Services/VaultAgentBroker.swift`
- `pastera/Sources/Services/VaultAgentTicketStore.swift`
- `pastera/Sources/Services/VaultAgentRateLimiter.swift`
- `pastera/Sources/Services/VaultAgentAuditLogger.swift`
- `pastera/Sources/Services/VaultAgentPeerVerifier.swift`
- `pastera/Sources/Services/VaultAgentIntegrationInstaller.swift`
- `pastera/Sources/Services/VaultAgentRuntime.swift`
- `pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift`

### Tests

- `pasteraAgentTests/VaultAgentProtocolTests.swift`
- `pasteraAgentTests/VaultAgentClientTests.swift`
- `pasteraAgentTests/VaultAgentCommandRunnerTests.swift`
- `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`
- `pasteraTests/VaultAgentBrokerTests.swift`
- `pasteraTests/VaultAgentTicketStoreTests.swift`
- `pasteraTests/VaultAgentPeerVerifierTests.swift`
- `pasteraTests/VaultAgentIntegrationInstallerTests.swift`
- `pasteraTests/VaultAgentLeakRegressionTests.swift`
- `pasteraTests/VaultAgentPerformanceTests.swift`

### Windows parity

Windows 必须保持 wire operation、授权结果、票据一次性、限流、审计脱敏、
取消和失败语义。Agent 集成是独立安全域，不能直接访问 UI 内存或 KDBX 文件。

### Platform replacement

使用 Windows 本机 IPC、用户 ACL、进程 token/签名信息、DPAPI/Windows Hello
和 Windows helper 生命周期替代 Unix socket、macOS code signing、Keychain 和
LocalAuthentication。替换平台机制不能放宽授权或秘密返回边界。

### UI evidence

`7b57094` Agent 设置页缺少安全参考图。Windows 开工前必须补齐未安装、安装中、
一次授权、已授权、撤销和失败状态；缺图时不得自行设计页面结构。

### Status

`Windows pending; UI reference missing`。

## 3. 密码箱主密码、安全设置与本地优先存储

### Product behavior

- KDBX 本地文件是工作副本和事实来源；云端副本不直接作为运行时工作文件。
- 支持主密码修改、原子 rekey、失败回滚和提交后清理恢复。
- 旧云端数据迁移与本地写入串行，不能覆盖较新的本地事务。
- 缺失、损坏或不满足前置条件时 fail closed，不创建看似成功的空密码箱。
- Windows Hello/DPAPI 只提供用户明确启用的本机快捷解锁；失效后退回主密码。

### macOS source

- `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- `pastera/Sources/Services/PasswordVaultLocalStorage.swift`
- `pastera/Sources/Services/PasswordVaultMigrationService.swift`
- `pastera/Sources/Services/PasswordVaultSecuritySettings.swift`
- `pastera/Sources/Services/VaultArtifactRekeyTransaction.swift`
- `pastera/Sources/Preferences/Panels/CPYPasswordVaultPreferenceViewController.swift`
- `pastera/Sources/Preferences/Panels/PasswordVaultMasterPasswordSheetController.swift`

### Tests

- `pasteraTests/PasswordVaultLocalStorageTests.swift`
- `pasteraTests/PasswordVaultMigrationTests.swift`
- `pasteraTests/PasswordVaultMasterPasswordTests.swift`
- `pasteraTests/PasswordVaultSecuritySettingsTests.swift`
- `pasteraTests/PasswordVaultTransactionAndMergeTests.swift`
- `pasteraTests/PasswordVaultStoreTests.swift`

### Windows parity

Windows KDBX 必须与 macOS 双向可读；本地工作副本、主密码变更、rekey rollback、
锁定和便捷解锁失效回退语义必须一致。

### Platform replacement

DPAPI/Windows Hello 可以替换 Keychain/LocalAuthentication；不得创建
Windows-only vault format，也不得把便捷解锁材料写入 KDBX 或 OneDrive。

### UI evidence

- 继续使用 `main-panel/04-vault-locked-dark.jpg` 约束锁定入口和主面板结构。
- 安全设置页和主密码变更 sheet 缺少 `7b57094` 安全参考图，开工前必须补图。

### Status

`Windows pending; partial baseline UI reference`。

## 4. 本地优先 OneDrive 密码箱同步

### Product behavior

- 加密 KDBX replica 写入 OneDrive 本地文件夹；云端传输由 OneDrive 客户端负责。
- 本地 revision、已同步 revision、远端 digest 和迁移版本分别跟踪。
- 并发本地/远端变更安全合并；缺失远端副本可重建，损坏或冲突可恢复。
- UI 区分“OneDrive 客户端可用”“本地副本已写入”“云端上传/下载未知”。
- 密码箱生命周期与同步生命周期分离；同步错误不伪装成密码箱被锁定。

### macOS source

- `pastera/Sources/Services/PasswordVaultCloudReplica.swift`
- `pastera/Sources/Services/PasswordVaultSyncMetadataStore.swift`
- `pastera/Sources/Services/PasswordVaultSyncModels.swift`
- `pastera/Sources/Services/PasswordVaultSyncService.swift`
- `pastera/Sources/Services/LocalOnlyPasswordVaultSyncController.swift`
- `pastera/Sources/Managers/PasswordVaultSyncView.swift`
- `pastera/Sources/Preferences/Panels/CPYSyncPreferenceViewController.swift`

### Tests

- `pasteraTests/PasswordVaultCloudReplicaTests.swift`
- `pasteraTests/PasswordVaultCloudReplicaMissingFileTests.swift`
- `pasteraTests/PasswordVaultSyncMetadataTests.swift`
- `pasteraTests/PasswordVaultSyncMigrationCommitTests.swift`
- `pasteraTests/PasswordVaultSyncServiceTests.swift`
- `pasteraTests/SyncPreferenceTopSectionTests.swift`

### Windows parity

Windows 使用相同的本地优先 KDBX 语义和加密 replica 兼容边界。必须保留合并、
恢复、重建、状态区分和“本地成功不等于云端成功”语义。

### Platform replacement

OneDrive 根发现、文件 watcher 和原子替换使用 Windows API；目录契约、加密
payload 和 revision/digest 语义不能私有分叉。

### UI evidence

- `preferences/06-sync-configured-dark.jpg` 继续约束同步设置的状态/位置/范围/
  操作分组。
- 密码箱就地同步、恢复和冲突状态缺少安全参考图，开工前必须补图。

### Status

`Windows pending; partial baseline UI reference`。

## 5. 历史提示词优化

### Product behavior

- 用户从历史编辑器显式触发优化；结果先进入草稿预览，不自动覆盖历史。
- 默认本地格式化可用；用户可以配置 OpenAI-compatible 自备服务。
- endpoint 校验、API key 保护、连接测试取消和失败回退明确。
- 支持撤销和显式保存；超时、取消、无需修改和失败都保留原文。
- Apple Foundation Models 是 macOS 可选 provider，不是 Windows 强制机制。

### macOS source

- `pastera/Sources/Managers/HistoryEditorWindowController.swift`
- `pastera/Sources/Models/PromptOptimization.swift`
- `pastera/Sources/Services/LocalPromptFormatter.swift`
- `pastera/Sources/Services/OpenAICompatiblePromptOptimizer.swift`
- `pastera/Sources/Services/PromptOptimizationService.swift`
- `pastera/Sources/Services/PromptOptimizationEndpointPolicy.swift`
- `pastera/Sources/Services/PromptOptimizationAPIKeyStore.swift`
- `pastera/Sources/Services/PromptOptimizationSettingsStore.swift`
- `pastera/Sources/Preferences/Panels/CPYPromptOptimizationPreferenceViewController.swift`
- `pastera/Sources/Preferences/Panels/PromptOptimizationPreferenceSection.swift`

### Tests

- `pasteraTests/HistoryEditorWindowControllerTests.swift`
- `pasteraTests/OpenAICompatiblePromptOptimizerTests.swift`
- `pasteraTests/PromptOptimizationServiceTests.swift`
- `pasteraTests/PromptOptimizationSettingsTests.swift`
- `pasteraTests/PromptOptimizationPreferenceTests.swift`

### Windows parity

Windows 必须交付本地格式化、OpenAI-compatible 自备服务、显式预览/撤销/保存、
凭据保护、取消和失败不覆盖语义。不得为了对等伪造 Apple Intelligence。

### Platform replacement

Windows 可选择符合隐私和资源边界的本地 provider；任何 provider 都必须服从
同一 Application 接口和用户显式调用门。

### UI evidence

历史编辑优化态和独立设置页缺少安全参考图。实现前必须补齐原文、优化中、
预览、撤销、保存、本地模式、远程配置和连接失败状态。

### Status

`Windows pending; UI reference missing`。

## 6. 软件更新、设置结构与脚本模板

### Product behavior

- 软件更新从关于页拆成独立页面，支持自动检查、手动检查、状态和用户确认后的
  下载/安装/重启。
- 版本源、更新元数据、签名和安装包必须一致；不能展示过期版本链。
- 脚本模板创建、编辑和测试流程修正；设置页保持紧凑语义分组。

### macOS source

- `pastera/Sources/Preferences/Panels/CPYSoftwareUpdatePreferenceViewController.swift`
- `pastera/Sources/Preferences/PasteraUpdaterFacade.swift`
- `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- `pastera/Sources/Preferences/Panels/CPYScriptsPreferenceViewController.swift`
- `pastera/Sources/Preferences/Panels/ScriptTemplateMarketViewController.swift`
- `pastera/Sources/Preferences/Panels/ScriptEditorViewController.swift`
- `pastera/Sources/Preferences/Panels/ScriptTestViewController.swift`
- `pastera/Sources/Services/ScriptTemplateCatalog.swift`

### Tests

- `pasteraTests/SoftwareUpdatePreferenceTests.swift`
- `pasteraTests/SparkleUpdateFeedTests.swift`
- `pasteraTests/ReleasePackagingConfigurationTests.swift`
- `pasteraTests/PreferenceSearchTests.swift`
- `pasteraTests/PreferenceWindowShellTests.swift`
- `pasteraTests/ScriptPreferenceTests.swift`
- `pasteraTests/ScriptTemplateCatalogTests.swift`

### Windows parity

Windows 使用独立更新页、签名 installer 和 Windows 更新元数据，保留版本一致性、
用户确认、失败回退和状态语义。脚本 UI 保留模板/编辑/测试入口与受限执行边界。

### Platform replacement

Windows updater 替代 Sparkle，MSIX/EXE/MSI 替代 DMG；不能复用 Sparkle 字段或
以 macOS appcast 作为 Windows 安装来源。

### UI evidence

- `preferences/03-scripts-empty-dark.jpg` 和 `preferences/07-about-dark.jpg`
  只约束未变化的信息层级。
- 独立更新页、修正后的脚本模板/编辑/测试页面缺少安全参考图，开工前必须补图。

### Status

`Windows pending; partial baseline UI reference`。

## 不属于产品增量

以下变更只作为仓库或发布背景，不创建 Windows 产品任务：

- CodeGraph 接入、MCP watcher 和本地 agent runtime ignore。
- `.gitignore`、`.codex/` 或本机 worktree 维护。
- Sparkle appcast 的具体 XML 字段和 macOS DMG 生成流程。

它们只提供“开发工具不能代替源码/测试事实”和“更新元数据必须与真实安装包
一致”的边界。

## UI 完成门

所有涉及 UI 的 Windows 任务必须同时满足：

1. 在实现前选定状态匹配的参考图；缺图则补安全参考图或请求用户确认。
2. 按 `REFERENCE_GEOMETRY.md` 记录主要区域、对齐线、间距和可见行数。
3. 提交 macOS 参考图、同状态 Windows 图和 50% 透明叠加图。
4. 未获批准的 P0 结构偏差和 P1 几何偏差为 0。
5. 深色、浅色和 125% 缩放 Windows 11 smoke 通过。
6. 自动化测试与截图证据同时存在；任何一项都不能替代另一项。
