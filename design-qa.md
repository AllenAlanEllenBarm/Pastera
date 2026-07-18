# Pastera Preferences Design QA

## Reference

- Selected direction: compact semantic grouped cards with colored SF Symbols, stable dark surfaces, and aligned trailing controls.
- Reference image: `/Users/feeyo/.codex/generated_images/019f3a77-b327-72a0-89c6-aa9c54a95181/exec-c49f5a7b-4c2f-4183-8b87-e2142946b749.png`

## Runtime Evidence

- Default General: `/tmp/pastera-preferences-polish-final/final-installed-default-20260711.jpeg`
- Default About: `/tmp/pastera-preferences-polish-final/final-installed-about.jpeg`
- Minimum window: `/tmp/pastera-preferences-polish-final/final-installed-min-20260711.jpeg`
- Wide window: `/tmp/pastera-preferences-polish-final/size-wide-sync.jpeg`
- Search result: `/tmp/pastera-preferences-polish-final/final-installed-search-20260711.jpeg`
- Search reveal and highlight: `/tmp/pastera-preferences-polish-final/final-installed-search-reveal-20260711.jpeg`

## Findings And Fixes

- P0: None.
- P1: Removed menu-opacity inheritance from the preferences window; fixed inconsistent pane top origins and trailing control alignment; restored the missing `图片数量` search alias and target reveal; made Escape handling field-aware; and stopped hidden sync pages from refreshing on application activation.
- P2: Added semantic group icons, compact card headers, consistent 48 pt rows, subtle separators, shortcut reset actions in group headers, excluded-app empty state, and higher-contrast borderless external links. Balanced the sidebar with `使用偏好` at the top and `服务与支持` anchored at the bottom.
- Stability: moved pane-entry and anchor-highlight fades to Core Animation, and made window-close deactivation conditional on there being no other visible app window.
- Responsive checks: passed at `680x480`, `760x600`, and `920x680`; overflow is handled by the page scroll view without horizontal clipping.
- Accessibility checks: sidebar and pane keyboard traversal, search navigation, field labels, and RecordView input remain available.

## Verification

- Preference-focused tests: 104 tests in 14 suites passed.
- Full serial clean test: 578 tests in 70 suites passed.
- `git diff --check`: passed.
- Local install: `/Applications/Pastera.app` launched, inspected, and passed strict code-signature verification.

Final result: passed.
