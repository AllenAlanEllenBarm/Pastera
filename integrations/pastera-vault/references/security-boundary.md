# Security boundary

Pastera remains the vault owner. The MCP client receives bounded metadata, paste completion, or a single-use command ticket; it never receives password bytes.

Before using a credential:

1. Search narrowly by the user's stated service, account, or folder.
2. If several entries remain, disambiguate only with title, folder, website, username, and updated time.
3. Prefer `vault_paste` for a GUI field.
4. Before `vault_prepare_exec`, verify from the target program's documentation that it reads the value from stdin or the inherited fd and does not echo, log, forward, or persist it.
5. Append the target command only after the returned adapter command's final `--`.

Never enumerate or export the full vault. Never ask the user or Pastera to reveal a password in chat. Never print, quote, summarize, transform, compare, infer, or log a password. Never place it in command arguments, environment variables, shell history, temporary files, tool output, stdout, or stderr. Do not use a generic shell wrapper to convert stdin or an fd into one of those channels.

Authorization belongs to the verified Codex or Claude client, not to the conversation. On `AUTHORIZATION_REQUIRED`, explain the one Pastera authorization action once and stop. Do not loop, spawn repeated requests, substitute another client, or treat the user's ownership claim as authorization.

If a GUI target is unavailable or a target command lacks a documented non-echoing stdin/fd interface, stop and explain the limitation. Do not fall back to clipboard output, plaintext retrieval, arguments, environment variables, or files.
