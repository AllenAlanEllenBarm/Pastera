---
name: pastera-vault
description: Use when the user asks Codex or Claude to find, paste, copy, or safely inject credentials stored in the local Pastera password vault.
---

# Pastera Vault

1. Call `vault_status` only when readiness is unknown.
2. Use a narrow `vault_search`; never enumerate or export the full vault.
3. Resolve ambiguity only from title, folder, website, username, and updated time.
4. Prefer `vault_paste` for GUI fields.
5. Use `vault_prepare_exec` only for commands documented to read stdin or an inherited fd without echoing it.
6. Never request, print, log, summarize, infer, or place a password in arguments, environment variables, or temporary files.
7. On authorization errors, explain the single Pastera authorization action once; do not loop.

Read `references/tool-contract.md` for exact schemas and stable errors.
Read `references/security-boundary.md` before command injection.
