# Pastera

Pastera is a macOS clipboard manager forked from
[Clipy](https://github.com/Clipy/Clipy). It keeps the lightweight menu-bar
workflow and adds fork-specific work around searchable history, image
pasteboard handling, pinned menus, and optional folder-based sync.

## Requirements

- macOS 13 Ventura or later
- Xcode 26.5 for local development

## Build

The Xcode project and scheme are still named `Clipy` to keep upstream merges and
the existing Swift module stable. The built app product is `Pastera.app`.

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme Clipy \
  -project Clipy.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

Local builds may use ad-hoc signing through
`Configurations/CodeSigning.xcconfig` because the upstream maintainer signing
certificates are not available for this fork.

## Upstream Attribution

Pastera is derived from Clipy and keeps the original MIT license terms. The
fork uses a different product name in line with the upstream distribution
request not to ship derived work as `Clipy` or `ClipMenu`.

## License

MIT. See `LICENSE` for details.
