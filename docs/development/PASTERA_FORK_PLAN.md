# Pastera 独立产品路线与历史迁移边界

## 仓库身份

`pastera-app/Pastera` 已脱离 `Clipy/Clipy` fork 网络，是 Pastera 唯一产品仓库。
仓库不再设置或跟踪 `upstream` remote，也不以 Clipy 的 PR、分支或发布节奏作为
开发输入。历史 Git 提交、原作者版权和 MIT 许可继续完整保留。

## 产品方向

1. macOS 与 Windows 都提供完整的 Pastera 核心能力，不将 Windows 缩减为纯文本版本。
2. 两端使用原生 UI 和系统 API，共享产品语义、同步协议、KDBX 和无隐私测试样本。
3. 历史存储与菜单显示数量分离，搜索覆盖已存储数据而非仅可见行。
4. OneDrive 只使用本地同步文件夹，云传输由 OneDrive 桌面客户端负责。
5. SQLiteData/SQLite 是当前事实存储；Realm 仅允许作为一次性只读导入通道。

## 未来目标功能

- 增强搜索能力：支持剪贴板记录的文本内容全文搜索，并为图片记录建立
  OCR 索引，支持按识别文本搜索图片。
- 截图工作流：增加截图捕获、截图 OCR 和截图翻译能力。
- 脚本功能：支持用户自定义脚本动作，用于处理剪贴板内容、片段和常用自动化流程。
- 密码箱：KDBX 是跨平台事实来源；macOS 系统认证和 Windows Hello/DPAPI
  只能作为本机快捷解锁层，秘密不得写入普通历史、日志或测试样本。
- 收藏：支持将重要历史记录或片段标记为收藏，方便快速找回。

## Windows 移植

Windows 实现交接以 `docs/development/WINDOWS_PORTING_GUIDE.md` 作为唯一入口。
Windows 11 x64 客户端使用 C#、WinUI 3、Windows App SDK 和 SQLite，在
`windows/` 中实现；共享协议和无隐私样本后续进入 `contracts/` 与
`test-fixtures/`。

## 存储策略

历史记录存储和菜单显示必须作为两个独立关注点处理：

- 菜单渲染继续受显示数量限制约束。
- 数据库保留使用更大的已存储历史记录上限。
- 搜索读取已存储的历史记录集合，而不只是当前可见的菜单项。
- 大体积资源必须设置同步边界，避免造成过多 OneDrive 变更和冲突。

## 历史来源与依赖清理

仍源自 Clipy 的文件保留原版权和 MIT 条款，但不得把历史来源描述成当前产品
上下游关系。生产依赖需要逐步移除或替换 `github.com/Clipy/*` 包；在完成替换
前，每项依赖必须有明确调用点和迁移处置记录。

## V1 不包含范围

- Microsoft Graph 或 OneDrive OAuth 集成。
- Pastera 内部的后台网络上传或下载代码。
- 重新引入基于 Realm 的剪贴板历史功能。
- 同步密钥、OAuth token 或明文同步口令。
