# Pastera Windows V1 界面参考

本目录保存 Windows V1 的 macOS 行为截图、几何约束、批准功能增量和 Windows
实机证据规则。冻结基线是 `windows-v1-baseline-20260718`，批准增量上限是
`origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`。

## 阅读顺序

1. `WINDOWS_PARITY_DELTA_20260726.md`
2. 本文件的截图索引
3. `REFERENCE_GEOMETRY.md`
4. `WINDOWS_UI_SPEC.md`
5. `WINDOWS_CODEX_HANDOFF.md`
6. `current-20260726/README.md`

功能、数据和安全范围仍以唯一计划
`docs/superpowers/plans/2026-07-18-pastera-windows-v1.md` 为准。

## 截图约束

- 截图是产品内容区主验收基准，不只是灵感或可选参考。
- Windows 可替换系统标题栏、系统字体栅格化、系统图标细节、焦点环、系统
  对话框和平台术语；产品内容区的信息架构、区域位置、顺序、尺寸、间距、
  可见行数和信息密度必须贴近参考图。
- 归一化到 100% DPI 后，主要区域边界容差 `8 epx`，间距和同类控件/列表行
  高度容差 `4 epx`，内容区宽高比容差 `3%`。
- 入口、导航、页面拆分、状态或主动作缺失/移动属于 P0；几何超差属于 P1。
  未获用户批准的 P0/P1 必须为 0。
- UI 完成证据必须包含 macOS 参考图、同状态 Windows 图和排除系统 chrome/
  动态内容后的 50% 透明叠加图。没有三联图只能标记“待视觉验收”。
- “Windows 原生”、WinUI 默认尺寸、构建成功或 AutomationId 存在不能成为
  接受明显视觉偏差的理由。

## 安全原则

- 默认浏览态不暴露编辑控件；进入明确编辑态后才显示创建、重命名、移动、
  删除和保存操作。
- 所有截图只使用合成内容或不含秘密的设置状态。
- 不得提交真实剪贴板、OneDrive 绝对路径、密码箱内容、Token、账号或本机
  凭据。

## 2026-07-18 基线截图

下列 14 张 JPEG 已验证可读且经过脱敏。精确尺寸和受保护结构见
`REFERENCE_GEOMETRY.md`。

| 功能 | 截图 | 状态与触发路径 | Windows V1 不变量 |
| --- | --- | --- | --- |
| 主面板历史 | `main-panel/01-history-synthetic-dark.jpg` | 托盘左键或全局快捷键；单条合成文本 | 紧凑浮层、类型筛选、分页、行级编辑入口、底部模式切换 |
| 主面板搜索 | `main-panel/02-search-open-dark.jpg` | 主面板点击搜索或 `Ctrl+F` | 搜索在当前面板展开，保留筛选、结果上下文和底部入口 |
| Snippet 浏览 | `main-panel/03-snippets-empty-dark.jpg` | 主面板切换到 Snippet | 浏览态只显示搜索、空状态和显式编辑入口 |
| 密码箱锁定 | `main-panel/04-vault-locked-dark.jpg` | 主面板切换到密码箱 | 主密码是标准解锁边界；Windows Hello 只能作为便利解锁 |
| 历史搜索窗口 | `history-browser/01-search-empty-dark.jpg` | 独立历史搜索入口 | 搜索、类型过滤、Regex、大小写敏感、结果计数和增量加载 |
| Snippet 编辑器 | `snippets/01-editor-empty-dark.jpg` | Snippet 显式编辑入口 | 顶部工具栏、左树、右详情、导入导出和启停操作 |
| 基础设置 | `preferences/01-general-dark.jpg` | 设置 > 基础设置 | 固定左导航；启动、外观、自动粘贴和远程行为按语义分组 |
| 历史设置 | `preferences/02-history-dark.jpg` | 设置 > 历史记录 | 保留、重复、保存类型、预览类型和危险操作分组 |
| 脚本设置 | `preferences/03-scripts-empty-dark.jpg` | 设置 > 脚本 | 空状态、新建、模板、测试入口和快捷键 |
| 快捷键设置 | `preferences/04-shortcuts-dark.jpg` | 设置 > 快捷键 | 功能分组、记录控件、冲突反馈和恢复默认 |
| 忽略应用 | `preferences/05-excluded-apps-empty-dark.jpg` | 设置 > 忽略应用 | 应用选择、空状态、删除及不可用状态 |
| OneDrive 同步 | `preferences/06-sync-configured-dark.jpg` | 设置 > 云同步 | 状态、位置、范围、方向和操作依次分组 |
| 关于 | `preferences/07-about-dark.jpg` | 设置 > 关于 | 版本、项目链接、许可证和更新状态层级 |
| 首次设置 | `onboarding/01-accessibility-setup-dark.jpg` | 首次启动或安装后引导 | 单一主任务、能力说明和继续/取消边界 |

## `7b57094` 增量截图缺口

仓库没有保留可复用的安全合成 UI 截图模式，因此本轮不从用户当前环境采集新
页面。缺口和补图条件记录在 `current-20260726/README.md`，包括：

- 提示词优化编辑态与独立设置页。
- 密码箱安全设置和主密码变更 sheet。
- Agent 集成设置。
- 密码箱就地 OneDrive 同步与恢复状态。
- 独立软件更新页。
- 脚本模板/编辑/测试修正版。

缺图不等于允许自由设计。实现这些页面前必须先形成安全的 macOS 参考图，或
取得用户对标注线框/Windows 提案图的明确批准。

## Windows 实机证据

Windows Codex 每完成一个 UI Task：

1. 把 Windows 图和叠加图放入对应的 Windows 证据目录，不覆盖 macOS 基线图。
2. 在 `WINDOWS_UI_SPEC.md` 验收矩阵登记参考图、Windows 图、叠加图和 P0-P3。
3. 同时补充深色、浅色和 125% 缩放 Windows 11 smoke。
4. 未获批准的 P0/P1 未清零时，状态保持“截图验收未通过”。
