# Windows Codex 交接与纠偏提示词

## 使用方式

将下面“开工提示词”完整发送给负责 Windows 的 Codex。若当前界面已经明显偏离，
先发送“界面纠偏提示词”，要求它停止扩展功能并完成截图差异盘点。

不要只发送一句“参考 macOS 做 Windows 版”。必须带上 commit 锚点、阅读顺序、
截图门禁和完成证据。

## 开工提示词

```text
你正在同一 Pastera 仓库的 windows/ 子树开发原生 Windows 11 x64 客户端。

先停止写代码，按顺序完整读取：
1. windows/AGENTS.md
2. docs/development/WINDOWS_PORTING_GUIDE.md
3. docs/windows-reference/WINDOWS_PARITY_DELTA_20260726.md
4. docs/windows-reference/README.md
5. docs/windows-reference/REFERENCE_GEOMETRY.md
6. docs/windows-reference/WINDOWS_UI_SPEC.md
7. docs/superpowers/plans/2026-07-18-pastera-windows-v1.md

范围固定为：
- frozen baseline: windows-v1-baseline-20260718
- approved parity delta:
  origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5
- 7b57094 之后的功能不会自动进入本任务。

开始前先报告：
- 当前绝对工作区、branch、HEAD SHA、与目标分支关系、clean/dirty。
- 当前执行的唯一 Windows plan Task。
- 计划修改的文件。
- 本任务的固定产品不变量、允许的平台替换、明确不做内容。
- 对应的 macOS 参考图和业务状态；没有状态匹配参考图时必须停下补图或请求确认。

UI 约束：
- 截图是产品内容区主验收基准。
- Windows 可以替换系统标题栏、字体栅格化、系统图标细节、焦点环、系统对话框
  和平台术语；不得改变产品内容区的信息架构、导航、区域位置、顺序、尺寸、
  间距、可见行数和信息密度。
- 100% DPI 归一化后，主要区域边界容差 8 epx；间距、同类控件和列表行高度
  容差 4 epx；内容区宽高比容差 3%。
- 入口/导航/页面拆分/状态/主动作缺失或移动为 P0；几何超差为 P1。
- 未获用户批准的 P0/P1 必须为 0。“Windows 原生”、WinUI 默认控件尺寸、
  构建成功或 AutomationId 存在不能作为接受偏差的理由。

每个 UI Task 完成时必须提交：
1. 来源明确的 macOS 参考图。
2. 相同状态、主题和内容区尺寸的 Windows 11 图。
3. 排除系统 chrome 和动态内容后的 50% 透明叠加图。
4. P0-P3 差异表。
5. 深色、浅色和 125% 缩放 smoke。
6. 自动化测试命令与结果。

没有三联图只能标记“待视觉验收”；存在未获批准的 P0/P1 只能标记
“截图验收未通过”，不得勾选 plan Task 完成。

安全边界：
- 不把真实密码、主密码、解锁材料、Token、DPAPI blob、OneDrive 绝对路径、
  私人剪贴板或个人账号写进源码、fixtures、日志、截图、文档、commit 或聊天。
- KDBX、OneDrive、clipboard 和 Agent wire contract 不得产生 Windows 私有分叉。
- Windows 产品代码只进入 windows/；需要修改共享契约时先说明双向兼容影响。

现在只做事实盘点和任务前置报告。报告完成后再开始当前 Task。
```

## 界面纠偏提示词

```text
当前 Windows 界面与 Pastera 参考图偏差过大。立即暂停新增功能和视觉重设计，
只做 UI 纠偏。

读取：
- windows/AGENTS.md
- docs/windows-reference/README.md
- docs/windows-reference/REFERENCE_GEOMETRY.md
- docs/windows-reference/WINDOWS_UI_SPEC.md

对当前页面执行：
1. 明确页面、业务状态、主题、DPI、内容区尺寸和对应 macOS 参考图。
2. 输出 macOS 参考图、当前 Windows 图和 50% 透明叠加图。
3. 按 P0-P3 列出全部差异。
4. 先修 P0：入口、导航、页面拆分、状态和主动作。
5. 再修 P1：主要区域、间距、尺寸、密度、可见行数和对齐。
6. 只保留 P2：系统标题栏、字体栅格化、系统图标细节、焦点环和原生对话框。
7. 不使用大卡片、额外留白、重新分组、隐藏入口或 WinUI 默认尺寸替换参考布局。
8. 修复后重新生成三联图，直到未获批准的 P0/P1 为 0。

内容区容差：
- 主要区域边界：8 epx
- 间距、同类控件和列表行高度：4 epx
- 内容区宽高比：3%

没有状态匹配参考图时停止实现并请求补图/确认，不得根据其他页面自由推导。
最终报告只包含：修改文件、三联图路径、P0-P3 结果、测试/smoke 结果、仍需用户
批准的差异。不要用“更符合 Windows 风格”解释未批准的结构或几何偏差。
```

## Windows UI 交付报告模板

```md
### Scope

- Plan Task:
- Worktree / branch / SHA:
- Reference commit:
- Reference image:
- State / theme / DPI / content size:

### Fixed invariants

-

### Evidence

- macOS reference:
- Windows screenshot:
- 50% overlay:
- Dark:
- Light:
- 125%:

### Differences

| Level | Region | Difference | Measurement | Decision |
| --- | --- | --- | --- | --- |
| P0/P1/P2/P3 | | | | pass / needs-fix / approved-difference |

### Verification

- Automated:
- Windows UI smoke:
- Unapproved P0:
- Unapproved P1:

### Result

- pass / pending-visual-acceptance / screenshot-acceptance-failed
```

## 结果判定

- `pass`：自动化和实机 smoke 通过，三联图齐全，未获批准的 P0/P1 为 0。
- `pending-visual-acceptance`：缺三联图、缺 Windows 实机状态或等待用户批准。
- `screenshot-acceptance-failed`：仍存在未获批准的 P0/P1。

Windows Codex 不得自行把后两种状态改写为完成。
