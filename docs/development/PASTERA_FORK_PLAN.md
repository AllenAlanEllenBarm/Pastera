# Pastera 派生版开发计划

## 上游方向

本派生版跟随 2026 年 5 月恢复推进的上游开发方向：

- 支持 Xcode 26 和现代 macOS 构建环境。
- 使用 Swift Package Manager 作为依赖管理工具。
- 使用 Swift Testing 编写自动化测试。
- 使用 SQLiteData / GRDB 作为持久化基础。
- 清理 Apple Silicon、通用二进制和发布签名相关工作。

当前派生功能的主要上游基线是 PR #615：“Migrate pasteboard histories to
SQLiteData”。在该工作合并到 `upstream/develop` 之前，本地功能开发应从
`refs/pull/615/head` 集成，并将新的历史记录行为保持在
`PasteboardHistoryRepository` / `PasteboardContent` 模型之上。

## 派生版目标

1. 增加历史搜索能力，让搜索可以覆盖菜单显示数量之外的已存储历史记录。
2. 修复并保持基于现代 pasteboard 类型的图片复制和粘贴行为。
3. 通过用户选择的 OneDrive 文件夹，增加可选的历史记录和片段同步能力。
4. 保持菜单弹窗和剪贴板监听轻量。

## 未来目标功能

- 增强搜索能力：支持剪贴板记录的文本内容全文搜索，并为图片记录建立
  OCR 索引，支持按识别文本搜索图片。
- 截图工作流：增加截图捕获、截图 OCR 和截图翻译能力。
- 脚本功能：支持用户自定义脚本动作，用于处理剪贴板内容、片段和常用自动化流程。
- 密码箱：已实现仅限本机的 macOS Keychain 轻量密码箱。密码箱数据与普通
  剪贴板历史隔离，不会写入 SQLite、OneDrive 同步导出、仓库文档或日志；
  跨设备同步、自动填充和浏览器扩展仍属于后续范围。
- 收藏：支持将重要历史记录或片段标记为收藏，方便快速找回。

## Windows 移植

Windows 实现交接以 `docs/development/WINDOWS_PORTING_GUIDE.md` 作为迁移入口。
该文档总结了 `v1.2.2-beta..develop` 的工作、跨平台 OneDrive 同步契约、
macOS 到 Windows 的替换点，以及 Windows 客户端的建议实现顺序。

## 存储策略

历史记录存储和菜单显示必须作为两个独立关注点处理：

- 菜单渲染继续受显示数量限制约束。
- 数据库保留使用更大的已存储历史记录上限。
- 搜索读取已存储的历史记录集合，而不只是当前可见的菜单项。
- 大体积资源必须设置同步边界，避免造成过多 OneDrive 变更和冲突。

## 当前本地状态

本地开发分支会有意保留 `Configurations/CodeSigning.xcconfig` 中的
ad-hoc 签名 include，用于在没有维护者签名证书时完成构建。本地 `.DS_Store`
可能会出现在工作区中，应保持未跟踪状态。

## V1 不包含范围

- Microsoft Graph 或 OneDrive OAuth 集成。
- Pastera 内部的后台网络上传或下载代码。
- 重新引入基于 Realm 的剪贴板历史功能。
- 同步密钥、OAuth token 或明文同步口令。
