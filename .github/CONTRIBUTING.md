# 参与 Pastera

感谢你帮助改进 Pastera。

Pastera 是一款独立、开源的 macOS 剪贴板效率工具。项目欢迎小而清晰、能够验证并尊重用户隐私的改进。

## 可以贡献什么

- 提交带有系统版本、Pastera 版本和最小复现步骤的缺陷报告。
- 改进历史记录、搜索、片段、脚本、OCR、密码箱、同步和设置体验。
- 修复键盘导航、辅助功能权限和不同 macOS 版本的兼容问题。
- 完善文档、本地化、发布脚本、测试和脱敏验证样本。
- 提出有明确用户价值和验收方式的产品建议。

不要在普通 Issue 中提交漏洞利用细节、真实剪贴板数据、密码、令牌或其他敏感信息。相关问题请先阅读[安全政策](../SECURITY.md)。

## 开始之前

1. 搜索现有 Issue 和 Pull Request，避免重复工作。
2. 对 UI、存储、同步、权限、打包或跨平台契约等较大改动，先通过 Issue 确认目标和边界。
3. 一个 Pull Request 只处理一条可独立评审的行为链。
4. 不把无关格式化、批量重命名或清理混入功能变更。
5. 保留现有用户数据、非破坏性同步语义和明确的权限提示。

## 本地开发环境

- macOS 13 Ventura 或更高版本。
- Xcode 26.5。
- 通过 Xcode Swift Package Manager 解析依赖。

公开 Developer ID、Apple 公证和发布凭据不属于仓库内容。本地开发使用无签名构建或 `Configurations/CodeSigning.xcconfig` 中的 ad-hoc 签名配置。

## 构建与测试

默认全量回归命令：

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

修改范围较小时，可以先运行聚焦测试，但在请求合并前应说明完整回归是否执行、结果如何，以及仍有哪些人工验证缺口。

改变应用行为、界面、打包或测试后，可以使用以下命令安装最新本地构建：

```bash
./script/install_local.sh
```

Finder、Notes、Preview、OneDrive 和真实粘贴目标的人工检查见 [`docs/verification/VERIFICATION.md`](../docs/verification/VERIFICATION.md)。

## Pull Request 检查清单

- [ ] 变更只覆盖一个清晰的用户问题或维护目标。
- [ ] 没有混入无关格式化、缓存、本机配置或生成产物。
- [ ] 新行为具有测试，或明确说明无法自动化验证的原因。
- [ ] 已执行相关验证并记录命令、结果和剩余缺口。
- [ ] 没有破坏现有 SQLite、KDBX、设置或 OneDrive 数据兼容性。
- [ ] 新的权限、粘贴、同步或网络行为对用户可见且默认安全。
- [ ] 日志、截图和测试样本不含真实剪贴板内容或凭据。
- [ ] 文档、界面文案和本地化已随行为同步更新。

## 本地化

通用产品文案集中在：

- `pastera/Resources/Localizable.xcstrings`

片段编辑器仍使用 Base XIB 和对应语言的 `.strings`：

- `pastera/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib`
- `pastera/Sources/Snippets/de.lproj/CPYSnippetsEditorWindowController.strings`
- `pastera/Sources/Snippets/it.lproj/CPYSnippetsEditorWindowController.strings`
- `pastera/Sources/Snippets/ja.lproj/CPYSnippetsEditorWindowController.strings`
- `pastera/Sources/Snippets/zh-Hans.lproj/CPYSnippetsEditorWindowController.strings`

通过 Xcode 添加语言后，只修改当前工程真实使用的 String Catalog、XIB 或 `.strings` 文件。不要重新创建已经移除的 Preferences 本地化目录。

## 隐私、凭据与用户数据

- 不提交证书、密码、令牌、OAuth 材料、公证凭据或 Keychain 内容。
- 不把真实剪贴板历史、KDBX 数据库、OneDrive 文件或用户路径加入测试样本。
- 新增遥测、网络传输、自动粘贴或权限请求前，必须先确认产品需求和用户可见行为。
- 同步和迁移改动必须保持可恢复、非破坏，并说明冲突和失败语义。

## 代码与协议入口

- 应用入口：`pastera/Sources/AppDelegate.swift`
- 菜单行为：`pastera/Sources/Managers/MenuManager.swift`
- 剪贴板捕获、粘贴和过滤：`pastera/Sources/Services/`
- SQLite schema、启动和迁移：`pastera/Sources/Database/`
- 片段持久化：`pastera/Sources/Repositories/SnippetRepository.swift`
- 独立产品路线图：`docs/development/PASTERA_FORK_PLAN.md`
- OneDrive 同步协议：`docs/sync/ONEDRIVE_SYNC.md`
- 验证矩阵：`docs/verification/VERIFICATION.md`

## 评审标准

维护者可能要求缩小范围、补充测试、澄清用户影响或提供人工验证证据。以下变更可以被拒绝：

- 引入不安全或不可见的剪贴板行为。
- 降低隐私、权限或自动粘贴透明度。
- 破坏用户数据或非破坏性同步语义。
- 无必要地扩大后台资源使用、依赖或维护面。
- 偏离已经确认的独立产品目标或跨平台契约。

所有参与者都需要遵守[社区行为准则](../CODE_OF_CONDUCT.md)。
