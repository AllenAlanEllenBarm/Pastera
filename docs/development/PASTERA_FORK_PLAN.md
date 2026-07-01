# Pastera Fork Development Plan

## Upstream Direction

This fork follows the revived upstream development direction from May 2026:

- Xcode 26 / modern macOS build support.
- Swift Package Manager as the dependency manager.
- Swift Testing for automated tests.
- SQLiteData / GRDB-backed persistence.
- Apple Silicon / universal binary and release-signing cleanup.

The key active upstream baseline for fork features is PR #615, "Migrate
pasteboard histories to SQLiteData". Until that work is merged into
`upstream/develop`, local feature work should integrate from
`refs/pull/615/head` and keep new history behavior on the
`PasteboardHistoryRepository` / `PasteboardContent` model.

## Fork Goals

1. Add history search that can reach stored history beyond the menu display
   limit.
2. Fix and preserve image copy/paste behavior with modern pasteboard types.
3. Add optional history/snippet sync through a user-selected OneDrive folder.
4. Keep menu popup and clipboard monitoring lightweight.

## Windows Porting

For the Windows implementation handoff, use
`docs/development/WINDOWS_PORTING_GUIDE.md` as the migration entrypoint. It
summarizes the `v1.2.2-beta..develop` work, the cross-platform OneDrive sync
contract, macOS-to-Windows replacement points, and the recommended implementation
order for a Windows client.

## Storage Policy

History storage and menu display must be separate concerns:

- Menu rendering stays bounded by a display limit.
- Database retention uses a larger stored-history limit.
- Search reads from the stored history set, not only visible menu items.
- Large assets must be bounded for sync to avoid excessive OneDrive churn.

## Current Local State

The local development branch intentionally preserves an ad-hoc signing include
in `Configurations/CodeSigning.xcconfig` for builds without maintainer
certificates. A local `.DS_Store` may appear in the worktree and should remain
untracked.

## Not In Scope For V1

- Microsoft Graph or OneDrive OAuth integration.
- Background network upload/download code inside Pastera.
- Reintroducing Realm-backed pasteboard history features.
- Syncing secrets, OAuth tokens, or plaintext passphrases.
