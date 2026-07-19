# Pastera 密码箱 CLI、Skill 与 MCP V1 实施计划（Implementation Plan）

> **当前确认门：** 产品与安全设计及中文书面规格已经确认。本文档是该需求在仓库内唯一的设计、实施与交付记录。

> **For agentic workers：** REQUIRED SUB-SKILL：使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，严格按任务顺序实施；每完成一个任务就更新复选框并进行独立审查，不得另建平行计划。

**目标（Goal）：** 为 Codex App 和 Claude Code 提供本地 Pastera 密码箱 CLI、共享 Agent Skill 与本地 stdio MCP 服务；按应用完成一次授权后，在有边界的无人值守期限内使用密码，同时保证工具输出不返回明文密码，并对性能与资源占用设置可验收上限。

**架构（Architecture）：** Pastera 继续作为唯一 KDBX 所有者。Codex、Claude Code 与人工 CLI 分别使用 Pastera 签名的独立适配器，通过用户私有 Unix Domain Socket 向应用进程内的 `PasteraVaultBroker` 发送有界请求。Broker 同时校验 Helper 代码身份与 Codex/Claude Host 父进程链、执行按应用授权、通过现有 store 边界串行处理 Keychain/KDBX 操作，并在不提供通用密码明文读取接口的前提下执行或授权秘密使用动作。

**技术栈（Tech Stack）：** 现有 App Target 保持 Swift 5 语言模式和 macOS 15 部署目标；新增共享模块与 Helper Target 使用 Swift 6。其余使用 AppKit、Foundation、CryptoKit、Security、LocalAuthentication、KDBXKit、固定为 `0.12.1` 的官方 [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)、Swift Testing、Xcode 26.5、本地 stdio MCP 与本地 Unix Domain Socket。官方 SDK 最低要求 Swift 6.0、macOS 13+，并提供 `StdioTransport`；V1 不需要 HTTP MCP 监听器，也不增加 Service Lifecycle 依赖。

## 全局约束（Global Constraints）

- Pastera 必须继续是唯一打开、解密、合并和保存 `PasteraVault.kdbx` 的组件。
- 不得新增会返回明文密码的 MCP 工具、CLI JSON 字段、日志路径或错误详情。
- V1 不向 Agent 暴露密码箱备注，因为备注可能包含非结构化秘密。
- 保持现有 KDBX 格式、OneDrive 路径、冲突语义、Keychain 快速解锁路径、主菜单密码箱 UI 和交互式 `LAContext` 行为兼容。
- Codex、Claude Code 与人工 CLI 必须具有不同的签名客户端身份和相互独立的授权。
- Codex/Claude 连接必须同时匹配应用包内签名 Helper 与安装时记录的签名 Host 父进程链；任意进程直接拉起已签名 Helper 不能借用已有授权。
- 保持现有 App Target 的 `SWIFT_VERSION = 5.0` 与 `MACOSX_DEPLOYMENT_TARGET = 15.0`；只对新增共享模块、Helper 和 Helper 测试启用 Swift 6。
- 初次授权的闲置有效期为 7 天；成功的敏感动作将闲置到期时间顺延 7 天，但任何授权都不得超过上次 macOS 身份验证后的 30 天。
- 状态查询、搜索、元数据读取、MCP 初始化、重试、失败和未使用的票据创建都不得续期。
- 无人值守解锁材料必须仅保存在本机、禁止同步、系统重启后必须先正常解锁 macOS 才可访问，并在不再存在有效外部授权时删除。
- V1 仅支持本地 macOS。远程 Codex 任务、远程 Claude 会话、云端 MCP、TCP 监听和跨设备授权不在范围内。
- 不新增 launchd 常驻服务。签名适配器可在需要时拉起一次 Pastera，Broker 仍运行在现有菜单栏应用进程中。
- 不得静默降低 Codex 或 Claude 的权限/沙箱策略。Pastera 授权表示应用信任；除非用户明确安装窄范围 Host 允许规则，否则 MCP 与 Shell 审批仍由 Host 独立控制。
- 所有 KDBX、Keychain、对端校验和 IPC 工作必须离开主线程，并复用当前密码箱串行 store 边界。
- 保留无关工作区改动以及未跟踪的 `.codex/config.toml` 与 `.superpowers/` 内容。

---

## 业务范围 / 不做范围（Business Scope / Out of Scope）

### 范围内（In Scope）

- 提供人工使用的 `pastera` CLI，支持集成管理、密码箱状态/搜索/元数据、直接粘贴、安全剪贴板复制和受控秘密注入。
- 提供 Codex 专用与 Claude 专用的签名 stdio MCP 适配器，并随 `Pastera.app` 一起发布。
- 提供一份规范源唯一的 `pastera-vault` Agent Skill；只在必要时添加 Host 专属元数据。
- 在 Pastera 偏好设置中新增 Agent 集成页面，支持安装、状态、卸载、首次授权、到期/续期展示、审计摘要和立即撤销。
- Agent 只读发现条目 ID、文件夹 ID/名称、标题、网站、用户名和更新时间。
- 将用户名或密码直接粘贴到当前前台目标，不把值返回给模型。
- 通过 30 秒单次票据，将秘密注入子进程 stdin 或继承文件描述符。
- 提供按应用授权、7 天滑动过期、30 天硬上限、本机无人值守恢复、限流、防重放和脱敏审计。
- 完成聚焦单元、集成、安全、性能测试，以及 Codex App 和 Claude Code 本地会话的真实验收。

### 不做范围（Out of Scope）

- 通过 CLI 或 MCP 创建、编辑、移动、排序或删除密码箱条目/文件夹。
- 向 Agent 返回密码、备注、原始 KDBX 记录、主密码、解锁密钥或解密后的数据库快照。
- 批量导出、备份、导入、密码生成、TOTP、Passkey、附件、浏览器扩展或表单字段识别。
- 通过环境变量、命令行参数或明文临时文件注入秘密。
- 在 Pastera 进程或 Broker 内执行任意命令。Agent 命令必须作为签名适配器的子进程运行，避免绕过 Host 的进程上下文和审批。
- Marketplace/Plugin 发布、远程 HTTP MCP、OAuth、团队/组织授权、Windows 或 Linux 支持。
- 超过上次 macOS 身份验证后 30 天仍自动续期。
- 在已授权客户端、当前 macOS 用户会话、管理员/root 或目标进程被完全攻陷后继续保护秘密。

## 当前系统事实

- `KDBXPasswordVaultStore` 已经在内存中保存解密后的 KDBX 快照和原始密钥解锁数据，串行处理文件访问，保留 KDBX 历史，合并外部变更，并在配置超时、休眠、会话失活和应用退出时自动锁定。
- `VaultUnlockKeyStore` 已使用 `.userPresence` 保存仅限本机的 KDBX 原始密钥；该交互式快速解锁条目保持不变。
- `PasswordVaultUIController` 已拥有串行 store queue、`LAContext.deviceOwnerAuthentication` 授权、直接粘贴、安全剪贴板复制和快照刷新能力。
- `SecureClipboardService` 已使用 concealed/transient Pasteboard 类型，能阻止秘密进入 Pastera 历史，并在 60 秒后仅清除仍未被替换的内容。
- Codex App/CLI/IDE 支持本地 stdio MCP 并共享 Codex MCP 配置；Claude Code 支持本地 stdio MCP 和用户级 Skill。V1 安装器调用官方 CLI 命令注册，不直接手写或覆盖无关配置。

## 架构与组件边界

### 1. Pastera Vault Broker

`PasteraVaultBroker` 位于现有应用进程中，是 Agent 请求的唯一新增运行时入口。它负责：

- 在权限为 `0700` 的目录中创建 `~/Library/Application Support/Pastera/Agent/v1/broker.sock`，并将 socket 权限设为 `0600`；
- 拒绝符号链接或非 socket 路径，发现未知既有文件时安全失败，绝不直接覆盖；
- 在协议协商前校验对端 UID、PID、可执行文件真实路径、代码有效性、签名标识和预期适配器身份；
- 从已验证的可执行文件推导客户端身份，不信任请求体中的客户端声明；
- 协商版本化请求/响应协议、连接随机数与递增请求号；
- 将授权后的工作转交现有密码箱 store queue；
- 统一管理授权、无人值守解锁可用性、限流、单次票据和脱敏审计；
- 在 Pastera 被激活前捕获当前前台粘贴目标，并使用后台方式拉起 Pastera，避免 `vault_paste` 误粘贴回 Pastera；
- 请求完成、取消、连接空闲或帧异常时关闭连接并清理请求级秘密缓冲。

Pastera 不监听 TCP、不发布 Bonjour，也不接受远程连接。

### 2. 共享协议模块

一组小型源码同时编译进应用与三个 Helper 产品，只包含：

- 协议版本常量；
- 根据已验证签名标识推导的客户端类型；
- 有界 Codable 请求/响应类型；
- 稳定错误码；
- 搜索分页与元数据 DTO；
- 单次票据和注入模式 DTO；
- 帧大小、超时和重试上限。

该模块不得导入 KDBXKit、AppKit UI、`PasswordVaultStore`、Keychain 实现或 MCP，从编译边界上阻止 Helper 直接访问数据库。

### 3. 签名客户端产品

Pastera 在应用包中发布三个可独立识别的 Helper：

- `PasteraCodexMCP`：Codex stdio MCP 服务与票据执行模式；
- `PasteraClaudeMCP`：Claude stdio MCP 服务与票据执行模式；
- `pastera`：人工 CLI，拥有独立授权与仅人工可用的安全复制命令。

两个 Agent 适配器共享实现源码，但使用不同的产品/签名标识。Broker 按当前已安装的 Pastera 应用包验证连接二进制。正式 Developer ID 构建在 designated requirement 稳定时允许普通升级后保留授权；ad-hoc/本地构建还必须匹配当前应用包内的预期 Helper 路径和精确代码身份，替换本地构建可能使授权失效。

### 4. MCP 层

Codex 与 Claude 产品使用 MCP Swift SDK `0.12.1` 和 `StdioTransport`，只暴露本文定义的 5 个 V1 工具。MCP 层解析有界 Schema、调用共享 Broker Client、把稳定错误映射成 MCP 结构化结果，并只通过 stdin/stdout 传输 MCP 协议。诊断信息只能写入已脱敏的 stderr/OSLog，不得包含敏感参数或结果。

### 5. Agent Skill

规范源唯一的 `pastera-vault` Skill 定义何时使用工具、如何缩小搜索、何时优先直接粘贴、如何兑换命令票据，以及哪些命令可能回显秘密而被禁止。Host 包装层可以增加 Codex UI 元数据，但工作流与安全规则保持单源。

### 6. 集成偏好设置与安装器

Pastera 新增 Agent 集成偏好页，为 Codex、Claude Code 与人工 CLI 各展示一行：

- 已安装/未安装；
- 已检测到的可执行文件与配置状态；
- 已授权/未授权；
- 7 天闲置到期时间和 30 天硬到期时间；
- 最近一次成功敏感动作时间；
- 安装/更新、授权/重新授权、撤销与卸载操作。

检测到相应客户端时，安装器调用当前官方命令：

~~~bash
codex mcp add pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP
claude mcp add --transport stdio --scope user pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraClaudeMCP
~~~

Codex Skill 安装到 `$HOME/.agents/skills/pastera-vault`，Claude Skill 安装到 `$HOME/.claude/skills/pastera-vault`。Pastera 保存安装所有权清单与内容摘要。只有当 Pastera 所有的已安装副本没有被用户修改时才自动更新；检测到用户修改必须报告冲突，不能覆盖。卸载只删除 Pastera 所有的 MCP 条目与 Skill 内容。

集成页可以提供 Pastera MCP 工具的窄范围 Host 权限片段，但应用这些规则必须是独立、明确的用户选择。Claude Code 只允许生成精确到已知工具名的 allowlist：推荐范围为 `vault_status`、`vault_search`、`vault_get`；把 `vault_paste`、`vault_prepare_exec` 加入免重复审批必须经过第二次独立确认。禁止使用 Server 级授权、glob、全局 bypass、宽泛 Shell 通配符或预授权未来工具。当前本机 Codex CLI 没有核查到可安全写入的单 MCP 工具 allowlist，因此 V1 只显示“由 Codex 管理工具审批”，不得写入全局 `approval_policy`、sandbox 或 bypass 配置；只有未来官方客户端提供并经兼容性测试确认窄权限能力后才可新增。若用户不选择，Codex/Claude 的常规工具与 Shell 审批保持不变，即使 Pastera 授权仍然有效。

## 授权与无人值守解锁

### 授权状态

每个外部客户端授权保存：

- 已验证客户端类型与签名要求；
- 允许的 Scope；
- `authorizedAt` 与 `lastMacOSAuthenticationAt`；
- `lastSensitiveUseAt`；
- `idleExpiresAt`；
- `absoluteExpiresAt`；
- 撤销状态与撤销原因；
- 协议代际。

实际到期时间为：

~~~text
min(lastSensitiveUseAt + 7 天, lastMacOSAuthenticationAt + 30 天)
~~~

初次授权把 `lastSensitiveUseAt` 设为授权时间。外部客户端成功完成秘密粘贴或票据注入时，只延长调用方的闲置到期时间。用户在 Pastera 内成功复制、粘贴或编辑密码时，延长当前所有有效外部授权，但每个授权仍受自己的 30 天硬上限约束。

以下动作绝不续期：

- 状态、搜索或元数据读取；
- MCP 初始化、ping、连接保活或工具发现；
- 创建后没有成功兑换的票据；
- 被取消、失败、超时、限流或重试的请求。

撤销、签名身份不匹配、协议代际失效或硬上限到期必须立即覆盖滑动到期时间。

### 首次授权

第一个有效请求为已验证客户端创建一条去重的待处理请求，并返回 `AUTHORIZATION_REQUIRED`。Pastera 展示应用身份、Scope、7 天闲置期限、30 天硬上限和无人值守风险提示。用户只进行一次 `LAContext.deviceOwnerAuthentication`。待处理期间的重复调用返回同一状态，绝不重复创建授权弹窗。

只有密码数据库已解锁时才能授权。如果数据库已锁定，用户先完成现有交互式快速解锁或主密码解锁。随后 Pastera 保存客户端授权，并把 KDBX 原始密钥写入独立的自动化 Keychain 条目：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`、`kSecAttrSynchronizable = false`，且仅允许已安装 Pastera 应用边界读取。

自动化条目不保存主密码。现有带 `.userPresence` 的快速解锁条目保持独立且不变。

### 冷恢复

Pastera 自动锁定、重启或 Mac 锁屏/解锁后，有效外部请求可读取自动化 Keychain 条目，通过 `UnlockData(rawKeyData:)` 重建解锁数据并重新打开 KDBX 快照，不再弹出 Pastera 验证。完整系统重启后，必须先正常登录并解锁 macOS，`AfterFirstUnlock` 材料才可访问。

如果自动化条目缺失、损坏、不可访问或无法解密当前 KDBX，Broker 删除该条目、锁定密码箱、使外部授权失效，返回稳定的不可重试错误并要求重新授权，绝不循环静默解锁。

当不再存在有效外部授权时，Pastera 删除自动化条目并锁定由 Broker 产生的会话状态。人工 Pastera 快速解锁仍使用现有交互式条目。

## 威胁模型与安全控制

### V1 能够防护

- 未签名或非预期本地进程连接 Broker socket；
- 外部客户端通过伪造客户端名称借用其他应用授权；
- 密码明文意外进入 MCP 输出、CLI JSON、日志、审计、临时文件、环境变量或进程参数；
- 无界列表输出、暴力请求循环、票据重放、跨连接重放、畸形帧和超大消息；
- 多个 Helper 并发访问 KDBX；
- 明确撤销、硬到期或签名身份变化后的陈旧授权；
- 秘密意外进入 Pastera 剪贴板历史或安全剪贴板长时间残留。

### 明确接受的风险

一次授权意味着用户主动信任该客户端：最多 7 天无敏感动作空闲期、最多 30 天绝对期限内，客户端可以重复请求允许的秘密动作。已授权的 Codex/Claude 进程如果被接管，攻击者可以利用现有授权。V1 不声称能够防护管理员/root、当前用户会话完全失陷、Pastera 进程被接管，或目标程序/命令主动泄露收到的秘密。

### 传输与防重放

- Broker 目录权限 `0700`，socket 权限 `0600`，要求相同有效 UID。
- 接受连接时捕获对端 PID 和可执行文件身份，并在处理请求前完成验证。
- 每个连接使用随机数与单调递增请求号，拒绝重复或乱序请求。
- 票据兑换中的秘密负载使用连接级 CryptoKit 会话密钥和认证加密。
- 最大帧 `64 KiB`，最大 MCP 结构化响应 `32 KiB`。
- 建连超时 3 秒，普通 Broker 请求 5 秒，冷 KDBX 恢复 10 秒。

### 秘密生命周期

- 搜索与元数据请求不加载密码值。
- 直接粘贴只加载一个密码，通过现有 Pastera 粘贴/安全剪贴板路径写入目标，请求完成后立即释放请求级引用。
- 命令注入先返回随机票据。兑换时，只有经过验证且匹配的适配器收到认证加密后的负载，并将其写入 stdin 或指定继承文件描述符。
- 票据 30 秒后过期，绑定客户端、条目、字段和注入模式，第一次兑换时原子删除。
- Swift/KDBXKit 无法保证每个 `String` 副本都可清零。V1 通过缩小作用域与生命周期、禁止缓存并增加泄漏测试来降低风险，不宣称无法实现的完全内存清零。

## 外部契约

### MCP 工具

| 工具 | 输入 | 输出 | 是否续期 |
| --- | --- | --- | --- |
| `vault_status` | 无 | 安装/授权状态、当前客户端到期时间、密码箱就绪状态、协议版本 | 否 |
| `vault_search` | 可选 `query`、可选 `folder_id`、默认 `20` 且最大 `50` 的 `limit`、可选不透明 `cursor` | 有界元数据分页与下一游标 | 否 |
| `vault_get` | `entry_id` | 条目 ID、文件夹元数据、标题、网站、用户名、更新时间 | 否 |
| `vault_paste` | `entry_id`、`field = username/password` | 只返回成功/失败 | 成功粘贴后 |
| `vault_prepare_exec` | `entry_id`、`field = username/password`、`mode = stdin/fd` | 随机单次票据、到期时间、适配器命令模板 | 之后成功兑换才续期 |

`vault_search` 和 `vault_get` 永不返回密码或备注。网站值可规范化展示，但不得发起网络请求。V1 授权不需要 MCP Resource、Prompt、Sampling、网络或 Elicitation；原生授权 UI 由 Pastera 管理。

工具描述将 `vault_status`、`vault_search`、`vault_get` 标记为只读且非破坏性。`vault_paste` 和 `vault_prepare_exec` 会促成外部动作，即使不修改密码箱，也必须标记为非只读。不得为了消除 Host 审批而错误标注秘密动作。

### CLI 命令

| 命令 | 用途 |
| --- | --- |
| `pastera integration install <codex-or-claude>` | 使用官方客户端命令注册 Pastera 所有的 MCP 与 Skill。 |
| `pastera integration status [codex-or-claude] [--json]` | 读取安装、授权和版本状态，不续期。 |
| `pastera integration uninstall <codex-or-claude>` | 只移除 Pastera 所有的配置与 Skill 内容。 |
| `pastera vault status [--json]` | 查看人工客户端密码箱状态。 |
| `pastera vault search [query] [--folder ID] [--limit N] [--cursor VALUE] [--json]` | 有界元数据搜索。 |
| `pastera vault get ID [--json]` | 只返回元数据。 |
| `pastera vault paste ID --field <username-or-password>` | 直接粘贴，不打印值。 |
| `pastera vault copy ID --field <username-or-password>` | 仅人工 CLI 授权；使用安全剪贴板并在 60 秒后条件清除。 |
| `<agent-adapter> exec --ticket T --stdin -- command ...` | 将票据对应秘密写入子进程 stdin。 |
| `<agent-adapter> exec --ticket T --fd N -- command ...` | 将票据对应秘密写入继承文件描述符 `N`。 |

所有 JSON 输出使用稳定封装：

~~~json
{"ok":true,"data":{}}
~~~

或：

~~~json
{"ok":false,"error":{"code":"GRANT_EXPIRED","message":"授权已过期。","retryable":false}}
~~~

两个封装都禁止出现秘密值。人工文本模式把诊断写入 stderr，把结构化结果写入 stdout。

### 稳定错误码

| 错误码 | 重试策略 |
| --- | --- |
| `AUTHORIZATION_REQUIRED` | 不自动重试；只展示一次授权说明。 |
| `GRANT_EXPIRED` / `GRANT_REVOKED` | 明确重新授权前不可重试。 |
| `VAULT_NOT_CONFIGURED` | 不可重试；引导用户在 Pastera 中完成设置。 |
| `AUTOMATION_UNLOCK_UNAVAILABLE` | 不可重试；交互式解锁后重新授权。 |
| `BROKER_UNAVAILABLE` | 适配器拉起 Pastera 后只重试一次。 |
| `VAULT_BUSY` / `RATE_LIMITED` | 仅在有界 `retry_after_ms` 后重试。 |
| `ENTRY_NOT_FOUND` | 重新搜索；错误中不得回显原始查询。 |
| `TARGET_UNAVAILABLE` | 不可重试；不得回退为输出明文。 |
| `TICKET_EXPIRED` / `TICKET_USED` | 丢弃票据，只允许重新准备一次。 |
| `PROTOCOL_MISMATCH` | 停止调用并要求更新组件。 |
| `INVALID_REQUEST` | 不可重试的输入/Schema 错误。 |

每个错误统一包含 `code`、本地化 `message`、`retryable` 和可选 `retry_after_ms`。Security、KDBX、文件系统、进程与解码错误必须映射，不能原样透传。

## Agent Skill 契约

当用户要求 Codex 或 Claude 查找、粘贴或使用 Pastera 中的凭据时，Skill 应触发并遵循：

1. 只有在就绪状态不确定时调用一次 `vault_status`。
2. 使用窄范围 `vault_search` 和有界分页，禁止列出或导出完整密码箱。
3. 仅使用元数据确认歧义，不请求或推断密码。
4. GUI 登录字段优先使用 `vault_paste`。
5. 终端使用先调用 `vault_prepare_exec`，再在 30 秒票据期限内执行返回的 Host 专属适配器模板。
6. 秘密动作周围禁止运行 `pbpaste`、`echo`、`printenv`、Shell trace、环境转储、进程参数转储或调试命令。
7. 禁止增加环境变量、命令参数、临时文件或日志回退路径。
8. 收到授权、撤销或协议错误后停止并让用户在 Pastera 中处理，禁止制造重复弹窗。
9. 用户要求直接显示、打印或导出秘密时，V1 明确不支持；改为提供直接粘贴或受控注入。

规范源唯一的 Skill 保持 `SKILL.md` 简洁，将工具/错误 Schema 放入 `references/tool-contract.md`，安全边界放入 `references/security-boundary.md`。不需要 Skill 脚本，因为所有确定性操作由签名可执行文件完成。

## 性能与资源预算

| 指标 | V1 预算 | 测量条件 |
| --- | --- | --- |
| 热态元数据搜索 | p95 `≤ 50 ms` | 10,000 条合成数据、默认返回 20 条、Broker 已连接且已解锁 |
| 冷态就绪 | p95 `≤ 2 s` | 参考开发 Mac 上适配器启动/连接 + Keychain/KDBX 恢复；主线程保持响应 |
| 单个适配器空闲 RSS | `≤ 30 MB` | stdio MCP 已初始化、无进行中请求、稳定后测量 |
| Broker 增量 RSS | `≤ 5 MB` | 与使用同一已解锁 KDBX 快照的 Pastera 基线比较 |
| 空闲 CPU | 约 `0%` | 不轮询，只使用事件驱动 socket/stdin 读取 |
| 搜索响应 | `≤ 32 KiB`、最多 50 条 | MCP 结构化输出或 CLI JSON |
| 秘密票据 | 30 秒、单次使用 | 不轮询清理；访问时校验并使用有界定时回收 |

V1 刻意使用有界线性元数据扫描，不建立常驻全文索引，以降低内存和同步成本。如果实测无法达到 10,000 条预算，后续只能增加“仅元数据索引”，不能缓存密码。

MCP 适配器只在 Host 会话持有 stdin 时长期运行。EOF 或 SIGTERM 触发正常关闭并清理连接状态。Broker 属于已经运行的 Pastera 进程，不增加 launchd 服务。

## 限流与审计

初始按客户端限额：

- 元数据调用：每分钟 60 次；
- 直接秘密动作：每分钟 10 次；
- 票据创建：每分钟 10 次；
- 签名/协议握手失败：立即拒绝连接，不创建授权请求。

审计只保存客户端类型、动作类别、使用本机审计密钥计算的条目 UUID 摘要、时间戳、结果码和延迟桶。禁止保存标题、文件夹名、网站、用户名、备注、查询、票据、命令、参数、密码、原始错误和文件路径。本地审计最多保留 1,000 条或 30 天，以先达到者为准。V1 不上传密码箱遥测。

## 计划文件与 Target 映射

### App Target

- 新建 `pastera/Sources/Services/VaultAgentBroker.swift`：socket 生命周期、版本握手、加密帧、请求分发和 Pastera 启动就绪。
- 新建 `pastera/Sources/Services/VaultAgentPeerVerifier.swift`：UID/PID/真实路径、Helper 代码签名、最多 4 层 Host 父进程链校验与已验证客户端类型推导。
- 新建 `pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift`：授权状态、7 天滑动到期、30 天硬到期、续期与撤销。
- 新建 `pastera/Sources/Services/VaultAgentAuthorizationCoordinator.swift`：首次请求去重、单次原生授权、取消冷却与偏好页显式重试。
- 新建 `pastera/Sources/Services/VaultAgentGrantStore.swift`：`AfterFirstUnlockThisDeviceOnly` Keychain 授权持久化，不把授权或秘密写入 Defaults/日志。
- 新建 `pastera/Sources/Services/VaultAutomationUnlockKeyStore.swift`：独立 `AfterFirstUnlockThisDeviceOnly` 原始密钥条目与删除生命周期。
- 新建 `pastera/Sources/Services/VaultAgentTicketStore.swift`：30 秒、绑定客户端、单次使用的票据。
- 新建 `pastera/Sources/Services/VaultAgentRateLimiter.swift`：有界按客户端时间窗。
- 新建 `pastera/Sources/Services/VaultAgentAuditLogger.swift`：脱敏有界审计和本机指标。
- 新建 `pastera/Sources/Services/VaultAgentPasteTargetTracker.swift`：事件驱动记录最近一个非 Pastera、非 Agent Host 的可恢复粘贴目标。
- 新建 `pastera/Sources/Services/VaultAgentIntegrationInstaller.swift`：官方 CLI 参数调用、Skill 原子安装、所有权摘要、冲突安全更新与卸载。
- 新建 `pastera/Sources/Services/VaultAgentRuntime.swift`：组装 Broker、授权、安装、Store 访问和偏好页状态，不新增全局常驻服务。
- 修改 `pastera/Sources/Services/PasswordVaultStore.swift`：暴露窄范围自动化解锁生命周期，不向调用方暴露原始密钥。
- 修改 `pastera/Sources/Services/KDBXPasswordVaultStore.swift`：在 store 边界内创建/恢复独立自动化密钥，保留现有交互式快速解锁。
- 修改 `pastera/Sources/Managers/PasswordVaultUIController.swift`：通过现有 queue 提供 Broker 的状态、搜索、元数据、粘贴和一次性秘密消费接口，并发布交互式敏感动作续期事件。
- 修改 `pastera/Sources/Managers/MenuManager.swift`：复用唯一 `PasswordVaultUIController`，避免 UI 与 Broker 各自创建 store queue。
- 修改 `pastera/Sources/Environments/Environment.swift` 与 `pastera/Sources/Environments/AppEnvironment.swift`：注入共享密码箱 Controller 和 `VaultAgentRuntime`，保持测试可替换。
- 修改 `pastera/Sources/AppDelegate.swift`：随应用生命周期启停事件驱动 Broker；空闲时不解锁 KDBX、不轮询。
- 新建 `pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift`：集成状态、安装、授权、到期、撤销和卸载 UI。
- 修改 `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift` 与 `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`：注册并导航 Agent 集成页面。
- 修改 `pastera/Resources/Localizable.xcstrings`：本地化集成、授权、到期、安全和错误文案。

### 共享模块与 Helper Target

- 新建 `pastera-agent/Sources/PasteraAgentProtocol/VaultAgentProtocol.swift`：共享操作、元数据 DTO、稳定错误和资源上限。
- 新建 `pastera-agent/Sources/PasteraAgentProtocol/VaultAgentFrames.swift`：握手、连接 ID、序列号、长度前缀与加密帧 DTO。
- 新建 `pastera-agent/Sources/PasteraAgentAdapter/VaultAgentClient.swift`：Unix socket Client、应用拉起、握手、加密请求与稳定错误映射。
- 新建 `pastera-agent/Sources/PasteraAgentAdapter/PasteraMCPServer.swift`：MCP Swift SDK 工具描述、Schema、结构化结果与 stdio Handler。
- 新建 `pastera-agent/Sources/PasteraAgentAdapter/VaultAgentCommandRunner.swift`：不经 Shell 的 `posix_spawnp` stdin/fd 票据消费。
- 新建 `pastera-agent/Sources/PasteraAgentAdapter/VaultCLI.swift`：人工 CLI 解析、文本/JSON 封装与集成子命令。
- 新建 `pastera-agent/Sources/PasteraCodexMCP/main.swift`：Codex 客户端身份与 MCP/exec 入口。
- 新建 `pastera-agent/Sources/PasteraClaudeMCP/main.swift`：Claude 客户端身份与 MCP/exec 入口。
- 新建 `pastera-agent/Sources/PasteraCLI/main.swift`：人工 CLI 入口。
- 修改 `pastera.xcodeproj/project.pbxproj`：增加 `PasteraAgentProtocol`、`PasteraAgentAdapter`、`PasteraCodexMCP`、`PasteraClaudeMCP`、`pastera` 与 `pasteraAgentTests` Target，固定官方 MCP Package `0.12.1`，嵌入三个 Helper 并定义签名标识。
- 修改 `pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme` 与 `pastera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`：把 Helper 测试纳入共享测试入口并锁定依赖解析。

### Skill 与安装资源

- 新建 `integrations/pastera-vault/SKILL.md`：跨 Host 的规范源唯一工作流。
- 新建 `integrations/pastera-vault/references/tool-contract.md`：MCP/CLI Schema 与错误处理。
- 新建 `integrations/pastera-vault/references/security-boundary.md`：禁止明文读取与安全使用约束。
- 新建 `integrations/pastera-vault/agents/openai.yaml`：根据规范 Skill 生成 Codex UI 元数据。
- 将 `integrations/pastera-vault/` 作为只读目录资源嵌入 App；运行时所有权清单写入用户私有 Application Support，只记录路径与 SHA-256 摘要，不得把凭据或本机配置写入仓库。

### 测试

- 新建 `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`。
- 新建 `pasteraTests/VaultAgentBrokerTests.swift`。
- 新建 `pasteraTests/VaultAgentPeerVerifierTests.swift`。
- 新建 `pasteraTests/VaultAgentTicketStoreTests.swift`。
- 新建 `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`。
- 新建 `pasteraTests/VaultAgentLeakRegressionTests.swift`。
- 新建 `pasteraTests/VaultAgentPerformanceTests.swift`。
- 新建 `pasteraTests/AgentIntegrationPreferenceTests.swift` 并扩展 `pasteraTests/PreferenceSearchTests.swift`。
- 新建 `pasteraAgentTests/VaultAgentProtocolTests.swift`、`pasteraAgentTests/VaultAgentClientTests.swift`、`pasteraAgentTests/PasteraMCPServerTests.swift`、`pasteraAgentTests/VaultCLITests.swift` 与 `pasteraAgentTests/VaultAgentCommandRunnerTests.swift`，覆盖协议、MCP Schema、stdio 生命周期、CLI JSON/文本封装和适配器票据执行。
- 新建仅测试的 `pasteraAgentTests/Fixtures/SecretConsumer/main.swift` 与 `PasteraSecretConsumerFixture` Target，真实验证 stdin/fd 且只输出字节数。
- 扩展 `pasteraTests/PasswordVaultStoreTests.swift`、`pasteraTests/PasswordVaultMenuTests.swift` 与 `pasteraTests/SecureClipboardServiceTests.swift`，覆盖兼容性和集成续期行为。

## 实施任务（Superpowers Tasks）

任务必须按顺序执行。每个任务结束时只提交该任务列出的文件；如果前一任务的接口需要改变，先在本文件的 `Plan Deviations` 中记录原因并重新核对后续接口名，不得在实现中静默漂移。

统一聚焦测试命令使用仓库现有无签名构建参数：

~~~bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test
~~~

### Task 1：建立共享协议模块与有界 Wire Contract

**Files：**

- Create: `pastera-agent/Sources/PasteraAgentProtocol/VaultAgentProtocol.swift`
- Create: `pastera-agent/Sources/PasteraAgentProtocol/VaultAgentFrames.swift`
- Create: `pasteraAgentTests/VaultAgentProtocolTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme`

**Interfaces：**

- Consumes: 无；这是 App、Broker、CLI 与 MCP Helper 的协议根。
- Produces: `VaultAgentClientKind`、`VaultAgentOperation`、`VaultAgentResponseBody`、`VaultAgentErrorCode`、`VaultAgentRequestEnvelope`、`VaultAgentResponseEnvelope`、握手/加密帧 DTO 和固定资源上限。

- [x] **Step 1：先写协议表面失败测试**

~~~swift
import Foundation
import Testing
@testable import PasteraAgentProtocol

@Suite("Vault agent protocol")
struct VaultAgentProtocolTests {
    @Test("metadata schema cannot encode notes or passwords")
    func metadataSchemaCannotEncodeSecrets() throws {
        let value = VaultAgentEntryMetadata(
            id: UUID(),
            folderID: UUID(),
            folderName: "Work",
            title: "Mail",
            website: "https://example.test",
            username: "alice",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("password"))
        #expect(!json.localizedCaseInsensitiveContains("note"))
    }

    @Test("frame codec rejects payloads above the fixed limit")
    func frameCodecRejectsOversizedPayload() {
        let bytes = Data(repeating: 0x41, count: VaultAgentLimits.maximumFrameBytes + 1)
        #expect(throws: VaultAgentProtocolError.frameTooLarge) {
            try VaultAgentFrameCodec.frame(payload: bytes)
        }
    }
}
~~~

- [x] **Step 2：运行测试并确认因模块和类型尚不存在而失败**

Run：在统一命令末尾追加 `-only-testing:pasteraAgentTests/VaultAgentProtocolTests`。

Expected：FAIL，错误明确指向 `no such module 'PasteraAgentProtocol'` 或首个缺失类型。

- [x] **Step 3：增加静态库 Target 并实现精确协议类型**

`PasteraAgentProtocol` 与 `pasteraAgentTests` 使用 `SWIFT_VERSION = 6.0`；现有 `pastera` 与 `pasteraTests` 保持 `5.0`。公开类型按以下表面实现，所有集合和字符串在解码后再次做上限校验：

~~~swift
public enum VaultAgentLimits {
    public static let protocolVersion = 1
    public static let maximumFrameBytes = 65_536
    public static let maximumQueryBytes = 512
    public static let maximumPageSize = 50
    public static let defaultPageSize = 20
    public static let maximumResponseBytes = 32 * 1_024
    public static let maximumMetadataFieldBytes = 2_048
    public static let maximumCursorBytes = 2_048
    public static let maximumTokenBytes = 1_024
    public static let maximumPathBytes = 4_096
    public static let maximumCommandArguments = 64
    public static let maximumCommandArgumentBytes = 4_096
    public static let maximumErrorMessageBytes = 1_024
    public static let maximumSecretBytes = 16 * 1_024
    public static let publicKeyBytes = 32
    public static let nonceBytes = 32
}

public enum VaultAgentProtocolError: Error, Equatable, Sendable {
    case frameTooLarge
    case malformedFrame
    case limitExceeded
    case invalidValue
}

public enum VaultAgentClientKind: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claude
    case cli
}

public enum VaultAgentSecretField: String, Codable, Sendable {
    case username
    case password
}

public enum VaultAgentInjectionMode: String, Codable, Sendable {
    case stdin
    case fileDescriptor
}

public enum VaultAgentHostKind: String, Codable, Sendable {
    case codex
    case claude
}

public struct VaultAgentEntryMetadata: Codable, Equatable, Sendable {
    public let id: UUID
    public let folderID: UUID
    public let folderName: String
    public let title: String
    public let website: String
    public let username: String
    public let updatedAt: Date
}

public struct VaultAgentSearchRequest: Codable, Equatable, Sendable {
    public let query: String?
    public let folderID: UUID?
    public let limit: Int
    public let cursor: String?
}

public struct VaultAgentSearchPage: Codable, Equatable, Sendable {
    public let entries: [VaultAgentEntryMetadata]
    public let nextCursor: String?
}

public struct VaultAgentStatus: Codable, Equatable, Sendable {
    public let client: VaultAgentClientKind
    public let installed: Bool
    public let authorized: Bool
    public let vaultReady: Bool
    public let idleExpiresAt: Date?
    public let hardExpiresAt: Date?
    public let protocolVersion: Int
}

public struct VaultAgentPreparedTicket: Codable, Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let command: [String]
}

public struct VaultAgentSecretDelivery: Codable, Equatable, Sendable {
    public let receiptID: UUID
    public let bytes: Data
}

public enum VaultAgentOperation: Codable, Equatable, Sendable {
    case status
    case search(VaultAgentSearchRequest)
    case get(entryID: UUID)
    case paste(entryID: UUID, field: VaultAgentSecretField)
    case copy(entryID: UUID, field: VaultAgentSecretField)
    case prepareExec(entryID: UUID, field: VaultAgentSecretField, mode: VaultAgentInjectionMode)
    case redeemTicket(token: String, mode: VaultAgentInjectionMode)
    case completeTicket(receiptID: UUID)
    case integrationStatus(host: VaultAgentHostKind?)
    case integrationInstall(host: VaultAgentHostKind)
    case integrationUninstall(host: VaultAgentHostKind)
}
~~~

错误与响应类型使用以下精确表面：

~~~swift
public enum VaultAgentErrorCode: String, Codable, CaseIterable, Error, Sendable {
    case authorizationRequired = "AUTHORIZATION_REQUIRED"
    case grantExpired = "GRANT_EXPIRED"
    case grantRevoked = "GRANT_REVOKED"
    case vaultNotConfigured = "VAULT_NOT_CONFIGURED"
    case automationUnlockUnavailable = "AUTOMATION_UNLOCK_UNAVAILABLE"
    case brokerUnavailable = "BROKER_UNAVAILABLE"
    case vaultBusy = "VAULT_BUSY"
    case rateLimited = "RATE_LIMITED"
    case entryNotFound = "ENTRY_NOT_FOUND"
    case targetUnavailable = "TARGET_UNAVAILABLE"
    case ticketExpired = "TICKET_EXPIRED"
    case ticketUsed = "TICKET_USED"
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case invalidRequest = "INVALID_REQUEST"
}

public struct VaultAgentFailure: Codable, Equatable, Sendable {
    public let code: VaultAgentErrorCode
    public let message: String
    public let retryable: Bool
    public let retryAfterMilliseconds: Int?
}

public struct VaultAgentHostIntegrationStatus: Codable, Equatable, Sendable {
    public let host: VaultAgentHostKind
    public let hostDetected: Bool
    public let hostExecutablePath: String?
    public let mcpInstalled: Bool
    public let skillInstalled: Bool
    public let installedVersion: String?
    public let authorized: Bool
    public let idleExpiresAt: Date?
    public let hardExpiresAt: Date?
}

public struct VaultAgentIntegrationStatus: Codable, Equatable, Sendable {
    public let hosts: [VaultAgentHostIntegrationStatus]
}

public enum VaultAgentResponsePayload: Codable, Equatable, Sendable {
    case empty
    case status(VaultAgentStatus)
    case search(VaultAgentSearchPage)
    case entry(VaultAgentEntryMetadata)
    case ticket(VaultAgentPreparedTicket)
    case secretDelivery(VaultAgentSecretDelivery)
    case integrationStatus(VaultAgentIntegrationStatus)
}

public enum VaultAgentResponseBody: Codable, Equatable, Sendable {
    case success(VaultAgentResponsePayload)
    case failure(VaultAgentFailure)
}
~~~

`VaultAgentFailure.retryAfterMilliseconds` 编码键固定为 `retry_after_ms`。`VaultAgentResponseBody` 只能是上述互斥的 `success` 或 `failure`，禁止同时出现 data 和 error。

所有带关联值的 wire enum 禁止依赖 Swift 自动合成的关联值布局，必须手写稳定 `Codable`：顶层使用字符串 `type` 鉴别器，可选关联对象使用 `payload`。`VaultAgentOperation` 的 type 固定为 `status`、`search`、`get`、`paste`、`copy`、`prepare_exec`、`redeem_ticket`、`complete_ticket`、`integration_status`、`integration_install`、`integration_uninstall`；`VaultAgentResponseBody` 固定为 `success`/`failure`；`VaultAgentResponsePayload` 固定为 `empty`、`status`、`search`、`entry`、`ticket`、`secret_delivery`、`integration_status`。未知 type 必须抛出 `VaultAgentProtocolError.invalidValue`。

外部解码后执行以下边界：query ≤ 512 UTF-8 bytes；limit 为 1...50；每页 entries ≤ 50；metadata 每个字符串 ≤ 2,048 bytes；cursor ≤ 2,048 bytes；ticket token ≤ 1,024 bytes；Host 路径与每个命令参数 ≤ 4,096 bytes；命令参数 ≤ 64 个；错误消息 ≤ 1,024 bytes；秘密 bytes ≤ 16 KiB；集成 Host 行 ≤ 2；握手 public key 与 nonce 分别严格为 32 bytes；ciphertext 与任何完整 frame ≤ 65,536 bytes。响应编码结果还必须 ≤ 32 KiB。越界统一抛出 `VaultAgentProtocolError.limitExceeded`；结构/枚举无效抛出 `invalidValue`，长度前缀不一致抛出 `malformedFrame`。

- [x] **Step 4：实现长度前缀、握手与加密帧 DTO**

~~~swift
public struct VaultAgentClientHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let publicKey: Data
    public let nonce: Data
}

public struct VaultAgentServerHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let publicKey: Data
    public let nonce: Data
}

public struct VaultAgentEncryptedFrame: Codable, Equatable, Sendable {
    public let connectionID: UUID
    public let sequence: UInt64
    public let ciphertext: Data
}

public struct VaultAgentRequestEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let sequence: UInt64
    public let requestID: UUID
    public let operation: VaultAgentOperation
}

public struct VaultAgentResponseEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let sequence: UInt64
    public let requestID: UUID
    public let body: VaultAgentResponseBody
}

public enum VaultAgentFrameCodec {
    public static func frame(payload: Data) throws -> Data {
        guard payload.count <= VaultAgentLimits.maximumFrameBytes else {
            throw VaultAgentProtocolError.frameTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + payload
    }

    public static func payload(from frame: Data) throws -> Data {
        guard frame.count >= MemoryLayout<UInt32>.size else {
            throw VaultAgentProtocolError.malformedFrame
        }
        let declared = frame.prefix(4).reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        guard declared <= VaultAgentLimits.maximumFrameBytes,
              frame.count == Int(declared) + 4 else {
            throw VaultAgentProtocolError.malformedFrame
        }
        return frame.dropFirst(4)
    }
}
~~~

- [x] **Step 5：运行协议测试并验证 App Target 仍可构建**

Run：统一命令追加 `-only-testing:pasteraAgentTests/VaultAgentProtocolTests -only-testing:pasteraTests/PasswordVaultStoreTests`。

Expected：PASS，且 `pastera.xcodeproj` 中现有 App Target 的 Swift/部署目标未改变。

- [x] **Step 6：提交协议闭环**

~~~bash
git add pastera-agent/Sources/PasteraAgentProtocol pasteraAgentTests/VaultAgentProtocolTests.swift \
  pastera.xcodeproj/project.pbxproj pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme
git commit -m "feat(agent): 建立密码箱共享协议"
~~~

### Task 2：实现按应用授权、7 天滑动期与 30 天硬上限

**Files：**

- Create: `pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift`
- Create: `pastera/Sources/Services/VaultAgentGrantStore.swift`
- Create: `pastera/Sources/Services/VaultAgentAuthorizationCoordinator.swift`
- Create: `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`
- Modify: `pastera-agent/Sources/PasteraAgentProtocol/VaultAgentProtocol.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: `VaultAgentClientKind`。
- Produces: `VaultAgentPeerIdentity`、`VaultAgentGrant`、`VaultAgentGrantDecision`、`VaultAgentGrantStoring`、`VaultAgentAuthorizationPolicy` 与首次授权协调器；Task 5 负责从真实进程生成这里定义的 identity。

- [x] **Step 1：写确定性时间与客户端隔离失败测试**

~~~swift
@Test("sensitive success slides idle expiry but never crosses hard expiry")
func sensitiveSuccessSlidesIdleExpiry() throws {
    let start = Date(timeIntervalSince1970: 10_000)
    let store = InMemoryVaultAgentGrantStore()
    let executor = VaultAgentSerialExecutor(
        queue: DispatchQueue(label: "test.pastera.password-vault.store")
    )
    let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
    let identity = VaultAgentPeerIdentity.testValue(client: .codex)
    try policy.authorize(identity: identity, authenticatedAt: start)

    let useTime = start.addingTimeInterval(6 * 24 * 60 * 60)
    try policy.recordSensitiveSuccess(for: identity, at: useTime)
    let grant = try #require(store.grants[.codex])

    #expect(grant.idleExpiresAt == useTime.addingTimeInterval(7 * 24 * 60 * 60))
    #expect(grant.hardExpiresAt == start.addingTimeInterval(30 * 24 * 60 * 60))
}

@Test("metadata and failed actions do not renew")
func nonSensitiveActionsDoNotRenew() throws {
    let start = Date(timeIntervalSince1970: 20_000)
    let store = InMemoryVaultAgentGrantStore()
    let executor = VaultAgentSerialExecutor(
        queue: DispatchQueue(label: "test.pastera.password-vault.store")
    )
    let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
    let identity = VaultAgentPeerIdentity.testValue(client: .claude)
    try policy.authorize(identity: identity, authenticatedAt: start)
    let original = try #require(store.grants[.claude])

    _ = policy.decision(for: identity, at: start.addingTimeInterval(60))
    policy.recordFailure(for: identity, at: start.addingTimeInterval(120))

    #expect(store.grants[.claude] == original)
    #expect(store.grants[.codex] == nil)
}
~~~

- [x] **Step 2：运行并确认授权类型缺失**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests`。

Expected：FAIL，首个错误为 `cannot find 'VaultAgentAuthorizationPolicy' in scope`。

- [x] **Step 3：实现授权模型和唯一续期入口**

~~~swift
struct VaultAgentPeerIdentity: Codable, Equatable {
    let client: VaultAgentClientKind
    let helperRequirement: String
    let helperCDHash: Data?
    let helperIsAdHoc: Bool
    let helperPath: String
    let hostRequirement: String?
    let hostCDHash: Data?
    let hostIsAdHoc: Bool?
    let hostPath: String?
}

struct VaultAgentGrant: Codable, Equatable {
    let identity: VaultAgentPeerIdentity
    let authenticatedAt: Date
    var idleExpiresAt: Date
    let hardExpiresAt: Date
    var lastSensitiveUseAt: Date?
    var revokedAt: Date?
}

enum VaultAgentGrantDecision: Equatable {
    case allowed(VaultAgentGrant)
    case missing
    case identityChanged
    case idleExpired
    case hardExpired
    case revoked
}

protocol VaultAgentGrantStoring {
    func load() throws -> [VaultAgentClientKind: VaultAgentGrant]
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws
}

final class VaultAgentSerialExecutor {
    init(queue: DispatchQueue)
    func sync<T>(_ work: () throws -> T) rethrows -> T
    func async(_ work: @escaping () -> Void)
}

final class VaultAgentAuthorizationPolicy {
    static let idleLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let hardLifetime: TimeInterval = 30 * 24 * 60 * 60

    init(store: VaultAgentGrantStoring, executor: VaultAgentSerialExecutor) throws
    @discardableResult
    func authorize(identity: VaultAgentPeerIdentity, authenticatedAt: Date) throws -> VaultAgentGrant
    func decision(for identity: VaultAgentPeerIdentity, at: Date) -> VaultAgentGrantDecision
    func recordSensitiveSuccess(for identity: VaultAgentPeerIdentity, at: Date) throws
    func recordInteractiveSensitiveSuccess(at: Date) throws
    func recordFailure(for identity: VaultAgentPeerIdentity, at: Date)
    func revoke(_ client: VaultAgentClientKind, at: Date) throws
    func revokeAll(at: Date) throws
    func validGrantCount(at: Date) -> Int
}
~~~

`recordSensitiveSuccess` 必须计算 `min(now + 7 days, hardExpiresAt)`；`recordInteractiveSensitiveSuccess` 只续期当前仍有效的授权；`decision` 遇到 identity 变化或到期时不自动创建新授权。

`VaultAgentSerialExecutor` 必须包装外部传入的 `DispatchQueue`，通过 queue-specific 标记支持同队列重入；它不能自行创建第二条授权队列。Policy 初始化时通过该 executor 只从 Store 加载一次到内存；即使调用方在主线程调用 Policy，所有 Store `load`/`save` 也必须在 executor 对应的密码箱串行队列执行。加载失败直接抛出，不得静默当成空授权。所有变更先基于副本计算并成功 `save`，再替换内存状态，避免 Keychain 写失败后内存与持久化分叉。`revoke`/`revokeAll` 设置 `revokedAt` 而不是删除记录，因此后续 `decision` 可稳定返回 `revoked`；`validGrantCount` 排除撤销、闲置到期和硬到期授权。Task 3 将把现有 `PasswordVaultUIController.storeQueue` 包装为唯一 executor，并同时注入 Policy、Coordinator 与 Broker。

Identity 匹配不能直接使用结构体全量相等：正式签名 Helper/Host 比较 client、designated requirement 和规范真实路径，允许 cdhash 随普通升级变化；ad-hoc 一侧必须额外精确匹配 cdhash。任何一侧从正式签名变为 ad-hoc、requirement/path 变化或签名失效都返回 `identityChanged`。

进入授权前还必须校验身份元组完整性：所有客户端都要求 Helper requirement/path 非空，ad-hoc Helper 还要求 cdhash；Codex 与 Claude 必须同时提供非空 Host requirement/path 和 `hostIsAdHoc`，ad-hoc Host 还要求 cdhash；独立 CLI 必须完全不带 Host 字段。缺失、部分存在或混合的 Host 元组不得创建 Grant，`authorize` 稳定抛出 `AUTHORIZATION_REQUIRED`，`identitiesMatch` 返回 `false`。

- [x] **Step 4：实现 Keychain Grant Store 与首次请求去重**

`VaultAgentGrantStore` 使用 service `com.pastera-app.Pastera.agent-grants.v1`、account `grants`、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 和 `kSecAttrSynchronizable = false`。更新采用单个编码对象覆盖，Keychain 错误只映射为稳定错误，不输出原始查询。`errSecItemNotFound` 映射为空字典；其他 Security 状态、编码损坏和写失败统一抛出 `VaultAgentErrorCode.automationUnlockUnavailable`。Store 通过窄 `VaultAgentKeychainAccessing` 依赖调用 `SecItemCopyMatching`/`SecItemAdd`/`SecItemUpdate`，测试使用真实查询字典 Probe，不增加生产测试分支。

Task 1 的 `VaultAgentErrorCode` 在本任务增加 `Error` conformance，`VaultAgentClientKind` 增加字典键所需的 `Hashable` conformance；wire raw value 与编码布局不变。这是 Swift `Result<VaultAgentGrant, VaultAgentErrorCode>` 与授权字典的编译前提。

~~~swift
final class VaultAgentAuthorizationCoordinator {
    enum Trigger {
        case automaticFirstRequest
        case explicitPreferencesAction
    }

    func authorize(
        identity: VaultAgentPeerIdentity,
        trigger: Trigger,
        completion: @escaping (Result<VaultAgentGrant, VaultAgentErrorCode>) -> Void
    )
}
~~~

Coordinator 注入与 Policy 相同的 `VaultAgentSerialExecutor`、`VaultAgentAuthorizationPolicy`、`VaultAgentIdentityAuthenticating`、`UserDefaults` 和 `now: () -> Date`，不得在内部新建独立队列。生产 authenticator 每次流程创建新的 `LAContext` 并调用 `deviceOwnerAuthentication`；测试使用协议 Probe。回调统一回到共享 executor 后再读写 pending/cooldown，completion 最终投递主队列，禁止跨线程并发修改字典。身份验证开始后 Coordinator 必须被该次 in-flight 流程强持有到回调完成，调用方释放外部引用也不得吞掉 pending completion；每个 completion 仍只能调用一次。

同一客户端且 identity 匹配的并发请求合并为一个 `LAContext` 流程并向所有等待者返回同一结果；同一客户端等待期间出现不同 identity 时立即返回 `AUTHORIZATION_REQUIRED`，不得加入旧流程。Codex、Claude、CLI 三者不得共用 pending 状态。自动首次请求被 `LAError.userCancel`、`systemCancel` 或 `appCancel` 取消后，把 24 小时冷却截止时间分别保存到 `UserDefaults` 键 `Pastera.Agent.AuthorizationCooldownUntil.v1.<client>`；该时间戳不是授权或秘密。冷却期内 automatic trigger 不创建 `LAContext`，只返回 `AUTHORIZATION_REQUIRED`；explicit preferences trigger 忽略冷却并可立即重试。授权成功先由 Policy 原子保存 Grant，再清除该客户端冷却；身份验证失败或持久化失败不得创建 Grant。

- [x] **Step 5：补 Keychain 属性、去重、撤销与硬上限测试并运行**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests`。

Expected：PASS，覆盖 7 天边界前后、30 天边界、取消冷却、Codex/Claude 隔离、交互式动作续期全部有效 Grant；还要覆盖 Codex/Claude 缺失或部分 Host 元组被拒绝、Host requirement/path/ad-hoc/cdhash 变化被拒绝、CLI 无 Host 可授权、Coordinator 外部引用释放后 completion 仍恰好一次返回，以及 Policy 的 Keychain Probe `load`/`save` 全部运行在注入的非主线程串行 executor。

- [x] **Step 6：提交授权闭环**

~~~bash
git add pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift \
  pastera/Sources/Services/VaultAgentGrantStore.swift \
  pastera/Sources/Services/VaultAgentAuthorizationCoordinator.swift \
  pasteraTests/VaultAgentAuthorizationPolicyTests.swift \
  pastera-agent/Sources/PasteraAgentProtocol/VaultAgentProtocol.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 增加按应用滑动授权"
~~~

### Task 3：增加无人值守自动化密钥并复用唯一 Store Queue

**Files：**

- Create: `pastera/Sources/Services/VaultAutomationUnlockKeyStore.swift`
- Create: `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`
- Modify: `pastera/Sources/Services/PasswordVaultStore.swift`
- Modify: `pastera/Sources/Services/KDBXPasswordVaultStore.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pastera/Sources/Managers/MenuManager.swift`
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pastera/Sources/Environments/AppEnvironment.swift`
- Modify: `pasteraTests/PasswordVaultStoreTests.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: 当前 KDBX `UnlockData.keyDataBytes`、现有交互式 `VaultUnlockKeyStore`、Task 2 的 `VaultAgentSerialExecutor`；有效 Grant 数在 Task 6 Runtime 接线时消费。
- Produces: `VaultAutomationUnlockKeyStoring`、`PasswordVaultStore.enableAutomationUnlock()`、`unlockForAutomation()`、`disableAutomationUnlock()`、复用现有 store queue 的共享 executor 与单一共享 `PasswordVaultUIController`。

- [x] **Step 1：写交互式密钥与自动化密钥隔离失败测试**

~~~swift
@Test("automation key restores a locked KDBX without reading the interactive key")
func automationKeyRestoresLockedStore() throws {
    let root = temporaryVaultRoot()
    let interactive = VaultUnlockKeyStoreProbe()
    let automation = VaultAutomationUnlockKeyStoreProbe()
    let store = KDBXPasswordVaultStore(
        syncRootProvider: { root },
        unlockKeyStore: interactive,
        automationUnlockKeyStore: automation
    )
    try store.createDatabase(masterPassword: "master", rememberQuickUnlock: true)
    try store.enableAutomationUnlock()
    store.lock()
    try store.unlockForAutomation()

    #expect(store.state == .unlocked)
    #expect(interactive.loadCallCount == 0)
    #expect(automation.loadCallCount == 1)
}
~~~

- [x] **Step 2：运行并确认新协议方法缺失**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests -only-testing:pasteraTests/PasswordVaultStoreTests`。

Expected：FAIL，指向 `extra argument 'automationUnlockKeyStore'` 或缺失方法。

- [x] **Step 3：实现独立 Keychain 条目和 Store 生命周期**

~~~swift
protocol VaultAutomationUnlockKeyStoring {
    var containsKey: Bool { get }
    func save(_ data: Data) throws
    func load() throws -> Data
    func delete() throws
}

extension PasswordVaultStore {
    var canAutomationUnlock: Bool { false }
    func enableAutomationUnlock() throws { throw PasswordVaultError.keychainUnavailable }
    func unlockForAutomation() throws { throw PasswordVaultError.keychainUnavailable }
    func disableAutomationUnlock() throws {}
}
~~~

`VaultAutomationUnlockKeyStore` 使用 service `com.pastera-app.Pastera.password-vault.agent-unlock.v1`、account `PasteraVaultAgentUnlock`、32 字节值、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 与 `kSecAttrSynchronizable = false`；不得使用 `SecAccessControl` 或 `userPresence`。通过独立窄 `VaultAutomationKeychainAccessing` 依赖封装 copy/update/add/delete，生产实现才调用 Security，测试检查真实查询字典。`save` 先 update、仅 `errSecItemNotFound` 时 add，不得先 delete 造成失败窗口；`delete` 接受 success/item-not-found；`containsKey` 不读取数据、不触发 UI。

`KDBXPasswordVaultStore.enableAutomationUnlock` 只能在 `.unlocked` 或仍持有可读内容的 `.readOnlyWarning` 且确实持有 `unlockData` 时，将 `keyDataBytes` 的 32 字节局部副本保存；仅有残留 `unlockData` 不能通过。它不能读取或覆盖交互式 `VaultUnlockKeyStore`。`unlockForAutomation` 开始时先取消旧 session timer，并清空旧 `content`、`unlockData`、`lastRevision`，再由自动化 Store 校验恰好 32 字节后构造 `UnlockData(rawKeyData:)`，避免不可信 Keychain 数据触发 precondition，也避免失败后出现“state 已 locked 但旧秘密仍可读”。之后复用当前 read/parse/revision/session touch 流程。自动化条目缺失、长度损坏或凭据错误统一保持 `.locked` 并抛 `PasswordVaultError.keychainUnavailable`，后续 Broker 将其稳定映射为 `AUTOMATION_UNLOCK_UNAVAILABLE`；数据库未配置、云目录不可用或数据库本身损坏仍保留现有错误语义。`disableAutomationUnlock` 只删除自动化条目，不删除交互式快速解锁条目，也不主动锁定已解锁数据库。

- [x] **Step 4：让 UI 与 Broker 共用同一个 Controller/Queue**

`Environment` 创建一次 `PasswordVaultUIController`，`MenuManager` 改为读取 `AppEnvironment.current.passwordVaultUIController`。在 Controller 上增加窄接口：

~~~swift
protocol PasswordVaultAgentAccess: AnyObject {
    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
    func agentMetadata(completion: @escaping (Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>) -> Void)
    func agentPaste(
        entryID: UUID,
        field: VaultAgentSecretField,
        target: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    )
    func agentSecret(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    )
}
~~~

Controller 初始化器增加可注入的 `storeQueue`，并在同一实例上创建公开给 App 内部组装使用的 `VaultAgentSerialExecutor`；两者必须包装同一个 queue，不能另建 Broker/授权队列。Controller 构造时通过新增的窄 `PasswordVaultStore.bindSessionExecutor(_:onStateChange:)` 把同一 executor 和状态变化回调绑定给 KDBX Store；默认协议实现 no-op。`VaultSessionController` 的 timer/通知只产生“请求锁定”事件，KDBX 必须把实际 `lock()` 提交到绑定的 executor，不能在 main queue 直接改 `content/unlockData/state`。Timer 到期请求携带 generation，可由后续成功活动取消；睡眠、session resign 和 terminate 请求属于不可取消系统锁，不得因队列中排在它前面的 metadata/secret 操作调用 `touch()` 而失效。Session timer 自身的 work item/token 状态必须加锁或固定在单一调度边界，取消后的旧 timer 不得晚到锁定新 session。KDBX session lock 或直接 `lock()` 完成后在同一 executor 调用状态变化回调；Controller 在回调中刷新受 `snapshotLock` 保护的 snapshot 并在主队列通知 `onChange`。Controller 公开 `state` 只能读取 snapshot，禁止从主线程直接读正在 store queue 写入的 `store.state`，也禁止为读取状态同步阻塞主线程等待 KDBX queue。现有 UI store 操作和以上 Agent 方法都进入该 queue/executor。`ensureReadyForAgent` 只接受当前可读状态或执行 `unlockForAutomation`，不得回退到交互式 quick unlock、主密码 UI 或 `PasswordVaultAuthorizing`。`agentMetadata` 只返回 Store 的 folder/entry 元数据；`agentSecret` 将 username/password 转成局部 UTF-8 `Data` 后立即结束 String 作用域，不缓存、不写 snapshot；`agentPaste` 使用指定 `PasteTargetContext` 调度现有 username/password 粘贴路径，但不得触发交互授权。`ensureReadyForAgent` 刷新 snapshot 后必须在主队列调用 `onChange`，让已显示的密码箱菜单同步就绪状态。

增加 `onInteractiveSensitiveUse`，只在现有 UI 的 entry 创建、更新、删除、复制密码、粘贴用户名或密码成功后在 store queue 调用一次；失败、Agent 方法、文件夹操作、解锁、搜索/元数据读取都不触发。Task 6 将该回调连接到 Policy 的 `recordInteractiveSensitiveSuccess`。

`Environment` 增加 `passwordVaultUIController`，每个 Environment 只创建一次。默认构造时必须把已经解析出的 `passwordVaultStore`、`secureClipboard` 与 `pasteService` 显式传入 Controller，禁止 Controller 初始化期间递归读取正在构造的 `AppEnvironment.current`。`AppEnvironment.push/replaceCurrent` 允许显式注入 Controller；沿用当前依赖时默认沿用当前 Controller，替换 Store 的测试必须同时显式提供匹配 Controller。`MenuManager` 不得一次性 lazy 缓存某个 Environment 的 Controller；它必须通过当前 Environment provider 取得 `AppEnvironment.current.passwordVaultUIController` 并为当前实例安装 `onChange`，因此已初始化的旧 Manager 经 push/replace/pop 后也始终指向当前 Controller。不得再调用 `PasswordVaultUIController()` 创建第二实例。

- [x] **Step 5：验证自动锁后恢复、环境注入和旧 UI 行为**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests -only-testing:pasteraTests/PasswordVaultStoreTests -only-testing:pasteraTests/PasswordVaultMenuTests`。

Expected：PASS；覆盖自动化条目的精确 Keychain 属性、update/add/delete 状态映射、非 32 字节和错误凭据安全失败、禁用不影响交互 key、Controller/Environment/MenuManager 共享实例与 queue、Agent 方法不触发交互认证或交互续期；还必须覆盖从已解锁状态使用错误 automation key 后旧秘密不可读且不能重新 enable、阻塞共享 executor 时 session auto-lock 只能排队、取消 timer 不锁定新 session、系统锁请求不会被其前方已排队 metadata 的 `touch()` 取消、未绑定 Store 保留自动锁、旧 Manager 已初始化后的 push/replace/pop 始终取得当前 Controller、Controller `state` 不再读取 Store，以及 session/Agent ready 刷新后主队列 `onChange`。原有快速解锁仍调用 user-presence Keychain。自动化条目随有效外部授权数量删除的最终生命周期由 Task 6 Runtime 测试完成。

- [x] **Step 6：提交自动化解锁闭环**

~~~bash
git add pastera/Sources/Services/VaultAutomationUnlockKeyStore.swift \
  pastera/Sources/Services/PasswordVaultStore.swift pastera/Sources/Services/KDBXPasswordVaultStore.swift \
  pastera/Sources/Managers/PasswordVaultUIController.swift pastera/Sources/Managers/MenuManager.swift \
  pastera/Sources/Environments/Environment.swift pastera/Sources/Environments/AppEnvironment.swift \
  pasteraTests/VaultAutomationUnlockKeyStoreTests.swift pasteraTests/PasswordVaultStoreTests.swift \
  pasteraTests/PasswordVaultMenuTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 增加密码箱无人值守恢复"
~~~

### Task 4：实现单次票据、限流与脱敏审计

**Files：**

- Create: `pastera/Sources/Services/VaultAgentTicketStore.swift`
- Create: `pastera/Sources/Services/VaultAgentRateLimiter.swift`
- Create: `pastera/Sources/Services/VaultAgentAuditLogger.swift`
- Create: `pasteraTests/VaultAgentTicketStoreTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: `VaultAgentClientKind`、`VaultAgentSecretField`、`VaultAgentInjectionMode`。
- Produces: `VaultAgentTicketStore.issue/redeem/complete/removeAll`、`VaultAgentRateLimiter.check` 和只能接收结构化低敏字段的 `VaultAgentAuditLogger.record/records`。

- [x] **Step 1：写票据原子兑换和限流恢复失败测试**

~~~swift
@Test("only one concurrent redeemer receives a receipt")
func ticketCanBeRedeemedOnce() async throws {
    let store = VaultAgentTicketStore(
        randomBytes: { Data(repeating: 7, count: 32) },
        commandBuilder: { _, _, token in ["adapter", "exec", "--ticket", token] }
    )
    let issued = try store.issue(
        client: .codex,
        entryID: UUID(),
        field: .password,
        mode: .stdin,
        now: Date(timeIntervalSince1970: 1_000)
    )
    async let first = Result { try store.redeem(token: issued.token, client: .codex, mode: .stdin, now: Date(timeIntervalSince1970: 1_001)) }
    async let second = Result { try store.redeem(token: issued.token, client: .codex, mode: .stdin, now: Date(timeIntervalSince1970: 1_001)) }
    let results = await [first, second]
    #expect(results.filter { try? $0.get() != nil }.count == 1)
}

@Test("metadata bucket recovers after its rolling minute")
func rateLimitRecovers() throws {
    let limiter = VaultAgentRateLimiter()
    let start = Date(timeIntervalSince1970: 2_000)
    for index in 0..<60 {
        try limiter.check(client: .claude, category: .metadata, at: start.addingTimeInterval(Double(index) / 10))
    }
    #expect(throws: VaultAgentRateLimitError.self) {
        try limiter.check(client: .claude, category: .metadata, at: start.addingTimeInterval(10))
    }
    try limiter.check(client: .claude, category: .metadata, at: start.addingTimeInterval(61))
}
~~~

- [x] **Step 2：运行并确认基础能力缺失**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentTicketStoreTests`。

Expected：FAIL，首个错误指向缺失 `VaultAgentTicketStore`。

- [x] **Step 3：实现不保存秘密的两阶段票据**

~~~swift
struct VaultAgentTicketBinding: Equatable {
    let client: VaultAgentClientKind
    let entryID: UUID
    let field: VaultAgentSecretField
    let mode: VaultAgentInjectionMode
}

final class VaultAgentTicketStore {
    static let ticketLifetime: TimeInterval = 30
    static let receiptLifetime: TimeInterval = 5

    func issue(
        client: VaultAgentClientKind,
        entryID: UUID,
        field: VaultAgentSecretField,
        mode: VaultAgentInjectionMode,
        now: Date
    ) throws -> VaultAgentPreparedTicket

    func redeem(
        token: String,
        client: VaultAgentClientKind,
        mode: VaultAgentInjectionMode,
        now: Date
    ) throws -> (receiptID: UUID, binding: VaultAgentTicketBinding)

    func complete(receiptID: UUID, client: VaultAgentClientKind, now: Date) throws -> VaultAgentTicketBinding
    func removeAll()
}
~~~

构造器注入 `randomBytes` 和 `commandBuilder(client, mode, token)`；生产随机源必须用 `SecRandomCopyBytes` 一次生成恰好 32 bytes，token 使用无 padding 的 base64url。随机源失败、长度不符、连续 3 次 hash 碰撞或 command 超过 Task 1 的参数/UTF-8 上限时，必须安全失败且不插入 pending 状态。`commandBuilder` 只负责生成返回给调用方的 Host 专属适配器模板，command 不进入 Store；Task 6 Runtime 负责提供真实构造器。

内存中只保存 token 的 SHA-256、binding 和时间，不保存 token 明文、command 或密码。全部状态由一把锁保护；`redeem` 在同一临界区校验 token hash、client、mode 和 `now < expiresAt`，随后原子删除 pending token并创建 5 秒 receipt。binding 不匹配不得消费正确客户端的票据；已成功兑换的 token hash 保留最多 30 秒的有界 used tombstone，使重放稳定返回 `used`。`complete` 同样绑定 receipt/client，并在同一临界区删除 receipt；只有适配器成功写入子进程 pipe 后调用 `complete`，授权续期发生在 `complete` 成功之后。过期判断统一使用 `now >= expiresAt`；访问时惰性清理，不启动 Timer。pending、receipt 和 tombstone 分别硬限制为 128、128、256，达到上限先惰性清理，仍满则安全失败；`removeAll` 原子清空三类状态，供 Task 6 撤销生命周期调用。

`VaultAgentTicketError` 使用可比较的 `expired`、`used`、`bindingMismatch`、`capacityExceeded`、`randomnessUnavailable`、`invalidCommand`；receipt 不存在、重复 complete 和已兑换 token 都返回 `used`，已知 pending/receipt 到期返回 `expired`。后续 Broker 只把 expired/used 映射到同名稳定 wire error，其他内部错误不得原样外泄。

- [x] **Step 4：实现无轮询限流与审计 Ring Buffer**

`VaultAgentRateLimiter` 使用按客户端/类别的时间戳 deque，访问时清理；`VaultAgentRateLimitCategory` 固定为 `metadata`、`directSecret`、`ticket`，对应 metadata 60/minute，paste/copy 10/minute，ticket 10/minute。窗口为半开区间 `(at - 60s, at]`，因此恰好 60 秒前的记录先清除；拒绝不追加时间戳。`VaultAgentRateLimitError` 携带向上取整且限制在 `1...60_000` 的 `retryAfterMilliseconds`，供 Broker 映射 `RATE_LIMITED`。全部 bucket 由一把锁保护，bucket 总数固定为 3 clients × 3 categories；不启动 Timer，调用时惰性清理。

`VaultAgentAuditAction` 固定覆盖 `status/search/get/paste/copy/prepareExec/redeemTicket/completeTicket/integrationStatus/integrationInstall/integrationUninstall`；`VaultAgentLatencyBucket` 固定为 `under10ms/under50ms/under200ms/under1s/atLeast1s`。`VaultAgentAuditLogger` API 固定为：

~~~swift
func record(
    client: VaultAgentClientKind,
    action: VaultAgentAuditAction,
    entryID: UUID?,
    result: VaultAgentErrorCode?,
    latencyBucket: VaultAgentLatencyBucket,
    at: Date
)

func records(at now: Date) -> [VaultAgentAuditRecord]
~~~

`VaultAgentAuditKeyStore` 使用独立 Keychain service `com.pastera-app.Pastera.password-vault.agent-audit.v1`、account `PasteraVaultAgentAuditKey`、32-byte 随机值、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 和 `kSecAttrSynchronizable = false`；update/read/add 的并发与错误语义复用 Task 3 已确认模式，但不得读取其他密码箱 Keychain 条目。Logger 初始化时加载或创建一次密钥；失败则初始化失败，禁止改用固定 key 或保存原始 UUID。

条目 ID 使用该密钥对 UUID 规范字符串做 HMAC-SHA256，并编码为无 padding base64url；`VaultAgentAuditRecord` 只包含 client、action、可选 `entryDigest`、可选稳定 result code、latency bucket 和 timestamp。API 不接受 title、folder、website、username、query、ticket、command、参数、原始错误或 path。Ring Buffer 是进程内存结构，最多 1,000 条；写入/读取时过滤 `timestamp <= now - 30 days`，再只保留最新 1,000 条，不持久化、不启动 Timer。Logger 的记录和读取由锁保护；返回值为副本，编码键集合必须只能来自上述低敏字段。

- [x] **Step 5：补审计编码哨兵测试并运行**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentTicketStoreTests`。

Expected：PASS；覆盖并发原子兑换、client/mode/receipt 绑定、30 秒与 5 秒边界、重放 tombstone、容量上限、随机/command 安全失败、`removeAll`、每客户端/类别限流隔离、窗口边界和 retry-after；审计覆盖精确 Keychain 属性、UUID HMAC 不可逆表示、1,000/30 天边界、并发记录以及编码键白名单。序列化审计记录不得包含原始 UUID，也不得存在可承载哨兵标题、查询、用户名、票据或命令的字段。

- [x] **Step 6：提交安全基础能力**

~~~bash
git add pastera/Sources/Services/VaultAgentTicketStore.swift \
  pastera/Sources/Services/VaultAgentRateLimiter.swift \
  pastera/Sources/Services/VaultAgentAuditLogger.swift \
  pasteraTests/VaultAgentTicketStoreTests.swift pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 增加单次票据和脱敏审计"
~~~

### Task 5：加固 Unix Socket、加密帧与 Helper/Host 双重身份

**Files：**

- Create: `pastera/Sources/Services/VaultAgentPeerVerifier.swift`
- Create: `pastera/Sources/Services/VaultAgentBroker.swift`
- Create: `pasteraTests/VaultAgentPeerVerifierTests.swift`
- Create: `pasteraTests/VaultAgentBrokerTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: Task 1 帧 DTO、安装记录中的 Host 代码身份、当前 App Bundle Helper 路径。
- Produces: `VaultAgentPeerVerifying`、`VaultAgentSecureChannel` 与事件驱动 `VaultAgentSocketServer`；验证结果使用 Task 2 已定义的 `VaultAgentPeerIdentity`。

- [ ] **Step 1：写父进程借用与重放拒绝失败测试**

~~~swift
@Test("a valid helper launched outside the recorded host chain is rejected")
func arbitraryLauncherCannotBorrowHelper() throws {
    let inspector = VaultAgentProcessInspectorProbe(
        processes: [
            41: .init(pid: 41, parentPID: 40, executableURL: expectedCodexHelper),
            40: .init(pid: 40, parentPID: 1, executableURL: URL(fileURLWithPath: "/tmp/launcher"))
        ]
    )
    let verifier = makePeerVerifier(processInspector: inspector)
    #expect(throws: VaultAgentPeerVerificationError.hostChainMismatch) {
        try verifier.verify(fileDescriptor: 9)
    }
}

@Test("secure channel rejects a repeated sequence")
func encryptedFrameCannotReplay() throws {
    let pair = try VaultAgentSecureChannel.makeTestPair()
    let frame = try pair.client.seal(Data("request".utf8))
    _ = try pair.server.open(frame)
    #expect(throws: VaultAgentProtocolError.replayedFrame) {
        try pair.server.open(frame)
    }
}
~~~

- [ ] **Step 2：运行并确认验证器/Channel 缺失**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentPeerVerifierTests -only-testing:pasteraTests/VaultAgentBrokerTests`。

Expected：FAIL，缺失 `VaultAgentPeerVerifier` 或 `VaultAgentSecureChannel`。

- [ ] **Step 3：实现双重身份验证**

`VaultAgentPeerVerifier.verify(fileDescriptor:)` 按固定顺序执行：

1. `getpeereid` 的 UID 必须等于当前 `getuid()`；
2. 通过 `LOCAL_PEERPID` 得到 peer PID，不信任请求字段；
3. `realpath` 后必须位于当前 `Pastera.app/Contents/Helpers`，`lstat` 拒绝符号链接和非普通文件；
4. `SecStaticCodeCheckValidity` 校验 Helper，签名标识映射为 codex/claude/cli；
5. Codex/Claude 从 Helper 父 PID 向上最多遍历 4 层，必须命中安装时记录的 Host designated requirement；ad-hoc Host 还必须匹配 cdhash 和真实路径；
6. CLI 只匹配当前 App 内 `pastera` Helper，保持独立授权；
7. 进程消失、PID 复用、路径变化、签名变化全部安全失败。

- [ ] **Step 4：实现认证加密 Channel**

握手在 peer 验证成功后进行。双方使用 `Curve25519.KeyAgreement.PrivateKey`，以 client/server nonce 和 connection ID 作为 HKDF-SHA256 salt/info 派生每连接 `SymmetricKey`；所有请求与响应用 `ChaChaPoly`，AAD 固定包含协议版本、connection ID、方向和 sequence。入站 sequence 必须从 1 严格递增，断连后密钥释放。

- [ ] **Step 5：实现私有 Socket 生命周期**

Socket 路径固定为 `~/Library/Application Support/Pastera/Agent/v1/broker.sock`。目录 `0700`、socket `0600`；使用 `openat/fstatat` 风格检查或等价无跟随检查拒绝符号链接/非 socket 冲突。`DispatchSourceRead` 驱动 accept/read，无轮询；最多 8 个连接、每连接最多 1 个进行中请求、空闲 30 秒关闭、单帧 64 KiB。

- [ ] **Step 6：运行真实权限、畸形帧、断连和并发测试**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentPeerVerifierTests -only-testing:pasteraTests/VaultAgentBrokerTests`。

Expected：PASS；测试覆盖 `0700/0600`、既有普通文件、socket 符号链接、错误 UID、伪造 Helper 名、错误 Host 父链、超大长度、乱序/重复 sequence、EOF 清理。

- [ ] **Step 7：提交 IPC 边界**

~~~bash
git add pastera/Sources/Services/VaultAgentPeerVerifier.swift \
  pastera/Sources/Services/VaultAgentBroker.swift \
  pasteraTests/VaultAgentPeerVerifierTests.swift pasteraTests/VaultAgentBrokerTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 加固密码箱本地 broker"
~~~

### Task 6：完成 Broker 操作、粘贴目标与续期状态机

**Files：**

- Create: `pastera/Sources/Services/VaultAgentPasteTargetTracker.swift`
- Create: `pastera/Sources/Services/VaultAgentRuntime.swift`
- Modify: `pastera/Sources/Services/VaultAgentBroker.swift`
- Modify: `pastera/Sources/Managers/PasswordVaultUIController.swift`
- Modify: `pasteraTests/VaultAgentBrokerTests.swift`
- Modify: `pasteraTests/PasswordVaultMenuTests.swift`

**Interfaces：**

- Consumes: Tasks 2–5 的授权、自动恢复、票据、限流、审计、peer identity 与共享 Controller。
- Produces: 全部 Broker operation 行为、`VaultAgentRuntime`、认证 cursor 和安全粘贴目标选择。

- [ ] **Step 1：写“只有成功敏感动作续期”失败测试**

~~~swift
@Test("search get failure and ticket creation do not renew; paste and ticket completion do")
func renewalMatrixMatchesContract() async throws {
    let fixture = VaultAgentBrokerFixture.authorizedCodex()
    let original = fixture.currentGrant

    _ = try await fixture.call(.search(.init(query: "mail", folderID: nil, limit: 20, cursor: nil)))
    _ = try await fixture.call(.get(entryID: fixture.entryID))
    _ = try? await fixture.call(.get(entryID: UUID()))
    let ticket = try await fixture.prepareTicket()
    #expect(fixture.currentGrant.idleExpiresAt == original.idleExpiresAt)

    _ = try await fixture.call(.paste(entryID: fixture.entryID, field: .password))
    #expect(fixture.currentGrant.idleExpiresAt > original.idleExpiresAt)

    let beforeRedeem = fixture.currentGrant.idleExpiresAt
    let delivery = try await fixture.redeem(ticket)
    #expect(fixture.currentGrant.idleExpiresAt == beforeRedeem)
    _ = try await fixture.call(.completeTicket(receiptID: delivery.receiptID))
    #expect(fixture.currentGrant.idleExpiresAt > beforeRedeem)
}
~~~

- [ ] **Step 2：运行并确认 dispatcher 尚未覆盖操作**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentBrokerTests`。

Expected：FAIL，Broker fixture 收到 unsupported operation 或类型缺失。

- [ ] **Step 3：实现状态、搜索、元数据与认证 cursor**

`vault_status` 无授权也可调用，但只返回当前客户端安装/授权/到期/就绪状态。其余密码箱操作先检查身份匹配、到期、限流，再调用 `ensureReadyForAgent`。搜索规则固定：

- query UTF-8 最大 512 bytes；
- limit 默认 20、最大 50；
- folder filter 先于 title/website/username 匹配；
- 排序为 `updatedAt descending`、再按 UUID 字符串稳定排序；
- cursor 编码 query 摘要、folder ID、offset 和 snapshot revision，并用本机 cursor key HMAC；篡改返回 `INVALID_REQUEST`；
- 响应编码后超过 32 KiB 时继续缩短当前页，绝不截断 JSON。

- [ ] **Step 4：实现最近非 Agent 粘贴目标**

`VaultAgentPasteTargetTracker` 订阅 `NSWorkspace.didActivateApplicationNotification`，只保存最近一个非 Pastera、非当前 Codex/Claude Host、非三个 Helper 的 `PasteTargetContext`，不使用 Timer 或轮询。目标进程已退出、Bundle/代码身份变化、无 Accessibility focus 且无法恢复时返回 `TARGET_UNAVAILABLE`，禁止回退为 stdout/clipboard 明文。

`paste` 成功调度现有 `PasteService` 后才记录敏感成功。`copy` 只允许 `client == .cli`，调用现有 `SecureClipboardService` 并保持 60 秒条件清除。

- [ ] **Step 5：实现 prepare/redeem/complete 和 Runtime 清理**

`prepareExec` 只创建 binding，不读取秘密；`redeemTicket` 原子兑换后才通过共享 store queue 读取一个字段并放入加密响应；`completeTicket` 成功才续期。`VaultAgentRuntime` 在有效 Grant 数变为 0、全部过期或撤销后删除自动化 Keychain 条目并清空票据；应用锁定不删除仍有效授权的自动化条目。

`integrationStatus/install/uninstall` 只允许已验证的 `client == .cli`，不要求密码箱 Grant，也不能访问任何密码箱 operation；这样首次安装可以在尚未授权密码箱时完成。除 `status` 与这三个 CLI-only 集成操作外，其他 operation 都必须经过独立客户端 Grant。

- [ ] **Step 6：运行 Broker、Store 和菜单续期测试**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentBrokerTests -only-testing:pasteraTests/PasswordVaultStoreTests -only-testing:pasteraTests/PasswordVaultMenuTests`。

Expected：PASS；并发 Codex/Claude 搜索仍串行进入同一个 store queue，交互式 Pastera 成功复制/粘贴/编辑续期全部有效 Grant。

- [ ] **Step 7：提交 Broker 业务闭环**

~~~bash
git add pastera/Sources/Services/VaultAgentPasteTargetTracker.swift \
  pastera/Sources/Services/VaultAgentRuntime.swift pastera/Sources/Services/VaultAgentBroker.swift \
  pastera/Sources/Managers/PasswordVaultUIController.swift \
  pasteraTests/VaultAgentBrokerTests.swift pasteraTests/PasswordVaultMenuTests.swift
git commit -m "feat(agent): 完成 broker 密码箱操作"
~~~

### Task 7：增加 Codex/Claude MCP Adapter 与 5 个工具

**Files：**

- Create: `pastera-agent/Sources/PasteraAgentAdapter/VaultAgentClient.swift`
- Create: `pastera-agent/Sources/PasteraAgentAdapter/PasteraMCPServer.swift`
- Create: `pastera-agent/Sources/PasteraCodexMCP/main.swift`
- Create: `pastera-agent/Sources/PasteraClaudeMCP/main.swift`
- Create: `pasteraAgentTests/VaultAgentClientTests.swift`
- Create: `pasteraAgentTests/PasteraMCPServerTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pastera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Modify: `pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme`

**Interfaces：**

- Consumes: Task 1 wire contract 与 Task 5/6 Broker。
- Produces: `VaultAgentClient.request(_:) async throws`、`PasteraMCPServer.run()`、`PasteraCodexMCP` 与 `PasteraClaudeMCP`。

- [ ] **Step 1：写工具清单、Schema 和注解失败测试**

~~~swift
@Test("MCP publishes exactly five bounded tools")
func publishesFiveTools() {
    let tools = PasteraMCPServer.makeTools()
    #expect(tools.map(\.name) == [
        "vault_status", "vault_search", "vault_get", "vault_paste", "vault_prepare_exec"
    ])
    #expect(tools[0].annotations.readOnlyHint == true)
    #expect(tools[1].annotations.readOnlyHint == true)
    #expect(tools[2].annotations.readOnlyHint == true)
    #expect(tools[3].annotations.readOnlyHint == false)
    #expect(tools[4].annotations.readOnlyHint == false)
}

@Test("MCP structured results never contain a password or note field")
func structuredResultOmitsSecretFields() throws {
    let result = try PasteraMCPServer.result(
        for: .entry(.fixture(username: "alice")),
        encoder: JSONEncoder()
    )
    let json = try #require(result.structuredContent).description
    #expect(!json.localizedCaseInsensitiveContains("password"))
    #expect(!json.localizedCaseInsensitiveContains("note"))
}
~~~

- [ ] **Step 2：增加 Target/依赖并确认测试先失败**

在 Xcode 中固定 `https://github.com/modelcontextprotocol/swift-sdk.git` 精确版本 `0.12.1`，产品 `MCP` 只链接 `PasteraAgentAdapter`/两个 MCP Helper，不链接现有 App Target。

Run：统一命令追加 `-only-testing:pasteraAgentTests/PasteraMCPServerTests`。

Expected：FAIL，缺失 `PasteraMCPServer`；依赖解析记录精确为 `0.12.1`。

- [ ] **Step 3：实现 Broker Client 与一次 App 拉起重试**

`VaultAgentClient` 连接失败时从当前 Helper 真实路径推导包含它的 `Pastera.app`，用 `NSWorkspace.OpenConfiguration` 或 `/usr/bin/open -gj` 后台拉起一次；按 50/100/200/400/800ms 有界等待 socket，总时长不超过 2 秒，不循环重启。连接后执行 Task 5 握手和严格 sequence；每次请求设置 10 秒上限，EOF/SIGTERM 关闭 fd 并释放密钥。

- [ ] **Step 4：按固定 SDK API 实现 MCP Server**

~~~swift
let server = Server(
    name: "pastera-vault",
    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1",
    capabilities: .init(tools: .init(listChanged: false))
)
await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: PasteraMCPServer.makeTools())
}
await server.withMethodHandler(CallTool.self) { parameters in
    try await handler.call(name: parameters.name, arguments: parameters.arguments)
}
try await server.start(transport: StdioTransport(logger: stderrLogger))
~~~

每个 Tool 都给出 `inputSchema` 与 `outputSchema`。read-only 三个工具使用 `readOnlyHint: true, destructiveHint: false, openWorldHint: false`；paste/prepare 使用 `readOnlyHint: false, destructiveHint: false, idempotentHint: false`，paste 的 `openWorldHint: true`。成功与错误都返回 `structuredContent`；文本 content 只包含简短中文状态，不包含秘密或原始错误。

- [ ] **Step 5：增加两个独立入口与 stdout 纯净测试**

两个 main 只差固定 `VaultAgentClientKind`；MCP stdin/stdout 不得写诊断。真实 pipe 测试覆盖 `initialize`、`tools/list`、`tools/call`、EOF 和 SIGTERM，捕获 stderr 后扫描哨兵秘密。

- [ ] **Step 6：运行 Adapter/MCP 测试**

Run：统一命令追加 `-only-testing:pasteraAgentTests/VaultAgentClientTests -only-testing:pasteraAgentTests/PasteraMCPServerTests`。

Expected：PASS；`tools/list` 精确返回 5 项，`vault_search.limit = 51` 返回 `INVALID_REQUEST`，未授权返回 `AUTHORIZATION_REQUIRED` 且不崩溃。

- [ ] **Step 7：提交 MCP 产品**

~~~bash
git add pastera-agent/Sources/PasteraAgentAdapter/VaultAgentClient.swift \
  pastera-agent/Sources/PasteraAgentAdapter/PasteraMCPServer.swift \
  pastera-agent/Sources/PasteraCodexMCP pastera-agent/Sources/PasteraClaudeMCP \
  pasteraAgentTests/VaultAgentClientTests.swift pasteraAgentTests/PasteraMCPServerTests.swift \
  pastera.xcodeproj
git commit -m "feat(agent): 增加 Codex 和 Claude MCP"
~~~

### Task 8：增加人工 CLI 与受控 stdin/fd 注入

**Files：**

- Create: `pastera-agent/Sources/PasteraAgentAdapter/VaultAgentCommandRunner.swift`
- Create: `pastera-agent/Sources/PasteraAgentAdapter/VaultCLI.swift`
- Create: `pastera-agent/Sources/PasteraCLI/main.swift`
- Create: `pasteraAgentTests/VaultCLITests.swift`
- Create: `pasteraAgentTests/VaultAgentCommandRunnerTests.swift`
- Create: `pasteraAgentTests/Fixtures/SecretConsumer/main.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme`

**Interfaces：**

- Consumes: `VaultAgentClient` 与 ticket redeem/complete。
- Produces: 文档外部契约中的 `pastera` 命令、稳定 JSON envelope 和 `VaultAgentCommandRunner.run`。

- [ ] **Step 1：写 CLI 解析和无明文 JSON 失败测试**

~~~swift
@Test("vault paste parses only the two supported fields")
func parsesPasteField() throws {
    #expect(try VaultCLICommand.parse(["vault", "paste", entryID.uuidString, "--field", "password"])
        == .paste(entryID: entryID, field: .password))
    #expect(throws: VaultCLIError.invalidArguments) {
        try VaultCLICommand.parse(["vault", "paste", entryID.uuidString, "--field", "note"])
    }
}

@Test("JSON failure uses the stable envelope")
func jsonFailureEnvelope() throws {
    let output = try VaultCLIJSONRenderer.render(
        .failure(.init(code: .grantExpired, message: "授权已过期。", retryable: false))
    )
    #expect(output == #"{"ok":false,"error":{"code":"GRANT_EXPIRED","message":"授权已过期。","retryable":false}}"#)
}
~~~

- [ ] **Step 2：运行并确认 CLI 类型缺失**

Run：统一命令追加 `-only-testing:pasteraAgentTests/VaultCLITests`。

Expected：FAIL，缺失 `VaultCLICommand`。

- [ ] **Step 3：实现无第三方解析器的命令树**

只接受外部契约列出的命令、选项和位置参数；重复参数、未知参数、limit 越界、无效 UUID、无命令分隔符 `--` 都返回 `INVALID_REQUEST`。文本结果写 stdout、诊断写 stderr；`--json` 使用稳定 envelope 和排序稳定的 `JSONEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`。

- [ ] **Step 4：先写真实 pipe 注入失败测试**

`SecretConsumer` 是仅测试 Target：stdin 模式只输出收到的字节数；fd 模式从指定 fd 读取并只输出字节数。测试在启动前后读取 `ProcessInfo.processInfo.environment`、`ps -o command=` 和临时目录，哨兵值不得出现。

~~~swift
@Test("runner writes the secret to fd and acknowledges only after the write")
func writesSecretToInheritedFD() async throws {
    let broker = VaultAgentClientProbe(secret: Data("sentinel-secret".utf8))
    let status = try await VaultAgentCommandRunner(client: broker).run(
        ticket: "ticket",
        mode: .fileDescriptor(9),
        command: [secretConsumerPath, "--fd", "9"]
    )
    #expect(status == 0)
    #expect(broker.completedReceiptCount == 1)
    #expect(broker.events == [.redeemed, .spawned, .secretWritten, .completed])
}
~~~

- [ ] **Step 5：用 `posix_spawnp` 实现命令执行**

Runner 本地参数类型固定为 `enum VaultAgentCommandInput { case standardInput; case fileDescriptor(Int32) }`，并映射到票据中的 `VaultAgentInjectionMode`。禁止 `/bin/sh -c`。为 stdin/fd 创建 `pipe`，用 `posix_spawn_file_actions_adddup2` 把 read end 映射到 `STDIN_FILENO` 或 3...255 的指定 fd；子进程参数与环境不加入秘密。spawn 成功后父进程写入 UTF-8 bytes，stdin 模式追加一个换行，关闭 write end，再发送 `completeTicket`，最后 `waitpid` 并透传子进程退出码。写入或 spawn 失败不发送 complete，且始终关闭所有 fd。

- [ ] **Step 6：运行 CLI 与命令执行测试**

Run：统一命令追加 `-only-testing:pasteraAgentTests/VaultCLITests -only-testing:pasteraAgentTests/VaultAgentCommandRunnerTests`。

Expected：PASS；覆盖 stdin、fd、30 秒过期、重复 ticket、spawn 失败、子进程非零退出、SIGTERM 清理，以及 argv/env/tmp 无哨兵值。

- [ ] **Step 7：提交 CLI 闭环**

~~~bash
git add pastera-agent/Sources/PasteraAgentAdapter/VaultAgentCommandRunner.swift \
  pastera-agent/Sources/PasteraAgentAdapter/VaultCLI.swift pastera-agent/Sources/PasteraCLI \
  pasteraAgentTests/VaultCLITests.swift pasteraAgentTests/VaultAgentCommandRunnerTests.swift \
  pasteraAgentTests/Fixtures/SecretConsumer pastera.xcodeproj
git commit -m "feat(agent): 增加密码箱 CLI 和安全注入"
~~~

### Task 9：增加规范 Skill 与可逆安装器

**Files：**

- Create: `integrations/pastera-vault/SKILL.md`
- Create: `integrations/pastera-vault/references/tool-contract.md`
- Create: `integrations/pastera-vault/references/security-boundary.md`
- Create: `integrations/pastera-vault/agents/openai.yaml`
- Create: `pastera/Sources/Services/VaultAgentIntegrationInstaller.swift`
- Create: `pasteraTests/VaultAgentIntegrationInstallerTests.swift`
- Modify: `pastera/Sources/Services/VaultAgentBroker.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: 当前 App 内三个 Helper 路径与规范 Skill 资源。
- Produces: `VaultAgentIntegrationInstalling`、Host 安装记录、所有权清单、CLI integration operations。

- [ ] **Step 1：写幂等安装、用户修改冲突与配置保留失败测试**

~~~swift
@Test("install is idempotent and uninstall preserves unrelated content")
func installAndUninstallAreOwned() throws {
    let root = temporaryUserRoot()
    let runner = AgentHostCommandRunnerProbe()
    let installer = makeInstaller(userRoot: root, runner: runner)

    try installer.install(.codex)
    try installer.install(.codex)
    #expect(runner.invocations.filter { $0.arguments.prefix(3) == ["mcp", "add", "pastera-vault"] }.count == 1)

    try installer.uninstall(.codex)
    #expect(FileManager.default.fileExists(
        atPath: root.appending(path: ".agents/skills/unrelated/SKILL.md").path
    ))
}

@Test("modified installed skill is never overwritten")
func modifiedSkillProducesConflict() throws {
    let fixture = try InstalledSkillFixture.modifiedAfterInstall()
    #expect(throws: VaultAgentInstallerError.userModifiedSkill) {
        try fixture.installer.install(.claude)
    }
    #expect(try fixture.readInstalledSkill() == fixture.userModifiedText)
}
~~~

- [ ] **Step 2：运行并确认安装器缺失**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentIntegrationInstallerTests`。

Expected：FAIL，缺失 `VaultAgentIntegrationInstaller`。

- [ ] **Step 3：实现 Host 定位、签名记录与官方 CLI 调用**

Host 定位只扫描已知路径与用户明确选择的文件，解析 symlink 后要求普通可执行文件并记录 designated requirement、Team ID、cdhash、真实路径。调用使用 `Process.executableURL` 与参数数组，不经 shell：

~~~text
codex mcp add pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP
claude mcp add --transport stdio --scope user pastera-vault -- /Applications/Pastera.app/Contents/Helpers/PasteraClaudeMCP
~~~

未签名或无法验证的 Host 安全失败，不能降级为只看路径。Codex/Claude 升级后 designated requirement 相同则保留；ad-hoc/无稳定 requirement 的 Host 更新必须重新安装并重新授权。

- [ ] **Step 4：实现 Skill 原子复制与所有权清单**

Codex 目标 `$HOME/.agents/skills/pastera-vault`，Claude 目标 `$HOME/.claude/skills/pastera-vault`。先复制到同父目录私有临时目录，校验每个文件 SHA-256，再原子 rename。清单保存在 `~/Library/Application Support/Pastera/Agent/v1/install-manifest.json`，只记录 Host、源/目标相对路径、摘要和安装版本。更新/卸载前摘要不匹配就报告冲突，不覆盖、不删除。

- [ ] **Step 5：先写 Host 权限片段安全边界测试**

~~~swift
@Test("Claude permission snippets contain only exact known tool names")
func claudePermissionSnippetIsNarrow() throws {
    let snippet = try makeInstaller().permissionSnippet(
        for: .claude,
        scope: .metadataOnly
    )
    #expect(snippet.allowedTools == [
        "mcp__pastera-vault__vault_get",
        "mcp__pastera-vault__vault_search",
        "mcp__pastera-vault__vault_status"
    ])
    #expect(!snippet.serialized.contains("*"))
    #expect(!snippet.serialized.contains("mcp__pastera-vault\""))
}

@Test("Codex never receives a broad approval override")
func codexHasNoUnsafePermissionMutation() throws {
    #expect(makeInstaller().supportedPermissionScopes(for: .codex).isEmpty)
    #expect(makeInstaller().configurationMutations(for: .codex).allSatisfy {
        !$0.serialized.contains("approval_policy") &&
        !$0.serialized.contains("sandbox") &&
        !$0.serialized.contains("bypass")
    })
}
~~~

Expected：测试先因缺少 `VaultAgentHostPermissionScope` 失败；不得通过放宽断言、加入 Server 级名称或修改全局 Host 配置使其通过。

- [ ] **Step 6：实现显式应用、可逆且不静默扩权的窄权限能力**

`VaultAgentHostPermissionScope` 仅定义 `metadataOnly` 与 `allCurrentPasteraTools`。Claude 片段使用精确名称 `mcp__pastera-vault__<toolName>`，排序稳定，不包含 glob、Server 级名称、Shell 命令或尚未发布工具。默认只生成 metadata-only 片段；粘贴/命令注入范围只能由偏好页的第二次明确确认请求生成。安装 MCP/Skill、Pastera authorize、续期与恢复都不自动应用任何 Host 权限。

用户单独确认“应用到 Claude”后，安装器才对 `~/.claude/settings.json` 的 `permissions.allow` 做语义合并：解析完整 JSON、保留全部未知字段和非 Pastera 条目、去重、写私有同目录临时文件、`fsync` 后原子 rename，并先创建 Pastera 私有备份。所有权清单只记录本次实际新加入的精确规则；原本已存在的同名规则不归 Pastera 所有。撤销 Pastera Grant 不删除 Host 规则；用户单独选择“移除免确认规则”时，只删除清单所有且仍精确匹配的条目。JSON 无效、文件为 symlink、权限异常、受管策略禁止用户规则或内容在读写间变化时安全失败，不覆盖配置。写后运行 `claude doctor`（如果可用）并重新读取确认；失败时从备份恢复且报告错误。

Codex V1 返回 `hostManagedUnsupported`，不生成或修改 `approval_policy`、sandbox、bypass 或任何同等全局设置。后续若 Codex 官方提供单工具机制，必须另做兼容性探测、Fixture 与用户确认，不能在本任务中猜测配置键。

- [ ] **Step 7：写入完整 Skill 契约**

`SKILL.md` 必须以以下头部和决策顺序为准，细节分别链接两个 references，正文不复制工具 Schema：

~~~markdown
---
name: pastera-vault
description: Use when the user asks Codex or Claude to find, paste, copy, or safely inject credentials stored in the local Pastera password vault.
---

# Pastera Vault

1. Call `vault_status` only when readiness is unknown.
2. Use a narrow `vault_search`; never enumerate or export the full vault.
3. Resolve ambiguity only from title, folder, website, username, and updated time.
4. Prefer `vault_paste` for GUI fields.
5. Use `vault_prepare_exec` only for commands documented to read stdin or an inherited fd without echoing it.
6. Never request, print, log, summarize, infer, or place a password in arguments, environment variables, or temporary files.
7. On authorization errors, explain the single Pastera authorization action once; do not loop.

Read `references/tool-contract.md` for exact schemas and stable errors.
Read `references/security-boundary.md` before command injection.
~~~

`agents/openai.yaml` 只包含 display name、短描述和默认触发提示；不得包含用户路径或授权配置。

偏好页 CLI 行把当前 App 内签名 `pastera` Helper 安装为 `$HOME/.local/bin/pastera` 符号链接；Broker 校验时先 realpath 回当前 App Helper。目标已存在且不是清单所有的同一链接时报告冲突，禁止覆盖。若 `$HOME/.local/bin` 不在当前 PATH，只显示一条添加 PATH 的提示，不自动修改 shell profile。

- [ ] **Step 8：用 Skill 校验器和安装测试验证**

Run：

~~~bash
python3 /Users/feeyo/.codex/skills/.system/skill-creator/scripts/quick_validate.py integrations/pastera-vault
~~~

再运行统一命令追加 `-only-testing:pasteraTests/VaultAgentIntegrationInstallerTests`。

Expected：Skill 校验成功；安装/状态/卸载、修改冲突、Host identity 变化、无关配置保留，以及 Claude 精确 allowlist/Codex 无全局绕过测试全部 PASS。

- [ ] **Step 9：提交 Skill 与安装器**

~~~bash
git add integrations/pastera-vault pastera/Sources/Services/VaultAgentIntegrationInstaller.swift \
  pastera/Sources/Services/VaultAgentBroker.swift pasteraTests/VaultAgentIntegrationInstallerTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 增加密码箱 skill 安装流程"
~~~

### Task 10：增加 Agent 集成偏好页与一次授权体验

**Files：**

- Create: `pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift`
- Create: `pasteraTests/AgentIntegrationPreferenceTests.swift`
- Modify: `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift`
- Modify: `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`
- Modify: `pastera/Sources/Services/VaultAgentRuntime.swift`
- Modify: `pastera/Resources/Localizable.xcstrings`
- Modify: `pasteraTests/PreferenceSearchTests.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: Runtime 的 install/status/authorize/revoke/uninstall。
- Produces: `PasteraPreferencePaneID.agentIntegrations`、可搜索偏好页和无重复授权的状态 UI。

- [ ] **Step 1：写偏好目录、状态行和按钮状态失败测试**

~~~swift
@Test("agent integrations are searchable and expose independent client rows")
func agentIntegrationPageIsRegistered() throws {
    let page = try #require(
        PasteraPreferenceCatalog.default.pages.first { $0.paneID == .agentIntegrations }
    )
    #expect(page.title == pasteraPreferenceString("Agent Integrations"))
    #expect(Set(page.searchItems.map(\.id)).isSuperset(of: [
        "agents.codex", "agents.claude", "agents.cli", "agents.authorization"
    ]))
}

@Test("authorized row shows both expiries and one revoke action")
func authorizedRowShowsBoundaries() throws {
    let runtime = VaultAgentRuntimeProbe.authorizedCodex()
    let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
    controller.loadView()
    let row = try #require(controller.rowSnapshotForTesting(.codex))
    #expect(row.showsIdleExpiry)
    #expect(row.showsHardExpiry)
    #expect(row.primaryAction == .revoke)
    #expect(!row.showsAuthorize)
}
~~~

- [ ] **Step 2：运行并确认 pane 尚不存在**

Run：统一命令追加 `-only-testing:pasteraTests/AgentIntegrationPreferenceTests -only-testing:pasteraTests/PreferenceSearchTests`。

Expected：FAIL，`PasteraPreferencePaneID` 无 `agentIntegrations`。

- [ ] **Step 3：实现三行紧凑状态页**

页面复用现有 `PasteraPreferencePageViewController`、card/setting row 视觉语言。Codex、Claude、CLI 每行显示安装、Host 路径摘要、授权、闲置到期、硬到期和最近敏感动作；按钮状态固定为 install/update、authorize、reauthorize、revoke、uninstall 中当前唯一合理动作。审计摘要只显示动作类别/结果/时间，不显示条目或查询。

- [ ] **Step 4：实现一次授权流程**

首次非 status 密码箱请求只创建一个 pending identity 并触发一次原生提示；取消后不自动反复弹出。偏好页 authorize：

1. 检查 Host 与 Helper 双重身份；
2. 密码箱已解锁时只做一次 `LAContext.deviceOwnerAuthentication`；
3. 密码箱锁定且交互式 quick key 可用时，以现有 Keychain user-presence 解锁结果作为本次身份确认，不再追加第二个 LAContext；
4. 没有 quick key 时引导用户先在主菜单解锁，不在偏好页收集主密码；
5. 成功后创建 Grant 与自动化密钥并刷新行状态。

- [ ] **Step 5：实现独立的 Host 权限选择，不并入 Pastera 授权**

Claude 行在 MCP/Skill 已安装后提供独立的“减少只读工具确认”操作，先展示精确的 metadata-only allowlist，并让用户明确选择“复制配置”或“应用到 Claude 用户设置”；`vault_paste` 与 `vault_prepare_exec` 默认不包含，用户选择“同时允许敏感动作”时再展示风险说明并进行第二次明确确认。另设独立的“移除免确认规则”操作；取消、未选择或配置被用户修改时保持 Host 原配置，不回退成更宽规则。

Codex 行固定显示“由 Codex 管理工具审批”，不提供伪造的免确认开关。Pastera 的 authorize/revoke 只改变 Grant 与自动化密钥，不能改变任一 Host 的工具审批、Shell 审批或沙箱策略。测试必须证明安装、授权、续期、撤销和卸载都不会顺带写入 Host 权限。

- [ ] **Step 6：补撤销隔离、权限隔离、取消冷却和布局测试**

Codex revoke 不改变 Claude；最后一个 Grant 撤销会删除自动化 key；按钮重复点击被 coordinator 合并；所有内容在现有偏好窗口宽度内，不添加模态 wizard。

Claude 权限测试覆盖只读精确列表、敏感动作二次确认、取消无写入、用户设置未知字段/原有规则保留、重复应用幂等、只移除清单所有规则、无效 JSON/符号链接/读写竞争回滚，以及不预授权未来工具；Codex 测试覆盖不出现免确认开关，且任何路径都不写全局审批或沙箱键。

Run：统一命令追加 `-only-testing:pasteraTests/AgentIntegrationPreferenceTests -only-testing:pasteraTests/PreferenceSearchTests -only-testing:pasteraTests/PreferenceWindowShellTests`。

Expected：PASS；`jq empty pastera/Resources/Localizable.xcstrings` 也通过。

- [ ] **Step 7：提交偏好页**

~~~bash
git add pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift \
  pastera/Sources/Preferences/PasteraPreferenceCatalog.swift \
  pastera/Sources/Preferences/CPYPreferencesWindowController.swift \
  pastera/Sources/Services/VaultAgentRuntime.swift pastera/Resources/Localizable.xcstrings \
  pasteraTests/AgentIntegrationPreferenceTests.swift pasteraTests/PreferenceSearchTests.swift \
  pastera.xcodeproj/project.pbxproj
git commit -m "feat(agent): 增加 Agent 集成偏好页"
~~~

### Task 11：完成 App 生命周期、Helper 嵌入与事件驱动启动

**Files：**

- Modify: `pastera/Sources/AppDelegate.swift`
- Modify: `pastera/Sources/Environments/Environment.swift`
- Modify: `pastera/Sources/Environments/AppEnvironment.swift`
- Modify: `pastera/Sources/Services/VaultAgentRuntime.swift`
- Modify: `pastera-agent/Sources/PasteraAgentAdapter/VaultAgentClient.swift`
- Modify: `pastera.xcodeproj/project.pbxproj`
- Modify: `pastera.xcodeproj/xcshareddata/xcschemes/pastera.xcscheme`
- Modify: `pasteraTests/ReleasePackagingConfigurationTests.swift`
- Modify: `script/install_local.sh` only if its existing verification cannot see embedded Helpers

**Interfaces：**

- Consumes: 已完成 Broker、三个 Helper、Skill 资源和安装记录。
- Produces: `Pastera.app/Contents/Helpers/{PasteraCodexMCP,PasteraClaudeMCP,pastera}`、事件驱动 Broker 生命周期与可验证签名。

- [ ] **Step 1：写产品嵌入和空闲启动失败测试**

~~~swift
@Test("release project embeds exactly three signed helper products")
func embedsAgentHelpers() throws {
    let project = try ProjectFileFixture.load()
    #expect(project.embeddedHelperNames == ["PasteraClaudeMCP", "PasteraCodexMCP", "pastera"])
    #expect(project.helperCodeSignOnCopyNames == Set(project.embeddedHelperNames))
}

@Test("idle runtime opens one broker socket without unlocking the vault")
func idleBrokerDoesNotUnlockVault() throws {
    let runtime = VaultAgentRuntimeFixture(installedHosts: [], grants: [])
    runtime.start()
    #expect(runtime.socketStartCount == 1)
    #expect(runtime.automationUnlockCount == 0)
}
~~~

- [ ] **Step 2：运行并确认产品尚未嵌入**

Run：统一命令追加 `-only-testing:pasteraTests/ReleasePackagingConfigurationTests`。

Expected：FAIL，嵌入 Helper 列表为空或不完整。

- [ ] **Step 3：配置 Target、签名标识和 Copy Files**

三个 command-line Target 使用 `SWIFT_VERSION = 6.0`、`MACOSX_DEPLOYMENT_TARGET = 15.0`；产品标识固定：

~~~text
com.pastera-app.Pastera.agent.codex
com.pastera-app.Pastera.agent.claude
com.pastera-app.Pastera.agent.cli
~~~

App 增加 `Contents/Helpers` Copy Files phase、Target dependency 和 `CodeSignOnCopy`。本地无签名测试允许通过依赖注入绕过真实 SecCode；`install_local.sh` 的 ad-hoc 构建必须让 `codesign --verify --deep --strict` 覆盖三个 Helper。`integrations/pastera-vault` 作为只读目录资源嵌入。

- [ ] **Step 4：接入 App 生命周期**

`applicationDidFinishLaunching` 完成 Environment 替换后调用 `vaultAgentRuntime.start()`。Broker 只创建一个事件驱动 Unix socket；没有请求时不解锁 KDBX、不读取 Grant/Keychain、不轮询。应用退出时停止 accept、关闭连接、删除 socket 文件和内存票据，但保留仍有效 Grant/自动化 key。不得注册 launchd、Login Item helper 或 TCP 端口。

- [ ] **Step 5：运行聚焦打包测试并安装本机构建**

Run：

~~~bash
./script/install_local.sh --verify
codesign --verify --deep --strict --verbose=2 /Applications/Pastera.app
test -x /Applications/Pastera.app/Contents/Helpers/PasteraCodexMCP
test -x /Applications/Pastera.app/Contents/Helpers/PasteraClaudeMCP
test -x /Applications/Pastera.app/Contents/Helpers/pastera
stat -f '%Sp %N' "$HOME/Library/Application Support/Pastera/Agent/v1"
~~~

Expected：build/install 成功，App 与三个 Helper 签名验证通过；目录显示 `drwx------`，安装集成后 socket 显示 `srw-------`。

- [ ] **Step 6：提交打包与生命周期**

~~~bash
git add pastera/Sources/AppDelegate.swift pastera/Sources/Environments \
  pastera/Sources/Services/VaultAgentRuntime.swift \
  pastera-agent/Sources/PasteraAgentAdapter/VaultAgentClient.swift \
  pastera.xcodeproj pasteraTests/ReleasePackagingConfigurationTests.swift script/install_local.sh
git commit -m "feat(agent): 随应用发布签名 helper"
~~~

如果 `script/install_local.sh` 无需修改，不得为了匹配命令而触达它，提交时从 `git add` 参数移除该文件。

### Task 12：完成泄漏、性能、完整回归与真实 Host 验收

**Files：**

- Create: `pasteraTests/VaultAgentLeakRegressionTests.swift`
- Create: `pasteraTests/VaultAgentPerformanceTests.swift`
- Modify: `pasteraTests/VaultAgentBrokerTests.swift`
- Modify: `pasteraAgentTests/PasteraMCPServerTests.swift`
- Modify: `pasteraAgentTests/VaultAgentCommandRunnerTests.swift`
- Modify: `docs/superpowers/plans/2026-07-19-pastera-vault-cli-skill-mcp.md`
- Modify: `pastera.xcodeproj/project.pbxproj`

**Interfaces：**

- Consumes: 全部实现。
- Produces: standard 档位的安全、性能、资源、兼容性、安装和真实 Host 证据，以及同一 plan 的 `Delivery Record` 回写。

- [ ] **Step 1：写哨兵秘密全表面泄漏测试**

使用随机唯一哨兵，覆盖 MCP content/structuredContent、CLI stdout/stderr、OSLog capture、审计编码、错误 description、Process argv/env、`NSTemporaryDirectory()`、一般 Pasteboard 和崩溃安全路径。测试必须明确允许直接粘贴期间的安全 Pasteboard 短暂值，并验证 60 秒条件清除；其他表面出现哨兵即失败。

- [ ] **Step 2：运行泄漏测试并修复所有真实暴露点**

Run：统一命令追加 `-only-testing:pasteraTests/VaultAgentLeakRegressionTests -only-testing:pasteraAgentTests/PasteraMCPServerTests -only-testing:pasteraAgentTests/VaultAgentCommandRunnerTests`。

Expected：第一次运行可因尚未脱敏的真实表面失败；逐个修复后 PASS。不得通过删掉断言、缩小扫描表面或替换成非秘密 fixture 让测试变绿。

- [ ] **Step 3：实现确定性性能/资源测试**

`VaultAgentPerformanceTests` 创建 10,000 条仅元数据条目并测量至少 100 次热搜索，丢弃前 10 次 warm-up，记录 p50/p95/max；p95 必须 ≤ 50ms。冷态测试分开记录 App/Broker 启动与 KDBX KDF，p95 ≤ 2s。Helper harness 初始化 stdio 后稳定 3 秒再采样 RSS，单个 ≤ 30 MB；同一已解锁 KDBX 基线对比 Broker 增量 RSS ≤ 5 MB；空闲 10 秒 CPU 采样约为 0 且不存在轮询唤醒。

- [ ] **Step 4：运行全部聚焦和默认回归**

Run：

~~~bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation -skipMacroValidation \
  test \
  -only-testing:pasteraTests/VaultAgentAuthorizationPolicyTests \
  -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests \
  -only-testing:pasteraTests/VaultAgentTicketStoreTests \
  -only-testing:pasteraTests/VaultAgentPeerVerifierTests \
  -only-testing:pasteraTests/VaultAgentBrokerTests \
  -only-testing:pasteraTests/VaultAgentLeakRegressionTests \
  -only-testing:pasteraTests/VaultAgentPerformanceTests \
  -only-testing:pasteraTests/AgentIntegrationPreferenceTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests \
  -only-testing:pasteraTests/SecureClipboardServiceTests \
  -only-testing:pasteraAgentTests/VaultAgentProtocolTests \
  -only-testing:pasteraAgentTests/VaultAgentClientTests \
  -only-testing:pasteraAgentTests/PasteraMCPServerTests \
  -only-testing:pasteraAgentTests/VaultCLITests \
  -only-testing:pasteraAgentTests/VaultAgentCommandRunnerTests
~~~

Expected：`** TEST SUCCEEDED **`。随后运行 AGENTS.md 中默认 `clean test`，Expected 同样为 `** TEST SUCCEEDED **`。

- [ ] **Step 5：做静态、Skill、资源和网络边界检查**

~~~bash
git diff --check
jq empty pastera/Resources/Localizable.xcstrings
python3 /Users/feeyo/.codex/skills/.system/skill-creator/scripts/quick_validate.py integrations/pastera-vault
lsof -nP -a -c Pastera -iTCP
~~~

Expected：前三项成功；`lsof` 不显示 Pastera Vault Broker TCP listener。SwiftLint 由 Xcode build plugin 在上述构建中执行，不另装全局工具。

- [ ] **Step 6：完成 Codex App 与 Claude Code 真实验收**

在全新测试条目中使用哨兵以外的专用凭据：

1. 偏好页分别 install Codex/Claude，验证官方 CLI `mcp list/get` 能发现 `pastera-vault`；
2. 两个 Host 首次调用分别只出现一次 Pastera 授权；
3. 重启 MCP、退出/重开 Host、退出/重开 Pastera、锁屏/解锁后，7 天窗口内不重复授权；
4. 搜索/get 对话只显示允许元数据；
5. 聚焦真实浏览器/文本字段，验证 username/password 直接粘贴到最近非 Agent 目标；
6. 用不回显的消费命令验证 stdin/fd；
7. 撤销 Codex 后 Codex 失败而 Claude 继续；最后一个 Grant 撤销后自动化 Keychain 条目消失；
8. 卸载后其他 MCP 与 Skill 保留。

Claude Code 未安装或未签名时，本任务不得伪造通过；记录 `未完成：缺少可验证 Claude Host`，Codex 证据仍可单独完成。

- [ ] **Step 7：回写唯一计划并提交验证闭环**

在本文件 `Delivery Record` 写入真实实现、偏差、命令结果、测试数量、参考 Mac、p50/p95/max、RSS、已安装 App/Helper 签名、真实 Host 结果与缺口。然后：

~~~bash
git add pasteraTests/VaultAgentLeakRegressionTests.swift \
  pasteraTests/VaultAgentPerformanceTests.swift pasteraTests/VaultAgentBrokerTests.swift \
  pasteraAgentTests/PasteraMCPServerTests.swift \
  pasteraAgentTests/VaultAgentCommandRunnerTests.swift \
  pastera.xcodeproj/project.pbxproj \
  docs/superpowers/plans/2026-07-19-pastera-vault-cli-skill-mcp.md
git commit -m "test(agent): 验证密码箱集成安全与性能"
~~~

## 验收映射（Acceptance Mapping）

| 验收项 | 实施任务 | 自动化证据 | 人工 / Host 证据 |
| --- | --- | --- | --- |
| 按应用一次授权 | Task 2、6、10、12 | 确定性时钟策略测试、待处理请求去重、客户端授权隔离测试 | Codex 与 Claude 各授权一次；新任务和 MCP 重启不再弹 Pastera 授权 |
| 7 天滑动、30 天硬上限 | Task 2、6、10、12 | 到期边界、成功敏感动作续期、状态/搜索/失败不续期测试 | 偏好页展示两种到期时间；硬上限后必须重新授权 |
| 冷态无人值守恢复 | Task 3、6、12 | 临时 KDBX + 自动化 Keychain Test Double、应用/store 重启、密钥损坏失效测试 | Pastera 重启和 Mac 锁屏/解锁后保持无人值守；重启后正常登录 macOS 即可使用 |
| 应用身份隔离 | Task 2、5、9、12 | UID/PID/路径/Helper 与 Host 父进程链签名测试，伪造标识/路径/哈希拒绝，Codex/Claude 授权分离 | 撤销 Codex 不影响 Claude；任意进程直启 Helper 与替换后的未知 Helper 均被拒绝 |
| 模型输出无明文 | Task 1、4、7、8、12 | Schema 测试；扫描 MCP 内容、CLI stdout/stderr、日志、审计、参数、环境、临时目录和错误中的哨兵秘密 | 检查捕获的 Codex/Claude 对话和 Pastera unified logs |
| 直接粘贴与命令注入 | Task 4、6、8、12 | Named Pasteboard、目标恢复、stdin/fd 子进程 Fixture、票据到期/重放测试 | 粘贴到真实文本/浏览器字段，并运行不回显的消费命令 |
| 性能与资源有界 | Task 5–8、11、12 | 10,000 条 p95、冷态就绪、RSS/空闲 CPU、重复会话泄漏测试 | 在参考 Mac 上用 Activity Monitor/Instruments 抽查 |
| 安装可逆 | Task 9–12 | 安装/状态/卸载幂等、修改过的 Skill 冲突、配置保留 Fixture | 在 Codex App/Claude Code 中确认 MCP/Skill 发现，卸载后其他配置不受影响 |
| Host 权限独立 | Task 7、9、10、12 | Claude 精确工具 allowlist、敏感动作二次确认、Codex 不写全局审批/沙箱、安装授权不联动权限 | 先保持 Host 默认策略；Claude 可选择只读或全部现有工具；Codex 继续使用自身审批 |
| 现有密码箱兼容 | Task 3、6、10–12 | 聚焦 KDBX、Keychain 快速解锁、冲突、菜单、剪贴板及默认完整 Xcode 测试 | 关闭 Agent 集成时，本地安装后的常规密码箱行为不变 |

## 测试与验证策略

### 单元与模型测试

- 使用确定性时钟覆盖授权创建、闲置续期、绝对到期、撤销与客户端隔离。
- 状态机测试证明只有成功敏感动作能够续期。
- 单次票据并发测试证明最多一个兑换者成功。
- 限流边界与恢复测试。
- 在所有禁止输出表面使用唯一哨兵秘密做脱敏测试。
- 工具/Schema 测试从结构上证明密码与备注字段不存在。

### Broker 与 Store 集成

- 使用真实临时 KDBX 覆盖创建、锁定、自动化恢复、搜索、粘贴和外部冲突只读行为。
- 验证真实私有 socket 权限与生命周期，拒绝符号链接/非 socket 冲突。
- 在测试环境允许时覆盖同用户与错误用户对端校验。
- 取消与超时后不得残留可兑换票据或迟到秘密结果。
- Codex 与 Claude 并发元数据调用仍由唯一 store 所有者串行处理。

### MCP 与 CLI 集成

- 两个适配器产品通过真实 stdio 覆盖 MCP `initialize`、`tools/list` 与 `tools/call`。
- 覆盖有界分页、稳定结构化错误、stdout 协议纯净、stderr 脱敏，以及 EOF/SIGTERM 关闭。
- 使用合成非秘密数据做 CLI 文本与 `--json` 快照。
- 使用只消费不回显的子进程 Fixture 覆盖 stdin 与继承 fd 注入。

### 安全回归

- 覆盖伪造客户端名、复制 Helper 路径、签名不匹配、陈旧 PID、请求重放、票据重复、超大帧、畸形 JSON 和协议降级。
- 扫描进程环境、参数列表、临时目录、Pasteboard、MCP 结果、CLI 流、OSLog、审计与崩溃安全错误描述，确认不存在哨兵秘密字节。
- 验证不存在 TCP 监听和 HTTP 请求路径。

### 性能与资源验证

- 使用接近 Release 的优化 Helper 构建验证 RSS/延迟预算；Debug 构建只作为功能证据。
- 对 10,000 条合成元数据做足够轮次的热态搜索，报告 p50/p95/max。
- 将冷 Broker/Pastera 恢复与 KDBX KDF 时间分开测量，并记录参考 Mac 与构建信息。
- MCP 初始化并稳定空闲后采样适配器 RSS 与 CPU。
- 重复连接/搜索/断开和票据到期循环，检查内存增长。

### 仓库与安装应用回归

- 先运行新增聚焦测试。
- 运行现有密码箱、安全剪贴板、偏好设置和主菜单测试。
- 运行仓库默认的无签名 `xcodebuild ... clean test`。
- 对触达文件运行 `git diff --check` 与仓库 SwiftLint 路径。
- 运行 `./script/install_local.sh`，验证已安装 App/Helper/签名、进程、socket 权限和真实 Codex/Claude MCP 发现。

## 风险、回滚与观察（Risks, Rollback and Observation）

- **风险——无人值守密钥暴露：** `AfterFirstUnlockThisDeviceOnly` 有意用重复身份验证换取无人值守访问。通过只允许 Broker 访问、按客户端授权、7 天闲置期限、30 天硬期限、可撤销、禁止同步和无有效授权时删除来降低风险。
- **风险——ad-hoc 签名下的 Helper 身份：** 本地 ad-hoc 更新可能改变代码身份并使授权失效。正式版本应使用稳定 designated requirement；本地构建还绑定到已安装应用包内的预期 Helper，替换后可能需要重新授权。
- **风险——模型驱动泄漏：** 已授权 Agent 可能选择会回显输入的目标。V1 删除直接明文读取与高泄漏注入方式，使用 Skill Guardrail，并把已授权客户端或目标的恶意/被接管行为列为保证边界之外。
- **风险——IPC 实现错误：** 对端校验、分帧、防重放和取消属于高敏感边界。协议类型必须保持小而明确，对畸形输入做 fuzz，限制所有负载，并在触达 KDBX 前安全失败。
- **风险——UI/store 耦合：** Broker 恢复会改变共享 store 状态。所有状态变化必须走现有 queue 并刷新 controller 快照，避免主菜单读取陈旧锁定状态。
- **风险——配置所有权：** 直接编辑配置可能破坏无关 MCP/Skill。使用官方命令、所有权清单、幂等状态检查和冲突安全更新。
- **风险——Host 免确认范围漂移：** Server 级授权、glob 或全局审批键会让后续工具被意外预授权。Claude 只生成当前五个工具中的精确名称，敏感动作单独确认；Codex V1 不具备已核查的单工具写入能力，因此保持 Host 自己审批。
- **风险——MCP Swift SDK 尚未到 1.0：** 次版本可能破坏 API。V1 固定 `0.12.1`，升级必须作为明确兼容性任务。
- **回滚：** 关闭 Agent 集成、停止接受新 Broker 连接、撤销全部外部授权、删除自动化 Keychain 条目与票据、注销 Pastera 所有的 MCP 条目并移除其 Skill 副本。KDBX 字节、OneDrive 路径、交互式快速解锁、主菜单 UI 与现有密码数据无需迁移或回滚。
- **观察：** 仅使用本机脱敏的连接/结果/延迟/资源分桶与有界审计，不上传密码箱遥测。重点观察授权请求去重、自动恢复失败、限流、适配器崩溃、延迟 p95 和 RSS 漂移。

## 交付元数据（Delivery Metadata）

- Plan Path：`docs/superpowers/plans/2026-07-19-pastera-vault-cli-skill-mcp.md`
- Plan Status：`implementation-in-progress-task-4-complete`
- Evidence Profile：`standard`
- Story ID：未请求、未分配
- Task IDs：未请求、未分配
- Superpowers Task Mapping：Task 1–12 已覆盖共享协议、授权/自动恢复、安全基础能力、IPC/Broker、MCP、CLI、Skill/安装、偏好页、打包和最终验收
- ZenTao Sync Status：`not-requested`
- ZenTao Readback Evidence / Time：不适用
- Prior Related Records：密码箱内嵌解锁、首次打开延迟、上下文动作和访问体验优化属于已完成的独立需求，不是本 CLI/Skill/MCP 范围的竞争计划
- External Basis：Codex MCP/Skill 官方文档、本机 Codex CLI 能力检查、Claude Code 官方 [权限规则](https://code.claude.com/docs/en/permissions) 与 [设置文件](https://code.claude.com/docs/en/settings) 文档，以及官方 [MCP Swift SDK `0.12.1`](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1)
- Last Updated：`2026-07-19`

## 交付记录（Delivery Record）

- Actual Implementation：Task 1 已建立共享协议、稳定错误码、严格载荷上限与 65,536-byte 完整帧边界；Task 2 已建立按 Codex、Claude、CLI 隔离的 Keychain Grant、7 天滑动期、30 天硬上限、首次授权去重/取消冷却、完整 Helper/Host 身份约束，以及复用外部密码箱串行队列的可重入 executor；Task 3 已完成独立自动化 Keychain 密钥、冷态无人值守恢复、Environment/Controller 单实例接线、UI/Agent/session lock 共用可重入 Store executor、可取消 timer 与不可取消系统锁分离，以及线程安全状态快照和主线程变化通知；Task 4 已完成仅存 SHA-256 binding 的 30 秒单次票据、5 秒 receipt、三类有界 outcome tombstone、固定 3×3 滚动限流，以及使用独立 ThisDeviceOnly Keychain HMAC key 的 1,000 条/30 天进程内脱敏审计 Ring Buffer。Task 5–12 尚未实现。
- Plan Deviations：由于项目工作流禁止为同一需求创建平行 plan/spec，Superpowers 设计规格与实施计划有意合并到这一份仓库文件中。Task 1 实施前发现原任务只引用了外部错误表，未给出响应 envelope、集成状态载荷和所有字符串/集合上限；已在不改变产品、安全或 Host 行为的前提下补齐精确 Wire Contract，避免实现猜测。Task 2 预检发现 `VaultAgentErrorCode` 作为 `Result.Failure` 缺少 `Error` conformance，并且原任务未固定 Keychain 失败、撤销持久化、并发身份变化与取消冷却语义；已补齐这些实现级契约，wire raw value 和产品授权边界不变。Task 2 独立审查进一步发现 Host 元组完整性、Coordinator in-flight 生命周期和“复用唯一密码箱 Store Queue”在原任务中的实现约束不足；已明确 Codex/Claude/CLI 的 Host 完整性规则，并以外部注入且可重入的 `VaultAgentSerialExecutor` 统一 Policy、Keychain 与 Coordinator 执行边界，Task 3 继续接入现有 `PasswordVaultUIController.storeQueue`。Task 3 预检发现自动化 Keychain 更新/错误映射、KDBX 原始 key 长度、Environment 构造依赖和交互续期触发矩阵仍可能由实现者猜测；已固定查询/更新规则、非 32 字节安全失败、共享 Controller/executor 构造方式与只在成功 UI 敏感动作触发的边界，未扩大产品授权范围。Task 3 首轮独立审查发现 Environment 切换时 lazy MenuManager 会缓存旧 Controller、session auto-lock 绕过共享 queue，以及 automation unlock 失败后可能残留旧敏感会话；已要求当前 Environment provider、session executor 绑定、timer 状态同步和失败前后清除敏感材料，并补 `onChange` 同步。Task 3 第二轮独立审查发现系统锁仍可能被队列前方活动取消，且 Controller `state` 仍跨队列读取 Store；已区分不可取消系统锁与可取消 timer 锁，并改为 executor 内状态回调更新受锁 snapshot，不改变外部授权时长或秘密暴露范围。Task 4 预检发现票据 command 生成、随机/碰撞失败、重放错误、容量边界、限流 retry-after 和审计密钥/记录 Schema 尚未固定；已明确 command builder 只生成响应且不落 Store、三类有界票据状态、严格滑动窗口、独立 Keychain HMAC key 和进程内 1,000 条 Ring Buffer，未改变 30 秒票据、5 秒 receipt 或外部操作范围。Task 4 首轮独立审查发现审计 key 读取未强制 ThisDeviceOnly，主流程复核同时发现票据/receipt 被其他访问惰性清理后会把 expired 漂移成 used；已把 accessibility 纳入全部 Keychain 匹配查询，并用单个 256 条 outcome tombstone 保持过期/重放语义。复审一度建议为成功 receipt 也保存 used tombstone；按原契约复核后撤回，因为未知与已完成 receipt 对外均为 used，额外状态不会改善安全行为且可能阻断秘密已写入后的 complete/续期。
- Impact：计划影响仅限 macOS Pastera 应用、三个内置 Helper、本地 Agent Skill 资源、用户自己的 Codex/Claude MCP 配置和新增本机 Keychain 授权材料；不计划修改 KDBX Schema 或 OneDrive 路径。
- Verification：基线默认回归 682 tests / 75 suites 通过。Task 1 独立验证为 9 个协议测试与 15 个 Store 回归通过；Task 2 经修复复审批准，主流程重新运行 22 个授权测试与 9 个协议测试，共 31 tests / 2 suites，`xcodebuild` 退出码 0；Task 3 经两轮修复复审批准，主流程重新运行自动化 Keychain、Agent 访问、Store、菜单和 Task 2 授权回归，共 87 tests / 5 suites，`xcodebuild` 退出码 0；Task 4 经修复和技术复核批准，主流程重新运行 23 个票据/限流/审计测试、22 个授权测试和 9 个协议测试，共 54 tests / 3 suites，`xcodebuild` 退出码 0。CoreSimulator、pkg-config/zlib、linkd、AppKit first-responder 与 SwiftLint recorder 告警与基线一致，不影响 macOS 测试结果。
- Remaining Risks：无人值守解锁、Helper 身份、目标命令泄漏、IPC 正确性和 MCP SDK 1.0 前兼容性仍是实施风险，均已映射到验收与回滚。
- Follow-ups：继续按已选择的 Subagent-Driven 流程顺序实施 Task 5–12，并持续更新本文件复选框与 Delivery Record；Task 5 在已确认的授权、票据和资源边界之上实现 Unix Socket、加密帧及 Helper/Host 双重进程身份校验。
- ZenTao Closeout：不适用；用户未要求禅道操作。
