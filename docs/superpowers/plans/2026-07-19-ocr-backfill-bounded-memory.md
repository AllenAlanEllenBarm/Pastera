# OCR Backfill Bounded-Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将启动 OCR 回填改为延迟物化的单条拉取流程，使最多 200 条回填任务只在内存中保留轻量 ID，并且同时最多加载一条历史内容。

**Architecture:** Repository 只返回按 `updateAt DESC` 排序且尚无 OCR 记录的候选 ID，不再组装包含 BLOB 的候选数组。Indexer 保存轻量 ID 队列，每次调度只弹出一个 ID、加载一条内容、在 `autoreleasepool` 中完成索引，然后把下一条回填重新放到串行队列尾部，让实时 OCR 可以自然插队。

**Tech Stack:** Swift 6、AppKit、Vision、SQLiteData/GRDB、Swift Testing、Xcode 26.5

## Global Constraints

- 保持 macOS 13+ 和现有 SQLiteData 数据模型，不增加数据库表、迁移或第三方依赖。
- `limit: 200` 只限制一次启动最多尝试的候选数量，不允许再次表示同时物化的图片内容数量。
- 回填同时最多存在一个已加载的 `PasteboardContent`；候选 ID 数组可以常驻。
- 保持实时 OCR、按需 OCR、OCR 文本搜索、12 MiB 图片源上限和识别失败语义不变。
- 每处理一条回填任务后重新异步调度下一条，不用一个长循环连续占用 OCR utility 队列。
- 多次调用 `backfillMissingImageOCR` 不得启动并行回填消费者，也不得复制第二份待处理 ID 队列。
- 历史在排队后被删除、已被实时 OCR 完成或内容变为不可识别时必须安全跳过并继续下一条。
- 只修改 OCR 回填行为链，不重构剪贴板捕获、历史保留策略、同步或主菜单。

## Business Scope / Out of Scope

### In Scope

- 将 OCR 候选查询从完整 `PasteboardContent` 改为轻量历史 ID。
- 使用单消费者状态机逐条加载、识别、释放历史内容。
- 允许应用退出时中断回填，并在下次启动依靠“缺少 OCR 记录”的数据库事实继续。
- 补充候选查询、单条物化、重新调度、重复启动和已删除历史的回归测试。

### Out of Scope

- 不增加持久化 OCR job 表、失败重试次数、优先级字段或 checkpoint。
- 不修改 Vision 识别精度、语言列表或图片压缩算法。
- 不处理实时 OCR 队列的整体背压问题；该问题作为独立后续项保留。
- 不改变启动回填上限 `200`。

## File Structure

- `pastera/Sources/Repositories/PasteboardHistoryRepository.swift`：提供轻量候选 ID 查询，继续复用现有 `fetchContent(id:)` 完成单条物化。
- `pastera/Sources/Services/PasteboardHistoryOCRIndexer.swift`：维护回填状态并逐条调度，不持有候选内容数组。
- `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`：验证候选查询契约、单条加载边界、调度公平性和回填结果。

## Acceptance Mapping

| Acceptance | Evidence |
| --- | --- |
| 候选查询不返回 `PasteboardContent` 或图片 BLOB | 编译期接口变更；Repository 测试只断言 ID 顺序和数量 |
| 回填开始时不会一次加载全部候选内容 | spy repository 记录 `fetchContent` 调用；首次 scheduler step 后调用数必须为 1 |
| 每次 scheduler step 最多物化一条内容 | 可控 scheduler 逐步执行测试，调用序列从 0 → 1 → 2 |
| 实时 OCR 能排在后续回填之前执行 | 可控 scheduler 队列顺序测试，首条回填完成后实时任务先于下一条回填 |
| 重复调用不会创建两个消费者 | 连续调用两次回填，候选查询一次且没有重复 ID 处理 |
| 删除、已索引或不可识别候选会跳过并继续 | fake repository/fake recognizer 覆盖三条分支 |
| 现有 OCR 搜索和识别行为无回归 | 定向 `PasteboardHistoryRepositoryTests` 通过 |
| 项目行为无回归 | AGENTS.md 指定的完整 `xcodebuild ... clean test` 通过 |
| 内存峰值符合单条物化设计 | 可控 scheduler 证明每个调度轮次只调用一次 `fetchContent`；人工 Instruments 场景确认对象逐条释放，不宣称绝对字节上限 |

---

### Task 1: Replace eager OCR candidates with lightweight IDs

**Files:**
- Modify: `pastera/Sources/Repositories/PasteboardHistoryRepository.swift:147-152, 695-739`
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`

**Interfaces:**
- Consumes: existing `PasteboardHistory`, `PasteboardHistoryOCRText`, `fetchContent(id:)`
- Produces: `func fetchOCRIndexingCandidateIDs(limit: Int) -> [PasteboardHistory.ID]`

- [ ] **Step 1: Write failing repository tests for lightweight candidate selection**

Add tests that save text and image histories, pre-index one image, then assert only missing-image IDs are returned newest-first and limited exactly:

```swift
@Test
func ocrCandidateIDsAreLightweightMissingImagesNewestFirst() throws {
    let older = try #require(PasteboardContent(image: NSImage.create(with: .red, size: .init(width: 8, height: 8))))
    let newer = try #require(PasteboardContent(image: NSImage.create(with: .blue, size: .init(width: 8, height: 8))))
    let olderID = PasteboardHistory.ID(rawValue: "older-image")
    let newerID = PasteboardHistory.ID(rawValue: "newer-image")
    repository.save(id: olderID, content: older, updateAt: 1)
    repository.save(id: newerID, content: newer, updateAt: 2)

    #expect(repository.fetchOCRIndexingCandidateIDs(limit: 1) == [newerID])
    #expect(repository.fetchOCRIndexingCandidateIDs(limit: 10) == [newerID, olderID])
}
```

Keep a separate assertion that a history with an existing OCR row is excluded.

- [ ] **Step 2: Run the focused test and verify the new API is absent**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/PasteboardHistoryOCRSearchTests test
```

Expected: FAIL because `fetchOCRIndexingCandidateIDs(limit:)` is not defined.

- [ ] **Step 3: Replace the eager candidate API with an ID-only query**

Remove `PasteboardHistoryOCRIndexingCandidate` and replace the protocol method with:

```swift
func fetchOCRIndexingCandidateIDs(limit: Int) -> [PasteboardHistory.ID]
```

Implement the query so it selects history metadata only, excludes rows already present in `pasteboardHistoryOCRTexts`, preserves newest-first ordering, filters by the existing `canHaveOCRImageSource(pasteboardTypes:)` predicate, and stops after `limit` IDs. Do not call `fetchContent` inside this method and do not create `PasteboardContent` values.

- [ ] **Step 4: Run the focused repository tests**

Run the command from Step 2.

Expected: PASS; selected IDs are newest-first, limited, image-capable, and missing OCR.

---

### Task 2: Pull and materialize one backfill item per scheduler turn

**Files:**
- Modify: `pastera/Sources/Services/PasteboardHistoryOCRIndexer.swift:67-105, 173-213`
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift:995-1021`

**Interfaces:**
- Consumes: `fetchOCRIndexingCandidateIDs(limit:)`, `fetchContent(id:)`, existing `index(...)`
- Produces: one active backfill consumer with an ID queue and one scheduled item per turn

- [ ] **Step 1: Add a controllable scheduler test harness**

Use a FIFO scheduler that stores closures without running them immediately:

```swift
final class ControlledOCRScheduler {
    private(set) var pending = [() -> Void]()
    func schedule(_ work: @escaping () -> Void) { pending.append(work) }
    func runNext() {
        let work = pending.removeFirst()
        work()
    }
}
```

Use a repository spy that returns candidate IDs and records every `fetchContent(id:)` call.

- [ ] **Step 2: Write failing tests for bounded materialization and rescheduling**

Cover these exact transitions:

```swift
indexer.backfillMissingImageOCR(limit: 200)
#expect(repository.fetchedContentIDs.isEmpty)

scheduler.runNext()
#expect(repository.fetchedContentIDs.count == 1)
#expect(scheduler.pending.count == 1)

scheduler.runNext()
#expect(repository.fetchedContentIDs.count == 2)
```

Also test that calling `backfillMissingImageOCR(limit:)` twice before completion does not query or process candidates twice.

- [ ] **Step 3: Run the focused test and verify eager processing fails the contract**

Run the focused command from Task 1.

Expected: FAIL because the existing implementation fetches complete candidates and processes them in one scheduler turn.

- [ ] **Step 4: Implement the single-consumer pull state machine**

Add queue-owned state accessed only on the indexer's serial scheduler:

```swift
private var backfillIDs = ArraySlice<PasteboardHistory.ID>()
private var isBackfilling = false
```

`backfillMissingImageOCR(limit:)` schedules initialization. Initialization returns immediately when `isBackfilling` is true; otherwise it loads only IDs, marks the consumer active, and schedules `processNextBackfillItem()` as a new scheduler turn.

`processNextBackfillItem()` removes one ID, loads content inside `autoreleasepool`, rechecks whether OCR now exists, invokes existing `index(...)` when needed, releases local content, and schedules the next item at the queue tail. When no IDs remain it clears `isBackfilling` and releases the slice storage.

Do not recursively call `processNextBackfillItem()` synchronously and do not use a loop that processes multiple contents in one closure.

- [ ] **Step 5: Test skip and interleaving behavior**

Add tests proving:

- a deleted candidate (`fetchContent == nil`) schedules the next candidate;
- a candidate indexed after ID discovery is skipped;
- an `enqueueIndexing` call inserted between two scheduler turns executes before the second backfill item;
- finishing clears state so a later explicit backfill call can start again.

- [ ] **Step 6: Run all OCR/repository tests**

Run:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:pasteraTests/PasteboardHistoryOCRSearchTests \
  -only-testing:pasteraTests/PasteboardHistoryRepositoryTests test
```

Expected: PASS with no OCR, search, retention, or repository regressions.

---

### Task 3: Verify the memory boundary and application regression surface

**Files:**
- Test: `pasteraTests/Repositories/PasteboardHistoryRepositoryTests.swift`
- Reference: `docs/verification/VERIFICATION.md`

**Interfaces:**
- Consumes: completed ID-only query and pull state machine
- Produces: repeatable scheduling evidence plus runtime allocation evidence that content materialization is bounded at one item

- [ ] **Step 1: Strengthen the per-turn materialization regression test**

Execute three scheduler turns independently and assert that each turn increases the repository's `fetchContent` call count by exactly one. Also assert that merely discovering all candidate IDs does not call `fetchContent`:

```swift
#expect(repository.fetchedContentIDs.isEmpty)
scheduler.runNext()
#expect(repository.fetchedContentIDs.count == 1)
scheduler.runNext()
#expect(repository.fetchedContentIDs.count == 2)
scheduler.runNext()
#expect(repository.fetchedContentIDs.count == 3)
```

Do not add a reference wrapper or production-only lifetime callback solely for this test. Swift value lifetime and Vision transient allocations are verified by Instruments in Step 3.

- [ ] **Step 2: Run the complete project regression command**

Run the exact default command from `AGENTS.md`:

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

Expected: PASS. If unrelated user-owned changes fail, record the exact failing test and keep the OCR focused suite result separate.

- [ ] **Step 3: Inspect runtime allocation behavior**

With a development database containing multiple missing image OCR rows, launch under Instruments Allocations and confirm that `PasteboardContent`, image `Data`, `CGImage`, and Vision allocations rise and fall per item rather than accumulating for the full 200-item budget. Record observed peak and test fixture size in this plan's Delivery Record; do not claim a fixed byte ceiling because Vision owns additional transient buffers.

- [ ] **Step 4: Run static closeout checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the planned OCR files, tests, this plan, and pre-existing user-owned changes appear.

## Risks, Rollback and Observation

- **Risk:** `ArraySlice` can retain the original ID array after processing. **Mitigation:** replace it with an empty slice when the run finishes; IDs are lightweight, but the ownership boundary remains explicit.
- **Risk:** a second backfill call during an active run could lose a newer request. **Mitigation:** startup has one fixed budget and repeated active calls intentionally coalesce; a call after completion starts a fresh query.
- **Risk:** OCR failure remains eligible next launch. **Mitigation:** preserve current retry-on-next-launch behavior; persistent failure state is outside scope.
- **Risk:** queued realtime OCR may still retain large content. **Mitigation:** unchanged and tracked as a separate resource issue; this plan only proves backfill boundedness.
- **Rollback:** restore `fetchOCRIndexingCandidates(limit:)` and the single-closure loop; no schema or persisted state needs rollback.
- **Observation:** compare cold-start memory for the same fixture before and after; watch peak resident memory, Vision allocation lifetime, OCR completion count, and database errors.

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-19-ocr-backfill-bounded-memory.md`
- Plan Status: implementation-complete / manual-instruments-pending
- Evidence Profile: `standard`
- Story ID: not-requested
- Task IDs: not-requested; Superpowers Tasks 1-3 form one bounded-memory delivery unit
- ZenTao Sync Status: not-synced (not requested)
- ZenTao Readback Evidence / Time: none
- Last Updated: 2026-07-19 Asia/Shanghai

## Delivery Record

### Actual Implementation

- Replaced `fetchOCRIndexingCandidates(limit:)` and its content-bearing candidate model with `fetchOCRIndexingCandidateIDs(limit:)`.
- Candidate discovery now reads history metadata and OCR IDs only; it no longer fetches history assets or creates `PasteboardContent` values.
- Added an OCR backfill single-consumer state machine backed by a lightweight `ArraySlice<PasteboardHistory.ID>`.
- Each scheduler turn pops one ID, rechecks existing OCR state, fetches at most one history content, indexes it inside `autoreleasepool`, and schedules the next turn at the queue tail.
- Repeated backfill calls coalesce while one consumer is active; finishing clears the queue and active flag.
- Added repository and controlled-scheduler regression coverage for ordering, limit handling, zero limit, indexed-history exclusion, one-item-per-turn materialization, and duplicate-start coalescing.

### Plan Deviations

- No architecture or scope deviation.
- The planned peak-live-content deinit counter was intentionally replaced during plan self-review with per-scheduler-turn `fetchContent` assertions because `PasteboardContent` is a value type and a production lifetime wrapper would exist only for test convenience.

### Impact

- Impact is limited to OCR candidate selection, startup backfill scheduling, the repository protocol default, and related tests.
- No database schema, migration, OCR search contract, Vision settings, clipboard capture behavior, or startup budget changed.

### Verification

- Design confirmed by the user on 2026-07-19.
- TDD red: focused build failed only because `fetchOCRIndexingCandidateIDs(limit:)` did not exist.
- TDD green: `PasteboardHistoryOCRSearchTests` passed 12 tests after the ID-only repository change.
- TDD red: controlled scheduler tests failed because the eager implementation fetched all three contents in one turn and duplicate starts queried twice.
- TDD green: `PasteboardHistoryOCRSearchTests` passed 14 tests after the pull state machine implementation.
- Focused regression: `PasteboardHistoryRepositoryTests` plus `PasteboardHistoryOCRSearchTests` passed 33 tests in 2 suites.
- Full regression: the `AGENTS.md` `xcodebuild ... clean test` command passed 680 tests in 75 suites with exit code 0.
- Static checks: `git diff --check` passed; no references to the removed eager candidate API remain.
- Local installation: `./script/install_local.sh` completed with `BUILD SUCCEEDED` and replaced `/Applications/Pastera.app`.
- Runtime launch check: PID `26774` is running `/Applications/Pastera.app/Contents/MacOS/Pastera`.
- Runtime Instruments allocation capture was not performed because no controlled large missing-OCR fixture was prepared in this implementation-only run.

### Remaining Risks

- Live OCR queue backpressure remains outside this plan.
- A real cold-start Instruments comparison with a large missing-OCR fixture remains a manual performance acceptance item.
- Vision owns transient buffers, so automated scheduler tests prove one-content materialization but do not establish an absolute resident-memory ceiling.

### Follow-ups

- Consider a separate bounded realtime OCR queue only after measuring post-fix behavior.
- Run Allocations against identical pre/post fixtures if an absolute peak-memory number is required.

### ZenTao Closeout

- Not requested; no ZenTao write or readback performed.
