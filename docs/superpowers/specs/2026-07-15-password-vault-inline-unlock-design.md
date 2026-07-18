# Password Vault Inline Unlock Design

## Goal

Replace the modal KDBX creation and unlock alert with an embedded password-vault access screen inside Pastera's existing main-menu content area. The same surface must transition from access state to folders and entries without opening another window.

## State and interaction

- `notConfigured` shows an embedded create form with master-password and confirmation fields.
- `locked` shows an embedded master-password field and unlock action.
- Entering password-vault mode automatically attempts Keychain quick unlock once per presentation when quick-unlock material is available.
- A successful quick unlock immediately renders folders and entries.
- Cancellation, unavailable Keychain material, or failed system authentication leaves the embedded master-password form visible and does not automatically retry.
- The user can explicitly request quick unlock again from the form when it is available.
- `unlocking` keeps the access form visible, disables its controls, and reports progress inline.
- Wrong passwords and confirmation mismatches remain inline, clear sensitive fields as appropriate, and never open an alert.
- Session timeout, sleep, or screen lock returns an open password-vault surface to the embedded locked form.
- `readOnlyWarning` continues to show readable vault content with the existing warning path; unrecoverable failure shows an embedded recovery message.

## Architecture

`PasswordVaultUIController` exposes database state and explicit create, master-password unlock, and quick-unlock operations. It no longer owns any password-entry UI or calls `NSAlert.runModal()`.

`MainMenuPasswordVaultDataSource` carries those explicit operations into `MainMenuPanelController`. The panel owns presentation-only access state, including the inline validation message and the "automatic quick unlock already attempted" flag.

`PasswordVaultAccessView` is a focused AppKit view embedded as an `EmbeddedRow`. It owns transient secure text fields only. It submits passwords to the controller, clears them after submission, and exposes no secret through logs, preferences, accessibility labels, or persistent controller properties.

## Layout

The password-vault header remains in the existing embedded main-menu header. The content area contains a compact vertical form: explanatory copy, one or two secure fields, inline status/error copy, a primary create/unlock button, and an optional secondary quick-unlock button. After success, the content area is replaced in place by the existing folder and entry rows.

## Error handling

- Empty passwords and mismatched confirmation are rejected locally.
- `wrongMasterPassword`, `authenticationFailed`, `userCancelled`, and stale quick-unlock material return to `locked` with an inline message.
- `databaseNotConfigured` renders creation rather than a generic unavailable state.
- `cloudUnavailable`, `unsupportedFormat`, `corruptedData`, and `saveFailed` use the existing classified error copy and do not start a modal retry loop.

## Verification

Tests cover embedded creation, embedded master-password unlock, one-shot automatic quick unlock, cancellation fallback, wrong-password retry, successful transition to folder rows, and relocking while the password-vault mode remains visible. Existing real-KDBX folder, entry, edit, copy, and deletion tests remain in the regression set. Final verification includes the focused test suite, full macOS build, strict code-signature verification, local installation, and a live installed-process check.
