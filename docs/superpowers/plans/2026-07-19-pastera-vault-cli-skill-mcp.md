# Pastera Vault CLI, Skill and MCP V1 Plan

> **Current gate:** The product and security design is approved. This file is the repository's unique design/plan record for this requirement. A detailed checkbox implementation sequence will be added to this same file only after written-spec review.

**Goal:** Provide a local Pastera password-vault CLI, a shared Agent Skill, and a local stdio MCP server for Codex App and Claude Code, with one application-level authorization, bounded unattended access, no plaintext-password tool output, and measurable performance/resource limits.

**Architecture:** Pastera remains the only KDBX owner. Codex, Claude Code, and the manual CLI use separate Pastera-signed adapters that send bounded requests to an in-process `PasteraVaultBroker` over a user-private Unix-domain socket. The broker verifies the peer, enforces per-application grants, serializes all Keychain/KDBX work through the existing store boundary, and performs or authorizes secret-use actions without exposing a generic reveal API.

**Tech Stack:** Swift 6, AppKit, Foundation, CryptoKit, Security, LocalAuthentication, KDBXKit, the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) pinned to `0.12.1`, Swift Testing, Xcode 26.5, local stdio MCP, and a local Unix-domain socket. The official SDK supports Swift 6, macOS 13+, and `StdioTransport`; no HTTP MCP listener or additional service-lifecycle dependency is needed for V1.

## Global Constraints

- Preserve Pastera as the only component that opens, decrypts, merges, and saves `PasteraVault.kdbx`.
- Do not add an MCP tool, CLI JSON field, log path, or error detail that returns a plaintext password.
- Do not expose password-vault notes to agents in V1 because notes may contain unstructured secrets.
- Keep the existing KDBX format, OneDrive path, conflict semantics, Keychain quick-unlock path, main-menu vault UI, and interactive `LAContext` behavior compatible.
- Codex, Claude Code, and the manual CLI must have distinct signed client identities and independent grants.
- Initial authorization lasts seven days; successful sensitive actions slide the idle expiry by seven days, but no grant may exceed 30 days since its last macOS authentication.
- Status, search, metadata reads, MCP initialization, retries, failures, and unused ticket creation must never extend a grant.
- Unattended unlock material must be device-local, non-synchronizable, unavailable before the user first unlocks macOS after boot, and deleted when no valid external grant remains.
- V1 is local-macOS only. Remote Codex tasks, remote Claude sessions, cloud-hosted MCP, TCP listeners, and cross-device grants are out of scope.
- Do not add a launchd daemon. The signed adapter may launch Pastera once when needed, while the broker remains part of the existing menu-bar app process.
- Do not silently weaken Codex or Claude permission/sandbox policy. Pastera authorization is application trust; host MCP/shell approvals remain independent unless the user explicitly installs a narrow host allow rule.
- All KDBX, Keychain, peer-verification, and IPC work runs off the main thread and reuses the current serial password-vault store boundary.
- Preserve unrelated worktree changes and the untracked `.codex/config.toml` and `.superpowers/` content.

---

## Business Scope / Out of Scope

### In Scope

- A manual `pastera` CLI for integration management, vault status/search/metadata, direct paste, secure clipboard copy, and controlled secret injection.
- A Codex-specific signed stdio MCP adapter and a Claude-specific signed stdio MCP adapter, shipped inside `Pastera.app`.
- One canonical `pastera-vault` Agent Skill, installed into the current Codex and Claude skill locations with host-specific metadata only where required.
- A Pastera Agent Integration preference page for install/status/uninstall, initial authorization, expiry/renewal display, audit summary, and immediate revocation.
- Read-only agent discovery of entry ID, folder ID/name, title, website, username, and update time.
- Direct paste of username or password into the current foreground target without returning the value to the model.
- Command secret injection through `stdin` or an inherited file descriptor using a one-use ticket.
- Per-application grants, seven-day sliding expiry, 30-day hard expiry, device-local unattended recovery, rate limits, replay protection, and redacted audit events.
- Focused unit/integration/security/performance tests plus real Codex App and Claude Code local-session acceptance.

### Out of Scope

- Creating, editing, moving, reordering, or deleting password-vault entries/folders through CLI or MCP.
- Returning a password, note, raw KDBX record, master password, unlock key, or decrypted database snapshot to an agent.
- Bulk export, backup, import, password generation, TOTP, passkeys, attachments, browser extensions, or form-field discovery.
- Environment-variable, command-line-argument, or plaintext temporary-file secret injection.
- Arbitrary command execution inside the Pastera process or broker. Agent commands remain children of the signed adapter so the host's process context and approvals are not bypassed.
- Marketplace/plugin publication, remote HTTP MCP, OAuth, team/organization grants, Windows support, or Linux support.
- Automatically renewing a grant beyond its 30-day macOS-authentication hard limit.
- Protecting secrets after an approved client, the current macOS user session, administrator/root, or the intended target process is fully compromised.

## Current System Facts

- `KDBXPasswordVaultStore` already keeps a decrypted KDBX snapshot and raw-key unlock data in memory, serializes file access, preserves KDBX history, merges external changes, and auto-locks on the configured timeout, sleep, session resignation, and termination.
- `VaultUnlockKeyStore` already stores a device-local raw KDBX key with `.userPresence`; that interactive quick-unlock item remains unchanged.
- `PasswordVaultUIController` already owns a serial store queue, `LAContext.deviceOwnerAuthentication` authorization, direct paste, secure clipboard copy, and snapshot refresh.
- `SecureClipboardService` already uses concealed/transient pasteboard types, suppresses Pastera history capture, and conditionally clears an unchanged value after 60 seconds.
- Codex App/CLI/IDE support local stdio MCP and share Codex MCP configuration; Claude Code supports local stdio MCP and user-scoped skills. The V1 installer uses their official CLI registration commands instead of hand-editing unrelated config.

## Architecture and Component Boundaries

### 1. Pastera Vault Broker

`PasteraVaultBroker` lives in the existing app process and is the only new runtime owner of agent requests. It:

- creates `~/Library/Application Support/Pastera/Agent/v1/broker.sock` inside a `0700` directory and sets the socket to `0600`;
- rejects symlinked/non-socket paths and refuses to replace an unexpected existing filesystem object;
- verifies the peer UID, peer PID, executable real path, code validity, signing identifier, and expected adapter identity before protocol negotiation;
- derives the effective client identity from the verified executable, never from a caller-provided `client` field;
- negotiates a versioned request/response protocol and connection nonce;
- dispatches authorized work to the existing password-vault store queue;
- owns grants, unattended-unlock availability, rate limits, one-use tickets, and redacted audit events;
- captures the current foreground paste target before any Pastera activation and keeps broker launches background-only, so `vault_paste` cannot accidentally paste back into Pastera;
- closes idle or malformed connections and erases request-local secret buffers when a request completes or is cancelled.

Pastera does not listen on TCP, advertise Bonjour, or accept remote connections.

### 2. Shared Protocol Module

A small source module is compiled into the app and all three helper products. It contains only:

- protocol version constants;
- client-kind constants derived from verified signing identifiers;
- bounded Codable request/response types;
- stable error codes;
- search pagination and metadata DTOs;
- one-use ticket and injection-mode DTOs;
- frame-size, timeout, and retry limits.

It does not import KDBXKit, AppKit UI, `PasswordVaultStore`, Keychain implementations, or MCP. This prevents helper targets from acquiring direct database access.

### 3. Signed Client Products

Pastera ships three independently identifiable helpers inside its app bundle:

- `PasteraCodexMCP`: stdio MCP server and Codex ticket-exec mode;
- `PasteraClaudeMCP`: stdio MCP server and Claude ticket-exec mode;
- `pastera`: manual CLI with its own grant and human-only secure-copy command.

The two agent adapters share implementation sources but have separate product/signing identifiers. The broker validates the connected binary against the current installed Pastera bundle. Production Developer ID builds preserve grants across ordinary upgrades when the designated requirement remains stable. Ad-hoc/local builds also require the expected installed helper path and exact current bundle code identity; replacing the local build may invalidate grants.

### 4. MCP Layer

The Codex and Claude products use MCP Swift SDK `0.12.1` and `StdioTransport`. They expose only the five V1 tools defined below. The MCP layer parses bounded schemas, invokes the shared broker client, maps stable errors to MCP structured results, and writes protocol traffic only to stdin/stdout. Diagnostic logging uses redacted stderr/OSLog and never includes arguments or results containing sensitive values.

### 5. Agent Skill

One canonical `pastera-vault` skill defines when to use the tools, how to search narrowly, when to prefer direct paste, how to redeem a command ticket, and which commands are forbidden because they can echo secrets. Host packages may add Codex UI metadata, but the workflow and security rules remain single-source.

### 6. Integration Preferences and Installer

Pastera adds an Agent Integration preference page with one row each for Codex, Claude Code, and manual CLI. Each row shows:

- installed/not installed;
- detected executable/config state;
- authorized/not authorized;
- idle expiry and 30-day hard expiry;
- last successful sensitive action time;
- install/update, authorize/reauthorize, and revoke actions.

The installer invokes current official commands when their clients are present:

```bash
codex mcp add pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP
claude mcp add --transport stdio --scope user pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraClaudeMCP
```

It installs the canonical skill to `$HOME/.agents/skills/pastera-vault` for Codex and `$HOME/.claude/skills/pastera-vault` for Claude Code. Pastera records an ownership manifest and content digest. It updates only an unchanged Pastera-owned installation; if the user modified the installed skill, it reports a conflict instead of overwriting it. Uninstall removes only entries and skill content owned by Pastera.

The integration page may offer narrow, host-specific permission snippets for `pastera-vault` MCP tools, but applying them is a separate explicit choice. It never turns on a global bypass mode or grants a broad shell wildcard. Without that choice, Codex and Claude retain their normal tool/shell approval behavior even while the Pastera grant remains valid.

## Authorization and Unattended Unlock

### Grant State

Each external client grant stores:

- verified client kind and signing requirement;
- allowed scopes;
- `authorizedAt` and `lastMacOSAuthenticationAt`;
- `lastSensitiveUseAt`;
- `idleExpiresAt`;
- `absoluteExpiresAt`;
- revoked state and revocation reason;
- protocol generation.

The effective expiry is:

```text
min(lastSensitiveUseAt + 7 days, lastMacOSAuthenticationAt + 30 days)
```

Initial authorization sets `lastSensitiveUseAt` to the authorization time. A successful external secret paste or completed ticket injection extends only the calling client's idle expiry. A successful interactive Pastera copy, paste, or password edit extends all currently valid external grants, each still bounded by its own 30-day hard expiry.

The following never renew a grant:

- status, search, or metadata reads;
- MCP initialization, ping, connection keepalive, or tool discovery;
- ticket creation without successful redemption;
- cancelled, failed, timed-out, rate-limited, or retried requests.

Revocation, signing-identity mismatch, protocol-generation invalidation, or hard expiry wins immediately over a sliding idle expiry.

### First Authorization

The first valid request creates one deduplicated pending request for that verified client and returns `AUTHORIZATION_REQUIRED`. Pastera shows the application identity, scopes, seven-day idle period, 30-day hard limit, and unattended-access warning. The user performs one `LAContext.deviceOwnerAuthentication` check. Repeated calls while the request is pending return the same state and never create repeated dialogs.

Authorization succeeds only while the password database is unlocked. If it is locked, the user completes the existing interactive quick-unlock or master-password path first. Pastera then stores the client grant and the raw KDBX key in a separate automation Keychain item protected as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`, and accessible only to the installed Pastera application boundary.

The automation item never contains the master password. The existing `.userPresence` quick-unlock item remains intact and separate.

### Cold Recovery

After Pastera auto-locks, restarts, or the Mac locks/unlocks, a valid external request may use the automation Keychain item to rebuild `UnlockData(rawKeyData:)` and reopen the KDBX snapshot without another Pastera prompt. After a full system restart, macOS must first be unlocked normally before `AfterFirstUnlock` material is available.

If the automation item is missing, corrupt, inaccessible, or cannot decrypt the current KDBX file, the broker deletes it, locks the vault, invalidates external grants, returns a stable non-retryable error, and requires a fresh authorization. It never loops through silent unlock attempts.

When no valid external grants remain, Pastera deletes the automation item and locks any broker-originated session state. Manual Pastera quick unlock remains available through the existing interactive item.

## Threat Model and Security Controls

### Protected Against in V1

- an unsigned or unexpected local process connecting to the broker socket;
- one external client borrowing another client's grant by declaring a false client name;
- accidental plaintext inclusion in MCP tool output, CLI JSON, logs, audit events, temporary files, environment variables, or process arguments;
- unbounded list output, brute-force request loops, ticket replay, cross-connection replay, malformed frames, and oversized messages;
- unintended KDBX concurrent access from multiple helpers;
- stale grants after explicit revocation, hard expiry, or signing identity change;
- accidental Pastera clipboard-history capture and stale secure clipboard content.

### Explicitly Accepted Risk

One authorization intentionally trusts the approved client for up to seven idle days and at most 30 absolute days. A compromised approved Codex/Claude process can request permitted secret actions during that period. V1 does not claim to protect against administrator/root, a fully compromised current-user session, a compromised Pastera process, or a target program/command that intentionally reveals what it receives.

### Transport and Replay Controls

- Broker directory `0700`; socket `0600`; same effective UID required.
- Peer PID and executable identity captured at connection acceptance and validated before requests.
- Connection nonce plus monotonically increasing request ID; duplicates and out-of-order replays are rejected.
- Secret-bearing ticket redemption uses a per-connection CryptoKit session key and authenticated encryption.
- Maximum frame size is `64 KiB`; maximum MCP structured response is `32 KiB`.
- Connection setup timeout is three seconds; ordinary broker requests five seconds; cold KDBX recovery ten seconds.

### Secret Lifetime

- Search and metadata operations never load password values.
- Direct paste loads one password, passes it to the existing Pastera paste/secure-clipboard path, and releases request-local references immediately.
- Command injection returns a random ticket first. On redemption, only the verified matching adapter receives an authenticated-encrypted payload and writes it to stdin or the requested inherited file descriptor.
- Tickets expire after 30 seconds, are bound to client, entry, field, and injection mode, and are deleted atomically on first redemption.
- Swift/KDBXKit cannot guarantee zeroization of every copied `String`; V1 minimizes scope and lifetime, avoids caches, and adds leak-oriented tests rather than claiming impossible complete memory erasure.

## External Contracts

### MCP Tools

| Tool | Input | Output | Renewal |
| --- | --- | --- | --- |
| `vault_status` | none | installed/authorized state, client-local expiry, vault readiness, protocol version | never |
| `vault_search` | optional `query`, optional `folder_id`, `limit` default `20` max `50`, optional opaque `cursor` | bounded entry metadata page and next cursor | never |
| `vault_get` | `entry_id` | entry ID, folder metadata, title, website, username, updated time | never |
| `vault_paste` | `entry_id`, `field = username | password` | success/failure only | after successful paste |
| `vault_prepare_exec` | `entry_id`, `field = username | password`, `mode = stdin | fd` | random one-use ticket, expiry, adapter command template | only after later successful redemption |

`vault_search` and `vault_get` never return password or note. Website values may be normalized for display but are not fetched. No MCP resources, prompts, sampling, networking, or elicitation are required for V1 authorization; Pastera owns the native authorization UI.

Tool descriptors mark `vault_status`, `vault_search`, and `vault_get` as read-only/non-destructive. `vault_paste` and `vault_prepare_exec` are marked non-read-only because they enable an external action, even though they do not modify the vault. Descriptors must not mislabel secret-use actions merely to suppress host approvals.

### CLI Commands

| Command | Purpose |
| --- | --- |
| `pastera integration install codex|claude` | Register the owned MCP and skill integration using official client commands. |
| `pastera integration status [codex|claude] [--json]` | Read installed/authorized/version status without extending grants. |
| `pastera integration uninstall codex|claude` | Remove only Pastera-owned configuration and skill content. |
| `pastera vault status [--json]` | Manual-client vault status. |
| `pastera vault search [query] [--folder ID] [--limit N] [--cursor VALUE] [--json]` | Bounded metadata search. |
| `pastera vault get ID [--json]` | Metadata only. |
| `pastera vault paste ID --field username|password` | Direct paste; never prints the value. |
| `pastera vault copy ID --field username|password` | Manual CLI grant only; secure clipboard, 60-second conditional clear. |
| `<agent-adapter> exec --ticket T --stdin -- command ...` | Redeem into child stdin. |
| `<agent-adapter> exec --ticket T --fd N -- command ...` | Redeem into inherited descriptor `N`. |

All JSON output uses a stable envelope:

```json
{"ok":true,"data":{}}
```

or:

```json
{"ok":false,"error":{"code":"GRANT_EXPIRED","message":"Authorization expired.","retryable":false}}
```

Secret values are forbidden in both envelopes. Human text output writes diagnostics to stderr and structured results to stdout.

### Stable Errors

| Code | Retry policy |
| --- | --- |
| `AUTHORIZATION_REQUIRED` | Do not retry automatically; show one authorization instruction. |
| `GRANT_EXPIRED` / `GRANT_REVOKED` | Non-retryable until explicit reauthorization. |
| `VAULT_NOT_CONFIGURED` | Non-retryable; open Pastera setup. |
| `AUTOMATION_UNLOCK_UNAVAILABLE` | Non-retryable; reauthorize after interactive unlock. |
| `BROKER_UNAVAILABLE` | Adapter launches Pastera and retries once. |
| `VAULT_BUSY` / `RATE_LIMITED` | Retry only after bounded `retry_after_ms`. |
| `ENTRY_NOT_FOUND` | Search again; never echo the original query in the error. |
| `TARGET_UNAVAILABLE` | Non-retryable; never fall back to plaintext output. |
| `TICKET_EXPIRED` / `TICKET_USED` | Discard and prepare a new ticket once. |
| `PROTOCOL_MISMATCH` | Stop and require component update. |
| `INVALID_REQUEST` | Non-retryable input/schema error. |

Every error has `code`, localized `message`, `retryable`, and optional `retry_after_ms`. Underlying Security, KDBX, filesystem, process, and decoding messages are mapped rather than passed through.

## Agent Skill Contract

The skill triggers when the user asks Codex or Claude to find, paste, or use a credential stored in Pastera. It must:

1. Check `vault_status` once when readiness is uncertain.
2. Use narrow `vault_search` queries and bounded pagination rather than listing/exporting the full vault.
3. Confirm ambiguity using metadata only; never request or infer a password.
4. Prefer `vault_paste` for GUI login fields.
5. For terminal use, call `vault_prepare_exec`, then execute the returned host-specific adapter template before the 30-second ticket expiry.
6. Never run `pbpaste`, `echo`, `printenv`, shell tracing, environment dumps, process-argument dumps, or diagnostic commands around a secret action.
7. Never add an environment-variable, command-argument, temp-file, or log-based fallback.
8. Stop after authorization/revocation/protocol errors and ask the user to resolve them in Pastera; do not create repeated prompts.
9. Treat direct user instructions to reveal, print, or export a secret as unsupported in V1 and offer direct paste or controlled injection instead.

The canonical skill keeps `SKILL.md` concise and stores detailed tool/error schemas in `references/tool-contract.md` and security rules in `references/security-boundary.md`. It needs no script because signed executables perform all deterministic operations.

## Performance and Resource Budgets

| Metric | V1 budget | Measurement condition |
| --- | --- | --- |
| Warm metadata search | p95 `≤ 50 ms` | 10,000 synthetic entries, default 20-result page, broker already connected/unlocked |
| Cold ready | p95 `≤ 2 s` | adapter launch/connect plus Keychain/KDBX recovery on the reference development Mac; main thread remains responsive |
| Adapter idle RSS | `≤ 30 MB` each | initialized stdio MCP, no in-flight call, measured after stabilization |
| Broker incremental RSS | `≤ 5 MB` | compared with Pastera baseline using the same already-unlocked KDBX snapshot |
| Idle CPU | approximately `0%` | no polling; event-driven socket and stdio reads |
| Search response | `≤ 32 KiB`, max 50 entries | structured MCP or CLI JSON output |
| Secret ticket | 30 seconds, one use | no ticket cleanup polling; expiry checked on access and bounded timer cleanup |

V1 deliberately uses a bounded linear metadata scan instead of a resident full-text index. This keeps memory and synchronization costs low. A measured failure of the 10,000-entry target is evidence for a later metadata-only index, not permission to cache password values.

The MCP adapters are long-lived only while their host session owns stdin. EOF or SIGTERM causes graceful shutdown and clears connection state. The broker remains part of the already-running Pastera process and adds no launchd service.

## Rate Limits and Audit

Initial per-client limits:

- metadata calls: 60 per minute;
- direct secret actions: 10 per minute;
- ticket creation: 10 per minute;
- failed signature/protocol handshakes: connection rejected immediately without creating an authorization request.

Audit stores only client kind, action category, a device-local keyed digest of the entry UUID, timestamp, result code, and latency bucket. It excludes title, folder name, website, username, note, query, ticket, command, arguments, password, raw error, and filesystem path. Local audit retention is bounded to 1,000 events or 30 days, whichever is smaller. V1 uploads no vault telemetry.

## Planned File and Target Map

### App Target

- Create `pastera/Sources/Services/VaultAgentBroker.swift` — socket lifecycle, version handshake, request dispatch, and Pastera launch readiness.
- Create `pastera/Sources/Services/VaultAgentPeerVerifier.swift` — UID/PID/path/code-signature verification and verified client-kind derivation.
- Create `pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift` — grant state, seven-day sliding expiry, 30-day hard expiry, renewal and revocation.
- Create `pastera/Sources/Services/VaultAgentGrantStore.swift` — device-local grant persistence without secrets in defaults/logs.
- Create `pastera/Sources/Services/VaultAutomationUnlockKeyStore.swift` — separate `AfterFirstUnlockThisDeviceOnly` raw-key item and deletion lifecycle.
- Create `pastera/Sources/Services/VaultAgentTicketStore.swift` — one-use, client-bound, 30-second tickets.
- Create `pastera/Sources/Services/VaultAgentRateLimiter.swift` — bounded per-client windows.
- Create `pastera/Sources/Services/VaultAgentAuditLogger.swift` — redacted bounded audit events and local metrics.
- Modify `pastera/Sources/Services/PasswordVaultStore.swift` — expose narrow automation-unlock lifecycle operations without exposing raw keys to callers.
- Modify `pastera/Sources/Services/KDBXPasswordVaultStore.swift` — create/recover the separate automation key inside the store boundary and preserve existing interactive quick unlock.
- Modify `pastera/Sources/Managers/PasswordVaultUIController.swift` — broker-facing async operations and renewal events through the existing queue.
- Modify `pastera/Sources/AppDelegate.swift` — start/stop the broker with the app lifecycle and feature setting.
- Create `pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift` — integration status, install, authorize, expiry, revoke, and uninstall UI.
- Modify `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift` and `pastera/Sources/Preferences/CPYPreferencesWindowController.swift` — register and navigate the Agent Integration page.
- Modify `pastera/Resources/Localizable.xcstrings` — localize integration, authorization, expiry, security, and error copy.

### Shared and Helper Targets

- Create `pastera-agent/Sources/PasteraAgentProtocol/` — shared bounded protocol and DTOs.
- Create `pastera-agent/Sources/PasteraAgentClient/` — Unix-socket client, handshake, encrypted ticket redemption, and stable error mapping.
- Create `pastera-agent/Sources/PasteraMCP/` — MCP Swift SDK tool descriptors and stdio handlers.
- Create `pastera-agent/Sources/PasteraCodexMCP/main.swift` — Codex client identity and MCP/exec entrypoint.
- Create `pastera-agent/Sources/PasteraClaudeMCP/main.swift` — Claude client identity and MCP/exec entrypoint.
- Create `pastera-agent/Sources/PasteraCLI/` — manual CLI parsing, text/JSON rendering, copy/paste, and integration subcommands.
- Modify `pastera.xcodeproj/project.pbxproj` — add the official MCP package and the three signed helper targets/products, embed helpers, and define target memberships/signing identifiers.

### Skill and Installer Assets

- Create `integrations/pastera-vault/SKILL.md` — canonical cross-host workflow.
- Create `integrations/pastera-vault/references/tool-contract.md` — MCP/CLI schemas and error handling.
- Create `integrations/pastera-vault/references/security-boundary.md` — no-reveal rules and safe-use constraints.
- Create `integrations/pastera-vault/agents/openai.yaml` — Codex UI metadata generated from the canonical skill.
- Create an owned-install manifest under the app's integration resources; do not add credentials or machine-local config to the repository.

### Tests

- Create `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`.
- Create `pasteraTests/VaultAgentBrokerTests.swift`.
- Create `pasteraTests/VaultAgentPeerVerifierTests.swift`.
- Create `pasteraTests/VaultAgentTicketStoreTests.swift`.
- Create `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`.
- Create `pasteraTests/VaultAgentLeakRegressionTests.swift`.
- Create `pasteraTests/VaultAgentPerformanceTests.swift`.
- Create helper-target tests for MCP schemas, stdio lifecycle, CLI JSON/text envelopes, and adapter ticket execution.
- Extend `pasteraTests/PasswordVaultStoreTests.swift`, `pasteraTests/PasswordVaultMenuTests.swift`, and `pasteraTests/SecureClipboardServiceTests.swift` for compatibility and integration renewal behavior.

## Implementation Slice Outline

The detailed TDD checklist will expand these slices in this same file after written-spec review:

1. Freeze the shared protocol, stable errors, metadata schema, and host-independent client API.
2. Implement grants, sliding/hard expiry, unattended Keychain recovery, revocation, tickets, rate limits, and redacted audit primitives.
3. Implement and harden the broker socket, peer verification, replay controls, app lifecycle, and existing-store integration.
4. Add signed manual/Codex/Claude helper targets, stdio MCP tools, CLI contracts, and controlled secret delivery.
5. Add the canonical Agent Skill and reversible Codex/Claude installer/status/uninstall flows.
6. Add the Pastera Agent Integration preference page and first-authorization/renewal/revocation UX.
7. Complete security, leak, concurrency, performance/resource, compatibility, installation, and real-host acceptance gates.

## Acceptance Mapping

| Acceptance | Automated evidence | Manual/host evidence |
| --- | --- | --- |
| One application authorization | deterministic-clock policy tests; pending-request dedup tests; independent client-grant tests | Codex and Claude each authorize once; new tasks and MCP restarts do not prompt again |
| Seven-day sliding and 30-day hard limit | boundary tests before/at/after expiry; successful-sensitive-action renewal tests; status/search/failure negative tests | preference page shows idle/hard expiries; reauthorization required at hard limit |
| Cold unattended recovery | temporary KDBX + automation Keychain test double; app/store restart tests; missing/corrupt key invalidation | Pastera relaunch and Mac lock/unlock remain unattended; post-boot access works after normal macOS login |
| App identity isolation | peer UID/PID/path/signing tests; forged identifier/path/hash rejection; Codex/Claude grant separation | revoking Codex does not revoke Claude; replaced helper is rejected |
| No plaintext model output | schema tests; sentinel-secret scans across MCP content, CLI stdout/stderr, logs, audit, args, env, temp directory, and errors | inspect captured Codex/Claude transcripts and Pastera unified logs |
| Direct paste and command injection | named pasteboard tests; target restoration tests; stdin/fd child fixture tests; ticket expiry/replay tests | paste into a real text/browser field and run non-echoing test consumers |
| Bounded performance/resources | 10,000-entry p95 benchmark; cold-ready measurement; RSS/idle CPU sampling; repeated-session leak test | Activity Monitor/instruments spot check on the reference Mac |
| Reversible installation | idempotent install/status/uninstall tests; modified-skill conflict test; config preservation fixtures | install in Codex App and Claude Code, confirm MCP tools/skill discovery, uninstall without disturbing other entries |
| Host permission independence | fixtures prove no global bypass/broad wildcard is written; optional narrow-rule output is exact and consent-gated | leave host defaults unchanged, then optionally install and inspect the narrow Pastera-only rule |
| Existing password vault compatibility | focused KDBX, Keychain quick unlock, conflict, menu, clipboard, and full default Xcode tests | local install and normal password-vault use remain unchanged when Agent Integration is disabled |

## Test and Verification Strategy

### Unit and Model Tests

- Deterministic clock coverage for grant creation, idle renewal, absolute expiry, revocation, and cross-client independence.
- State-machine tests proving only successful sensitive actions renew grants.
- One-use ticket concurrency tests proving at most one redeemer succeeds.
- Rate-limit boundary and recovery tests.
- Redaction tests with a unique sentinel secret in every prohibited output surface.
- Tool/schema tests proving notes and passwords are structurally absent.

### Broker and Store Integration

- Real temporary KDBX creation, lock, automation recovery, search, paste, and external-conflict read behavior.
- Real private socket permissions and lifecycle; symlink/non-socket collision rejection.
- Same-user and wrong-user peer checks where the test environment permits them.
- Cancellation and timeout tests that leave no redeemable ticket or late secret result.
- Concurrent Codex and Claude metadata calls serialized through one store owner.

### MCP and CLI Integration

- MCP `initialize`, `tools/list`, and `tools/call` over real stdio for both adapter products.
- Bounded pagination, stable structured errors, stdout protocol purity, stderr redaction, and EOF/SIGTERM shutdown.
- CLI text and `--json` snapshots using synthetic non-secret data.
- Child fixture consumers for stdin and inherited-fd injection; fixtures consume without echoing.

### Security Regression

- Forged client name, copied helper path, signature mismatch, stale PID, replayed request, repeated ticket, oversized frame, malformed JSON, and protocol downgrade.
- Scan captured process environment, argument list, filesystem temp roots, pasteboard, MCP result, CLI streams, OSLog capture, audit storage, and crash-safe error descriptions for sentinel secret bytes.
- Verify no TCP listener and no HTTP request path exists.

### Performance and Resource Verification

- Use release-like optimized helper builds for RSS/latency budgets; debug builds remain functional evidence only.
- Measure warm search over 10,000 synthetic metadata entries for enough iterations to report p50/p95/max.
- Measure cold broker/Pastera recovery separately from KDBX KDF time and record the reference Mac/build.
- Sample adapter RSS and CPU after initialization/idle stabilization.
- Repeat connect/search/disconnect and ticket-expiry cycles to detect memory growth.

### Repository and Installed-App Regression

- Run focused new suites first.
- Run existing password-vault, secure-clipboard, preference, and menu suites.
- Run the repository's default no-signing `xcodebuild ... clean test` command.
- Run `git diff --check` and the repository's Swift lint path for touched files.
- Run `./script/install_local.sh`, verify the installed app/helpers/signatures, process state, socket permissions, and actual Codex/Claude MCP discovery.

## Risks, Rollback and Observation

- **Risk — unattended key exposure:** `AfterFirstUnlockThisDeviceOnly` intentionally trades repeated user presence for unattended access. Mitigation is app-bound broker-only access, per-client grants, seven-day idle expiry, 30-day hard expiry, revocation, no synchronization, and deletion when no valid grants remain.
- **Risk — helper identity under ad-hoc signing:** a local ad-hoc update may change code identity and invalidate grants. Production should use a stable designated requirement; local builds also bind to the expected helper inside the installed Pastera bundle and may require reauthorization after replacement.
- **Risk — model-directed exfiltration:** an approved agent can choose a target that echoes input. V1 removes direct reveal and high-leak injection modes, uses Skill guardrails, and treats compromise/malicious behavior of an approved client or target as outside the guaranteed boundary.
- **Risk — IPC implementation errors:** peer verification, framing, replay, and cancellation are security-sensitive. Keep protocol types small, fuzz malformed input, cap every payload, and fail closed before touching KDBX.
- **Risk — UI/store coupling:** broker recovery changes the shared store's state. All state changes stay on the existing queue and refresh the controller snapshot so the main menu never reads a stale unlocked/locked view.
- **Risk — config ownership:** direct config edits could damage unrelated MCP/skill setup. Use official client commands, owned manifests, idempotent status checks, and conflict-safe skill updates.
- **Risk — MCP Swift SDK pre-1.0:** minor versions may break APIs. Pin `0.12.1` for V1 and upgrade only through an explicit compatibility task.
- **Rollback:** disable Agent Integration, stop accepting new broker connections, revoke all external grants, delete the automation Keychain item/tickets, unregister owned MCP entries, and remove owned skill copies. KDBX bytes, OneDrive paths, interactive quick unlock, main-menu UI, and existing password data require no rollback or migration.
- **Observation:** local-only redacted counters for connection/result/latency/resource buckets; bounded audit events; no uploaded vault telemetry. Observe authorization-request deduplication, automatic recovery failures, rate limiting, adapter crashes, latency p95, and RSS drift.

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-19-pastera-vault-cli-skill-mcp.md`
- Plan Status: `design-approved-pending-written-review`
- Evidence Profile: `standard`
- Story ID: not requested or assigned
- Task IDs: not requested or assigned
- Superpowers Task Mapping: implementation slices are outlined above; detailed checkbox tasks are intentionally gated on written-spec review
- ZenTao Sync Status: `not-requested`
- ZenTao Readback Evidence / Time: not applicable
- Prior Related Records: password-vault inline unlock, first-open latency, contextual actions, and access polish remain separate completed requirements; none is a competing plan for this CLI/Skill/MCP scope
- External Basis: official Codex MCP/Skill documentation, official Claude Code MCP/Skill documentation, and official MCP Swift SDK `0.12.1`
- Last Updated: `2026-07-19`

## Delivery Record

- Actual Implementation: none; this record currently contains the approved design only.
- Plan Deviations: the Superpowers design spec and implementation plan are intentionally consolidated into this one repository file because project workflow forbids parallel plan/spec records.
- Impact: planned impact is limited to the macOS Pastera app, three bundled helper products, local Agent Skill assets, user-owned Codex/Claude MCP configuration, and new device-local Keychain grant material. No KDBX schema or OneDrive path change is planned.
- Verification: repository/source inspection and official Codex, Claude Code, MCP SDK documentation checks completed for design. No implementation verification has started.
- Remaining Risks: unattended unlock, helper identity, target-command disclosure, IPC correctness, and pre-1.0 MCP SDK compatibility remain implementation risks covered by the acceptance and rollback sections.
- Follow-ups: user written-spec review, then detailed TDD implementation tasks in this same file.
- ZenTao Closeout: not applicable; no ZenTao work was requested.
