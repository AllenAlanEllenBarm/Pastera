# `7b57094` 增量截图状态

## 来源

- 增量上限：`7b57094ce32cf19ac737d24d10e91ebf121aaed5`
- 冻结基线：`windows-v1-baseline-20260718`
- 记录日期：2026-07-30 Asia/Shanghai

## 当前结论

仓库没有保留可直接复用的安全合成 UI 截图模式。现有
`docs/windows-reference/` 14 张 JPEG 已经过人工脱敏，但它们属于
2026-07-18 基线。为了避免把真实剪贴板、密码箱、OneDrive 路径、账号或凭据
带入仓库，本轮不从用户当前运行环境补拍 `7b57094` 新页面。

这不代表 Windows 可以自由设计缺图页面。以下状态在实现前必须先通过安全合成
数据形成 macOS 参考图，或取得用户对标注线框/Windows 提案图的明确批准：

| 缺少的增量状态 | macOS 入口 | Windows 开工门 |
| --- | --- | --- |
| 历史提示词优化编辑态 | `HistoryEditorWindowController` | 先补原文、优化中、预览、撤销/保存状态图 |
| 提示词独立设置页 | `CPYPromptOptimizationPreferenceViewController` | 先补本地/provider/连接测试状态图 |
| 密码箱安全设置 | `CPYPasswordVaultPreferenceViewController` | 先补锁定、主密码设置和变更入口图 |
| 主密码变更 sheet | `PasswordVaultMasterPasswordSheetController` | 先补校验、忙碌、成功/失败状态图 |
| Agent 集成设置 | `CPYAgentIntegrationPreferenceViewController` | 先补未安装、授权中、已授权、撤销/失败图 |
| 密码箱就地 OneDrive 同步 | `PasswordVaultSyncView` | 先补本地、同步中、恢复、冲突/失败图 |
| 独立软件更新页 | `CPYSoftwareUpdatePreferenceViewController` | 先补自动检查、检查中、可更新、错误图 |
| 脚本模板/编辑/测试修正版 | `CPYScriptsPreferenceViewController` 及子控制器 | 先补空态、模板、编辑、测试结果图 |

补图时必须使用隔离临时数据库、合成 KDBX、合成 OneDrive 目录和无效示例
endpoint；临时数据与截图辅助代码在提交前删除。若无法安全复现，验收状态保持
“缺少安全参考证据”，不得以其他页面截图或 WinUI 默认布局推导。
