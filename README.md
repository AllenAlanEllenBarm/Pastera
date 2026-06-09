# Pastera

Pastera is a macOS clipboard manager forked from
[Clipy](https://github.com/Clipy/Clipy). It keeps the lightweight menu-bar
workflow and adds fork-specific work around searchable history, image
pasteboard handling, pinned menus, and optional folder-based sync.

## Requirements

- macOS 13 Ventura or later
- Xcode 26.5 for local development

## Latest Beta: 1.2.2beta

- 增加历史搜索功能
- 优化 UI
- 修复部分截图软件无法成功纳入历史的问题

## Build

The Xcode project, scheme, and source directory use lowercase `pastera`.
The built app product is `Pastera.app`.

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

Local builds may use ad-hoc signing through
`Configurations/CodeSigning.xcconfig` because the upstream maintainer signing
certificates are not available for this fork.

## Local Install

For manual testing, build and replace the local app with:

```bash
./script/install_local.sh
```

The script installs to `/Applications/Pastera.app` by default and launches the
fresh build. Set `PASTERA_INSTALL_DIR="$HOME/Applications"` if `/Applications`
is not writable.

Codex local development also uses `.codex/hooks.json`: the Stop hook runs
`script/codex_stop_install_if_changed.sh`, which reinstalls only when
build-relevant app paths changed since the last local install.

## Upstream Attribution

Pastera is derived from Clipy and keeps the original MIT license terms. The
fork uses a different product name in line with the upstream distribution
request not to ship derived work as `Clipy` or `ClipMenu`.

## License

MIT. See `LICENSE` for details.
