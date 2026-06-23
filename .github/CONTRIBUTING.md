# Contributing to Pastera

Thank you for helping improve Pastera.

Pastera is an MIT-licensed macOS clipboard manager derived from Clipy. The
project values small, practical changes that keep clipboard history, snippets,
permissions, and sync behavior predictable for users.

## Ways To Contribute

- Report bugs with a clear macOS version, Pastera version, and reproduction
  steps.
- Suggest focused improvements for clipboard history, snippets, search, sync,
  settings, packaging, and accessibility permission flows.
- Improve documentation, release notes, and localization.
- Submit pull requests that are scoped to one behavior chain at a time.

## Before Opening A Pull Request

1. Open an issue first for larger behavior, UI, storage, sync, or packaging
   changes.
2. Keep unrelated formatting and cleanup out of the pull request.
3. Preserve existing user data and non-destructive sync semantics.
4. Add or update tests when changing behavior.
5. Run the relevant verification command before requesting review.

The default regression command is:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  clean test
```

## Development Notes

- Runtime entrypoint: `pastera/Sources/AppDelegate.swift`
- Menu behavior: `pastera/Sources/Managers/MenuManager.swift`
- Clipboard, pasteback, and filtering: `pastera/Sources/Services/`
- Database and migrations: `pastera/Sources/Database/`
- Fork roadmap: `docs/development/PASTERA_FORK_PLAN.md`
- OneDrive folder sync protocol: `docs/sync/ONEDRIVE_SYNC.md`

Local development uses ad-hoc signing because public Developer ID credentials
are not part of the repository. Do not commit certificates, passwords, tokens,
notarization credentials, or local keychain material.

## Localization

### Add New Language
<img src="../Resources/new_localization.png" width="600">

After adding the language, please make changes to the various `.strings` files as follows.

### Modify an Existing Language
The files to be localized are as follows.
- Localizable.strings ( `pastera/Resources/#{language_name}.lproj/Localizable.strings` )
- Preferences ( `pastera/Sources/Preferences/#{language_name}.lproj/*.strings` )
- PreferencesPanels ( `pastera/Sources/Preferences/Panels/#{language_name}.lproj/*.strings` )
- SnippetsEditor ( `pastera/Sources/Snippets/#{language_name}.lproj/*.strings` )

**English localization only, please edit `.xib` files directly**

## Review Expectations

Maintainers may ask for a smaller scope, additional tests, or clearer user
impact. A pull request can be declined if it adds unsafe clipboard behavior,
breaks privacy expectations, weakens permission transparency, or moves the fork
away from its documented goals without prior agreement.
