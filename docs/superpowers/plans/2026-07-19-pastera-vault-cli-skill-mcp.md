# Pastera 密码箱 CLI、Skill 与 MCP V1 计划

> **当前确认门：** 产品与安全设计已经确认。本文档是该需求在仓库内唯一的设计与计划记录。用户完成书面规格复核后，只在本文件中补充详细的复选框实施步骤。

**目标（Goal）：** 为 Codex App 和 Claude Code 提供本地 Pastera 密码箱 CLI、共享 Agent Skill 与本地 stdio MCP 服务；按应用完成一次授权后，在有边界的无人值守期限内使用密码，同时保证工具输出不返回明文密码，并对性能与资源占用设置可验收上限。

**架构（Architecture）：** Pastera 继续作为唯一 KDBX 所有者。Codex、Claude Code 与人工 CLI 分别使用 Pastera 签名的独立适配器，通过用户私有 Unix Domain Socket 向应用进程内的 `PasteraVaultBroker` 发送有界请求。Broker 校验对端身份、执行按应用授权、通过现有 store 边界串行处理 Keychain/KDBX 操作，并在不提供通用密码明文读取接口的前提下执行或授权秘密使用动作。

**技术栈（Tech Stack）：** Swift 6、AppKit、Foundation、CryptoKit、Security、LocalAuthentication、KDBXKit、固定为 `0.12.1` 的官方 [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)、Swift Testing、Xcode 26.5、本地 stdio MCP 与本地 Unix Domain Socket。官方 SDK 支持 Swift 6、macOS 13+ 和 `StdioTransport`；V1 不需要 HTTP MCP 监听器，也不增加 Service Lifecycle 依赖。

## 全局约束（Global Constraints）

- Pastera 必须继续是唯一打开、解密、合并和保存 `PasteraVault.kdbx` 的组件。
- 不得新增会返回明文密码的 MCP 工具、CLI JSON 字段、日志路径或错误详情。
- V1 不向 Agent 暴露密码箱备注，因为备注可能包含非结构化秘密。
- 保持现有 KDBX 格式、OneDrive 路径、冲突语义、Keychain 快速解锁路径、主菜单密码箱 UI 和交互式 `LAContext` 行为兼容。
- Codex、Claude Code 与人工 CLI 必须具有不同的签名客户端身份和相互独立的授权。
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

集成页可以提供 Pastera MCP 工具的窄范围 Host 权限片段，但应用这些规则必须是独立、明确的用户选择。禁止启用全局 bypass 模式或宽泛 Shell 通配符。如果用户不选择，Codex/Claude 的常规工具与 Shell 审批保持不变，即使 Pastera 授权仍然有效。

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

- 新建 `pastera/Sources/Services/VaultAgentBroker.swift`：socket 生命周期、版本握手、请求分发和 Pastera 启动就绪。
- 新建 `pastera/Sources/Services/VaultAgentPeerVerifier.swift`：UID/PID/路径/代码签名校验与已验证客户端类型推导。
- 新建 `pastera/Sources/Services/VaultAgentAuthorizationPolicy.swift`：授权状态、7 天滑动到期、30 天硬到期、续期与撤销。
- 新建 `pastera/Sources/Services/VaultAgentGrantStore.swift`：本机授权持久化，不把秘密写入 Defaults/日志。
- 新建 `pastera/Sources/Services/VaultAutomationUnlockKeyStore.swift`：独立 `AfterFirstUnlockThisDeviceOnly` 原始密钥条目与删除生命周期。
- 新建 `pastera/Sources/Services/VaultAgentTicketStore.swift`：30 秒、绑定客户端、单次使用的票据。
- 新建 `pastera/Sources/Services/VaultAgentRateLimiter.swift`：有界按客户端时间窗。
- 新建 `pastera/Sources/Services/VaultAgentAuditLogger.swift`：脱敏有界审计和本机指标。
- 修改 `pastera/Sources/Services/PasswordVaultStore.swift`：暴露窄范围自动化解锁生命周期，不向调用方暴露原始密钥。
- 修改 `pastera/Sources/Services/KDBXPasswordVaultStore.swift`：在 store 边界内创建/恢复独立自动化密钥，保留现有交互式快速解锁。
- 修改 `pastera/Sources/Managers/PasswordVaultUIController.swift`：通过现有 queue 提供 Broker 异步操作和续期事件。
- 修改 `pastera/Sources/AppDelegate.swift`：随应用生命周期与功能开关启停 Broker。
- 新建 `pastera/Sources/Preferences/Panels/CPYAgentIntegrationPreferenceViewController.swift`：集成状态、安装、授权、到期、撤销和卸载 UI。
- 修改 `pastera/Sources/Preferences/PasteraPreferenceCatalog.swift` 与 `pastera/Sources/Preferences/CPYPreferencesWindowController.swift`：注册并导航 Agent 集成页面。
- 修改 `pastera/Resources/Localizable.xcstrings`：本地化集成、授权、到期、安全和错误文案。

### 共享模块与 Helper Target

- 新建 `pastera-agent/Sources/PasteraAgentProtocol/`：共享有界协议与 DTO。
- 新建 `pastera-agent/Sources/PasteraAgentClient/`：Unix socket Client、握手、加密票据兑换和稳定错误映射。
- 新建 `pastera-agent/Sources/PasteraMCP/`：MCP Swift SDK 工具描述与 stdio Handler。
- 新建 `pastera-agent/Sources/PasteraCodexMCP/main.swift`：Codex 客户端身份与 MCP/exec 入口。
- 新建 `pastera-agent/Sources/PasteraClaudeMCP/main.swift`：Claude 客户端身份与 MCP/exec 入口。
- 新建 `pastera-agent/Sources/PasteraCLI/`：人工 CLI 解析、文本/JSON 渲染、复制/粘贴和集成子命令。
- 修改 `pastera.xcodeproj/project.pbxproj`：增加官方 MCP Package 与三个签名 Helper Target/Product，嵌入 Helper，并定义 Target Membership 和签名标识。

### Skill 与安装资源

- 新建 `integrations/pastera-vault/SKILL.md`：跨 Host 的规范源唯一工作流。
- 新建 `integrations/pastera-vault/references/tool-contract.md`：MCP/CLI Schema 与错误处理。
- 新建 `integrations/pastera-vault/references/security-boundary.md`：禁止明文读取与安全使用约束。
- 新建 `integrations/pastera-vault/agents/openai.yaml`：根据规范 Skill 生成 Codex UI 元数据。
- 在应用集成资源下新增安装所有权清单；不得把凭据或本机配置写入仓库。

### 测试

- 新建 `pasteraTests/VaultAgentAuthorizationPolicyTests.swift`。
- 新建 `pasteraTests/VaultAgentBrokerTests.swift`。
- 新建 `pasteraTests/VaultAgentPeerVerifierTests.swift`。
- 新建 `pasteraTests/VaultAgentTicketStoreTests.swift`。
- 新建 `pasteraTests/VaultAutomationUnlockKeyStoreTests.swift`。
- 新建 `pasteraTests/VaultAgentLeakRegressionTests.swift`。
- 新建 `pasteraTests/VaultAgentPerformanceTests.swift`。
- 新增 Helper Target 测试，覆盖 MCP Schema、stdio 生命周期、CLI JSON/文本封装和适配器票据执行。
- 扩展 `pasteraTests/PasswordVaultStoreTests.swift`、`pasteraTests/PasswordVaultMenuTests.swift` 与 `pasteraTests/SecureClipboardServiceTests.swift`，覆盖兼容性和集成续期行为。

## 实施切片概览

用户完成书面规格复核后，在本文件中把以下切片展开为详细 TDD 复选步骤：

1. 固化共享协议、稳定错误、元数据 Schema 与 Host 无关 Client API。
2. 实现授权、滑动/硬到期、无人值守 Keychain 恢复、撤销、票据、限流与脱敏审计基础能力。
3. 实现并加固 Broker socket、对端校验、防重放、应用生命周期和现有 store 集成。
4. 增加签名的人工/Codex/Claude Helper Target、stdio MCP 工具、CLI 契约与受控秘密交付。
5. 增加规范 Agent Skill 和可逆的 Codex/Claude 安装、状态与卸载流程。
6. 增加 Pastera Agent 集成偏好页，以及首次授权、续期和撤销 UI。
7. 完成安全、泄漏、并发、性能/资源、兼容性、安装与真实 Host 验收门。

## 验收映射（Acceptance Mapping）

| 验收项 | 自动化证据 | 人工 / Host 证据 |
| --- | --- | --- |
| 按应用一次授权 | 确定性时钟策略测试、待处理请求去重、客户端授权隔离测试 | Codex 与 Claude 各授权一次；新任务和 MCP 重启不再弹 Pastera 授权 |
| 7 天滑动、30 天硬上限 | 到期边界、成功敏感动作续期、状态/搜索/失败不续期测试 | 偏好页展示两种到期时间；硬上限后必须重新授权 |
| 冷态无人值守恢复 | 临时 KDBX + 自动化 Keychain Test Double、应用/store 重启、密钥损坏失效测试 | Pastera 重启和 Mac 锁屏/解锁后保持无人值守；重启后正常登录 macOS 即可使用 |
| 应用身份隔离 | UID/PID/路径/签名测试，伪造标识/路径/哈希拒绝，Codex/Claude 授权分离 | 撤销 Codex 不影响 Claude；替换后的未知 Helper 被拒绝 |
| 模型输出无明文 | Schema 测试；扫描 MCP 内容、CLI stdout/stderr、日志、审计、参数、环境、临时目录和错误中的哨兵秘密 | 检查捕获的 Codex/Claude 对话和 Pastera unified logs |
| 直接粘贴与命令注入 | Named Pasteboard、目标恢复、stdin/fd 子进程 Fixture、票据到期/重放测试 | 粘贴到真实文本/浏览器字段，并运行不回显的消费命令 |
| 性能与资源有界 | 10,000 条 p95、冷态就绪、RSS/空闲 CPU、重复会话泄漏测试 | 在参考 Mac 上用 Activity Monitor/Instruments 抽查 |
| 安装可逆 | 安装/状态/卸载幂等、修改过的 Skill 冲突、配置保留 Fixture | 在 Codex App/Claude Code 中确认 MCP/Skill 发现，卸载后其他配置不受影响 |
| Host 权限独立 | Fixture 证明不写全局 bypass 或宽通配符；可选窄规则内容精确且需要确认 | 先保持 Host 默认策略，再选择性安装并检查只针对 Pastera 的规则 |
| 现有密码箱兼容 | 聚焦 KDBX、Keychain 快速解锁、冲突、菜单、剪贴板及默认完整 Xcode 测试 | 关闭 Agent 集成时，本地安装后的常规密码箱行为不变 |

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
- **风险——MCP Swift SDK 尚未到 1.0：** 次版本可能破坏 API。V1 固定 `0.12.1`，升级必须作为明确兼容性任务。
- **回滚：** 关闭 Agent 集成、停止接受新 Broker 连接、撤销全部外部授权、删除自动化 Keychain 条目与票据、注销 Pastera 所有的 MCP 条目并移除其 Skill 副本。KDBX 字节、OneDrive 路径、交互式快速解锁、主菜单 UI 与现有密码数据无需迁移或回滚。
- **观察：** 仅使用本机脱敏的连接/结果/延迟/资源分桶与有界审计，不上传密码箱遥测。重点观察授权请求去重、自动恢复失败、限流、适配器崩溃、延迟 p95 和 RSS 漂移。

## 交付元数据（Delivery Metadata）

- Plan Path：`docs/superpowers/plans/2026-07-19-pastera-vault-cli-skill-mcp.md`
- Plan Status：`design-approved-pending-written-review`
- Evidence Profile：`standard`
- Story ID：未请求、未分配
- Task IDs：未请求、未分配
- Superpowers Task Mapping：上文已经给出实施切片；详细复选框任务有意等待书面规格复核后再写入本文件
- ZenTao Sync Status：`not-requested`
- ZenTao Readback Evidence / Time：不适用
- Prior Related Records：密码箱内嵌解锁、首次打开延迟、上下文动作和访问体验优化属于已完成的独立需求，不是本 CLI/Skill/MCP 范围的竞争计划
- External Basis：Codex MCP/Skill 官方文档、Claude Code MCP/Skill 官方文档和官方 MCP Swift SDK `0.12.1`
- Last Updated：`2026-07-19`

## 交付记录（Delivery Record）

- Actual Implementation：无；当前记录只包含已确认设计。
- Plan Deviations：由于项目工作流禁止为同一需求创建平行 plan/spec，Superpowers 设计规格与实施计划有意合并到这一份仓库文件中。
- Impact：计划影响仅限 macOS Pastera 应用、三个内置 Helper、本地 Agent Skill 资源、用户自己的 Codex/Claude MCP 配置和新增本机 Keychain 授权材料；不计划修改 KDBX Schema 或 OneDrive 路径。
- Verification：设计阶段已经完成仓库/源码检查，以及 Codex、Claude Code、MCP SDK 官方文档核查；尚未开始实现验证。
- Remaining Risks：无人值守解锁、Helper 身份、目标命令泄漏、IPC 正确性和 MCP SDK 1.0 前兼容性仍是实施风险，均已映射到验收与回滚。
- Follow-ups：用户完成中文书面规格复核后，在同一文件中补充详细 TDD 实施任务。
- ZenTao Closeout：不适用；用户未要求禅道操作。
