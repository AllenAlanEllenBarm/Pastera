# Pastera Code Intelligence

Pastera uses CodeGraphContext as an optional candidate-finding layer for Codex.
`rg`, focused source reads, Xcode builds, and tests remain the sources of truth.
Only the read-only `find_code` and `analyze_code_relationships` tools are exposed
to Codex.

## Bootstrap

Run this once per clone:

```bash
script/codex/code-intelligence.sh bootstrap
```

The command:

1. Adds the `pastera_codegraph` MCP block to the clone-local, Git-ignored
   `.codex/config.toml` without replacing unrelated settings.
2. Installs pinned uv, Python 3.12, and CodeGraphContext 0.5.1 under the clone's
   Git common directory.
3. Selects CodeGraphContext `per-repo` mode when no mode has been configured.
   It refuses to overwrite another existing mode.
4. Creates a FalkorDB-backed index for the current worktree and starts one
   managed watcher.

Start a new Codex task after bootstrap so the project MCP is loaded.

The runtime does not modify system Python, Homebrew, shell profiles, or
`~/.codex/config.toml`. CodeGraphContext's own global mode is stored under
`~/.codegraphcontext/config.yaml`.

## Commands

```bash
script/codex/code-intelligence.sh activate-codex
script/codex/code-intelligence.sh doctor
script/codex/code-intelligence.sh status
script/codex/code-intelligence.sh ensure-codegraph-watcher
script/codex/code-intelligence.sh stop-codegraph-watcher
script/codex/code-intelligence.sh reindex-codegraph
```

- `activate-codex` is idempotent and only appends the Pastera MCP block.
- `doctor` checks pinned tools, context mode, MCP activation, watcher, and
  backend state.
- `status` is safe before bootstrap and reports the derived database paths.
- `reindex-codegraph` advances the database generation and rebuilds the graph.

MCP startup is non-required. A CodeGraph failure must not block Codex work; use
`rg` and focused source reads while diagnosing it.

## Swift Query Discipline

Use CodeGraph to narrow a search, then confirm in the worktree:

| Question | Candidate query | Required confirmation |
| --- | --- | --- |
| Where is a type or method defined? | `find_code` with the exact symbol | Read the returned file and declaration |
| Who calls a method? | Relationship analysis for callers | `rg` the symbol and inspect each reachable call site |
| What might a change affect? | Relationship analysis with a small depth | Check protocols, delegates, notifications, tests, and build targets |
| Which implementation satisfies a protocol? | Search the protocol and conforming types | `rg ': <Protocol>'` and inspect extensions |

Static edges are incomplete for AppKit target-action, selectors,
`NSSelectorFromString`, notifications, Objective-C runtime dispatch, bindings,
XIB connections, and dependency injection assembled at runtime. Do not treat an
empty CodeGraph result as proof that no caller or consumer exists.

The project MCP compacts source-heavy results and returns at most six candidates
per tool call. Narrow the symbol, path, or relationship type instead of raising
the global limit.

## State And Isolation

- Reviewed configuration:
  `.codegraphcontext/.env`, `.codegraphcontext/config.yaml`, `.cgcignore`,
  `tools/code-intelligence/`.
- Clone-shared tool runtime:
  `$(git rev-parse --git-common-dir)/codex-code-intelligence/`.
- Worktree-local generated state:
  `.codegraphcontext/db/` and `.codegraphcontext/runtime/`.
- A short `/tmp/cgc-...` symlink gives FalkorDB a safe Unix socket path.
- `FALKORDB_PORT=0` disables Redis TCP listening and prevents port conflicts.

Configuration fingerprints include the dependency lock, indexing environment,
backend config, ignore rules, and manual generation. Response-size limits are
excluded so tightening output budgets does not rebuild the database.

## Troubleshooting

```bash
script/codex/tests/code-intelligence-smoke.sh
script/codex/code-intelligence.sh doctor
script/codex/code-intelligence.sh status
```

- `runtime=missing`: run `bootstrap`.
- `codex_mcp=missing`: run `activate-codex`, then start a new Codex task.
- Context mode mismatch: review `~/.codegraphcontext/config.yaml`; the project
  script intentionally will not overwrite another mode.
- Unexpected KuzuDB fallback: fix the FalkorDB cause, then run
  `reindex-codegraph`.
- Watcher startup timeout: inspect
  `.codegraphcontext/runtime/watcher.log`; a first Swift index may take longer
  than later starts.

To stop the watcher:

```bash
script/codex/code-intelligence.sh stop-codegraph-watcher
```

Only delete the clone runtime or worktree database after confirming no active
Codex task depends on it. Do not remove the global CodeGraphContext mode when
other repositories may still use it.
