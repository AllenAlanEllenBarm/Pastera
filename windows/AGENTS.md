# Pastera Windows

## 必读顺序

进入 `windows/` 后按顺序读取：

1. `docs/development/WINDOWS_PORTING_GUIDE.md`
2. `docs/windows-reference/WINDOWS_PARITY_DELTA_20260726.md`
3. `docs/windows-reference/README.md`
4. `docs/windows-reference/REFERENCE_GEOMETRY.md`
5. `docs/windows-reference/WINDOWS_UI_SPEC.md`
6. `docs/windows-reference/WINDOWS_CODEX_HANDOFF.md`
7. `docs/superpowers/plans/2026-07-18-pastera-windows-v1.md`

这些文档共同定义 Windows 行为、范围和视觉验收。不得只看计划标题或单张截图
自行补全产品设计。

## 范围锚点

- 冻结基线：`windows-v1-baseline-20260718`，不得移动或重建。
- 批准增量：`origin/develop@7b57094ce32cf19ac737d24d10e91ebf121aaed5`。
- `7b57094` 之后只有计划或尚未进入批准增量的功能，不自动属于 Windows V1。
- Windows 代码只进入 `windows/`；共享协议或 fixtures 变化必须同时验证 macOS
  兼容读取，不得为了 Windows 方便创建私有 KDBX、OneDrive 或 clipboard 协议。

## 架构边界

- 使用 C#、WinUI 3、Windows App SDK 稳定通道和 SQLite；V1 只承诺
  Windows 11 x64。
- Presentation 只依赖 Application/Domain 接口；WinUI、Win32、Clipboard、
  Input、Windows Hello、DPAPI、Agent IPC 和 OneDrive 发现留在 App 或
  Platform.Windows 层。
- KDBX 是密码箱事实来源；Windows Hello/DPAPI 只是本机便捷解锁层。
- OneDrive 只使用本地文件夹协议，不接入 Microsoft Graph/OAuth；本地文件写入
  完成不能表述为云端上传完成。
- JavaScript 只支持受限 `transform(clip)`，禁止文件、网络、进程和系统 API。
- 不复制 AppKit/XIB/Swift 实现，也不得因 WinUI 实现困难删减业务状态、安全
  边界、错误反馈或键盘路径。

## 截图门禁

- 截图是产品内容区主验收基准。实现 UI 前先选定状态匹配的参考图；没有参考图
  时先补安全截图或向用户确认，不能自由设计后追认。
- Windows 可替换系统标题栏、系统字体栅格化、系统图标细节、焦点环、原生
  对话框和平台术语；产品内容区的信息架构、区域位置、顺序、尺寸、间距、
  可见行数和信息密度必须贴近参考图。
- 归一化到 100% DPI 后：主要区域边界容差 `8 epx`，间距和同类控件/列表行
  高度容差 `4 epx`，内容区宽高比容差 `3%`。
- 入口、导航、页面拆分、状态或主动作缺失/移动是 P0；几何超差是 P1。
  未获用户批准的 P0/P1 为 0 才能完成。
- UI 任务必须提交 macOS 参考图、同状态 Windows 图和排除系统 chrome/动态
  内容后的 50% 透明叠加图；没有三联图只能标记“待视觉验收”。
- “Windows 原生”、WinUI 默认尺寸、构建成功、AutomationId 存在或单元测试
  通过都不能单独证明视觉验收通过。

## 构建与验证

Windows 工程存在后使用：

```powershell
dotnet test windows/Pastera.Windows.sln -c Release -a x64
```

UI 任务还必须在真实 Windows 11 上完成深色、浅色和 125% 缩放 smoke，并把
三联图与 P0-P3 差异记录放入 `docs/windows-reference/` 对应 Windows 证据目录。
当前 checkout 尚无 Windows solution；不得把 macOS 测试通过报告成 Windows
实现已验证。

## 凭据与本机状态

不得把密码、主密码、解锁材料、Token、DPAPI blob、OAuth 数据、OneDrive
绝对路径、真实剪贴板内容或个人账号写入源码、fixtures、日志、截图、文档、
commit 或聊天。长期本机凭据按根 `AGENTS.md` 的凭据入口处理。

## Skill 路由

- 只有显式创建/更新计划、Goal/Scope/Architecture/Acceptance 变化时使用
  `$delivery-workflow`；复用唯一 Windows V1 计划。
- Windows 代码修改、重构和审查先用 `$coding-guardrails`；新行为与 Bug 修复
  使用 `$superpowers:test-driven-development`。
- Bug、构建失败、测试失败或非预期行为先用
  `$superpowers:systematic-debugging` 查根因。
- WinUI 页面功能实现完成后，使用 `$frontend-ui-quality` 做截图差异验收；
  该 skill 只承担视觉检查，不替代 C#/WinUI 实现边界。
- 普通 commit/push 不触发 `$change-sync`；只有明确要求唯一 plan 的
  Delivery Record 收尾时才使用。
