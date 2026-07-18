# Pastera 独立产品迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留完整 Git 历史、用户数据和必要开源归属的前提下，将 `pastera-app/Pastera` 从 `Clipy/Clipy` fork 网络及其运行时依赖中完全剥离，并形成承载 macOS 与 Windows 客户端的独立 Pastera 单仓库基线。

**Architecture:** 迁移按四个不可跨越的门执行：先收敛当前 macOS 工作区并建立可验证基线，再解除 GitHub fork 身份，然后按依赖、数据、命名和文档边界清理 Clipy 遗留，最后冻结供 Windows V1 使用的跨平台产品契约。任何不可逆远端操作前都必须生成本地 Git bundle、远端元数据快照和基线 tag。

**Tech Stack:** Swift 5 / AppKit / SQLiteData / Swift Testing / Xcode 26.5 / Git / GitHub / C# + WinUI 3 + Windows App SDK（后续 Windows 客户端）

## Global Constraints

- 保留完整 Git commit 历史，不创建 orphan 根提交，不抹除 Clipy 来源。
- 根 `LICENSE` 继续满足 MIT 许可；新增 `NOTICE` 说明 Clipy 历史来源和 Pastera 后续修改。
- 仍源自 Clipy 的文件保留原版权；只有完成实质性重写的文件才能改为纯 Pastera 文件头。
- 现有用户的 SQLite 历史、片段、设置、脚本和 KDBX 密码箱不得因独立化丢失。
- Realm/旧模型只允许作为一次性只读迁移通道存在，不得继续承载产品运行时写入。
- 独立化完成时，生产依赖图不得引用 `github.com/Clipy/*`。
- 解除 fork 后删除本地 `upstream` remote，不再建立自动跟踪 `Clipy/Clipy` 的流程。
- 采用单仓库双平台结构；现有 `pastera/` 在本轮不做无业务价值的整体目录搬迁。
- Windows 客户端新增在 `windows/`；共享协议与样本分别进入 `contracts/` 和 `test-fixtures/`。
- 本轮独立化不实现 Windows 客户端；Windows V1 另从本计划冻结的基线和契约制定实施任务。
- `.codex/config.toml`、`.superpowers/`、`.DS_Store`、本机构建缓存和凭据不得提交。

---

## Business Scope / Out of Scope

### In Scope

- 收敛当前约 5,000 行未提交 macOS 功能变更及其测试契约。
- 建立独立化前 Git bundle、GitHub 元数据快照、基线 commit 和 annotated tag。
- 使用 GitHub `Leave fork network` 将 `pastera-app/Pastera` 转为 standalone repository。
- 复核默认分支、Release、Actions、分支保护、远端和 GitHub 仓库身份。
- 移除或替代 `Sauce`、`Magnet`、`KeyHolder`、`LoginServiceKit`、`Screeen` 等 `Clipy/*` 生产依赖。
- 把 Realm 限定为一次性数据导入，并在兼容窗口结束后删除 Realm 运行时。
- 分批替换 `CPY*`、`Clipy` URL、旧类名、旧设置语义和上游同步文档。
- 建立独立 Pastera 的 LICENSE/NOTICE、README、AGENTS、发布与平台文档边界。
- 冻结 macOS 功能基线 commit/tag，作为 Windows V1 对等矩阵的唯一事实来源。

### Out of Scope

- 抹除 Git 历史、许可证来源或已有 commit 作者信息。
- 在独立化提交中同时实现 Windows 客户端。
- 把现有 `pastera/` 目录整体移动为 `macos/`。
- 为了消除名字而一次性重写所有稳定业务逻辑。
- 保留 Clipy 的 UI、菜单结构、旧测试预期或上游同步兼容行为。
- Microsoft Store、winget 或 Windows 安装器交付。

## Architecture

### 仓库身份层

`origin` 继续指向 `https://github.com/pastera-app/Pastera.git`。解除 fork 前后 URL 不变，Git 历史不变；GitHub `isFork` 从 `true` 变为 `false`，`parent` 变为空。本地 `upstream` 在远端验证完成后删除。

### macOS 应用层

现有 AppKit 产品能力继续运行。独立化先以测试和实际行为定义 Pastera 契约，再逐域替换 Clipy 命名与第三方依赖，避免在一个提交中同时改变数据、快捷键、菜单和持久化语义。

### 数据迁移层

SQLiteData 是当前事实存储。Realm 只读取旧数据库并导入尚未迁移的数据；迁移必须幂等、有完成标记、有失败日志，并保留原文件备份。完成一个稳定版本观察后，删除 Realm package、旧模型和导入实现。

### 双平台契约层

`contracts/` 记录剪贴板类型、OneDrive 目录、SQLite 快照版本、KDBX 路径与冲突语义；`test-fixtures/` 保存不含真实隐私数据的跨平台样本。macOS 和 Windows 各自使用原生 UI/API，不共享 UI 框架。

## Tasks

### Task 1: 收敛当前 macOS 工作区为可验证基线

**Files:**
- Modify: `pasteraTests/PreferenceWindowShellTests.swift`
- Modify: `pasteraTests/PreferencePaneAlignmentTests.swift`
- Modify: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pasteraTests/DefaultNumericShortcutTests.swift`
- Modify: `pasteraTests/HistoryDisplayContentTests.swift`
- Modify: `pasteraTests/SnippetBrowserPanelTests.swift`
- Modify: `pasteraTests/MainMenuPinFooterTests.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Preserve: all current source changes already present in the working tree

**Interfaces:**
- Consumes: current seven-pane `PasteraPreferenceCatalog`, `PasteboardHistoryRepositoryProtocol`, system clipboard and KDBX store behavior.
- Produces: a test-clean macOS baseline without restoring obsolete six-pane Clipy expectations.

- [x] Update stale preference expectations to the current seven-pane order: `general, history, scripts, shortcuts, excludedApps, sync, about`.
- [x] Inject an explicit empty `PasteboardHistoryRepositoryProtocol` into UI-only tests that construct `MenuManager`; do not let tests fall through to the live SQLiteData dependency.
- [x] Add every new preference key to all supported `Localizable.xcstrings` locales and keep the localization completeness test enabled.
- [x] Isolate the real KDBX clipboard integration test from other system-clipboard tests using an injectable named pasteboard and explicit Secure Event Input state.
- [x] Run the previously failing suites serially and require zero failures.
- [x] Run the repository default `xcodebuild ... clean test` command and require zero failures.
- [ ] Run `./script/install_local.sh`, verify `/Applications/Pastera.app` is running, and perform the manual clipboard matrix from `docs/verification/VERIFICATION.md`.（安装和进程核验已完成；Finder/Notes/Preview/OneDrive 人工矩阵待人工验收。）
- [x] Update only the already-associated plan's `Delivery Record` with real verification evidence; do not create another feature plan.
- [ ] Commit the consolidated baseline as `feat(app): 固化 Pastera 独立化前功能基线`.

### Task 2: 建立可恢复的远端脱离检查点

**Files:**
- Create: `.build/repository-backups/pastera-pre-standalone.bundle` (local-only, never commit)
- Create: `.build/repository-backups/github-metadata.json` (local-only, never commit)
- Modify: no product source files

**Interfaces:**
- Consumes: verified Task 1 commit and current `origin` state.
- Produces: a local recovery bundle, metadata snapshot and pushed annotated tag.

- [x] Confirm `git status --short` contains only intentional local-only files.
- [x] Fetch all `origin` refs and record the exact `develop` commit.
- [x] Create a full `git bundle` containing all refs and verify it with `git bundle verify`.
- [x] Export repository identity, branches, tags, releases, rulesets, Actions workflows, issues and pull request counts to the local backup directory without credentials.
- [x] Create annotated tag `pastera-pre-standalone` at the verified baseline commit.
- [x] Push `develop` and `pastera-pre-standalone` to `origin`.
- [x] Verify remote branch and tag SHAs with `git ls-remote`.

### Task 3: 解除 GitHub fork 网络身份

**Files:**
- Modify: local Git remote configuration
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/development/PASTERA_FORK_PLAN.md`
- Modify: `docs/development/WINDOWS_PORTING_GUIDE.md`

**Interfaces:**
- Consumes: Task 2 recovery artifacts and pushed tag.
- Produces: `pastera-app/Pastera` with `isFork=false`, no `parent`, and no local `upstream` remote.

- [x] Reconfirm the repository is public, below 1 GB, has no child forks, and the backup bundle verifies.
- [x] Use GitHub Settings → General → Danger Zone → `Leave fork network`; this irreversible action requires a final user confirmation immediately before clicking.
- [x] Poll `gh repo view pastera-app/Pastera --json isFork,parent` until it reports `false` and `null`.
- [x] Verify `develop`, tags, releases and Actions still exist; compare against the Task 2 metadata snapshot.
- [x] Remove the local `upstream` remote only after remote identity verification succeeds.
- [x] Rewrite repository docs from “fork/upstream alignment” to “independent Pastera product”; retain historical attribution in LICENSE/NOTICE.
- [x] Commit as `chore(repo): 将 Pastera 转为独立仓库` and push `develop`.

### Task 4: 建立许可证和依赖审计边界

**Files:**
- Modify: `LICENSE`
- Create: `NOTICE`
- Create: `docs/development/DEPENDENCY_MIGRATION.md`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pastera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:**
- Consumes: current package graph and actual import/call paths.
- Produces: a checked dependency disposition for every `Clipy/*` package and durable attribution rules.

- [x] Record each imported API and call site for `Sauce`, `Magnet`, `KeyHolder`, `LoginServiceKit` and `Screeen`.
- [x] Replace `Screeen` with a local `NSMetadataQuery` observer after confirming its active screenshot call path.
- [x] Replace `LoginServiceKit` with `SMAppService` behind a small launch-at-login service and focused tests.
- [x] Replace the single `Sauce` Command-V lookup with a local keyboard-layout-aware adapter and focused tests.
- [x] Decide `Magnet` and `KeyHolder` from evidence: retain their broad compatibility surface in Pastera-maintained forks with preserved licenses.
- [x] Add a CI/static check that fails when production package URLs contain `github.com/Clipy/`.
- [x] Run package resolution, focused tests and the full macOS suite.
- [x] Commit each independently testable dependency removal separately.

### Task 5: 将 Realm 收敛为一次性导入并移除运行时

**Files:**
- Modify: `pastera/Sources/AppDelegate.swift`
- Modify: `pastera/Sources/Extensions/Realm+Migration.swift`
- Modify: `pastera/Sources/Utility/CPYUtilities.swift`
- Modify: `pastera/Sources/Models/CPYClip.swift`
- Modify: `pastera/Sources/Models/CPYFolder.swift`
- Modify: `pastera/Sources/Models/CPYSnippet.swift`
- Create: `pastera/Sources/Database/LegacyClipyImportService.swift`
- Create: `pasteraTests/Database/LegacyClipyImportServiceTests.swift`
- Modify: project/package files after the compatibility window

**Interfaces:**
- Consumes: legacy Realm files and current SQLiteData repositories.
- Produces: `LegacyClipyImportService.runIfNeeded() -> LegacyImportResult` with idempotent import, backup and completion marker.

- [ ] Add fixtures proving a legacy history/folder/snippet database imports once without deleting current SQLite rows.
- [ ] Make import failure leave the original Realm file and completion marker untouched.
- [ ] Remove unconditional `Realm.migration()` and invoke the import service before normal repository reads.
- [ ] Record success/failure without logging clipboard content or credentials.
- [ ] Ship and observe one stable compatibility release.
- [ ] In a later independently approved commit, remove Realm package, old Realm models/extensions and import code after the observation gate is satisfied.

### Task 6: 分域替换 Clipy 命名和旧产品契约

**Files:**
- Modify: `pastera/Sources/**`
- Modify: `pasteraTests/**`
- Modify: `Configurations/**`
- Modify: `README.md`
- Modify: `docs/**`

**Interfaces:**
- Consumes: test-clean, dependency-clean and data-safe macOS application.
- Produces: Pastera-named domain types with no active Clipy product behavior.

- [ ] Generate an inventory separating legal attribution, protocol compatibility identifiers, file/type names and obsolete product naming.
- [ ] Preserve protocol identifiers such as historical pasteboard type strings when changing them would break data compatibility; rename only the Swift-facing symbols.
- [ ] Rename `CPY*` types by bounded domain (preferences, snippets, models, utilities), one buildable commit per domain.
- [ ] Replace Clipy URLs and upstream workflow text with Pastera URLs.
- [ ] Delete obsolete Clipy tests only when the tested behavior is intentionally out of scope; replace them with Pastera behavior tests before deletion.
- [ ] Keep source attribution in derived files and add Pastera modification notices where appropriate.
- [ ] Require `rg` inventory, `git diff --check`, focused tests, full tests and installed-app smoke checks after each domain.

### Task 7: 建立独立单仓库双平台契约

**Files:**
- Create: `contracts/README.md`
- Create: `contracts/clipboard-types.json`
- Create: `contracts/sync-protocol.json`
- Create: `test-fixtures/history/`
- Create: `test-fixtures/snippets/`
- Create: `test-fixtures/files/`
- Create: `test-fixtures/vault/README.md`
- Create: `windows/README.md`
- Modify: `docs/development/WINDOWS_PORTING_GUIDE.md`

**Interfaces:**
- Consumes: frozen independent macOS baseline and existing OneDrive/KDBX contracts.
- Produces: machine-readable, secret-free fixtures and the Windows V1 implementation entrypoint.

- [ ] Freeze the final macOS baseline with commit SHA and annotated tag.
- [ ] Encode clipboard logical types independently from `NSPasteboard` and Windows native constants.
- [ ] Encode existing history `schemaVersion=4`, snippet `schemaVersion=3`, file manifest/schema version `1`, device ID and conflict semantics.
- [ ] Add sanitized macOS-produced fixtures and tests that round-trip them without private clipboard content or credentials.
- [ ] Document Windows 11 x64, C# + WinUI 3 + Windows App SDK + SQLite as the Windows V1 platform baseline.
- [ ] Keep JavaScript `transform(clip)`, KDBX, OneDrive folder sync and full product-capability parity as Windows contracts.
- [ ] Commit as `docs(windows): 冻结 Pastera 跨平台实现契约`.

## Acceptance Mapping

| Acceptance | Evidence |
| --- | --- |
| 当前 macOS 基线可用 | 660+ tests zero failures, `install_local.sh`, process check, manual clipboard matrix |
| 远端可恢复 | verified Git bundle, metadata snapshot, pushed baseline tag, matching remote SHA |
| GitHub 已独立 | `gh repo view` returns `isFork=false` and `parent=null` |
| 不再跟踪 Clipy upstream | `git remote -v` has no `upstream`; docs contain no active upstream workflow |
| 零 Clipy 生产依赖 | package URL/static check and resolved package graph contain no `github.com/Clipy/*` |
| 用户数据不丢失 | legacy import idempotency/backup/failure tests plus current SQLite/KDBX tests |
| 命名与行为独立 | categorized `rg` inventory has no obsolete Clipy product identifiers; retained matches are documented attribution/protocol compatibility |
| Windows 可接手 | baseline tag plus `contracts/`, `test-fixtures/`, and Windows porting entrypoint agree on versions and semantics |

Evidence Profile: `standard`.

## Risks, Rollback and Observation

- `Leave fork network` 永久且可能丢失 GitHub 平台元数据；执行前依赖 bundle、metadata snapshot 和 pushed tag，执行后逐项对比。
- GitHub fork 身份无法通过普通 git 回滚；若远端异常，停止代码清理并使用 bundle 在新的 standalone repository 恢复。
- 更新旧测试时可能把真实回归误判成旧契约；每项变化必须对应当前可见产品行为或已确认设计。
- Realm 删除过早会丢失极老版本用户数据；必须经过兼容发布观察门，不能与首次导入实现同提交删除。
- 快捷键依赖替换可能影响非 US 键盘、冲突检测和远程桌面；需要布局、注册失败和远程会话测试。
- 大规模 `CPY*` 改名容易制造无业务 diff；按域拆分，不与行为变化合并。
- Windows 契约冻结后如需改变同步版本，必须同时评估 macOS/Windows 双端兼容，不能创建 Windows 私有协议目录。

Rollback points:

1. Task 1 前：保留当前工作区，不做远端操作。
2. Task 2 后：可从 `pastera-pre-standalone` tag 和 bundle 恢复。
3. Task 3 后：fork 关系不可恢复，但代码/refs 可恢复到新 standalone repo。
4. Tasks 4-6：每个依赖或命名域独立 commit，可按 commit 回退，不回退用户数据文件。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-18-pastera-standalone.md`
- Plan Status: `design-confirmed-awaiting-implementation-confirmation`
- Evidence Profile: `standard`
- Story ID: `not-synced`
- Task IDs: `not-synced`
- ZenTao Sync Status: `not-synced`（本需求未要求 ZenTao）
- ZenTao Readback Evidence / Time: `none`
- Baseline Before Work: `d09b637` plus current uncommitted working tree
- Last Updated: `2026-07-18`

## Delivery Record

### Actual Implementation

- 已收敛当前 macOS 工作区：偏好设置契约更新为七页，UI-only 测试显式注入历史仓库和内存数据库，新脚本设置文案补齐全部支持语言。
- `PasteService` 新增可注入 pasteboard provider，生产默认仍使用系统剪贴板；真实 KDBX/AppKit 测试使用独立命名剪贴板，并固定 Secure Event Input 状态，消除全量并行污染。
- 当前功能源码、测试、KDBX store、脚本和 UI 改动作为独立化前 Pastera 基线统一收敛。
- 已在 `.build/repository-backups/` 生成并验证完整 Git bundle 和 GitHub 元数据快照，推送 `pastera-pre-standalone` annotated tag。
- GitHub 仓库已解除 fork 网络身份；文档改为独立 Pastera 产品边界，本地仅保留 `origin` remote。
- 已用 `SMAppService`、`NSMetadataQuery` 和本地键盘布局解析器替代 `LoginServiceKit`、`Screeen` 与直接 `Sauce` 调用。
- 快捷键与录制控件的广泛兼容面保留在 `pastera-app/Magnet` 3.5.1、`pastera-app/KeyHolder` 4.3.1 和 `pastera-app/Sauce` 2.5.1；生产依赖图不再引用 `github.com/Clipy/*`。
- 根许可证保留 Clipy 版权并新增 Pastera 贡献者归属，`NOTICE` 和依赖迁移记录明确历史来源、第三方许可与后续维护边界。
- 已从生产工程、Swift Package 解析结果和启动链路中移除 Realm；旧 `CPYClip`、`CPYClipData`、`CPYFolder`、`CPYSnippet` 模型与 Realm 扩展一并删除，当前 SQLite 数据链保持不变。
- 新增生产工程静态约束，阻止 Realm package、product 或源码引用回流。

### Plan Deviations

- 原计划描述为 serialized suite/change-count cleanup；实际根因还包含系统 Secure Event Input 状态，最终采用依赖注入隔离两个系统全局状态，覆盖更完整且不改变生产默认行为。
- `docs/verification/VERIFICATION.md` 的 Finder、Notes、Preview 和 OneDrive 双配置人工矩阵无法由本轮命令行验证代替，保留为人工验收项。
- 用户明确批准跳过原计划中的兼容发布观察期并直接删除 Realm，因此未交付一次性 `LegacyClipyImportService`；磁盘上已有 `.realm` 文件未被删除，仍可用于外部恢复。

### Impact

- Tasks 1–5 已完成 macOS 基线收敛、GitHub 独立化、Clipy 依赖迁移和 Realm 运行时移除；当前持久化事实源继续使用 SQLite，不改写现有用户数据。

### Verification

- `git diff --check`：通过。
- `jq empty pastera/Resources/Localizable.xcstrings`：通过。
- 偏好窗口聚焦回归：12 tests / 1 suite 通过；相关 KDBX 与粘贴聚焦回归通过。
- 默认全量并行回归：660 tests / 75 suites 通过，`** TEST SUCCEEDED **`。
- `./script/install_local.sh`：构建成功并安装到 `/Applications/Pastera.app`；运行进程 PID 54227，Bundle ID `com.pastera-app.Pastera.debug`，版本 `2.0.1-beta`，adhoc 签名。
- 远端身份：`isFork=false`、`parent=null`、public、默认分支 `develop`。
- 远端完整性：`develop` 和 `pastera-pre-standalone^{}` 均指向 `509223ce063b9bc9545460adf94a69ce69265f45`；2 branches、3 tags、2 releases、4 workflows、0 issues、1 pull request。
- 恢复证据：bundle SHA-256 `ec1a5b28e05c5494e02e42acd7dcd113e3f77a6e877986f6ae6c9102403f6f2c`，`git bundle verify` 通过。
- Task 4 聚焦回归：40 tests / 3 suites 通过；完整 macOS 回归：665 tests / 75 suites 通过，`** TEST SUCCEEDED **`。
- Swift Package 解析结果：`Magnet`、`KeyHolder`、`Sauce` 均来自 `https://github.com/pastera-app/*`；静态测试阻止 `github.com/Clipy/*` 回流。
- Realm 静态聚焦回归：15 tests / 1 suite 通过；完整 macOS 回归：666 tests / 75 suites 通过，`** TEST SUCCEEDED **`。
- `./script/install_local.sh`：Realm 删除后重新构建并安装成功；`/Applications/Pastera.app` 正常运行（PID 93102），`codesign --verify --deep --strict` 通过。
- `git diff --check` 与 Realm/旧导入源码扫描通过，生产工程和 `Package.resolved` 均无 Realm 运行时引用。

### Remaining Risks

- Finder/Notes/Preview 的图片与文件粘贴，以及 OneDrive 双配置人工矩阵尚未执行。
- Windows 最终冻结基线仍需 Tasks 4–7。
- GitHub fork 身份已解除且不可恢复；代码与 refs 可通过本地 bundle 和基线 tag 恢复。
- 仅持有未迁移 Realm 数据的极老版本用户无法再通过应用内导入；这是本轮直接删除决策的已接受风险，原 `.realm` 文件仍保留在磁盘。

### Follow-ups

- 开始 Task 6：按域盘点并清理遗留 `Clipy` / `CPY*` 产品命名，保留必要的历史归属和协议兼容标识。

### ZenTao Closeout

- 未执行，未回读。
