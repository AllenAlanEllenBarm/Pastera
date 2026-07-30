# Windows UI 参考图几何清单

## 用途

本文件把 `docs/windows-reference/` 中已脱敏 macOS 截图转换为 Windows UI 的
可执行几何约束。截图约束产品内容区，不要求复制 macOS 标题栏、交通灯按钮、
字体栅格化、焦点环或系统对话框绘制。

所有尺寸都是截图原始像素。Windows 比较时先裁掉系统 chrome，再把内容区归一化
到 100% DPI；归一化后的有效像素记为 `epx`。

## 全局容差

| 项目 | 允许偏差 |
| --- | --- |
| 主区域、导航、工具栏、底部模式栏边界 | 每条边不超过 `8 epx` |
| 相邻控件、卡片、分组和列表行间距 | 不超过 `4 epx` |
| 同类控件和列表行高度 | 不超过 `4 epx` |
| 内容区宽高比 | 不超过 `3%` |
| 固定视口可见列表行数 | 应一致；系统字体度量最多相差一行并说明 |

超出容差属于 P1。入口、导航、页面拆分、状态或主动作缺失/移动属于 P0。
未获用户批准的 P0/P1 必须修复。

## 基线图清单

| 页面/状态 | 参考图 | 原始尺寸 | 必须保持的结构 |
| --- | --- | ---: | --- |
| 主面板历史 | `main-panel/01-history-synthetic-dark.jpg` | 300×356 | 顶部类型栏、紧凑单行历史、底部搜索和三模式入口 |
| 主面板搜索 | `main-panel/02-search-open-dark.jpg` | 300×398 | 搜索在当前浮层内展开；筛选、结果上下文和底部入口不重排 |
| 主面板 Snippet 空态 | `main-panel/03-snippets-empty-dark.jpg` | 300×398 | 浏览态、单一空状态和显式编辑入口 |
| 主面板密码箱锁定 | `main-panel/04-vault-locked-dark.jpg` | 300×398 | 标准主密码解锁边界、锁定反馈和底部入口 |
| 历史独立搜索 | `history-browser/01-search-empty-dark.jpg` | 680×520 | 搜索/过滤条件区、结果区、状态与增量加载层级 |
| Snippet 编辑器 | `snippets/01-editor-empty-dark.jpg` | 680×432 | 顶部工具栏、左树、右详情；空态不改变双栏比例 |
| 基础设置 | `preferences/01-general-dark.jpg` | 760×600 | 固定左导航、右侧语义分组、紧凑行高和危险项分离 |
| 历史设置 | `preferences/02-history-dark.jpg` | 760×600 | 左导航不变；保留、重复、保存/预览类型按语义分组 |
| 脚本设置空态 | `preferences/03-scripts-empty-dark.jpg` | 760×600 | 左导航、脚本列表/空态、新建/模板/测试入口 |
| 快捷键设置 | `preferences/04-shortcuts-dark.jpg` | 760×600 | 快捷键按功能分组；记录控件、冲突反馈和恢复默认位置 |
| 忽略应用空态 | `preferences/05-excluded-apps-empty-dark.jpg` | 760×600 | 应用选择、列表/空态和删除入口 |
| OneDrive 设置 | `preferences/06-sync-configured-dark.jpg` | 760×600 | 状态、位置、同步范围和操作依次分组；不得声明云端完成 |
| 关于 | `preferences/07-about-dark.jpg` | 760×600 | 版本、链接、许可证和更新状态层级 |
| 首次设置 | `onboarding/01-accessibility-setup-dark.jpg` | 680×462 | 单一主任务、能力说明和继续/取消边界 |

## 三联图制作规则

每个 Windows UI 状态必须保存三项证据：

1. 来源明确的 macOS 参考图。
2. 相同业务状态、主题和归一化内容区尺寸的 Windows 11 图。
3. 参考图与 Windows 图各 50% 透明度的叠加图。

比较前只允许遮罩：

- macOS/Windows 系统标题栏和窗口阴影。
- 时间、版本号和合成记录正文等 P3 动态内容。
- 字体抗锯齿造成的像素级差异。

不得遮罩导航、工具栏、表单分组、卡片边界、主按钮、空状态、错误状态或底部
模式栏。叠加图中出现双重区域边缘、明显位移、不同卡片数量或不同可见行数时，
必须按 P0/P1 记录并修正。

## 差异报告格式

| 字段 | 要求 |
| --- | --- |
| Reference | 参考图相对路径和来源 commit |
| Windows evidence | Windows 图和叠加图相对路径 |
| State | 页面、触发路径、业务状态、主题、DPI |
| P0 | 结构差异；未获批准必须为 0 |
| P1 | 超出几何容差的差异；未获批准必须为 0 |
| P2 | 字体、系统图标、焦点环等允许的平台绘制差异 |
| P3 masks | 被遮罩的动态内容 |
| Decision | `pass`、`needs-fix` 或带用户确认依据的 `approved-difference` |

构建成功、DOM/AutomationId 断言或单元测试结果不写入 `Decision` 代替截图结论。
