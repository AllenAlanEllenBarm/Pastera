# Clipboard Compatibility Fixtures

These synthetic fixtures freeze the clipboard normalization contract for
`windows-v1-baseline-20260718`. They contain no user clipboard content.

The Windows adapter must keep native Windows clipboard format identifiers out of
the cross-platform `protocolType` field. `manifest.json` covers deterministic
text payloads. Image, PDF, and file-list fixtures must be generated from the
baseline tests before their Windows adapters are implemented, because their
byte-level representation is platform-specific while their normalized Pastera
type and user-visible result are not.

Verify the tracked fixture set with:

```bash
find windows/fixtures -type f -print0 | sort -z | xargs -0 shasum -a 256
```
