# Pastera Windows V1 界面参考

本目录冻结 macOS 基线的界面结构、状态反馈和主要交互，用于 Windows
11 x64 客户端实现。截图是视觉证据，不替代
`docs/superpowers/plans/2026-07-18-pastera-windows-v1.md` 中的功能、数据、
安全和验收契约。

## 使用原则

- 保持功能入口、信息层级、状态反馈、编辑边界和操作结果对等。
- Windows 使用 WinUI 3 原生控件、窗口、托盘、快捷键与系统设置入口，
  不逐像素复制 AppKit 外观。
- 截图中的 macOS 标题栏、交通灯按钮、Finder、Applications、Command
  键、Sparkle 和辅助功能文案必须替换为 Windows 对等表达。
- 默认浏览态不暴露编辑控件；进入明确编辑态后才显示创建、重命名、移动、
  删除和保存操作。
- 所有截图使用合成内容或不含秘密的设置状态。不得从截图反推或提交真实
  剪贴板、OneDrive 路径、密码箱内容或本机凭据。

## 截图索引

| 功能 | 截图 | 状态与触发路径 | Windows V1 要点 |
| --- | --- | --- | --- |
| 主面板历史 | `main-panel/01-history-synthetic-dark.jpg` | 托盘左键或全局快捷键；单条合成文本 | 紧凑浮层、类型筛选、分页、行级编辑入口、底部模式切换 |
| 主面板搜索 | `main-panel/02-search-open-dark.jpg` | 主面板点击搜索或 `Ctrl+F` | 搜索框在当前面板展开，保留筛选和结果上下文 |
| Snippet 浏览 | `main-panel/03-snippets-empty-dark.jpg` | 主面板切换到 Snippet | 浏览态只显示搜索、空状态和显式编辑入口 |
| 密码箱锁定 | `main-panel/04-vault-locked-dark.jpg` | 主面板切换到密码箱 | 主密码是标准解锁边界；Windows Hello 只能作为便利解锁 |
| 历史搜索窗口 | `history-browser/01-search-empty-dark.jpg` | 独立历史搜索入口 | 搜索、类型过滤、Regex、大小写敏感、结果计数和增量加载 |
| Snippet 编辑器 | `snippets/01-editor-empty-dark.jpg` | Snippet 的显式编辑入口 | 左侧树、右侧详情、导入导出和启停操作；空状态明确 |
| 基础设置 | `preferences/01-general-dark.jpg` | 设置 > 基础设置 | 启动、浮层外观、自动粘贴和远程会话行为 |
| 历史设置 | `preferences/02-history-dark.jpg` | 设置 > 历史记录 | 保留上限、重复项、保存类型、预览类型和危险操作 |
| 脚本设置 | `preferences/03-scripts-empty-dark.jpg` | 设置 > 脚本 | 空状态、新建、模板、测试入口和全局快捷键 |
| 快捷键设置 | `preferences/04-shortcuts-dark.jpg` | 设置 > 快捷键 | 菜单与历史面板快捷键分组，支持恢复默认与冲突反馈 |
| 忽略应用 | `preferences/05-excluded-apps-empty-dark.jpg` | 设置 > 忽略应用 | 应用选择、空状态、删除及不可用状态 |
| OneDrive 同步 | `preferences/06-sync-configured-dark.jpg` | 设置 > 云同步 | 本地 OneDrive 文件夹状态、同步范围、方向开关和手动同步 |
| 关于 | `preferences/07-about-dark.jpg` | 设置 > 关于 | 版本、项目链接、许可证和更新状态 |
| 首次设置 | `onboarding/01-accessibility-setup-dark.jpg` | 首次启动或安装后引导 | Windows 替换为安装位置、开机启动和系统能力检查，不照搬辅助功能权限 |

## 尚需在 Windows 实机形成的证据

以下状态由 Windows 客户端实现时使用合成测试数据补拍，不从用户真实数据
采集：多类型历史列表、图片/文件预览、Snippet 文件夹和条目编辑、密码箱首次
创建及解锁后列表、同步冲突/失败、脚本编辑和测试结果、安装/升级/卸载流程、
浅色模式、高对比度、125%/150% 缩放、窄屏和键盘完整操作。

Windows Codex 每完成一个阶段，应把新截图放入对应目录，并在
`WINDOWS_UI_SPEC.md` 的验收矩阵中更新状态，不能覆盖 macOS 基线图。
