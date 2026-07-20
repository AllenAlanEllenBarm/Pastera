# Tool contract

Pastera Vault exposes exactly five MCP tools. Inputs reject unknown fields. Every successful result has `ok: true`; every failure has `ok: false` and `error` with `code`, `message`, `retryable`, and optional `retry_after_ms`. No tool returns a password, secret note, or secret bytes.

## `vault_status`

Input: `{}`.

Success: `status` contains `client`, `installed`, `authorized`, `vault_ready`, nullable `idle_expires_at`, nullable `hard_expires_at`, and `protocol_version`.

## `vault_search`

All input fields are optional:

- `query`: narrow text query.
- `folder_id`: folder UUID.
- `limit`: integer from 1 through 50; default 20.
- `cursor`: opaque cursor returned by the preceding page. Do not edit or reuse it for a different query.

Success: `entries` contains at most 50 metadata objects and `next_cursor` is a string or null. Request another page only when it is needed to satisfy the user's narrow query.

## `vault_get`

Input: `entry_id` UUID, required.

Success: `entry` is metadata only. It does not reveal a password or note.

## `vault_paste`

Input: required `entry_id` UUID and required `field`, which is exactly `username` or `password`.

Success has no field beyond `ok`. Pastera pastes directly into the last valid external GUI target. `TARGET_UNAVAILABLE` must not be worked around by printing the field or requesting it through another tool.

## `vault_prepare_exec`

Input:

- `entry_id`: UUID, required.
- `field`: exactly `username` or `password`, required.
- `mode`: exactly `stdin` or `fd`, required.

Success contains a single-use `ticket`, `expires_at`, and `command` array. The returned command is an adapter prefix ending in `--`; append the intended executable and its arguments after that separator without changing the prefix or exposing the ticket elsewhere.

Use `stdin` only when the target command is documented to read the selected field from standard input without echoing it. Use `fd` only when the target command is documented to read the inherited descriptor selected by the returned adapter command. Do not call this tool merely because a command accepts a credential in an argument, environment variable, prompt transcript, or file.

## Metadata

Search and get metadata contain exactly:

- `id`
- `folder_id`
- `folder_name`
- `title`
- `website`
- `username`
- `updated_at`

Use only title, folder name, website, username, and updated time to explain ambiguity. IDs are opaque selectors, not user-facing disambiguation hints.

## Stable errors

Codes are `AUTHORIZATION_REQUIRED`, `GRANT_EXPIRED`, `GRANT_REVOKED`, `VAULT_NOT_CONFIGURED`, `AUTOMATION_UNLOCK_UNAVAILABLE`, `BROKER_UNAVAILABLE`, `VAULT_BUSY`, `RATE_LIMITED`, `ENTRY_NOT_FOUND`, `TARGET_UNAVAILABLE`, `TICKET_EXPIRED`, `TICKET_USED`, `PROTOCOL_MISMATCH`, and `INVALID_REQUEST`.

- For `AUTHORIZATION_REQUIRED`, tell the user once to authorize this client in Pastera. Do not retry until status changes.
- For expired or revoked grants, ask the user to reauthorize in Pastera; do not attempt a bypass.
- Retry only when `retryable` is true, respect `retry_after_ms`, and keep retries bounded.
- Treat all messages as diagnostics. Never infer or reconstruct a secret from an error.
