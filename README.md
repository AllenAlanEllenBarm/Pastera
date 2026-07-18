<p align="center">
  <img src="docs/assets/readme-hero.svg" alt="Pastera macOS clipboard manager" width="100%" />
</p>

<p align="center">
  <a href="https://github.com/pastera-app/Pastera/releases/tag/v2.0.1-beta"><strong>Download 2.0.1-beta</strong></a>
  ·
  <a href="#latest-beta-201-beta">更新说明</a>
  ·
  <a href="#project-status">Status</a>
  ·
  <a href="#build">Build</a>
  ·
  <a href="#community-and-governance">Governance</a>
  ·
  <a href="#license">License</a>
</p>

# Pastera

Pastera is an independent, open-source clipboard productivity product. The
current macOS app combines searchable history, snippet folders, script
transforms, KDBX password-vault workflows, OneDrive folder sync, rich pasteboard
compatibility, and a keyboard-first operating model for fast pasteback. A native
Windows client is planned in the same repository against shared product
contracts rather than a shared UI framework.

## Project Status

Pastera is an active beta maintained in the `pastera-app/Pastera` GitHub
organization. The repository is standalone and does not track a product
upstream. macOS is the current executable baseline; Windows will use native
Windows APIs while preserving the same product capabilities and cross-platform
data contracts.

Current public beta builds are unsigned and not notarized yet. macOS may show a
Gatekeeper warning on first launch. The project is working toward a compliant
Developer ID signing and notarization path so users can install releases without
manual trust bypass steps.

## Highlights

- **Searchable history**: filter clipboard records quickly without leaving the
  compact history panel.
- **Snippet folders**: organize reusable prompts and text snippets with folder
  shortcuts and numeric item selection.
- **Image pasteboard support**: improves compatibility with screenshots from
  tools that use custom image pasteboard types.
- **Keyboard-first workflow**: navigate panels, settings, snippets, and history
  with shortcuts, arrows, Tab, and Return.
- **Native macOS feel**: lightweight menu-bar app, semantic colors, translucent
  surfaces, and no heavy background effects.

## Product Direction

Pastera began from Clipy source history but is now developed as an independent
product with its own architecture, interaction design, data model, and release
direction:

- Search and storage behavior separated from the compact menu display limit.
- Snippet folders and item shortcuts for prompt and text reuse.
- Optional OneDrive folder sync that keeps local data non-destructive.
- Opt-in automatic paste, with Accessibility permission requested only when the
  user enables that behavior.
- Distribution work for DMG packaging, Homebrew Cask metadata, and future
  notarized releases.

See `docs/development/PASTERA_FORK_PLAN.md` for the independent product roadmap
and historical migration boundary.

## Requirements

- macOS 13 Ventura or later
- Xcode 26.5 for local development

## Latest Beta: 2.0.1-beta

- 新增 OneDrive 本地文件夹同步：默认使用
  `~/Library/CloudStorage/OneDrive*/Pastera/sync`，自动同步默认关闭，也可手动立即同步。
- 同步协议简化为明文 JSON beta 格式，方便排查 OneDrive 冲突副本；旧加密同步记录会被跳过。
- 修正同步正确性：按更新时间做 LWW 导入、导入计数只统计实际写入，并在片段导出时补齐父文件夹上下文。
- 精简设置页：移除失效菜单项、同步口令和自定义同步目录，清空历史警告迁回通用页。
- 自动粘贴默认关闭；需要自动发送 Command+V 时可在通用设置里开启，并由系统引导授权辅助功能。
- 增加 DMG 发布脚本、GitHub Release workflow 和启动位置提示，降低从临时目录运行带来的权限问题。

## Install

Download the unsigned beta DMG from the
[2.0.1-beta release](https://github.com/pastera-app/Pastera/releases/tag/v2.0.1-beta),
or install through the repository-local Homebrew Cask once the release DMG asset
is uploaded:

```bash
brew install --cask ./Casks/pastera.rb
```

Maintainers can refresh the cask after building a DMG:

```bash
./script/update_homebrew_cask.sh \
  --version "2.0.1-beta" \
  --dmg ".build/release-artifacts/Pastera-2.0.1-beta-macOS.dmg"
```

For local unsigned beta preparation before the DMG exists on GitHub, pass
`--no-check-url`. The resulting cask still requires the matching DMG to be
uploaded before other users can install it from the release URL.

## Funding

Pastera has applied to Open Source Collective fiscal hosting. If accepted,
project funds will be used transparently for open-source maintenance needs such
as Apple Developer Program membership, Developer ID signing, notarization,
release infrastructure, and testing hardware or services.

See `docs/funding/OPEN_COLLECTIVE.md` for the intended funding policy.

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
`Configurations/CodeSigning.xcconfig`; public releases require Pastera-owned
Developer ID signing and notarization credentials.

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

## Historical Attribution

Pastera preserves the Git history, copyright notices, and MIT terms of source
originally derived from [Clipy](https://github.com/Clipy/Clipy). This attribution
does not imply an active fork relationship or upstream tracking workflow.

## Community And Governance

Pastera is maintained in public on GitHub. Contributions are welcome through
issues and pull requests, with a focus on small, reviewable changes that keep
clipboard behavior reliable and privacy-conscious.

- Contributing guide: `.github/CONTRIBUTING.md`
- Code of conduct: `CODE_OF_CONDUCT.md`
- Governance: `GOVERNANCE.md`
- Security reporting: `SECURITY.md`

## License

MIT. See `LICENSE` for details.
